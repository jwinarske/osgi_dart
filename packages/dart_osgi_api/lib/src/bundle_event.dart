import 'bundle.dart';

/// Types of bundle lifecycle events.
enum BundleEventType {
  installed,
  resolved,
  starting,
  started,
  stopping,
  stopped,
  updated,
  unresolved,
  uninstalled,
}

/// Fired when a bundle transitions through lifecycle states.
class BundleEvent {
  BundleEvent(this.type, this.bundle);

  /// The type of lifecycle transition.
  final BundleEventType type;

  /// The bundle whose state changed.
  final Bundle bundle;

  @override
  String toString() => 'BundleEvent($type, ${bundle.symbolicName})';
}
