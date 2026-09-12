// Named parameters assigned to private fields. Dart forbids a named parameter
// that starts with an underscore, so these cannot be initializing formals
// unless the fields become public -- and the framework port is not something a
// bundle's own code should be able to reach around this class to use.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:isolate';

import 'package:osgi_api/osgi_api.dart';

import 'protocol.dart';

/// Raised when the framework refuses a request.
///
/// The framework serves bundles in other isolates, so it cannot throw into
/// them: it answers with [RequestFailed] and the client raises this.
class FrameworkException implements Exception {
  FrameworkException(this.message);

  final String message;

  @override
  String toString() => 'FrameworkException: $message';
}

/// A [BundleContext] for a bundle that lives in its own isolate, talking to a
/// `FrameworkServer` elsewhere in the process.
///
/// The registry is not here, so every operation is a message. One rule follows
/// from that and is enforced rather than documented away: **a service must be a
/// `SendPort`**. Objects sent between isolates are copied, so registering a
/// service object would publish a copy that no call could ever reach. What a
/// bundle publishes is the port it listens on; what a consumer gets is a
/// [ServiceEndpoint] carrying that port.
///
/// Service properties are best declared `const`, which travel by reference
/// rather than being copied.
class RemoteBundleContext implements BundleContext {
  RemoteBundleContext({
    required this.symbolicName,
    required SendPort framework,
    this.requestTimeout,
  }) : _framework = framework {
    _inbox.listen(_onMessage);
  }

  @override
  final String symbolicName;

  final SendPort _framework;

  /// How long to wait for the framework before giving up.
  ///
  /// Null waits indefinitely, which is the default because the real bound is
  /// the shell's startup deadline and only the bundle knows how much of it is
  /// left. Set it if a hung framework isolate should surface as an error here
  /// rather than as a bundle that never reports ACTIVE.
  final Duration? requestTimeout;

  final ReceivePort _inbox = ReceivePort('osgi.bundle');

  final Map<int, Completer<FrameworkReply>> _pending =
      <int, Completer<FrameworkReply>>{};
  final Map<int, _RemoteTracker> _trackers = <int, _RemoteTracker>{};
  final List<_RemoteRegistration> _registrations = <_RemoteRegistration>[];

  final StreamController<Object?> _incoming =
      StreamController<Object?>.broadcast();

  int _nextRequestId = 1;
  int _nextTrackerId = 1;
  BundleState _state = BundleState.resolved;
  bool _detached = false;

  /// Anything another bundle routed here through the framework.
  ///
  /// The framework forwards without inspecting, so the shape of these messages
  /// is between the two bundles.
  Stream<Object?> get incoming => _incoming.stream;

  /// This bundle's own view of its state.
  ///
  /// Coarse on purpose: [BundleState.resolved] until [attach], then
  /// [BundleState.active]. When this context is driven by a lifecycle owner,
  /// that owner's state is the authoritative one.
  @override
  BundleState get state => _state;

  /// Announce this bundle to the framework, so it can be found and routed to.
  Future<void> attach() async {
    await _request<Acknowledged>(
      (int id) =>
          AttachBundle(id: id, bundle: symbolicName, replyTo: _inbox.sendPort),
    );
    _state = BundleState.active;
  }

  /// Release everything this bundle holds in the framework and stop listening.
  ///
  /// Safe to call twice, because teardown runs on failure paths too.
  Future<void> detach() async {
    if (_detached) return;
    // Set before the request, so nothing new is started while we tear down --
    // and sent with allowDetached, or the guard below would refuse the one
    // request that has to get through.
    _detached = true;
    try {
      await _request<Acknowledged>(
        (int id) => DetachBundle(
          id: id,
          bundle: symbolicName,
          replyTo: _inbox.sendPort,
        ),
        allowDetached: true,
      );
    } on Object {
      // Teardown usually runs because something else already failed; a
      // framework that has already forgotten us is the state we wanted.
    }
    _state = BundleState.resolved;
    for (final _RemoteTracker tracker in _trackers.values.toList()) {
      await tracker.shutdown();
    }
    _trackers.clear();
    _registrations.clear();
    for (final Completer<FrameworkReply> pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(
          FrameworkException('bundle "$symbolicName" detached'),
        );
      }
    }
    _pending.clear();
    await _incoming.close();
    _inbox.close();
  }

  /// Publish [service] -- which must be a `SendPort` -- under [interfaceName].
  @override
  Future<ServiceRegistration> registerService(
    String interfaceName,
    Object? service, [
    Map<String, Object?> properties = const <String, Object?>{},
  ]) async {
    if (service is! SendPort) {
      throw ArgumentError.value(
        service,
        'service',
        'a remote service must be a SendPort: objects are copied between '
            'isolates, so a copy would not be the service',
      );
    }
    final EndpointRegistered reply = await _request<EndpointRegistered>(
      (int id) => RegisterEndpoint(
        id: id,
        bundle: symbolicName,
        replyTo: _inbox.sendPort,
        interfaceName: interfaceName,
        port: service,
        properties: properties,
      ),
    );
    final _RemoteRegistration registration = _RemoteRegistration(
      context: this,
      serviceId: reply.serviceId,
      interfaceName: interfaceName,
      properties: properties,
    );
    _registrations.add(registration);
    return registration;
  }

  /// The highest-ranked service under [interfaceName], or null.
  ///
  /// Throws [FrameworkException] for a malformed [filter]: the framework parses
  /// it, and a parse failure in another isolate cannot be thrown here.
  Future<ServiceEndpoint?> lookup(
    String interfaceName, {
    String? filter,
  }) async {
    final List<ServiceEndpoint> found = await lookupAll(
      interfaceName,
      filter: filter,
      all: false,
    );
    return found.isEmpty ? null : found.first;
  }

  /// Every service under [interfaceName], highest-ranked first.
  Future<List<ServiceEndpoint>> lookupAll(
    String interfaceName, {
    String? filter,
    bool all = true,
  }) async {
    final EndpointsFound reply = await _request<EndpointsFound>(
      (int id) => LookupEndpoints(
        id: id,
        bundle: symbolicName,
        replyTo: _inbox.sendPort,
        interfaceName: interfaceName,
        filter: filter,
        all: all,
      ),
    );
    return reply.endpoints;
  }

  /// Watch [interfaceName]. Call [ServiceTracker.open] to start.
  ///
  /// As in-process, each listener first receives the services already tracked,
  /// so what a listener sees does not depend on whether it subscribed before or
  /// after `open()`.
  @override
  ServiceTracker trackService(String interfaceName, {String? filter}) {
    final int trackerId = _nextTrackerId++;
    final _RemoteTracker tracker = _RemoteTracker(
      context: this,
      trackerId: trackerId,
      interfaceName: interfaceName,
      filter: filter,
    );
    _trackers[trackerId] = tracker;
    return tracker;
  }

  /// Route [message] to another attached bundle.
  ///
  /// Throws [FrameworkException] when no bundle of that name is attached.
  Future<void> sendToBundle(String target, Object? message) =>
      _request<Acknowledged>(
        (int id) => SendToBundle(
          id: id,
          bundle: symbolicName,
          replyTo: _inbox.sendPort,
          target: target,
          message: message,
        ),
      );

  void _onMessage(dynamic message) {
    switch (message) {
      case FrameworkReply():
        _pending.remove(message.id)?.complete(message);
      case TrackerEvent():
        _trackers[message.trackerId]?.handle(message);
      default:
        // Anything else came from another bundle by way of the framework.
        if (!_incoming.isClosed) _incoming.add(message);
    }
  }

  Future<R> _request<R extends FrameworkReply>(
    FrameworkRequest Function(int id) build, {
    bool allowDetached = false,
  }) async {
    if (_detached && !allowDetached) {
      throw StateError(
        'bundle "$symbolicName" has detached from the framework',
      );
    }
    final int id = _nextRequestId++;
    final Completer<FrameworkReply> completer = Completer<FrameworkReply>();
    _pending[id] = completer;
    _framework.send(build(id));

    Future<FrameworkReply> answer = completer.future;
    final Duration? timeout = requestTimeout;
    if (timeout != null) {
      answer = answer.timeout(
        timeout,
        onTimeout: () {
          _pending.remove(id);
          throw TimeoutException(
            'the framework did not answer a request from "$symbolicName"',
            timeout,
          );
        },
      );
    }

    final FrameworkReply reply = await answer;
    if (reply is RequestFailed) throw FrameworkException(reply.message);
    if (reply is! R) {
      throw FrameworkException(
        'expected $R from the framework, got ${reply.runtimeType}',
      );
    }
    return reply;
  }

  Future<void> _unregister(_RemoteRegistration registration) async {
    _registrations.remove(registration);
    if (_detached) return; // detach already released everything
    await _request<Acknowledged>(
      (int id) => UnregisterEndpoint(
        id: id,
        bundle: symbolicName,
        replyTo: _inbox.sendPort,
        serviceId: registration.serviceId,
      ),
    );
  }

  Future<void> _openTracker(_RemoteTracker tracker) => _request<Acknowledged>(
    (int id) => OpenTracker(
      id: id,
      bundle: symbolicName,
      replyTo: _inbox.sendPort,
      trackerId: tracker.trackerId,
      interfaceName: tracker.interfaceName,
      filter: tracker.filter,
    ),
  );

  Future<void> _closeTracker(_RemoteTracker tracker) async {
    _trackers.remove(tracker.trackerId);
    if (_detached) return;
    await _request<Acknowledged>(
      (int id) => CloseTracker(
        id: id,
        bundle: symbolicName,
        replyTo: _inbox.sendPort,
        trackerId: tracker.trackerId,
      ),
    );
  }
}

class _RemoteRegistration implements ServiceRegistration {
  _RemoteRegistration({
    required RemoteBundleContext context,
    required this.serviceId,
    required this.interfaceName,
    required Map<String, Object?> properties,
  }) : _context = context,
       properties = Map<String, Object?>.unmodifiable(properties);

  final RemoteBundleContext _context;
  final int serviceId;

  @override
  final String interfaceName;

  @override
  final Map<String, Object?> properties;

  bool _unregistered = false;

  @override
  Future<void> unregister() async {
    // Idempotent, like the in-process registry: stop() runs on failed starts
    // too, where it cannot know how far the start got.
    if (_unregistered) return;
    _unregistered = true;
    await _context._unregister(this);
  }
}

class _RemoteTracker implements ServiceTracker {
  _RemoteTracker({
    required RemoteBundleContext context,
    required this.trackerId,
    required this.interfaceName,
    required this.filter,
  }) : _context = context;

  final RemoteBundleContext _context;
  final int trackerId;
  final String interfaceName;
  final String? filter;

  /// What is tracked right now, so a listener arriving later starts from the
  /// current state rather than from whatever it happened to catch.
  final List<ServiceEndpoint> _tracked = <ServiceEndpoint>[];

  final Set<MultiStreamController<Object?>> _addListeners =
      <MultiStreamController<Object?>>{};

  late final Stream<Object?> _adding = Stream<Object?>.multi(
    _onAddListen,
    isBroadcast: true,
  );

  final StreamController<Object?> _removed =
      StreamController<Object?>.broadcast();

  bool _open = false;
  bool _closed = false;

  @override
  Stream<Object?> get addingService => _adding;

  @override
  Stream<Object?> get removedService => _removed.stream;

  @override
  Future<void> open() async {
    if (_open || _closed) return;
    _open = true;
    await _context._openTracker(this);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    await _context._closeTracker(this);
    await shutdown();
  }

  /// Close the local side without talking to the framework, for a context that
  /// is detaching anyway.
  Future<void> shutdown() async {
    if (_closed) return;
    _closed = true;
    _open = false;
    for (final MultiStreamController<Object?> listener
        in _addListeners.toList()) {
      unawaited(listener.close());
    }
    _addListeners.clear();
    await _removed.close();
  }

  void handle(TrackerEvent event) {
    if (_closed) return;
    if (event.added) {
      _tracked.add(event.endpoint);
      for (final MultiStreamController<Object?> listener
          in _addListeners.toList()) {
        listener.add(event.endpoint);
      }
    } else {
      _tracked.remove(event.endpoint);
      if (!_removed.isClosed) _removed.add(event.endpoint);
    }
  }

  void _onAddListen(MultiStreamController<Object?> listener) {
    if (_closed) {
      unawaited(listener.close());
      return;
    }
    _addListeners.add(listener);
    listener.onCancel = () {
      _addListeners.remove(listener);
    };
    for (final ServiceEndpoint endpoint in _tracked) {
      listener.add(endpoint);
    }
  }
}
