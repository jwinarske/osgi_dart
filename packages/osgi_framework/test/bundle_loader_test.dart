import 'dart:async';
import 'dart:isolate';

import 'package:osgi_framework/osgi_framework.dart';
import 'package:test/test.dart';

/// Publishes a port that echoes what it is sent, so a caller in another isolate
/// can prove the call reached this one rather than a copy of it.
class _EchoActivator implements BundleActivator {
  ReceivePort? _service;

  @override
  Future<void> start(BundleContext context) async {
    final ReceivePort service = ReceivePort('echo.service');
    _service = service;
    service.listen((dynamic message) {
      if (message is List && message.length == 2) {
        (message[1] as SendPort).send('echo:${message[0]}');
      }
    });
    await context.registerService(
      'Echo',
      service.sendPort,
      const <String, Object?>{'zone': 'front'},
    );
  }

  @override
  Future<void> stop(BundleContext context) async {
    _service?.close();
  }
}

class _FailingActivator implements BundleActivator {
  @override
  Future<void> start(BundleContext context) async {
    // After registering, so the test can prove a failed start leaves nothing.
    await context.registerService('Echo', ReceivePort().sendPort);
    throw StateError('no display');
  }

  @override
  Future<void> stop(BundleContext context) async {}
}

/// Registers a service and then takes its own isolate down, standing in for a
/// bundle that crashes: it never gets to detach.
class _DyingActivator implements BundleActivator {
  @override
  Future<void> start(BundleContext context) async {
    await context.registerService('Echo', ReceivePort().sendPort);
    Future<void>.delayed(const Duration(milliseconds: 50), () {
      Isolate.current.kill(priority: Isolate.immediate);
    });
  }

  @override
  Future<void> stop(BundleContext context) async {}
}

// Activator factories must be top-level: a closure cannot cross to a spawned
// isolate, and an instance would be copied.
BundleActivator makeEcho() => _EchoActivator();
BundleActivator makeFailing() => _FailingActivator();
BundleActivator makeDying() => _DyingActivator();

void main() {
  late FrameworkServer server;
  late BundleLoader loader;
  late RemoteBundleContext observer;

  setUp(() async {
    server = FrameworkServer()..start();
    loader = BundleLoader(framework: server.port);
    observer = RemoteBundleContext(
      symbolicName: 'com.ivi.observer',
      framework: server.port,
      requestTimeout: const Duration(seconds: 20),
    );
    await observer.attach();
  });

  tearDown(() async {
    await loader.close();
    await observer.detach();
    await server.stop();
  });

  /// Wait until [lookup] stops finding anything, or give up.
  Future<void> untilGone(String interfaceName) async {
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      if (await observer.lookup(interfaceName) == null) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    fail('"$interfaceName" was still registered after 20s');
  }

  test(
    'a spawned bundle publishes a service the rest of the process can call',
    () async {
      await loader.spawn(
        symbolicName: 'com.ivi.can',
        activatorFactory: makeEcho,
        startTimeout: const Duration(seconds: 20),
      );

      expect(loader.running, contains('com.ivi.can'));

      final ServiceEndpoint? endpoint = await observer.lookup(
        'Echo',
        filter: '(zone=front)',
      );
      expect(endpoint, isNotNull);

      final ReceivePort reply = ReceivePort();
      addTearDown(reply.close);
      endpoint!.port.send(<Object>[42, reply.sendPort]);

      expect(
        await reply.first,
        'echo:42',
        reason: 'the call reached the isolate the loader spawned',
      );
    },
  );

  test(
    'an activator that throws fails the spawn and leaves nothing behind',
    () async {
      await expectLater(
        loader.spawn(
          symbolicName: 'com.ivi.broken',
          activatorFactory: makeFailing,
          startTimeout: const Duration(seconds: 20),
        ),
        throwsA(
          isA<BundleStartException>().having(
            (BundleStartException e) => e.error,
            'error',
            contains('no display'),
          ),
        ),
      );

      expect(loader.running, isEmpty);
      expect(
        await observer.lookup('Echo'),
        isNull,
        reason: 'the failed start detached, releasing what it had registered',
      );
    },
  );

  test('stopping a bundle releases what it published', () async {
    await loader.spawn(
      symbolicName: 'com.ivi.can',
      activatorFactory: makeEcho,
      startTimeout: const Duration(seconds: 20),
    );
    expect(await observer.lookup('Echo'), isNotNull);

    await loader.stop('com.ivi.can', timeout: const Duration(seconds: 20));

    expect(loader.running, isEmpty);
    expect(await observer.lookup('Echo'), isNull);
  });

  test('a bundle whose isolate dies is released by the loader', () async {
    // The hole this closes: a dead isolate cannot detach itself, so without the
    // exit watcher its endpoint would stay in the registry pointing at a port
    // nothing listens on.
    await loader.spawn(
      symbolicName: 'com.ivi.crasher',
      activatorFactory: makeDying,
      startTimeout: const Duration(seconds: 20),
    );

    await untilGone('Echo');

    expect(loader.running, isEmpty);
  });

  test('spawning the same name twice is a programming error', () async {
    await loader.spawn(
      symbolicName: 'com.ivi.can',
      activatorFactory: makeEcho,
      startTimeout: const Duration(seconds: 20),
    );

    await expectLater(
      loader.spawn(
        symbolicName: 'com.ivi.can',
        activatorFactory: makeEcho,
        startTimeout: const Duration(seconds: 20),
      ),
      throwsStateError,
    );
  });
}
