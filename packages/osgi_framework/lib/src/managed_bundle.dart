// The constructor takes named parameters and assigns them to private fields.
// Dart forbids a named parameter that starts with an underscore, so these
// cannot be initializing formals unless the fields become public -- and a
// bundle reaching the transport directly is exactly what this class prevents.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:isolate';

import 'package:osgi_api/osgi_api.dart';

import 'bundle_scope.dart';
import 'service_registry.dart';

/// One bundle's activator, driven through the OSGi lifecycle.
///
/// A bundle begins here at [BundleState.resolved]. For a bundle the shell
/// spawned, `INSTALLED -> RESOLVED` is the shell's business: by the time Dart
/// runs, the shell has read the `[[osgi.bundles]]` entry and started an engine
/// for it.
///
/// What this owns is the part the shell cannot see -- calling the activator,
/// reporting ACTIVE once `start()` has really finished, and unwinding a failed
/// start the same way a healthy stop unwinds.
///
/// It does not decide *when* to start: for a shell-spawned bundle the shell's
/// orchestrator does, and a critical bundle's startup deadline is running
/// throughout [start].
///
/// Where the bundle's [BundleContext] comes from is a [BundleScope], so the
/// same lifecycle drives a bundle sharing this isolate with the registry and
/// one talking to a `FrameworkServer` from its own isolate.
class ManagedBundle {
  /// Give either [registry], for a bundle in this isolate, or [scope] for
  /// anything else.
  ManagedBundle({
    required this.symbolicName,
    required BundleActivator activator,
    required ShellTransport transport,
    ServiceRegistry? registry,
    BundleScope? scope,
  }) : assert(
         registry != null || scope != null,
         'ManagedBundle needs a registry or a scope',
       ),
       assert(
         registry == null || scope == null,
         'ManagedBundle takes a registry or a scope, not both',
       ),
       _activator = activator,
       _transport = transport,
       _scope = scope ?? RegistryScope(registry!);

  /// For a shell-spawned bundle this must match an `[[osgi.bundles]]` entry.
  /// The shell accepts a name it does not know and then ignores its reports,
  /// so a mismatch shows up as the correctly named bundle's deadline expiring
  /// -- see `docs/ARCHITECTURE.md`.
  final String symbolicName;

  final BundleActivator _activator;
  final ShellTransport _transport;
  final BundleScope _scope;

  final StreamController<BundleState> _states =
      StreamController<BundleState>.broadcast();

  BundleState _state = BundleState.resolved;

  BundleContext? _context;
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
  ///
  /// On a transport with no shell behind it this completes with an error
  /// rather than hanging -- see [DetachedShellTransport].
  Future<SendPort>? get frameworkPort => _binding?.frameworkPort;

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

    try {
      _binding = await _transport.register(symbolicName);
      final BundleContext context = await _scope.open(this);
      _context = context;
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
    final BundleContext? context = _context;

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

    await _scope.close();
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
