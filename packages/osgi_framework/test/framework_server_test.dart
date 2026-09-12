import 'dart:async';
import 'dart:isolate';

import 'package:osgi_framework/osgi_framework.dart';
import 'package:test/test.dart';

void main() {
  late FrameworkServer server;
  final List<RemoteBundleContext> contexts = <RemoteBundleContext>[];

  setUp(() {
    server = FrameworkServer()..start();
  });

  tearDown(() async {
    for (final RemoteBundleContext context in contexts) {
      await context.detach();
    }
    contexts.clear();
    await server.stop();
  });

  /// A bundle talking to the framework. In-process here, which exercises the
  /// same protocol: a SendPort to your own isolate behaves like any other.
  Future<RemoteBundleContext> bundle(String name) async {
    final RemoteBundleContext context = RemoteBundleContext(
      symbolicName: name,
      framework: server.port,
      requestTimeout: const Duration(seconds: 10),
    );
    contexts.add(context);
    await context.attach();
    return context;
  }

  group('services', () {
    test('a published port can be found by another bundle', () async {
      final RemoteBundleContext producer = await bundle('com.ivi.can');
      final RemoteBundleContext consumer = await bundle('com.ivi.cluster');
      final ReceivePort service = ReceivePort();
      addTearDown(service.close);

      await producer.registerService('CanBus', service.sendPort);
      final ServiceEndpoint? found = await consumer.lookup('CanBus');

      expect(found, isNotNull);
      expect(found!.interfaceName, 'CanBus');
      expect(found.port, service.sendPort);
    });

    test('a service is reachable through the port it published', () async {
      // The point of endpoints: the consumer talks to the owner, not to a copy.
      final RemoteBundleContext producer = await bundle('com.ivi.can');
      final RemoteBundleContext consumer = await bundle('com.ivi.cluster');
      final ReceivePort service = ReceivePort();
      addTearDown(service.close);
      service.listen((dynamic message) {
        if (message is List && message.length == 2) {
          (message[1] as SendPort).send('rpm=${message[0]}');
        }
      });

      await producer.registerService('CanBus', service.sendPort);
      final ServiceEndpoint endpoint = (await consumer.lookup('CanBus'))!;

      final ReceivePort reply = ReceivePort();
      addTearDown(reply.close);
      endpoint.port.send(<Object>[900, reply.sendPort]);

      expect(await reply.first, 'rpm=900');
    });

    test('ranking and filters decide what a lookup returns', () async {
      final RemoteBundleContext producer = await bundle('com.ivi.nav');
      final ReceivePort fallback = ReceivePort();
      final ReceivePort preferred = ReceivePort();
      addTearDown(fallback.close);
      addTearDown(preferred.close);

      await producer.registerService(
        'Nav',
        fallback.sendPort,
        const <String, Object?>{'zone': 'front'},
      );
      await producer.registerService(
        'Nav',
        preferred.sendPort,
        const <String, Object?>{'zone': 'rear', 'service.ranking': 10},
      );

      expect((await producer.lookup('Nav'))!.port, preferred.sendPort);
      expect(
        (await producer.lookup('Nav', filter: '(zone=front)'))!.port,
        fallback.sendPort,
      );
      expect(await producer.lookupAll('Nav'), hasLength(2));
    });

    test('a malformed filter comes back as a failure, not a hang', () async {
      // The framework parses it in another isolate, so it cannot throw here.
      final RemoteBundleContext consumer = await bundle('com.ivi.cluster');

      await expectLater(
        consumer.lookup('Nav', filter: 'zone=front'),
        throwsA(isA<FrameworkException>()),
      );
    });

    test('unregistering withdraws the service', () async {
      final RemoteBundleContext producer = await bundle('com.ivi.can');
      final ReceivePort service = ReceivePort();
      addTearDown(service.close);

      final ServiceRegistration registration = await producer.registerService(
        'CanBus',
        service.sendPort,
      );
      await registration.unregister();

      expect(await producer.lookup('CanBus'), isNull);
      // Idempotent, as in-process.
      await expectLater(registration.unregister(), completes);
    });

    test('a bundle cannot withdraw another bundle service', () async {
      final RemoteBundleContext producer = await bundle('com.ivi.can');
      final RemoteBundleContext other = await bundle('com.ivi.cluster');
      final ReceivePort service = ReceivePort();
      addTearDown(service.close);

      final ServiceRegistration registration = await producer.registerService(
        'CanBus',
        service.sendPort,
      );
      final int serviceId = (await other.lookup('CanBus'))!.serviceId;
      expect(serviceId, greaterThan(0));

      // Reaching the protocol directly, the way a hostile or buggy bundle
      // would: the framework checks ownership rather than trusting the name.
      final ReceivePort replies = ReceivePort();
      addTearDown(replies.close);
      server.port.send(
        UnregisterEndpoint(
          id: 99,
          bundle: 'com.ivi.cluster',
          replyTo: replies.sendPort,
          serviceId: serviceId,
        ),
      );

      expect(await replies.first, isA<RequestFailed>());
      expect(await producer.lookup('CanBus'), isNotNull);
      await registration.unregister();
    });

    test(
      'a service must be a SendPort, not an object that would be copied',
      () async {
        final RemoteBundleContext producer = await bundle('com.ivi.can');

        await expectLater(
          producer.registerService('CanBus', <String, Object?>{
            'not': 'a port',
          }),
          throwsArgumentError,
        );
      },
    );
  });

  group('trackers', () {
    test('deliver services already registered, then later ones', () async {
      final RemoteBundleContext producer = await bundle('com.ivi.can');
      final RemoteBundleContext consumer = await bundle('com.ivi.cluster');
      final ReceivePort first = ReceivePort();
      final ReceivePort second = ReceivePort();
      addTearDown(first.close);
      addTearDown(second.close);

      await producer.registerService('CanBus', first.sendPort);

      final ServiceTracker tracker = consumer.trackService('CanBus');
      final List<Object?> seen = <Object?>[];
      final StreamSubscription<Object?> sub = tracker.addingService.listen(
        seen.add,
      );
      await tracker.open();
      await pumpEventQueue();

      expect(seen, hasLength(1), reason: 'the one already registered');

      await producer.registerService('CanBus', second.sendPort);
      await pumpEventQueue();

      expect(seen, hasLength(2));
      await sub.cancel();
      await tracker.close();
    });

    test(
      'a listener that arrives after open() still sees what is tracked',
      () async {
        // The same guarantee as in-process: the client keeps the tracked set, so
        // this does not depend on subscribing before open().
        final RemoteBundleContext producer = await bundle('com.ivi.can');
        final RemoteBundleContext consumer = await bundle('com.ivi.cluster');
        final ReceivePort service = ReceivePort();
        addTearDown(service.close);
        await producer.registerService('CanBus', service.sendPort);

        final ServiceTracker tracker = consumer.trackService('CanBus');
        await tracker.open();
        await pumpEventQueue();

        expect(await tracker.addingService.first, isA<ServiceEndpoint>());
        await tracker.close();
      },
    );

    test('report a service going away', () async {
      final RemoteBundleContext producer = await bundle('com.ivi.can');
      final RemoteBundleContext consumer = await bundle('com.ivi.cluster');
      final ReceivePort service = ReceivePort();
      addTearDown(service.close);

      final ServiceRegistration registration = await producer.registerService(
        'CanBus',
        service.sendPort,
      );
      final ServiceTracker tracker = consumer.trackService('CanBus');
      final Future<Object?> removed = tracker.removedService.first;
      await tracker.open();
      await pumpEventQueue();

      await registration.unregister();

      expect(await removed, isA<ServiceEndpoint>());
      await tracker.close();
    });
  });

  group('routing', () {
    test('a bundle can send to another by name', () async {
      final RemoteBundleContext sender = await bundle('com.ivi.can');
      final RemoteBundleContext receiver = await bundle('com.ivi.cluster');
      final Future<Object?> received = receiver.incoming.first;

      await sender.sendToBundle('com.ivi.cluster', 'wake up');

      expect(await received, 'wake up');
    });

    test('sending to a bundle that is not attached fails', () async {
      final RemoteBundleContext sender = await bundle('com.ivi.can');

      await expectLater(
        sender.sendToBundle('com.ivi.absent', 'hello'),
        throwsA(isA<FrameworkException>()),
      );
    });
  });

  group('detach', () {
    test('releases the services the bundle published', () async {
      final RemoteBundleContext producer = await bundle('com.ivi.can');
      final RemoteBundleContext consumer = await bundle('com.ivi.cluster');
      final ReceivePort service = ReceivePort();
      addTearDown(service.close);
      await producer.registerService('CanBus', service.sendPort);

      await producer.detach();

      expect(await consumer.lookup('CanBus'), isNull);
      expect(server.attached, isNot(contains('com.ivi.can')));
    });

    test('is idempotent and refuses later requests', () async {
      final RemoteBundleContext producer = await bundle('com.ivi.can');

      await producer.detach();
      await expectLater(producer.detach(), completes);
      await expectLater(producer.lookup('CanBus'), throwsStateError);
    });
  });
}
