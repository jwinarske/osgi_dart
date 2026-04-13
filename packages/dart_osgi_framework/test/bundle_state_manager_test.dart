import 'dart:async';

import 'package:dart_osgi_framework/dart_osgi_framework.dart';
import 'package:test/test.dart';

/// Minimal Bundle stub for testing the state manager.
class _TestBundle implements Bundle {
  _TestBundle(this.symbolicName);

  @override
  final String symbolicName;

  @override
  String get version => '1.0.0';

  @override
  BundleState get state => BundleState.installed;

  @override
  Map<String, Object> get headers => {};

  @override
  BundleContext? get bundleContext => null;

  @override
  BundlePriority get priority => BundlePriority.normal;
}

void main() {
  late BundleStateManager manager;
  late _TestBundle bundle;

  setUp(() {
    bundle = _TestBundle('com.test');
    manager = BundleStateManager(bundle);
  });

  tearDown(() {
    manager.dispose();
  });

  group('BundleStateManager', () {
    test('initial state is installed', () {
      expect(manager.state, BundleState.installed);
    });

    group('valid transitions', () {
      test('installed -> resolved', () {
        manager.transition(BundleState.resolved);
        expect(manager.state, BundleState.resolved);
      });

      test('installed -> uninstalled', () {
        manager.transition(BundleState.uninstalled);
        expect(manager.state, BundleState.uninstalled);
      });

      test('resolved -> starting', () {
        manager.transition(BundleState.resolved);
        manager.transition(BundleState.starting);
        expect(manager.state, BundleState.starting);
      });

      test('resolved -> uninstalled', () {
        manager.transition(BundleState.resolved);
        manager.transition(BundleState.uninstalled);
        expect(manager.state, BundleState.uninstalled);
      });

      test('starting -> active', () {
        manager.transition(BundleState.resolved);
        manager.transition(BundleState.starting);
        manager.transition(BundleState.active);
        expect(manager.state, BundleState.active);
      });

      test('starting -> stopping (activation failure)', () {
        manager.transition(BundleState.resolved);
        manager.transition(BundleState.starting);
        manager.transition(BundleState.stopping);
        expect(manager.state, BundleState.stopping);
      });

      test('active -> stopping', () {
        manager.transition(BundleState.resolved);
        manager.transition(BundleState.starting);
        manager.transition(BundleState.active);
        manager.transition(BundleState.stopping);
        expect(manager.state, BundleState.stopping);
      });

      test('stopping -> resolved (restartable)', () {
        manager.transition(BundleState.resolved);
        manager.transition(BundleState.starting);
        manager.transition(BundleState.active);
        manager.transition(BundleState.stopping);
        manager.transition(BundleState.resolved);
        expect(manager.state, BundleState.resolved);
      });

      test('stopping -> uninstalled (terminal)', () {
        manager.transition(BundleState.resolved);
        manager.transition(BundleState.starting);
        manager.transition(BundleState.active);
        manager.transition(BundleState.stopping);
        manager.transition(BundleState.uninstalled);
        expect(manager.state, BundleState.uninstalled);
      });

      test(
        'full lifecycle: installed -> resolved -> starting -> active -> stopping -> resolved',
        () {
          manager.transition(BundleState.resolved);
          manager.transition(BundleState.starting);
          manager.transition(BundleState.active);
          manager.transition(BundleState.stopping);
          manager.transition(BundleState.resolved);
          expect(manager.state, BundleState.resolved);
        },
      );
    });

    group('invalid transitions', () {
      test('installed -> active throws', () {
        expect(
          () => manager.transition(BundleState.active),
          throwsA(isA<InvalidTransitionException>()),
        );
      });

      test('installed -> starting throws', () {
        expect(
          () => manager.transition(BundleState.starting),
          throwsA(isA<InvalidTransitionException>()),
        );
      });

      test('installed -> stopping throws', () {
        expect(
          () => manager.transition(BundleState.stopping),
          throwsA(isA<InvalidTransitionException>()),
        );
      });

      test('active -> installed throws', () {
        manager.transition(BundleState.resolved);
        manager.transition(BundleState.starting);
        manager.transition(BundleState.active);
        expect(
          () => manager.transition(BundleState.installed),
          throwsA(isA<InvalidTransitionException>()),
        );
      });

      test('active -> resolved throws', () {
        manager.transition(BundleState.resolved);
        manager.transition(BundleState.starting);
        manager.transition(BundleState.active);
        expect(
          () => manager.transition(BundleState.resolved),
          throwsA(isA<InvalidTransitionException>()),
        );
      });

      test('uninstalled -> any throws', () {
        manager.transition(BundleState.uninstalled);
        for (final target in BundleState.values) {
          expect(
            () => manager.transition(target),
            throwsA(isA<InvalidTransitionException>()),
            reason: 'uninstalled -> $target should be invalid',
          );
        }
      });

      test('resolved -> active throws (must go through starting)', () {
        manager.transition(BundleState.resolved);
        expect(
          () => manager.transition(BundleState.active),
          throwsA(isA<InvalidTransitionException>()),
        );
      });
    });

    group('events', () {
      test('resolved event emitted on installed -> resolved', () async {
        final events = <BundleEvent>[];
        manager.events.listen(events.add);

        manager.transition(BundleState.resolved);
        await Future<void>.delayed(Duration.zero);

        expect(events, hasLength(1));
        expect(events.first.type, BundleEventType.resolved);
        expect(events.first.bundle, same(bundle));
      });

      test('starting event emitted', () async {
        final events = <BundleEvent>[];
        manager.events.listen(events.add);

        manager.transition(BundleState.resolved);
        manager.transition(BundleState.starting);
        await Future<void>.delayed(Duration.zero);

        expect(events[1].type, BundleEventType.starting);
      });

      test('started event emitted on starting -> active', () async {
        final events = <BundleEvent>[];
        manager.events.listen(events.add);

        manager.transition(BundleState.resolved);
        manager.transition(BundleState.starting);
        manager.transition(BundleState.active);
        await Future<void>.delayed(Duration.zero);

        expect(events[2].type, BundleEventType.started);
      });

      test('stopping event emitted', () async {
        final events = <BundleEvent>[];
        manager.events.listen(events.add);

        manager.transition(BundleState.resolved);
        manager.transition(BundleState.starting);
        manager.transition(BundleState.active);
        manager.transition(BundleState.stopping);
        await Future<void>.delayed(Duration.zero);

        expect(events[3].type, BundleEventType.stopping);
      });

      test('uninstalled event emitted', () async {
        final events = <BundleEvent>[];
        manager.events.listen(events.add);

        manager.transition(BundleState.uninstalled);
        await Future<void>.delayed(Duration.zero);

        expect(events.first.type, BundleEventType.uninstalled);
      });

      test('resolved event emitted on stopping -> resolved', () async {
        final events = <BundleEvent>[];
        manager.events.listen(events.add);

        manager.transition(BundleState.resolved);
        manager.transition(BundleState.starting);
        manager.transition(BundleState.active);
        manager.transition(BundleState.stopping);
        manager.transition(BundleState.resolved);
        await Future<void>.delayed(Duration.zero);

        // Last event should be resolved.
        expect(events.last.type, BundleEventType.resolved);
      });

      test('full lifecycle emits correct event sequence', () async {
        final types = <BundleEventType>[];
        manager.events.listen((e) => types.add(e.type));

        manager.transition(BundleState.resolved);
        manager.transition(BundleState.starting);
        manager.transition(BundleState.active);
        manager.transition(BundleState.stopping);
        manager.transition(BundleState.uninstalled);
        await Future<void>.delayed(Duration.zero);

        expect(types, [
          BundleEventType.resolved,
          BundleEventType.starting,
          BundleEventType.started,
          BundleEventType.stopping,
          BundleEventType.uninstalled,
        ]);
      });
    });

    test('dispose() closes the event stream', () async {
      manager.dispose();
      // After dispose, the stream should be done.
      final done = Completer<void>();
      manager.events.listen(null, onDone: done.complete);
      await done.future;
    });

    group('isValidTransition static method', () {
      test('installed -> resolved is valid', () {
        expect(
          BundleStateManager.isValidTransition(
            BundleState.installed,
            BundleState.resolved,
          ),
          isTrue,
        );
      });

      test('installed -> active is invalid', () {
        expect(
          BundleStateManager.isValidTransition(
            BundleState.installed,
            BundleState.active,
          ),
          isFalse,
        );
      });

      test('starting -> active is valid', () {
        expect(
          BundleStateManager.isValidTransition(
            BundleState.starting,
            BundleState.active,
          ),
          isTrue,
        );
      });

      test('starting -> stopping is valid', () {
        expect(
          BundleStateManager.isValidTransition(
            BundleState.starting,
            BundleState.stopping,
          ),
          isTrue,
        );
      });

      test('active -> stopping is valid', () {
        expect(
          BundleStateManager.isValidTransition(
            BundleState.active,
            BundleState.stopping,
          ),
          isTrue,
        );
      });

      test('stopping -> resolved is valid', () {
        expect(
          BundleStateManager.isValidTransition(
            BundleState.stopping,
            BundleState.resolved,
          ),
          isTrue,
        );
      });

      test('stopping -> uninstalled is valid', () {
        expect(
          BundleStateManager.isValidTransition(
            BundleState.stopping,
            BundleState.uninstalled,
          ),
          isTrue,
        );
      });

      test('uninstalled -> anything is invalid', () {
        for (final target in BundleState.values) {
          expect(
            BundleStateManager.isValidTransition(
              BundleState.uninstalled,
              target,
            ),
            isFalse,
            reason: 'uninstalled -> $target should be invalid',
          );
        }
      });
    });
  });

  group('InvalidTransitionException', () {
    test('toString includes bundle name, from, and to states', () {
      final ex = InvalidTransitionException(
        'com.test',
        BundleState.installed,
        BundleState.active,
      );
      final str = ex.toString();
      expect(str, contains('com.test'));
      expect(str, contains('installed'));
      expect(str, contains('active'));
      expect(str, contains('InvalidTransitionException'));
    });

    test('fields are accessible', () {
      final ex = InvalidTransitionException(
        'bundle.name',
        BundleState.active,
        BundleState.installed,
      );
      expect(ex.symbolicName, 'bundle.name');
      expect(ex.from, BundleState.active);
      expect(ex.to, BundleState.installed);
    });
  });
}
