import 'dart:async';

import 'package:osgi_framework/osgi_framework.dart';
import 'package:test/test.dart';

void main() {
  group('ranking', () {
    test('higher ranking wins regardless of registration order', () {
      final ServiceRegistry registry = ServiceRegistry();
      registry.register('Nav', 'default');
      registry.register('Nav', 'override', <String, Object?>{
        'service.ranking': 10,
      });

      expect(registry.getService('Nav'), 'override');
    });

    test('equal ranking resolves oldest first, not by start order luck', () {
      // The whole reason the tie-break exists: without it, which navigation
      // implementation a bundle gets depends on which activator finished
      // sooner, which is not a property anyone controls.
      final ServiceRegistry registry = ServiceRegistry();
      registry.register('Nav', 'first');
      registry.register('Nav', 'second');

      expect(registry.getService('Nav'), 'first');
      expect(registry.getServices('Nav'), <String>['first', 'second']);
    });

    test('unregistering the winner falls back to the next', () {
      final ServiceRegistry registry = ServiceRegistry();
      final ServiceRegistration fallback = registry.register('Nav', 'default');
      final ServiceRegistration winner = registry.register(
        'Nav',
        'override',
        <String, Object?>{'service.ranking': 10},
      );

      expect(registry.getService('Nav'), 'override');
      winner.unregister();
      expect(registry.getService('Nav'), 'default');
      fallback.unregister();
      expect(registry.getService('Nav'), isNull);
    });

    test('unregister twice is not an error', () {
      // stop() runs on the failed-start path too, where it cannot know how far
      // start() got.
      final ServiceRegistry registry = ServiceRegistry();
      final ServiceRegistration reg = registry.register('Nav', 'x');
      reg.unregister();
      expect(reg.unregister, returnsNormally);
      expect(registry.getService('Nav'), isNull);
    });
  });

  group('properties', () {
    test('mutating the caller map does not reach the registry', () {
      final ServiceRegistry registry = ServiceRegistry();
      final Map<String, Object?> props = <String, Object?>{'zone': 'front'};
      registry.register('Display', 'd', props);

      props['zone'] = 'rear';

      expect(registry.getService('Display', filter: '(zone=front)'), 'd');
      expect(registry.getService('Display', filter: '(zone=rear)'), isNull);
    });

    test('compound filters narrow by several properties', () {
      final ServiceRegistry registry = ServiceRegistry();
      registry.register('Display', 'front-hd', <String, Object?>{
        'zone': 'front',
        'height': 1080,
      });
      registry.register('Display', 'front-sd', <String, Object?>{
        'zone': 'front',
        'height': 480,
      });
      registry.register('Display', 'rear', <String, Object?>{
        'zone': 'rear',
        'height': 1080,
      });

      expect(
        registry.getServices('Display', filter: '(&(zone=front)(height>=720))'),
        <String>['front-hd'],
      );
      expect(
        registry.getServices('Display', filter: '(!(zone=front))'),
        <String>['rear'],
      );
      expect(registry.getServices('Display', filter: '(zone=*)'), hasLength(3));
    });

    test('a malformed filter throws rather than matching nothing', () {
      // Matching nothing is safe but silent: the bundle would simply never
      // find its service. Throwing puts the mistake where it was made.
      final ServiceRegistry registry = ServiceRegistry();
      registry.register('Nav', 'x', <String, Object?>{'zone': 'front'});

      expect(
        () => registry.getService('Nav', filter: 'zone=front'),
        throwsFormatException,
      );
      expect(
        () => registry.getServices('Nav', filter: '(zone=front'),
        throwsFormatException,
      );
      expect(
        () => registry.track('Nav', filter: '(zone~=front)'),
        throwsFormatException,
      );
    });

    test('an unsupported substring pattern narrows, never widens', () {
      final ServiceRegistry registry = ServiceRegistry();
      registry.register('Nav', 'x', <String, Object?>{'zone': 'front'});

      expect(registry.getService('Nav', filter: '(zone=fr*)'), isNull);
    });
  });

  group('trackers', () {
    test('a tracker opened late still sees existing services', () async {
      // Otherwise what a tracker sees depends on bundle start order.
      final ServiceRegistry registry = ServiceRegistry();
      registry.register('Nav', 'already-there');

      final ServiceTracker tracker = registry.track('Nav');
      final Future<List<Object?>> seen = tracker.addingService.take(1).toList();
      await tracker.open();

      expect(await seen, <String>['already-there']);
      await tracker.close();
    });

    test('later registrations and removals are delivered', () async {
      final ServiceRegistry registry = ServiceRegistry();
      final ServiceTracker tracker = registry.track('Nav');
      await tracker.open();

      final Future<Object?> added = tracker.addingService.first;
      final ServiceRegistration reg = registry.register('Nav', 'late');
      expect(await added, 'late');

      final Future<Object?> removed = tracker.removedService.first;
      await reg.unregister();
      expect(await removed, 'late');

      await tracker.close();
    });

    test('a filtered tracker ignores non-matching services', () async {
      final ServiceRegistry registry = ServiceRegistry();
      final ServiceTracker tracker = registry.track(
        'Display',
        filter: '(zone=rear)',
      );
      await tracker.open();

      final List<Object?> seen = <Object?>[];
      final subscription = tracker.addingService.listen(seen.add);

      registry.register('Display', 'front', <String, Object?>{'zone': 'front'});
      registry.register('Display', 'rear', <String, Object?>{'zone': 'rear'});
      await Future<void>.delayed(Duration.zero);

      expect(seen, <String>['rear']);
      await subscription.cancel();
      await tracker.close();
    });

    test('a closed tracker stops receiving', () async {
      final ServiceRegistry registry = ServiceRegistry();
      final ServiceTracker tracker = registry.track('Nav');
      await tracker.open();
      await tracker.close();

      // Registering after close must not throw on a closed StreamController.
      expect(() => registry.register('Nav', 'x'), returnsNormally);
    });

    test(
      'a listener attached after an awaited open() sees existing services',
      () async {
        // The natural way to write it. A replay delivered only to whoever was
        // listening during open() would hand the services to nobody.
        final ServiceRegistry registry = ServiceRegistry();
        registry.register('Nav', 'already-there');
        final ServiceTracker tracker = registry.track('Nav');
        await tracker.open();

        expect(await tracker.addingService.first, 'already-there');
        await tracker.close();
      },
    );

    test(
      'a service removed right after open() is not left looking present',
      () async {
        final ServiceRegistry registry = ServiceRegistry();
        final ServiceRegistration reg = registry.register('Nav', 'x');
        final ServiceTracker tracker = registry.track('Nav');
        final List<String> log = <String>[];
        tracker.addingService.listen((Object? s) => log.add('+$s'));
        tracker.removedService.listen((Object? s) => log.add('-$s'));

        unawaited(tracker.open());
        await reg.unregister();
        await Future<void>.delayed(Duration.zero);

        // Ending on '+x' would leave the consumer holding a service that is gone.
        expect(log, <String>['+x', '-x']);
        await tracker.close();
      },
    );

    test('each listener gets its own replay', () async {
      final ServiceRegistry registry = ServiceRegistry();
      registry.register('Nav', 'x');
      final ServiceTracker tracker = registry.track('Nav');
      await tracker.open();

      expect(await tracker.addingService.first, 'x');
      expect(await tracker.addingService.first, 'x');
      await tracker.close();
    });
  });
}
