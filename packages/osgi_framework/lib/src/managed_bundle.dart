// The constructor takes named parameters and assigns them to private fields.
// Dart forbids a named parameter that starts with an underscore, so these
// cannot be initializing formals unless the fields become public -- and a
// bundle reaching the transport directly is exactly what this class prevents.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:osgi_api/osgi_api.dart';

import 'service_registry.dart';

/// One bundle's activator, driven through the OSGi lifecycle.
///
/// A bundle begins here at [BundleState.resolved]. `INSTALLED -> RESOLVED` is
/// the shell's business: by the time Dart runs, the shell has read the
/// `[[osgi.bundles]]` entry and spawned an engine for it.
///
/// What this owns is the part the shell cannot see -- calling the activator,
/// reporting ACTIVE once `start()` has really finished, and unwinding a failed
/// start the same way a healthy stop unwinds.
///
/// It does not decide *when* to start: the shell's orchestrator does that, and
/// a critical bundle's startup deadline is running throughout [start].
class ManagedBundle {
  ManagedBundle({
    required this.symbolicName,
    required BundleActivator activator,
    required ShellTransport transport,
    required ServiceRegistry registry,
  }) : _activator = activator,
       _transport = transport,
       _registry = registry;

  /// Must match an `[[osgi.bundles]]` entry. The shell accepts a name it does
  /// not know and then ignores its reports, so a mismatch shows up as the
  /// correctly named bundle's deadline expiring -- see `docs/ARCHITECTURE.md`.
  final String symbolicName;

  final BundleActivator _activator;
  final ShellTransport _transport;
  final ServiceRegistry _registry;

  final StreamController<BundleState> _states =
      StreamController<BundleState>.broadcast();

  BundleState _state = BundleState.resolved;

  _Context? _context;
  ShellBinding? _binding;

  /// Where the bundle is now. Starts at [BundleState.resolved].
  BundleState get state => _state;

  /// Every state this bundle enters from now on.
  Stream<BundleState> get states => _states.stream;

  /// The framework isolate's port, once [start] has registered with the shell.
  ///
  /// Null before then. Awaiting it is how a bundle that talks to peers blocks
  /// until it can; a bundle with no peers must not await it, because the port
  /// may arrive long after registration and the startup deadline is running.
  Future<int>? get frameworkPort => _binding?.frameworkPort;

  /// Register with the shell, run the activator, and report ACTIVE.
  ///
  /// ACTIVE is reported only after [BundleActivator.start] has returned, which
  /// is what releases a critical bundle's startup wait.
  ///
  /// If anything fails, the bundle is torn down completely -- services
  /// released, shell registration dropped, state back at
  /// [BundleState.resolved], so the same name can start again -- and the
  /// original error is then rethrown. ACTIVE is never reported on that path.
  Future<void> start() async {
    if (_state != BundleState.resolved) {
      throw StateError(
        'cannot start "$symbolicName" from $_state; '
        'a bundle starts from ${BundleState.resolved}',
      );
    }
    _to(BundleState.starting);

    final _Context context = _Context(this, _registry);
    _context = context;
    try {
      _binding = await _transport.register(symbolicName);
      await _activator.start(context);
      await _transport.reportActive(symbolicName);
      _to(BundleState.active);
    } catch (_) {
      // A stop() that also fails is not the interesting error here: the start
      // failure is what the caller needs to see, so it is the one that
      // survives.
      await _unwind(callStop: true, rethrowStopError: false);
      rethrow;
    }
  }

  /// Run the activator's `stop()`, release what the bundle published, and
  /// report STOPPED.
  ///
  /// The teardown always completes: an activator whose `stop()` throws still
  /// has its services released and its registration dropped, and the bundle
  /// still lands at [BundleState.resolved] so it can start again. The error is
  /// rethrown afterwards rather than swallowed, because a bundle that cannot
  /// stop cleanly is worth knowing about.
  Future<void> stop() async {
    if (_state != BundleState.active) {
      throw StateError(
        'cannot stop "$symbolicName" from $_state; '
        'a bundle stops from ${BundleState.active}',
      );
    }
    await _unwind(callStop: true, report: true);
  }

  /// Release the state stream. The bundle must already be stopped.
  Future<void> dispose() => _states.close();

  /// The one teardown path, used by a failed start and by a healthy stop --
  /// which is the point of the `STARTING -> STOPPING` edge in the lifecycle.
  Future<void> _unwind({
    required bool callStop,
    bool report = false,
    bool rethrowStopError = true,
  }) async {
    _to(BundleState.stopping);
    final _Context? context = _context;

    Object? activatorError;
    StackTrace? activatorStack;
    if (callStop && context != null) {
      try {
        await _activator.stop(context);
      } catch (e, s) {
        // Recorded, not thrown yet: the rest of the teardown has to happen
        // either way, or the next start finds half a bundle still published.
        activatorError = e;
        activatorStack = s;
      }
    }

    await context?.release();
    _context = null;
    _binding = null;

    // Transport failures are swallowed here. Teardown usually runs because
    // something else already failed, and a throw would mask it.
    if (report) {
      try {
        await _transport.reportStopped(symbolicName);
      } on Object {
        // The shell has forgotten this bundle, which is what we were asking for.
      }
    }
    try {
      await _transport.unregister(symbolicName);
    } on Object {
      // Likewise.
    }

    _to(BundleState.resolved);

    if (rethrowStopError && activatorError != null) {
      Error.throwWithStackTrace(activatorError, activatorStack!);
    }
  }

  void _to(BundleState next) {
    if (!isLegalTransition(_state, next)) {
      // The framework drives these itself, so reaching this means the sequence
      // above is wrong rather than a caller being wrong.
      throw StateError(
        'illegal transition $_state -> $next for "$symbolicName"',
      );
    }
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }
}

/// The bundle's view of the framework.
///
/// Everything published through it is released when the bundle stops, so an
/// activator's `stop()` does not have to be exhaustive to leave the registry
/// clean -- and a `stop()` that runs after a partial start does not need to
/// know how far the start got.
class _Context implements BundleContext {
  _Context(this._bundle, this._registry);

  final ManagedBundle _bundle;
  final ServiceRegistry _registry;

  final List<ServiceRegistration> _registrations = <ServiceRegistration>[];
  final List<ServiceTracker> _trackers = <ServiceTracker>[];

  bool _released = false;

  @override
  String get symbolicName => _bundle.symbolicName;

  @override
  BundleState get state => _bundle.state;

  @override
  Future<ServiceRegistration> registerService(
    String interfaceName,
    Object? service, [
    Map<String, Object?> properties = const <String, Object?>{},
  ]) async {
    _requireLive('register "$interfaceName"');
    final ServiceRegistration registration = _registry.register(
      interfaceName,
      service,
      properties,
    );
    _registrations.add(registration);
    return registration;
  }

  @override
  ServiceTracker trackService(String interfaceName, {String? filter}) {
    _requireLive('track "$interfaceName"');
    final ServiceTracker tracker = _registry.track(
      interfaceName,
      filter: filter,
    );
    _trackers.add(tracker);
    return tracker;
  }

  /// Drop everything this bundle published or watched.
  Future<void> release() async {
    if (_released) return;
    _released = true;
    for (final ServiceRegistration registration in _registrations) {
      // Idempotent, so an activator that already unregistered is fine.
      await registration.unregister();
    }
    _registrations.clear();
    for (final ServiceTracker tracker in _trackers) {
      await tracker.close();
    }
    _trackers.clear();
  }

  void _requireLive(String what) {
    if (_released) {
      throw StateError(
        'cannot $what: bundle "${_bundle.symbolicName}" has stopped. '
        'An asynchronous callback that outlived the activator is the usual '
        'cause, and publishing from it would leave a service nothing owns.',
      );
    }
  }
}
