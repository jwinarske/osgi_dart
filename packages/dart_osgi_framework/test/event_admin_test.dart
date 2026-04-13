import 'dart:async';

import 'package:dart_osgi_framework/dart_osgi_framework.dart';
import 'package:test/test.dart';

/// Minimal Bundle implementation for testing wireBundleEvents.
class _TestBundle implements Bundle {
  _TestBundle({required this.symbolicName, this.state = BundleState.active})
    : version = '1.0.0';

  @override
  final String symbolicName;

  @override
  final String version;

  @override
  final BundleState state;

  @override
  Map<String, Object> get headers => const {};

  @override
  BundleContext? get bundleContext => null;

  @override
  BundlePriority get priority => BundlePriority.normal;
}

void main() {
  late EventAdmin eventAdmin;

  setUp(() {
    eventAdmin = EventAdmin();
  });

  tearDown(() {
    eventAdmin.dispose();
  });

  group('EventAdmin', () {
    group('post()', () {
      test('delivers event to matching subscriber', () async {
        final events = <Event>[];
        eventAdmin.subscribe('com/ivi/can/THRESHOLD').listen(events.add);

        eventAdmin.post('com/ivi/can/THRESHOLD', {'value': 42});

        // Allow stream delivery.
        await Future<void>.delayed(Duration.zero);

        expect(events, hasLength(1));
        expect(events[0].topic, 'com/ivi/can/THRESHOLD');
        expect(events[0].property<int>('value'), 42);
      });

      test('does not deliver to non-matching subscriber', () async {
        final events = <Event>[];
        eventAdmin.subscribe('com/ivi/sensor/TEMP').listen(events.add);

        eventAdmin.post('com/ivi/can/THRESHOLD');

        await Future<void>.delayed(Duration.zero);

        expect(events, isEmpty);
      });

      test('uses empty properties by default', () async {
        final events = <Event>[];
        eventAdmin.subscribe('com/ivi/test').listen(events.add);

        eventAdmin.post('com/ivi/test');

        await Future<void>.delayed(Duration.zero);

        expect(events, hasLength(1));
        expect(events[0].properties, isEmpty);
      });
    });

    group('postEvent()', () {
      test('delivers pre-built Event to matching subscriber', () async {
        final events = <Event>[];
        eventAdmin.subscribe('com/ivi/test').listen(events.add);

        final event = Event('com/ivi/test', {'key': 'value'});
        eventAdmin.postEvent(event);

        await Future<void>.delayed(Duration.zero);

        expect(events, hasLength(1));
        expect(identical(events[0], event), isTrue);
      });
    });

    group('subscribe()', () {
      test('exact topic subscription', () async {
        final events = <Event>[];
        eventAdmin.subscribe('com/ivi/can/X').listen(events.add);

        eventAdmin.post('com/ivi/can/X');
        eventAdmin.post('com/ivi/can/Y');

        await Future<void>.delayed(Duration.zero);

        expect(events, hasLength(1));
        expect(events[0].topic, 'com/ivi/can/X');
      });

      test('wildcard subscription', () async {
        final events = <Event>[];
        eventAdmin.subscribe('com/ivi/can/*').listen(events.add);

        eventAdmin.post('com/ivi/can/X');
        eventAdmin.post('com/ivi/can/Y');
        eventAdmin.post('com/ivi/sensor/Z');

        await Future<void>.delayed(Duration.zero);

        expect(events, hasLength(2));
        expect(events[0].topic, 'com/ivi/can/X');
        expect(events[1].topic, 'com/ivi/can/Y');
      });

      test('multiple subscribers receive same event', () async {
        final eventsA = <Event>[];
        final eventsB = <Event>[];
        eventAdmin.subscribe('com/ivi/can/*').listen(eventsA.add);
        eventAdmin.subscribe('com/ivi/can/*').listen(eventsB.add);

        eventAdmin.post('com/ivi/can/X');

        await Future<void>.delayed(Duration.zero);

        expect(eventsA, hasLength(1));
        expect(eventsB, hasLength(1));
      });

      test('multiple subscribers with different filters', () async {
        final canEvents = <Event>[];
        final sensorEvents = <Event>[];
        eventAdmin.subscribe('com/ivi/can/*').listen(canEvents.add);
        eventAdmin.subscribe('com/ivi/sensor/*').listen(sensorEvents.add);

        eventAdmin.post('com/ivi/can/X');
        eventAdmin.post('com/ivi/sensor/TEMP');

        await Future<void>.delayed(Duration.zero);

        expect(canEvents, hasLength(1));
        expect(canEvents[0].topic, 'com/ivi/can/X');
        expect(sensorEvents, hasLength(1));
        expect(sensorEvents[0].topic, 'com/ivi/sensor/TEMP');
      });
    });

    group('subscription cancel', () {
      test('cancel removes listener', () async {
        final events = <Event>[];
        final sub = eventAdmin.subscribe('com/ivi/test').listen(events.add);

        eventAdmin.post('com/ivi/test');
        await Future<void>.delayed(Duration.zero);
        expect(events, hasLength(1));

        await sub.cancel();

        eventAdmin.post('com/ivi/test');
        await Future<void>.delayed(Duration.zero);
        expect(events, hasLength(1)); // No new events after cancel.
      });
    });

    group('registerIn()', () {
      test('registers EventAdmin as OSGi service', () {
        final registry = ServiceRegistry();
        final reg = eventAdmin.registerIn(registry, 'com.test.bundle');

        expect(reg, isNotNull);
        expect(reg.reference, isNotNull);

        final ref = registry.getServiceReference<EventAdmin>(
          EventAdmin.serviceName,
        );
        expect(ref, isNotNull);

        final service = registry.getService<EventAdmin>(ref!);
        expect(service, same(eventAdmin));
      });
    });

    group('wireBundleEvents()', () {
      test('posts STARTED topic for started event', () async {
        final events = <Event>[];
        eventAdmin.subscribe('com/ivi/bundle/*').listen(events.add);

        final bundleEvents = StreamController<BundleEvent>();
        eventAdmin.wireBundleEvents(bundleEvents.stream);

        bundleEvents.add(
          BundleEvent(
            BundleEventType.started,
            _TestBundle(symbolicName: 'com.test', state: BundleState.active),
          ),
        );

        await Future<void>.delayed(Duration.zero);

        expect(events, hasLength(1));
        expect(events[0].topic, Topics.bundleStarted);
        expect(events[0].property<String>('bundle.symbolicName'), 'com.test');
        expect(events[0].property<String>('bundle.version'), '1.0.0');
        expect(events[0].property<String>('bundle.state'), 'active');

        await bundleEvents.close();
      });

      test('posts STOPPED topic for stopped event', () async {
        final events = <Event>[];
        eventAdmin.subscribe(Topics.bundleStopped).listen(events.add);

        final bundleEvents = StreamController<BundleEvent>();
        eventAdmin.wireBundleEvents(bundleEvents.stream);

        bundleEvents.add(
          BundleEvent(
            BundleEventType.stopped,
            _TestBundle(
              symbolicName: 'com.stopped',
              state: BundleState.uninstalled,
            ),
          ),
        );

        await Future<void>.delayed(Duration.zero);

        expect(events, hasLength(1));
        expect(events[0].topic, Topics.bundleStopped);

        await bundleEvents.close();
      });

      test('posts UPDATED topic for updated event', () async {
        final events = <Event>[];
        eventAdmin.subscribe(Topics.bundleUpdated).listen(events.add);

        final bundleEvents = StreamController<BundleEvent>();
        eventAdmin.wireBundleEvents(bundleEvents.stream);

        bundleEvents.add(
          BundleEvent(
            BundleEventType.updated,
            _TestBundle(symbolicName: 'com.updated'),
          ),
        );

        await Future<void>.delayed(Duration.zero);

        expect(events, hasLength(1));
        expect(events[0].topic, Topics.bundleUpdated);

        await bundleEvents.close();
      });

      test('ignores other event types', () async {
        final events = <Event>[];
        eventAdmin.subscribe('com/ivi/bundle/*').listen(events.add);

        final bundleEvents = StreamController<BundleEvent>();
        eventAdmin.wireBundleEvents(bundleEvents.stream);

        for (final type in [
          BundleEventType.installed,
          BundleEventType.resolved,
          BundleEventType.starting,
          BundleEventType.stopping,
          BundleEventType.unresolved,
          BundleEventType.uninstalled,
        ]) {
          bundleEvents.add(
            BundleEvent(type, _TestBundle(symbolicName: 'com.test')),
          );
        }

        await Future<void>.delayed(Duration.zero);

        expect(events, isEmpty);

        await bundleEvents.close();
      });
    });

    group('dispose()', () {
      test('closes all streams', () async {
        final events = <Event>[];
        var done = false;
        eventAdmin
            .subscribe('com/ivi/test')
            .listen(events.add, onDone: () => done = true);

        eventAdmin.dispose();

        await Future<void>.delayed(Duration.zero);

        expect(done, isTrue);
      });
    });

    test('serviceName constant', () {
      expect(EventAdmin.serviceName, 'org.osgi.service.event.EventAdmin');
    });
  });
}
