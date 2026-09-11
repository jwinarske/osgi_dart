import 'dart:async';

import 'package:osgi_api/osgi_api.dart';

import 'event.dart';
import 'service_registry.dart';
import 'topic_filter.dart';

/// Topic-based publish/subscribe between bundles: OSGi EventAdmin.
///
/// In-process for now. Publishers and subscribers must share this isolate
/// until the framework isolate carries events between bundles.
///
/// Delivery is asynchronous: [post] returns before any subscriber runs, and
/// each subscriber sees events in the order they were posted.
///
/// ```dart
/// eventAdmin.post('com/ivi/can/THRESHOLD_EXCEEDED',
///     const <String, Object?>{'signal': 'EngineTemp', 'value': 105.0});
///
/// eventAdmin.subscribe('com/ivi/can/*').listen((Event event) { ... });
/// ```
class EventAdmin {
  /// The interface name [registerIn] publishes under.
  static const String serviceName = 'org.osgi.service.event.EventAdmin';

  final StreamController<Event> _events = StreamController<Event>.broadcast();

  /// Post an event on [topic]. See [postEvent].
  void post(
    String topic, [
    Map<String, Object?> properties = const <String, Object?>{},
  ]) => postEvent(Event(topic, properties));

  /// Post [event] to every matching subscriber.
  ///
  /// After [dispose] this does nothing rather than throwing: publishers are
  /// often bundles that are themselves stopping, and a throw there would mask
  /// whatever made them stop.
  void postEvent(Event event) {
    if (_events.isClosed) return;
    _events.add(event);
  }

  /// Events whose topic matches [topicPattern] (see [TopicFilter]).
  ///
  /// Nothing is held for a subscription until it is listened to, and cancelling
  /// the listener releases it. Events posted before a listener starts are not
  /// delivered to it.
  ///
  /// Throws [ArgumentError] for a malformed pattern.
  Stream<Event> subscribe(String topicPattern) {
    final TopicFilter filter = TopicFilter(topicPattern);
    return _events.stream.where((Event event) => filter.matches(event.topic));
  }

  /// Publish this EventAdmin in [registry] under [serviceName].
  ServiceRegistration registerIn(ServiceRegistry registry) => registry.register(
    serviceName,
    this,
    const <String, Object?>{'service.description': 'OSGi EventAdmin'},
  );

  /// Close every subscriber's stream. Later posts are dropped.
  Future<void> dispose() => _events.close();
}
