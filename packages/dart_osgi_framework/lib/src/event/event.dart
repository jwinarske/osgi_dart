/// An OSGi EventAdmin event.
///
/// Immutable topic + property map. When [properties] is declared `const`,
/// the Dart VM sends it by reference across isolates — O(1), zero allocation.
class Event {
  const Event(this.topic, [this.properties = const {}]);

  /// The topic string (e.g. "com/ivi/can/THRESHOLD_EXCEEDED").
  final String topic;

  /// Immutable property map. Use `const` maps for zero-copy cross-isolate
  /// delivery within the shared Dart VM.
  final Map<String, Object> properties;

  /// Convenience accessor for a typed property.
  T? property<T>(String key) {
    final value = properties[key];
    return value is T ? value : null;
  }

  @override
  String toString() => 'Event($topic, $properties)';
}

/// Standard topic prefixes used across the framework.
abstract final class Topics {
  /// Bundle lifecycle events: STARTED, STOPPED, UPDATED.
  static const bundle = 'com/ivi/bundle';

  /// Navigation route changes.
  static const navigation = 'com/ivi/navigation';

  /// CAN bus signals and thresholds.
  static const can = 'com/ivi/can';

  /// Sensor data events.
  static const sensor = 'com/ivi/sensor';

  /// Media playback events.
  static const media = 'com/ivi/media';

  // Standard event topics.
  static const bundleStarted = 'com/ivi/bundle/STARTED';
  static const bundleStopped = 'com/ivi/bundle/STOPPED';
  static const bundleUpdated = 'com/ivi/bundle/UPDATED';
  static const routeChanged = 'com/ivi/navigation/ROUTE_CHANGED';
}
