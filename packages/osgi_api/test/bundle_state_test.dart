import 'package:osgi_api/osgi_api.dart';
import 'package:test/test.dart';

void main() {
  group('fromValue', () {
    test('round-trips every state', () {
      for (final BundleState state in BundleState.values) {
        expect(BundleState.fromValue(state.value), state);
      }
    });

    test('rejects a value the shell would never send', () {
      expect(() => BundleState.fromValue(0), throwsArgumentError);
      expect(() => BundleState.fromValue(0x40), throwsArgumentError);
    });
  });

  group('transitions', () {
    test('the happy path is walkable end to end', () {
      const List<BundleState> path = <BundleState>[
        BundleState.installed,
        BundleState.resolved,
        BundleState.starting,
        BundleState.active,
        BundleState.stopping,
        BundleState.resolved,
      ];
      for (int i = 0; i + 1 < path.length; i++) {
        expect(
          isLegalTransition(path[i], path[i + 1]),
          isTrue,
          reason: '${path[i]} -> ${path[i + 1]}',
        );
      }
    });

    test('stopping returns to resolved, so restart is a normal operation', () {
      expect(
        isLegalTransition(BundleState.stopping, BundleState.resolved),
        isTrue,
      );
      expect(
        isLegalTransition(BundleState.stopping, BundleState.uninstalled),
        isFalse,
      );
      // ...and resolved can start again.
      expect(
        isLegalTransition(BundleState.resolved, BundleState.starting),
        isTrue,
      );
    });

    test('a failed start unwinds the same way a healthy stop does', () {
      expect(
        isLegalTransition(BundleState.starting, BundleState.stopping),
        isTrue,
      );
    });

    test('starting cannot skip to stopped-and-gone or back to resolved', () {
      expect(
        isLegalTransition(BundleState.starting, BundleState.resolved),
        isFalse,
      );
      expect(
        isLegalTransition(BundleState.starting, BundleState.uninstalled),
        isFalse,
      );
    });

    test('uninstalled is terminal', () {
      for (final BundleState to in BundleState.values) {
        expect(
          isLegalTransition(BundleState.uninstalled, to),
          isFalse,
          reason: 'uninstalled -> $to',
        );
      }
      expect(BundleState.uninstalled.isTerminal, isTrue);
    });

    test('a self-transition is not an edge', () {
      // A caller re-asserting the current state has lost track of the bundle,
      // and accepting it would hide that.
      for (final BundleState state in BundleState.values) {
        expect(isLegalTransition(state, state), isFalse, reason: '$state');
      }
    });

    test('active goes only to stopping', () {
      for (final BundleState to in BundleState.values) {
        expect(
          isLegalTransition(BundleState.active, to),
          to == BundleState.stopping,
          reason: 'active -> $to',
        );
      }
    });
  });

  group('isLive', () {
    test('covers exactly the span the shell holds registrations across', () {
      expect(BundleState.starting.isLive, isTrue);
      expect(BundleState.active.isLive, isTrue);
      expect(BundleState.resolved.isLive, isFalse);
      expect(BundleState.stopping.isLive, isFalse);
      expect(BundleState.installed.isLive, isFalse);
      expect(BundleState.uninstalled.isLive, isFalse);
    });
  });
}
