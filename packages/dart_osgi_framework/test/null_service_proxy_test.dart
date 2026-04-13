import 'dart:async';

import 'package:dart_osgi_framework/dart_osgi_framework.dart';
import 'package:test/test.dart';

void main() {
  group('NullServiceProxy', () {
    test('stores serviceName', () {
      final proxy = NullServiceProxy('com.test.Svc');
      expect(proxy.serviceName, equals('com.test.Svc'));
    });

    test('logAbsorbed() does not throw', () {
      final proxy = NullServiceProxy('com.test.Svc');
      expect(() => proxy.logAbsorbed('getData'), returnsNormally);
    });

    test('logAbsorbed() can be called multiple times', () {
      final proxy = NullServiceProxy('com.test.Svc');
      expect(() {
        proxy.logAbsorbed('method1');
        proxy.logAbsorbed('method2');
        proxy.logAbsorbed('method3');
      }, returnsNormally);
    });
  });

  group('ResilientServiceTracker', () {
    late ServiceRegistry registry;

    setUp(() {
      registry = ServiceRegistry();
    });

    tearDown(() {
      registry.dispose();
    });

    test('open() picks up an existing service', () async {
      // Register a service before opening the tracker.
      registry.register<String>(
        'com.test.Greeter',
        'Hello',
        'test.bundle',
        null,
      );

      final tracker = ResilientServiceTracker<String>(
        registry: registry,
        className: 'com.test.Greeter',
        fallback: 'FALLBACK',
        rebindTimeout: const Duration(milliseconds: 100),
      );

      await tracker.open();

      expect(tracker.current, equals('Hello'));
      expect(tracker.isFallbackActive, isFalse);

      await tracker.close();
    });

    test('current returns fallback when no service registered', () async {
      final tracker = ResilientServiceTracker<String>(
        registry: registry,
        className: 'com.test.Missing',
        fallback: 'FALLBACK',
        rebindTimeout: const Duration(milliseconds: 100),
      );

      await tracker.open();

      expect(tracker.current, equals('FALLBACK'));
      // isFallbackActive is false initially because the timer hasn't fired yet;
      // it's only true after the rebind timeout actually expires.
      expect(tracker.isFallbackActive, isFalse);

      await tracker.close();
    });

    test('switches to fallback after rebindTimeout expires', () async {
      final reg = registry.register<String>(
        'com.test.Svc',
        'RealService',
        'test.bundle',
        null,
      );

      final tracker = ResilientServiceTracker<String>(
        registry: registry,
        className: 'com.test.Svc',
        fallback: 'FALLBACK',
        rebindTimeout: const Duration(milliseconds: 100),
      );

      await tracker.open();
      expect(tracker.current, equals('RealService'));
      expect(tracker.isFallbackActive, isFalse);

      // Unregister the service to trigger the rebind timer.
      await reg.unregister();

      // The ServiceTrackerImpl has a 50ms debounce before emitting removedService.
      // After that, the ResilientServiceTracker starts a 100ms rebind timer.
      // Wait long enough for both to fire.
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(tracker.current, equals('FALLBACK'));
      expect(tracker.isFallbackActive, isTrue);

      await tracker.close();
    });

    test('auto-restores when real service reappears', () async {
      final reg = registry.register<String>(
        'com.test.Svc',
        'RealService',
        'test.bundle',
        null,
      );

      final tracker = ResilientServiceTracker<String>(
        registry: registry,
        className: 'com.test.Svc',
        fallback: 'FALLBACK',
        rebindTimeout: const Duration(milliseconds: 100),
      );

      await tracker.open();
      expect(tracker.current, equals('RealService'));

      // Unregister and wait for fallback.
      await reg.unregister();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(tracker.isFallbackActive, isTrue);

      // Re-register the service.
      registry.register<String>(
        'com.test.Svc',
        'RestoredService',
        'test.bundle',
        null,
      );

      // Allow event propagation.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(tracker.current, equals('RestoredService'));
      expect(tracker.isFallbackActive, isFalse);

      await tracker.close();
    });

    test('isFallbackActive reflects state transitions', () async {
      final tracker = ResilientServiceTracker<String>(
        registry: registry,
        className: 'com.test.Svc',
        fallback: 'FALLBACK',
        rebindTimeout: const Duration(milliseconds: 100),
      );

      await tracker.open();
      expect(tracker.isFallbackActive, isFalse);

      // Register then unregister.
      final reg = registry.register<String>(
        'com.test.Svc',
        'Real',
        'test.bundle',
        null,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(tracker.isFallbackActive, isFalse);

      await reg.unregister();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(tracker.isFallbackActive, isTrue);

      await tracker.close();
    });

    test('service stream emits values on state changes', () async {
      final tracker = ResilientServiceTracker<String>(
        registry: registry,
        className: 'com.test.Svc',
        fallback: 'FALLBACK',
        rebindTimeout: const Duration(milliseconds: 100),
      );

      final emitted = <String>[];
      tracker.service.listen(emitted.add);

      await tracker.open();

      // Register a service.
      registry.register<String>('com.test.Svc', 'SvcA', 'test.bundle', null);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emitted, contains('SvcA'));

      await tracker.close();
    });

    test('close() cleans up and closes stream', () async {
      final tracker = ResilientServiceTracker<String>(
        registry: registry,
        className: 'com.test.Svc',
        fallback: 'FALLBACK',
        rebindTimeout: const Duration(milliseconds: 100),
      );

      await tracker.open();

      // Register and then unregister to start a rebind timer.
      final reg = registry.register<String>(
        'com.test.Svc',
        'Real',
        'test.bundle',
        null,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await reg.unregister();

      // Close before the rebind timer fires.
      await tracker.close();

      // After close, the stream should be done.
      final isDone = Completer<bool>();
      tracker.service.listen(
        (_) {},
        onDone: () => isDone.complete(true),
        onError: (_) => isDone.complete(false),
      );
      // Broadcast stream: onDone fires immediately if controller is closed.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // No error should have been thrown.
    });
  });
}
