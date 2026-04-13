import 'dart:async';
import 'dart:isolate';

import 'package:dart_osgi_framework/dart_osgi_framework.dart';
import 'package:test/test.dart';

/// Helper to create a BundleManifest for testing.
BundleManifest _testManifest({
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
  late ServiceRegistry registry;
  late IsolateBus bus;
  late ManagedBundle managedBundle;
  late IsolateBundleContext context;
  late ReceivePort frameworkRp;
  late StreamController<BundleEvent> bundleEventCtrl;
  late StreamController<ServiceEvent> serviceEventCtrl;

  setUp(() {
    registry = ServiceRegistry();
    bus = IsolateBus();
    managedBundle = ManagedBundle(_testManifest());
    frameworkRp = ReceivePort();
    bundleEventCtrl = StreamController<BundleEvent>.broadcast();
    serviceEventCtrl = StreamController<ServiceEvent>.broadcast();

    context = IsolateBundleContext(
      managedBundle: managedBundle,
      registry: registry,
      bus: bus,
      frameworkPort: frameworkRp.sendPort,
      bundleEvents: bundleEventCtrl.stream,
      serviceEvents: serviceEventCtrl.stream,
    );
  });

  tearDown(() async {
    // Dispose context if not already disposed.
    try {
      await context.dispose();
    } catch (_) {}
    frameworkRp.close();
    await bundleEventCtrl.close();
    await serviceEventCtrl.close();
    bus.dispose();
    registry.dispose();
  });

  group('IsolateBundleContext', () {
    test('bundle getter returns managedBundle', () {
      expect(context.bundle, same(managedBundle));
      expect(context.bundle.symbolicName, equals('com.test.bundle'));
    });

    group('service registration', () {
      test('registerService delegates to registry and tracks registration', () {
        final reg = context.registerService<String>(
          'MyService',
          'service-impl',
          {'key': 'value'},
        );

        expect(reg, isNotNull);
        expect(reg.reference.bundleSymbolicName, equals('com.test.bundle'));

        // Should be findable in the registry.
        final ref = registry.getServiceReference<String>('MyService');
        expect(ref, isNotNull);
        expect(ref!.getProperty('key'), equals('value'));
      });

      test('registerService with null properties', () {
        final reg = context.registerService<String>(
          'MyService',
          'service-impl',
          null,
        );

        expect(reg, isNotNull);
        final ref = registry.getServiceReference<String>('MyService');
        expect(ref, isNotNull);
      });
    });

    group('service lookup', () {
      test('getServiceReference delegates', () {
        context.registerService<String>('MyService', 'impl', null);

        final ref = context.getServiceReference<String>('MyService');
        expect(ref, isNotNull);
        expect(ref!.getProperty('objectClass'), equals('MyService'));
      });

      test('getServiceReference returns null for unknown service', () {
        final ref = context.getServiceReference<String>('Unknown');
        expect(ref, isNull);
      });

      test('getServiceReferences delegates', () {
        context.registerService<String>('MyService', 'impl1', null);
        context.registerService<String>('MyService', 'impl2', null);

        final refs = context.getServiceReferences<String>('MyService', null);
        expect(refs, hasLength(2));
      });

      test('getServiceReferences with filter', () {
        context.registerService<String>('MyService', 'impl1', {'env': 'prod'});
        context.registerService<String>('MyService', 'impl2', {'env': 'dev'});

        final refs = context.getServiceReferences<String>(
          'MyService',
          '(env=prod)',
        );
        expect(refs, hasLength(1));
      });

      test('getService delegates', () {
        context.registerService<String>('MyService', 'the-impl', null);

        final ref = context.getServiceReference<String>('MyService');
        final svc = context.getService<String>(ref!);
        expect(svc, equals('the-impl'));
      });

      test('ungetService returns true', () {
        context.registerService<String>('MyService', 'the-impl', null);

        final ref = context.getServiceReference<String>('MyService');
        expect(context.ungetService<String>(ref!), isTrue);
      });
    });

    group('service tracking', () {
      test('trackService creates tracker', () {
        final tracker = context.trackService<String>('MyService');
        expect(tracker, isNotNull);
        expect(tracker, isA<ServiceTracker<String>>());
      });

      test('trackService with filter', () {
        final tracker = context.trackService<String>(
          'MyService',
          filter: '(env=prod)',
        );
        expect(tracker, isNotNull);
      });
    });

    group('bundle listeners', () {
      test('addBundleListener receives events', () async {
        final events = <BundleEvent>[];
        context.addBundleListener(events.add);

        bundleEventCtrl.add(
          BundleEvent(BundleEventType.started, managedBundle),
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(events, hasLength(1));
        expect(events.first.type, equals(BundleEventType.started));
      });

      test(
        'addBundleListener twice with same listener is idempotent',
        () async {
          final events = <BundleEvent>[];
          void listener(BundleEvent e) => events.add(e);

          context.addBundleListener(listener);
          context.addBundleListener(listener);

          bundleEventCtrl.add(
            BundleEvent(BundleEventType.started, managedBundle),
          );

          await Future<void>.delayed(const Duration(milliseconds: 20));
          // Only one subscription, so only one event.
          expect(events, hasLength(1));
        },
      );

      test('removeBundleListener stops receiving events', () async {
        final events = <BundleEvent>[];
        void listener(BundleEvent e) => events.add(e);

        context.addBundleListener(listener);
        context.removeBundleListener(listener);

        bundleEventCtrl.add(
          BundleEvent(BundleEventType.started, managedBundle),
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(events, isEmpty);
      });

      test('removeBundleListener for non-existent listener is a no-op', () {
        context.removeBundleListener((_) {});
      });
    });

    group('service listeners', () {
      test('addServiceListener receives events', () async {
        final events = <ServiceEvent>[];
        context.addServiceListener(events.add);

        // Register a service to trigger an event via the registry.
        final reg = registry.register<String>(
          'SomeService',
          'impl',
          'com.other',
          null,
        );

        serviceEventCtrl.add(
          ServiceEvent(
            ServiceEventType.registered,
            reg.reference as ServiceReference<Object>,
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(events, hasLength(1));
      });

      test('addServiceListener with LDAP filter', () async {
        final events = <ServiceEvent>[];
        context.addServiceListener(events.add, filter: '(env=prod)');

        // Create a reference with matching properties.
        final regMatch = registry.register<String>(
          'Svc',
          'impl1',
          'com.other',
          {'env': 'prod'},
        );

        final regNoMatch = registry.register<String>(
          'Svc2',
          'impl2',
          'com.other',
          {'env': 'dev'},
        );

        serviceEventCtrl.add(
          ServiceEvent(
            ServiceEventType.registered,
            regMatch.reference as ServiceReference<Object>,
          ),
        );
        serviceEventCtrl.add(
          ServiceEvent(
            ServiceEventType.registered,
            regNoMatch.reference as ServiceReference<Object>,
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));
        // Only the matching event should pass through.
        expect(events, hasLength(1));
      });

      test('removeServiceListener stops receiving events', () async {
        final events = <ServiceEvent>[];
        void listener(ServiceEvent e) => events.add(e);

        context.addServiceListener(listener);
        context.removeServiceListener(listener);

        final reg = registry.register<String>('Svc', 'impl', 'com.other', null);

        serviceEventCtrl.add(
          ServiceEvent(
            ServiceEventType.registered,
            reg.reference as ServiceReference<Object>,
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(events, isEmpty);
      });

      test('removeServiceListener for non-existent listener is a no-op', () {
        context.removeServiceListener((_) {});
      });
    });

    group('bus convenience', () {
      test('sendToBundle delegates to bus', () async {
        final rp = ReceivePort();
        addTearDown(rp.close);

        bus.registerPort('com.target', rp.sendPort);

        final future = rp.first;
        final result = context.sendToBundle('com.target', 'hello');

        expect(result, isTrue);
        expect(await future, equals('hello'));
      });

      test('sendToBundle returns false for unknown bundle', () {
        final result = context.sendToBundle('nonexistent', 'hello');
        expect(result, isFalse);
      });
    });

    group('dispose', () {
      test('unregisters all services', () async {
        context.registerService<String>('Svc1', 'impl1', null);
        context.registerService<String>('Svc2', 'impl2', null);

        await context.dispose();

        expect(registry.getServiceReference<String>('Svc1'), isNull);
        expect(registry.getServiceReference<String>('Svc2'), isNull);
      });

      test('closes trackers', () async {
        final tracker = context.trackService<String>('MyService');
        await tracker.open();

        await context.dispose();
        // After close, the tracker streams should be done.
      });

      test('cancels bundle listeners', () async {
        final events = <BundleEvent>[];
        context.addBundleListener(events.add);

        await context.dispose();

        bundleEventCtrl.add(
          BundleEvent(BundleEventType.stopped, managedBundle),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(events, isEmpty);
      });

      test('cancels service listeners', () async {
        final events = <ServiceEvent>[];
        context.addServiceListener(events.add);

        await context.dispose();

        // Events after dispose should not reach the listener.
      });

      test('dispose twice is safe', () async {
        await context.dispose();
        await context.dispose();
      });
    });

    group('_checkDisposed', () {
      test('throws StateError after dispose', () async {
        await context.dispose();

        expect(
          () => context.registerService<String>('Svc', 'impl', null),
          throwsStateError,
        );
        expect(
          () => context.getServiceReference<String>('Svc'),
          throwsStateError,
        );
        expect(
          () => context.getServiceReferences<String>('Svc', null),
          throwsStateError,
        );
        expect(() => context.trackService<String>('Svc'), throwsStateError);
        expect(() => context.sendToBundle('target', 'msg'), throwsStateError);
        expect(() => context.addBundleListener((_) {}), throwsStateError);
        expect(() => context.addServiceListener((_) {}), throwsStateError);
      });

      test('getService throws after dispose', () async {
        final reg = context.registerService<String>('Svc', 'impl', null);
        final ref = reg.reference;
        await context.dispose();

        expect(() => context.getService<String>(ref), throwsStateError);
      });

      test('ungetService throws after dispose', () async {
        final reg = context.registerService<String>('Svc', 'impl', null);
        final ref = reg.reference;
        await context.dispose();

        expect(() => context.ungetService<String>(ref), throwsStateError);
      });
    });
  });
}
