import 'dart:async';

import 'package:dart_osgi_api/dart_osgi_api.dart';

import '../registry/service_registry.dart';
import 'event.dart';
import 'topic_filter.dart';

/// OSGi EventAdmin service — topic-based publish/subscribe across all
/// bundle types.
///
/// Registered as an OSGi service so bundles can discover it via the
/// service registry. Automatically posts bundle lifecycle events
/// (STARTED, STOPPED, UPDATED) when wired to a [BundleManager].
///
/// Usage:
/// ```dart
/// // Post
/// eventAdmin.post("com/ivi/can/THRESHOLD_EXCEEDED",
///   const {"signal": "EngineTemp", "value": 105.0, "unit": "degC"});
///
/// // Subscribe
/// eventAdmin.subscribe("com/ivi/can/*").listen((event) { ... });
/// ```
class EventAdmin {
  /// The service name used when registering EventAdmin in the OSGi registry.
  static const serviceName = 'org.osgi.service.event.EventAdmin';

  final _controller = StreamController<Event>.broadcast();

  final _subscriptions = <_Subscription>[];

  /// Post an event to all matching subscribers.
  ///
  /// If [properties] is a `const` map, it is sent by VM reference —
  /// O(1), zero allocation across isolates in the shared Dart VM.
  void post(String topic, [Map<String, Object> properties = const {}]) {
    final event = Event(topic, properties);
    _controller.add(event);
  }

  /// Post a pre-built [Event].
  void postEvent(Event event) {
    _controller.add(event);
  }

  /// Subscribe to events matching [topicPattern].
  ///
  /// Returns a broadcast [Stream] of matching [Event]s. The stream
  /// remains active until the caller cancels the subscription.
  ///
  /// Supports exact match (`"com/ivi/can/THRESHOLD_EXCEEDED"`) and
  /// wildcard suffix (`"com/ivi/can/*"`).
  Stream<Event> subscribe(String topicPattern) {
    final filter = TopicFilter(topicPattern);
    late final _Subscription sub;
    final controller = StreamController<Event>.broadcast(
      onCancel: () {
        sub.innerSubscription?.cancel();
        _subscriptions.remove(sub);
      },
    );

    final innerSub = _controller.stream
        .where((event) => filter.matches(event.topic))
        .listen(controller.add);

    sub = _Subscription(
      filter: filter,
      controller: controller,
      innerSubscription: innerSub,
    );
    _subscriptions.add(sub);

    return controller.stream;
  }

  /// Register this EventAdmin as an OSGi service in the [registry].
  ///
  /// Returns the registration so it can be unregistered later.
  ServiceRegistration<EventAdmin> registerIn(
    ServiceRegistry registry,
    String bundleSymbolicName,
  ) {
    return registry.register<EventAdmin>(
      serviceName,
      this,
      bundleSymbolicName,
      const {'service.description': 'OSGi EventAdmin service'},
    );
  }

  /// Wire bundle lifecycle events from a [BundleEvent] stream.
  ///
  /// Automatically posts standard topic events when bundles transition:
  /// - `com/ivi/bundle/STARTED` on [BundleEventType.started]
  /// - `com/ivi/bundle/STOPPED` on [BundleEventType.stopped]
  /// - `com/ivi/bundle/UPDATED` on [BundleEventType.updated]
  StreamSubscription<BundleEvent> wireBundleEvents(
    Stream<BundleEvent> bundleEvents,
  ) {
    return bundleEvents.listen((event) {
      final topic = switch (event.type) {
        BundleEventType.started => Topics.bundleStarted,
        BundleEventType.stopped => Topics.bundleStopped,
        BundleEventType.updated => Topics.bundleUpdated,
        _ => null,
      };
      if (topic != null) {
        post(topic, {
          'bundle.symbolicName': event.bundle.symbolicName,
          'bundle.version': event.bundle.version,
          'bundle.state': event.bundle.state.name,
        });
      }
    });
  }

  /// Dispose the EventAdmin and close all streams.
  void dispose() {
    for (final sub in _subscriptions) {
      sub.innerSubscription?.cancel();
      sub.controller.close();
    }
    _subscriptions.clear();
    _controller.close();
  }
}

class _Subscription {
  _Subscription({
    required this.filter,
    required this.controller,
    this.innerSubscription,
  });

  final TopicFilter filter;
  final StreamController<Event> controller;
  final StreamSubscription<Event>? innerSubscription;
}
