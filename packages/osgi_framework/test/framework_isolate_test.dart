import 'dart:async';
import 'dart:isolate';

import 'package:osgi_framework/osgi_framework.dart';
import 'package:test/test.dart';

/// A bundle in its own isolate: attach, publish a service, say so.
///
/// Top-level because `Isolate.spawn` needs an entry point it can reach without
/// a closure over this isolate's state -- which is the same reason a service
/// crosses as a port rather than as an object.
void producerMain(List<Object> args) async {
  final SendPort framework = args[0] as SendPort;
  final SendPort ready = args[1] as SendPort;

  final RemoteBundleContext context = RemoteBundleContext(
    symbolicName: 'com.ivi.can',
    framework: framework,
    requestTimeout: const Duration(seconds: 20),
  );
  await context.attach();

  final ReceivePort service = ReceivePort('can.service');
  service.listen((dynamic message) {
    // The service's own protocol: [value, replyTo].
    if (message is List && message.length == 2) {
      (message[1] as SendPort).send('rpm=${message[0]}');
    }
  });

  await context.registerService(
    'CanBus',
    service.sendPort,
    const <String, Object?>{'interface': 'can0'},
  );
  ready.send('registered');
}

/// A bundle in its own isolate that attaches and posts one event.
///
/// The parent subscribes before spawning this, so the post cannot arrive
/// before there is anything listening for it.
void posterMain(List<Object> args) async {
  final SendPort framework = args[0] as SendPort;

  final RemoteBundleContext context = RemoteBundleContext(
    symbolicName: 'com.ivi.poster',
    framework: framework,
    requestTimeout: const Duration(seconds: 20),
  );
  await context.attach();
  context.post('com/ivi/can/THRESHOLD', const <String, Object?>{
    'signal': 'EngineTemp',
    'value': 105.0,
  });
}

void main() {
  late FrameworkServer server;
  late RemoteBundleContext consumer;
  final List<Isolate> spawned = <Isolate>[];

  setUp(() async {
    server = FrameworkServer()..start();
    consumer = RemoteBundleContext(
      symbolicName: 'com.ivi.cluster',
      framework: server.port,
      requestTimeout: const Duration(seconds: 20),
    );
    await consumer.attach();
  });

  tearDown(() async {
    for (final Isolate isolate in spawned) {
      isolate.kill(priority: Isolate.immediate);
    }
    spawned.clear();
    await consumer.detach();
    await server.stop();
  });

  Future<void> spawnProducer(SendPort ready) async {
    spawned.add(
      await Isolate.spawn(producerMain, <Object>[
        server.port,
        ready,
      ], debugName: 'com.ivi.can'),
    );
  }

  test(
    'a bundle in another isolate publishes a service this one can call',
    () async {
      // The end-to-end case the endpoint design exists for: two real isolates,
      // one service, and a call that reaches the owner rather than a copy.
      final ReceivePort ready = ReceivePort();
      addTearDown(ready.close);
      await spawnProducer(ready.sendPort);
      await ready.first;

      final ServiceEndpoint? endpoint = await consumer.lookup(
        'CanBus',
        filter: '(interface=can0)',
      );
      expect(endpoint, isNotNull);

      final ReceivePort reply = ReceivePort();
      addTearDown(reply.close);
      endpoint!.port.send(<Object>[2400, reply.sendPort]);

      expect(
        await reply.first,
        'rpm=2400',
        reason: 'the call reached the isolate that published the service',
      );
    },
  );

  test('a tracker opened first sees a service registered later from another '
      'isolate', () async {
    // Bundle start order is not something a bundle controls, so waiting for a
    // service that does not exist yet has to work.
    final ServiceTracker tracker = consumer.trackService('CanBus');
    final Future<Object?> appeared = tracker.addingService.first;
    await tracker.open();

    final ReceivePort ready = ReceivePort();
    addTearDown(ready.close);
    await spawnProducer(ready.sendPort);

    final Object? endpoint = await appeared.timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw StateError('no tracker event crossed isolates'),
    );

    expect(endpoint, isA<ServiceEndpoint>());
    expect((endpoint! as ServiceEndpoint).interfaceName, 'CanBus');
    await tracker.close();
  });

  test(
    'an event posted in another isolate reaches a subscriber here',
    () async {
      // An event is a value, so copying it across the boundary is what delivery
      // means -- unlike a service, where a copy would be useless.
      final Future<Event> received = consumer.subscribe('com/ivi/can/*').first;
      await pumpEventQueue();

      spawned.add(
        await Isolate.spawn(posterMain, <Object>[
          server.port,
        ], debugName: 'com.ivi.poster'),
      );

      final Event event = await received.timeout(const Duration(seconds: 20));
      expect(event.topic, 'com/ivi/can/THRESHOLD');
      expect(event.property<double>('value'), 105.0);
    },
  );

  test('killing a bundle isolate leaves its service registered', () async {
    // Worth stating plainly: the framework learns that a bundle is gone only
    // when it says so. A killed isolate cannot, so its endpoint stays until
    // something else releases it -- a lifecycle owner, or the shell noticing
    // the engine died.
    final ReceivePort ready = ReceivePort();
    addTearDown(ready.close);
    await spawnProducer(ready.sendPort);
    await ready.first;
    expect(await consumer.lookup('CanBus'), isNotNull);

    spawned.removeLast().kill(priority: Isolate.immediate);
    await pumpEventQueue();

    expect(
      await consumer.lookup('CanBus'),
      isNotNull,
      reason: 'a dead isolate cannot detach itself',
    );
  });
}
