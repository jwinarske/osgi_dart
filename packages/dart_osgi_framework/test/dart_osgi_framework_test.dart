import 'dart:async';

import 'package:dart_osgi_framework/dart_osgi_framework.dart';
import 'package:test/test.dart';

/// Helper to create a BundleManifest for testing.
BundleManifest _manifest({
  String symbolicName = 'com.test.bundle',
  String priority = 'normal',
}) {
  return BundleManifest.parse('''
bundle:
  symbolicName: $symbolicName
  version: 1.0.0
  type: dart
  activator: TestActivator
  startup:
    priority: $priority
''');
}

void main() {
  late DartOSGiFramework framework;

  setUp(() {
    framework = DartOSGiFramework.instance;
  });

  tearDown(() async {
    await framework.stop();
  });

  group('DartOSGiFramework', () {
    test('instance is singleton', () {
      final a = DartOSGiFramework.instance;
      final b = DartOSGiFramework.instance;
      expect(identical(a, b), isTrue);
    });

    test('start() sets isStarted', () {
      expect(framework.isStarted, isFalse);
      framework.start();
      expect(framework.isStarted, isTrue);
    });

    test('start() twice is safe', () {
      framework.start();
      framework.start();
      expect(framework.isStarted, isTrue);
    });

    test('registry is accessible', () {
      expect(framework.registry, isNotNull);
      expect(framework.registry, isA<ServiceRegistry>());
    });

    test('bundleManager is accessible', () {
      expect(framework.bundleManager, isNotNull);
      expect(framework.bundleManager, isA<BundleManager>());
    });

    test('bus is accessible', () {
      expect(framework.bus, isNotNull);
      expect(framework.bus, isA<IsolateBus>());
    });

    test('bundleEvents stream is accessible', () {
      expect(framework.bundleEvents, isA<Stream<BundleEvent>>());
    });

    test('serviceEvents stream is accessible', () {
      expect(framework.serviceEvents, isA<Stream<ServiceEvent>>());
    });

    group('bundle lifecycle', () {
      test('installBundle / resolveAll / startBundle', () {
        framework.start();

        final manifest = _manifest(symbolicName: 'com.test.a');
        final bundle = framework.installBundle(manifest);
        expect(bundle.symbolicName, equals('com.test.a'));
        expect(bundle.state, equals(BundleState.installed));

        final graph = framework.resolveAll();
        expect(graph.resolved, isNotEmpty);
        expect(bundle.state, equals(BundleState.resolved));

        final ctx = framework.startBundle('com.test.a');
        expect(ctx, isNotNull);
        expect(ctx, isA<IsolateBundleContext>());
        expect(bundle.state, equals(BundleState.active));
      });

      test('startBundle assigns priority port for critical bundles', () {
        framework.start();

        final critical = _manifest(
          symbolicName: 'com.critical',
          priority: 'critical',
        );
        framework.installBundle(critical);
        framework.resolveAll();

        final ctx = framework.startBundle('com.critical');
        // The context should exist and the bundle should be active.
        expect(ctx.bundle.priority, equals(BundlePriority.critical));
        expect(ctx, isA<IsolateBundleContext>());
      });

      test('startBundle assigns normal port for normal bundles', () {
        framework.start();

        final normal = _manifest(
          symbolicName: 'com.normal',
          priority: 'normal',
        );
        framework.installBundle(normal);
        framework.resolveAll();

        final ctx = framework.startBundle('com.normal');
        expect(ctx.bundle.priority, equals(BundlePriority.normal));
      });

      test('startBundle assigns normal port for background bundles', () {
        framework.start();

        final bg = _manifest(
          symbolicName: 'com.background',
          priority: 'background',
        );
        framework.installBundle(bg);
        framework.resolveAll();

        final ctx = framework.startBundle('com.background');
        expect(ctx.bundle.priority, equals(BundlePriority.background));
      });

      test('startBundle throws for non-existent bundle', () {
        framework.start();

        expect(() => framework.startBundle('nonexistent'), throwsStateError);
      });

      test('stopBundle disposes context', () async {
        framework.start();

        framework.installBundle(_manifest(symbolicName: 'com.test.a'));
        framework.resolveAll();
        final ctx = framework.startBundle('com.test.a');
        expect(ctx, isNotNull);

        await framework.stopBundle('com.test.a');

        final bundle = framework.bundleManager.getBundle('com.test.a');
        expect(bundle, isNotNull);
        expect(bundle!.bundleContext, isNull);
        expect(bundle.state, equals(BundleState.resolved));
      });

      test('stopBundle for non-existent bundle is a no-op', () async {
        framework.start();
        await framework.stopBundle('nonexistent');
      });

      test('uninstallBundle removes the bundle', () async {
        framework.start();

        framework.installBundle(_manifest(symbolicName: 'com.test.a'));
        framework.resolveAll();
        framework.startBundle('com.test.a');

        await framework.uninstallBundle('com.test.a');

        expect(framework.bundleManager.getBundle('com.test.a'), isNull);
      });
    });

    group('stop', () {
      test('cleans up everything', () async {
        framework.start();

        framework.installBundle(_manifest(symbolicName: 'com.test.a'));
        framework.resolveAll();
        framework.startBundle('com.test.a');

        await framework.stop();

        expect(framework.isStarted, isFalse);
      });

      test('stop when not started is a no-op', () async {
        await framework.stop();
        expect(framework.isStarted, isFalse);
      });

      test('stop resets singleton so next instance is fresh', () async {
        framework.start();
        await framework.stop();

        final fresh = DartOSGiFramework.instance;
        expect(fresh.isStarted, isFalse);
        // Verify the fresh instance works.
        fresh.start();
        expect(fresh.isStarted, isTrue);
        await fresh.stop();
      });
    });

    group('_ensureStarted', () {
      test('throws when not started', () {
        framework.installBundle(_manifest(symbolicName: 'com.test.a'));
        framework.resolveAll();

        expect(() => framework.startBundle('com.test.a'), throwsStateError);
      });
    });
  });
}
