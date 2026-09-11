/// An event posted through `EventAdmin`: a topic and a property map.
///
/// The properties are copied into an unmodifiable map when the event is built.
/// Every subscriber receives the same [Event], so without the copy one
/// subscriber could change what the next one sees, and a publisher that reuses
/// its map could change an event after posting it.
class Event {
  /// Throws [ArgumentError] if [topic] is empty or contains `*`: a topic names
  /// one thing, and wildcards belong to subscriptions.
  Event(
    this.topic, [
    Map<String, Object?> properties = const <String, Object?>{},
  ]) : properties = Map<String, Object?>.unmodifiable(properties) {
    if (topic.isEmpty || topic.contains('*')) {
      throw ArgumentError.value(
        topic,
        'topic',
        'must be non-empty and contain no "*"',
      );
    }
  }

  /// Slash-separated, e.g. `com/ivi/can/THRESHOLD_EXCEEDED`.
  final String topic;

  final Map<String, Object?> properties;

  /// The property [key] if it is a [T], otherwise null.
  T? property<T>(String key) {
    final Object? value = properties[key];
    return value is T ? value : null;
  }

  @override
  String toString() => 'Event($topic, $properties)';
}

/// Topic namespaces used across the framework.
abstract final class Topics {
  /// Bundle lifecycle: STARTED, STOPPED, UPDATED.
  static const String bundle = 'com/ivi/bundle';

  /// Navigation route changes.
  static const String navigation = 'com/ivi/navigation';

  /// CAN bus signals and thresholds.
  static const String can = 'com/ivi/can';

  /// Sensor data.
  static const String sensor = 'com/ivi/sensor';

  /// Media playback.
  static const String media = 'com/ivi/media';

  static const String bundleStarted = 'com/ivi/bundle/STARTED';
  static const String bundleStopped = 'com/ivi/bundle/STOPPED';
  static const String bundleUpdated = 'com/ivi/bundle/UPDATED';
  static const String routeChanged = 'com/ivi/navigation/ROUTE_CHANGED';
}
