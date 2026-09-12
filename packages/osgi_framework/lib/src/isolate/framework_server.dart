import 'dart:async';
import 'dart:isolate';

import 'package:osgi_api/osgi_api.dart';

import '../event.dart';
import '../event_admin.dart';
import '../service_registry.dart';
import 'protocol.dart';

/// The framework's side of the isolate boundary: one registry, one routing
/// table, and a port that bundles send requests to.
///
/// This is what makes the registry usable by bundles at all. A
/// [ServiceRegistry] is ordinary Dart objects, so it cannot be shared with
/// another isolate -- an attempt to send it would copy it, and every bundle
/// would end up with its own private registry. Instead the registry stays here
/// and bundles reach it by message.
///
/// What the registry holds for a remote bundle is a [ServiceEndpoint], so a
/// lookup answers with the port to talk to rather than a copy of a service.
///
/// ## Priority
///
/// One port, not the two the project plan describes. Two ports and a
/// drain-priority-first loop would only order messages that had already been
/// delivered to this isolate in the same event-loop turn: the VM decides
/// delivery order across ports, and nothing in Dart can inspect a port's queue
/// to do better. The weaker guarantee is worth having only once something
/// measures it, so it is deliberately absent rather than claimed.
class FrameworkServer {
  FrameworkServer({ServiceRegistry? registry, EventAdmin? events})
    : registry = registry ?? ServiceRegistry(),
      events = events ?? EventAdmin();

  /// The registry every bundle shares. Owned here and never sent anywhere.
  final ServiceRegistry registry;

  /// The event admin every bundle shares.
  ///
  /// Remote subscriptions are served by subscribing to this, so a bundle in
  /// this isolate and one in another see the same events, matched the same
  /// way. Disposed by [stop].
  final EventAdmin events;

  final ReceivePort _requests = ReceivePort('osgi.framework');

  /// Where bundles send [FrameworkRequest]s. Hand this to a bundle isolate at
  /// spawn, or over the shell's bridge.
  SendPort get port => _requests.sendPort;

  /// Bundle inboxes, by symbolic name. Routing only: the framework never
  /// inspects what it forwards.
  final Map<String, SendPort> _inboxes = <String, SendPort>{};

  final Map<int, _Published> _published = <int, _Published>{};
  final Map<String, Map<int, _Subscription>> _trackers =
      <String, Map<int, _Subscription>>{};
  final Map<String, Map<int, StreamSubscription<Event>>> _topics =
      <String, Map<int, StreamSubscription<Event>>>{};

  int _nextServiceId = 1;
  StreamSubscription<dynamic>? _listening;

  /// Begin serving. Returns once the port is listening.
  void start() {
    _listening ??= _requests.listen(_onMessage);
  }

  /// Stop serving and drop every bundle's registrations and trackers.
  Future<void> stop() async {
    await _listening?.cancel();
    _listening = null;
    for (final String bundle in _trackers.keys.toList()) {
      await _dropTrackers(bundle);
    }
    for (final int serviceId in _published.keys.toList()) {
      await _published.remove(serviceId)?.registration.unregister();
    }
    for (final String bundle in _topics.keys.toList()) {
      await _dropTopics(bundle);
    }
    await events.dispose();
    _inboxes.clear();
    _requests.close();
  }

  /// Bundles currently attached, in attach order.
  Iterable<String> get attached => _inboxes.keys;

  void _onMessage(dynamic message) {
    // Not ours: ignore rather than die. A stray message must not take the
    // framework down with it, and every bundle with it.
    if (message is! FrameworkRequest) return;
    unawaited(_serve(message));
  }

  Future<void> _serve(FrameworkRequest request) async {
    switch (request) {
      case AttachBundle():
        _inboxes[request.bundle] = request.replyTo;
        request.replyTo.send(Acknowledged(request.id));

      case DetachBundle():
        await _detach(request.bundle);
        request.replyTo.send(Acknowledged(request.id));

      case RegisterEndpoint():
        final int serviceId = _nextServiceId++;
        final ServiceEndpoint endpoint = ServiceEndpoint(
          serviceId: serviceId,
          interfaceName: request.interfaceName,
          port: request.port,
          properties: request.properties,
        );
        _published[serviceId] = _Published(
          bundle: request.bundle,
          registration: registry.register(
            request.interfaceName,
            endpoint,
            request.properties,
          ),
        );
        request.replyTo.send(EndpointRegistered(request.id, serviceId));

      case UnregisterEndpoint():
        final _Published? published = _published[request.serviceId];
        if (published == null || published.bundle != request.bundle) {
          // Either already gone, or another bundle's service. A bundle may only
          // withdraw what it published.
          request.replyTo.send(
            RequestFailed(
              request.id,
              'service ${request.serviceId} is not registered by '
              '"${request.bundle}"',
            ),
          );
          return;
        }
        _published.remove(request.serviceId);
        await published.registration.unregister();
        request.replyTo.send(Acknowledged(request.id));

      case LookupEndpoints():
        try {
          final List<Object?> found = request.all
              ? registry.getServices(
                  request.interfaceName,
                  filter: request.filter,
                )
              : <Object?>[
                  registry.getService(
                    request.interfaceName,
                    filter: request.filter,
                  ),
                ];
          request.replyTo.send(
            EndpointsFound(
              request.id,
              found.whereType<ServiceEndpoint>().toList(growable: false),
            ),
          );
        } on FormatException catch (e) {
          // A malformed filter is the caller's mistake, and it is in another
          // isolate: report it rather than throwing where nobody can catch it.
          request.replyTo.send(RequestFailed(request.id, e.toString()));
        }

      case OpenTracker():
        await _openTracker(request);

      case CloseTracker():
        final _Subscription? subscription = _trackers[request.bundle]?.remove(
          request.trackerId,
        );
        await subscription?.cancel();
        request.replyTo.send(Acknowledged(request.id));

      case PostEvent():
        // No reply: posting is asynchronous, and the poster is not waiting.
        events.postEvent(request.event);

      case SubscribeTopic():
        try {
          final StreamSubscription<Event> subscription = events
              .subscribe(request.topicPattern)
              .listen((Event event) {
                request.replyTo.send(
                  EventDelivered(
                    subscriptionId: request.subscriptionId,
                    event: event,
                  ),
                );
              });
          _topics.putIfAbsent(
            request.bundle,
            () => <int, StreamSubscription<Event>>{},
          )[request.subscriptionId] = subscription;
          request.replyTo.send(Acknowledged(request.id));
        } on ArgumentError catch (e) {
          // The client validates the pattern before sending, so this is a
          // bundle reaching the protocol directly. Answer rather than throw:
          // an exception here would be an unhandled error in the framework.
          request.replyTo.send(RequestFailed(request.id, e.toString()));
        }

      case UnsubscribeTopic():
        final StreamSubscription<Event>? subscription = _topics[request.bundle]
            ?.remove(request.subscriptionId);
        await subscription?.cancel();
        request.replyTo.send(Acknowledged(request.id));

      case SendToBundle():
        final SendPort? inbox = _inboxes[request.target];
        if (inbox == null) {
          request.replyTo.send(
            RequestFailed(
              request.id,
              'no bundle named "${request.target}" is attached',
            ),
          );
          return;
        }
        inbox.send(request.message);
        request.replyTo.send(Acknowledged(request.id));
    }
  }

  Future<void> _openTracker(OpenTracker request) async {
    final ServiceTracker tracker;
    try {
      tracker = registry.track(request.interfaceName, filter: request.filter);
    } on FormatException catch (e) {
      request.replyTo.send(RequestFailed(request.id, e.toString()));
      return;
    }

    final SendPort replyTo = request.replyTo;
    void forward(Object? service, {required bool added}) {
      if (service is! ServiceEndpoint) return;
      replyTo.send(
        TrackerEvent(
          trackerId: request.trackerId,
          added: added,
          endpoint: service,
        ),
      );
    }

    final StreamSubscription<Object?> adds = tracker.addingService.listen(
      (Object? s) => forward(s, added: true),
    );
    final StreamSubscription<Object?> removes = tracker.removedService.listen(
      (Object? s) => forward(s, added: false),
    );

    _trackers.putIfAbsent(
      request.bundle,
      () => <int, _Subscription>{},
    )[request.trackerId] = _Subscription(
      tracker,
      adds,
      removes,
    );

    // Acknowledge before opening, so the bundle's reply arrives before the
    // first event rather than interleaved with the replay.
    request.replyTo.send(Acknowledged(request.id));
    await tracker.open();
  }

  Future<void> _detach(String bundle) async {
    await _dropTrackers(bundle);
    await _dropTopics(bundle);
    for (final int serviceId in _published.keys.toList()) {
      final _Published published = _published[serviceId]!;
      if (published.bundle != bundle) continue;
      _published.remove(serviceId);
      await published.registration.unregister();
    }
    _inboxes.remove(bundle);
  }

  Future<void> _dropTrackers(String bundle) async {
    final Map<int, _Subscription>? subscriptions = _trackers.remove(bundle);
    if (subscriptions == null) return;
    for (final _Subscription subscription in subscriptions.values) {
      await subscription.cancel();
    }
  }

  Future<void> _dropTopics(String bundle) async {
    final Map<int, StreamSubscription<Event>>? subscriptions = _topics.remove(
      bundle,
    );
    if (subscriptions == null) return;
    for (final StreamSubscription<Event> subscription in subscriptions.values) {
      await subscription.cancel();
    }
  }
}

class _Published {
  _Published({required this.bundle, required this.registration});

  final String bundle;
  final ServiceRegistration registration;
}

class _Subscription {
  _Subscription(this._tracker, this._adds, this._removes);

  final ServiceTracker _tracker;
  final StreamSubscription<Object?> _adds;
  final StreamSubscription<Object?> _removes;

  Future<void> cancel() async {
    await _adds.cancel();
    await _removes.cancel();
    await _tracker.close();
  }
}
