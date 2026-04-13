import 'dart:async';

import 'package:dart_osgi_api/dart_osgi_api.dart';

/// Validates and manages lifecycle state transitions for a single bundle.
///
/// Legal transitions:
/// ```
/// INSTALLED → RESOLVED → STARTING → ACTIVE
///                                       ↓
///                          STOPPING ← ──┘
///                              ↓
///                         UNINSTALLED
///
/// RESOLVED ← ACTIVE (on dependency loss → unresolved → re-resolved)
/// ```
class BundleStateManager {
  BundleStateManager(this._bundle);

  final Bundle _bundle;

  final _controller = StreamController<BundleEvent>.broadcast(sync: true);

  /// Stream of lifecycle events for this bundle.
  Stream<BundleEvent> get events => _controller.stream;

  BundleState _state = BundleState.installed;

  /// The current state.
  BundleState get state => _state;

  /// Attempt a state transition. Throws [InvalidTransitionException] if
  /// the transition is not legal.
  void transition(BundleState target) {
    if (!isValidTransition(_state, target)) {
      throw InvalidTransitionException(_bundle.symbolicName, _state, target);
    }
    final previous = _state;
    _state = target;
    _controller.add(BundleEvent(_eventType(previous, target), _bundle));
  }

  /// Whether transitioning from [from] to [to] is legal.
  static bool isValidTransition(BundleState from, BundleState to) {
    return _validTransitions[from]?.contains(to) ?? false;
  }

  void dispose() {
    _controller.close();
  }

  static BundleEventType _eventType(BundleState from, BundleState to) {
    return switch (to) {
      BundleState.installed => BundleEventType.installed,
      BundleState.resolved =>
        from == BundleState.installed
            ? BundleEventType.resolved
            : BundleEventType.resolved,
      BundleState.starting => BundleEventType.starting,
      BundleState.active => BundleEventType.started,
      BundleState.stopping => BundleEventType.stopping,
      BundleState.uninstalled => BundleEventType.uninstalled,
    };
  }

  static const _validTransitions = <BundleState, Set<BundleState>>{
    BundleState.installed: {BundleState.resolved, BundleState.uninstalled},
    BundleState.resolved: {BundleState.starting, BundleState.uninstalled},
    BundleState.starting: {BundleState.active, BundleState.stopping},
    BundleState.active: {BundleState.stopping},
    BundleState.stopping: {BundleState.resolved, BundleState.uninstalled},
    BundleState.uninstalled: {},
  };
}

/// Thrown when an illegal lifecycle transition is attempted.
class InvalidTransitionException implements Exception {
  InvalidTransitionException(this.symbolicName, this.from, this.to);

  final String symbolicName;
  final BundleState from;
  final BundleState to;

  @override
  String toString() =>
      'InvalidTransitionException: "$symbolicName" cannot transition '
      'from $from to $to';
}
