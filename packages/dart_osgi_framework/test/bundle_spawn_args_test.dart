import 'dart:isolate';

import 'package:dart_osgi_framework/dart_osgi_framework.dart';
import 'package:test/test.dart';

void main() {
  group('BundleSpawnArgs', () {
    test('constructor with all fields', () {
      final rp = ReceivePort();
      addTearDown(rp.close);

      final args = BundleSpawnArgs(
        frameworkPort: rp.sendPort,
        symbolicName: 'com.test.bundle',
        version: '1.2.3',
        activatorClass: 'MyActivator',
        priority: BundlePriority.critical,
        properties: {'key': 'value', 'count': 42},
      );

      expect(args.frameworkPort, equals(rp.sendPort));
      expect(args.symbolicName, equals('com.test.bundle'));
      expect(args.version, equals('1.2.3'));
      expect(args.activatorClass, equals('MyActivator'));
      expect(args.priority, equals(BundlePriority.critical));
      expect(args.properties, equals({'key': 'value', 'count': 42}));
    });

    test('properties can be empty map', () {
      final rp = ReceivePort();
      addTearDown(rp.close);

      final args = BundleSpawnArgs(
        frameworkPort: rp.sendPort,
        symbolicName: 'com.test.empty',
        version: '0.0.1',
        activatorClass: 'Activator',
        priority: BundlePriority.background,
        properties: {},
      );

      expect(args.properties, isEmpty);
    });

    test('all priority values are accepted', () {
      final rp = ReceivePort();
      addTearDown(rp.close);

      for (final p in BundlePriority.values) {
        final args = BundleSpawnArgs(
          frameworkPort: rp.sendPort,
          symbolicName: 'com.test.${p.name}',
          version: '1.0.0',
          activatorClass: 'Activator',
          priority: p,
          properties: {},
        );
        expect(args.priority, equals(p));
      }
    });
  });

  group('HandshakeMessage subclasses', () {
    test('BundleHandshake is HandshakeMessage', () {
      final rp = ReceivePort();
      addTearDown(rp.close);

      final handshake = BundleHandshake(
        symbolicName: 'com.test.a',
        bundlePort: rp.sendPort,
      );

      expect(handshake, isA<HandshakeMessage>());
      expect(handshake.symbolicName, equals('com.test.a'));
      expect(handshake.bundlePort, equals(rp.sendPort));
    });

    test('StopSignal is HandshakeMessage', () {
      const signal = StopSignal();

      expect(signal, isA<HandshakeMessage>());
    });

    test('BundleReady is HandshakeMessage', () {
      const ready = BundleReady(symbolicName: 'com.test.ready');

      expect(ready, isA<HandshakeMessage>());
      expect(ready.symbolicName, equals('com.test.ready'));
    });

    test('BundleStartFailed is HandshakeMessage with error/stackTrace', () {
      final error = Exception('activation failed');
      final stackTrace = StackTrace.current;

      final failed = BundleStartFailed(
        symbolicName: 'com.test.failed',
        error: error,
        stackTrace: stackTrace,
      );

      expect(failed, isA<HandshakeMessage>());
      expect(failed.symbolicName, equals('com.test.failed'));
      expect(failed.error, equals(error));
      expect(failed.stackTrace, equals(stackTrace));
    });

    test('BundleStartFailed with string error', () {
      final failed = BundleStartFailed(
        symbolicName: 'com.test.failed',
        error: 'plain string error',
        stackTrace: StackTrace.current,
      );

      expect(failed.error, equals('plain string error'));
    });

    test('HandshakeMessage sealed hierarchy covers all cases', () {
      // Verify exhaustive pattern matching compiles (sealed class).
      final messages = <HandshakeMessage>[
        BundleHandshake(symbolicName: 'a', bundlePort: ReceivePort().sendPort),
        const StopSignal(),
        const BundleReady(symbolicName: 'b'),
        BundleStartFailed(
          symbolicName: 'c',
          error: 'err',
          stackTrace: StackTrace.current,
        ),
      ];

      for (final msg in messages) {
        final description = switch (msg) {
          BundleHandshake() => 'handshake',
          StopSignal() => 'stop',
          BundleReady() => 'ready',
          BundleStartFailed() => 'failed',
        };
        expect(description, isNotEmpty);
      }
    });
  });
}
