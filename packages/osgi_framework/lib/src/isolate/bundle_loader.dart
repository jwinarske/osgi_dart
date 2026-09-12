import 'dart:async';
import 'dart:isolate';

import 'package:osgi_api/osgi_api.dart';

import '../bundle_scope.dart';
import '../detached_shell_transport.dart';
import '../managed_bundle.dart';
import 'protocol.dart';
import 'remote_bundle_context.dart';

/// Builds a bundle's activator inside its own isolate.
///
/// A top-level or static function, because that is what can cross to a spawned
/// isolate: a closure cannot, and an instance would be copied. The factory runs
/// in the new isolate, so the activator it builds is genuinely that isolate's.
typedef ActivatorFactory = BundleActivator Function();

/// Spawns pure-Dart bundles, each in its own isolate, against one
/// `FrameworkServer`.
///
/// These bundles are the framework's own: the shell tracks engines it started
/// from `[[osgi.bundles]]`, and an isolate spawned here has no engine, so it
/// uses [DetachedShellTransport] and reports to nobody outside. Its lifecycle
/// is otherwise the ordinary one -- [ManagedBundle] runs the activator, and a
/// failed start unwinds the same way.
///
/// The loader also watches each isolate's exit. A bundle that dies cannot
/// release itself, so without this its services would stay in the registry
/// pointing at a port nothing listens on. What a bundle throws and never
/// catches arrives on [errors].
class BundleLoader {
  BundleLoader({required this.framework});

  /// The `FrameworkServer` port that spawned bundles talk to.
  final SendPort framework;

  final Map<String, _Loaded> _loaded = <String, _Loaded>{};
  final ReceivePort _replies = ReceivePort('osgi.loader');
  int _nextRequestId = 1;
  bool _closed = false;

  final StreamController<BundleError> _errors =
      StreamController<BundleError>.broadcast();

  /// Bundles running right now.
  Iterable<String> get running => _loaded.keys;

  /// Uncaught errors from running bundles.
  ///
  /// Two things to know before relying on it. It is a broadcast stream, so an
  /// error raised while nothing is listening is dropped rather than buffered --
  /// attach before spawning if you care. And an uncaught error does not stop
  /// the bundle: the isolates are spawned with `errorsAreFatal: false`, because
  /// a bundle that throws in some background timer is still serving whatever
  /// else it published. This reports; it does not decide.
  Stream<BundleError> get errors => _errors.stream;

  /// Spawn [symbolicName] and run its activator to completion.
  ///
  /// Returns once the bundle is ACTIVE. Throws [BundleStartException] if the
  /// activator failed, having left nothing of the bundle behind, or
  /// [TimeoutException] if [startTimeout] passes first.
  Future<void> spawn({
    required String symbolicName,
    required ActivatorFactory activatorFactory,
    Duration? startTimeout,
  }) async {
    if (_loaded.containsKey(symbolicName)) {
      throw StateError('bundle "$symbolicName" is already running');
    }

    final ReceivePort fromBundle = ReceivePort('osgi.loader.$symbolicName');
    final ReceivePort onExit = ReceivePort('osgi.loader.$symbolicName.exit');
    final ReceivePort onError = ReceivePort('osgi.loader.$symbolicName.error');

    final Completer<SendPort> started = Completer<SendPort>();
    fromBundle.listen((dynamic message) {
      switch (message) {
        case BundleStarted(:final SendPort control):
          if (!started.isCompleted) started.complete(control);
        case BundleStartFailed(:final String error):
          if (!started.isCompleted) {
            started.completeError(BundleStartException(symbolicName, error));
          }
        case BundleStopped():
          // Without this, stop() would wait out its timeout every time.
          final Completer<void>? stopped = _loaded[symbolicName]?.stopped;
          if (stopped != null && !stopped.isCompleted) stopped.complete();
      }
    });

    // An uncaught error arrives as two strings: the error and its stack, the
    // latter null when there is none. Reporting it is the difference between a
    // bundle that misbehaves visibly and one that misbehaves in silence.
    onError.listen((dynamic message) {
      if (_errors.isClosed) return;
      final List<Object?> parts = message is List<Object?>
          ? message
          : <Object?>[message, null];
      _errors.add(
        BundleError(
          symbolicName: symbolicName,
          error: '${parts.isEmpty ? message : parts.first}',
          stackTrace: parts.length > 1 ? parts[1]?.toString() : null,
        ),
      );
    });

    // An isolate that dies takes its bundle with it, and a dead isolate cannot
    // detach. Releasing it here is the difference between a stale endpoint and
    // a registry that tells the truth.
    onExit.listen((dynamic _) {
      unawaited(_release(symbolicName));
    });

    final Isolate isolate = await Isolate.spawn(
      bundleIsolateMain,
      BundleSpawnRequest(
        symbolicName: symbolicName,
        framework: framework,
        activatorFactory: activatorFactory,
        loader: fromBundle.sendPort,
      ),
      debugName: 'bundle.$symbolicName',
      errorsAreFatal: false,
      onExit: onExit.sendPort,
      onError: onError.sendPort,
    );

    _loaded[symbolicName] = _Loaded(
      isolate: isolate,
      fromBundle: fromBundle,
      onExit: onExit,
      onError: onError,
    );

    try {
      final Future<SendPort> waiting = startTimeout == null
          ? started.future
          : started.future.timeout(startTimeout);
      _loaded[symbolicName]!.control = await waiting;
    } on Object {
      await _tearDown(symbolicName, kill: true);
      rethrow;
    }
  }

  /// Stop [symbolicName]: run its activator's `stop()`, release what it
  /// published, then let its isolate go.
  Future<void> stop(String symbolicName, {Duration? timeout}) async {
    final _Loaded? loaded = _loaded[symbolicName];
    if (loaded == null) return;

    final SendPort? control = loaded.control;
    if (control != null) {
      final Completer<void> stopped = Completer<void>();
      loaded.stopped = stopped;
      control.send(const StopBundle());
      try {
        await (timeout == null
            ? stopped.future
            : stopped.future.timeout(timeout));
      } on TimeoutException {
        // A bundle that will not stop still has to go, or its name can never
        // be used again. The exit watcher releases what it left behind.
      }
    }
    await _tearDown(symbolicName, kill: true);
  }

  /// Stop everything and close the loader.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final String name in _loaded.keys.toList()) {
      await stop(name, timeout: const Duration(seconds: 5));
    }
    _replies.close();
    await _errors.close();
  }

  Future<void> _tearDown(String symbolicName, {required bool kill}) async {
    final _Loaded? loaded = _loaded.remove(symbolicName);
    if (loaded == null) return;
    if (kill) loaded.isolate.kill(priority: Isolate.beforeNextEvent);
    loaded.fromBundle.close();
    loaded.onExit.close();
    loaded.onError.close();
  }

  /// Tell the framework to let go of a bundle that cannot say so itself.
  ///
  /// This works because the framework trusts the name on attach and detach --
  /// it checks ownership only when a service is withdrawn. That is convenient
  /// here and a gap elsewhere; see `docs/ARCHITECTURE.md`.
  Future<void> _release(String symbolicName) async {
    if (_closed) return;
    framework.send(
      DetachBundle(
        id: _nextRequestId++,
        bundle: symbolicName,
        replyTo: _replies.sendPort,
      ),
    );
    await _tearDown(symbolicName, kill: false);
  }
}

/// Something a bundle threw and nothing in it caught.
///
/// Text rather than the error itself: an isolate reports an uncaught error as
/// two strings, and an arbitrary error object would not reliably survive the
/// crossing in any case.
class BundleError {
  const BundleError({
    required this.symbolicName,
    required this.error,
    this.stackTrace,
  });

  final String symbolicName;
  final String error;
  final String? stackTrace;

  @override
  String toString() => 'BundleError("$symbolicName"): $error';
}

/// Raised when a spawned bundle's activator failed to start.
class BundleStartException implements Exception {
  BundleStartException(this.symbolicName, this.error);

  final String symbolicName;

  /// The activator's error, as text: an arbitrary error object may not survive
  /// the trip between isolates, so the bundle sends its description.
  final String error;

  @override
  String toString() =>
      'BundleStartException: "$symbolicName" failed to start: $error';
}

/// The bundle is up; [control] is where the loader sends [StopBundle].
class BundleStarted {
  const BundleStarted(this.control);

  final SendPort control;
}

/// The activator threw during start; the bundle has already torn itself down.
class BundleStartFailed {
  const BundleStartFailed(this.error);

  final String error;
}

/// Ask a running bundle to stop.
class StopBundle {
  const StopBundle();
}

/// The bundle's activator has stopped and its services are released.
class BundleStopped {
  const BundleStopped();
}

/// Everything a spawned bundle isolate needs, as one sendable argument.
class BundleSpawnRequest {
  const BundleSpawnRequest({
    required this.symbolicName,
    required this.framework,
    required this.activatorFactory,
    required this.loader,
  });

  final String symbolicName;
  final SendPort framework;
  final ActivatorFactory activatorFactory;
  final SendPort loader;
}

class _Loaded {
  _Loaded({
    required this.isolate,
    required this.fromBundle,
    required this.onExit,
    required this.onError,
  });

  final Isolate isolate;
  final ReceivePort fromBundle;
  final ReceivePort onExit;
  final ReceivePort onError;

  SendPort? control;
  Completer<void>? stopped;
}

/// What a spawned bundle isolate runs.
///
/// Top-level because `Isolate.spawn` needs an entry point that crosses without
/// closing over this isolate's state.
@pragma('vm:entry-point')
void bundleIsolateMain(BundleSpawnRequest request) async {
  final ReceivePort control = ReceivePort('bundle.${request.symbolicName}');
  final RemoteBundleContext context = RemoteBundleContext(
    symbolicName: request.symbolicName,
    framework: request.framework,
  );

  final ManagedBundle bundle = ManagedBundle(
    symbolicName: request.symbolicName,
    activator: request.activatorFactory(),
    transport: const DetachedShellTransport(),
    scope: RemoteScope(context),
  );

  try {
    await bundle.start();
  } catch (e) {
    // start() has already unwound: the context detached, so nothing of this
    // bundle is left in the framework. Report the reason as text, since the
    // error object itself may not be sendable.
    request.loader.send(BundleStartFailed('$e'));
    control.close();
    return;
  }

  request.loader.send(BundleStarted(control.sendPort));

  await for (final dynamic message in control) {
    if (message is StopBundle) break;
  }

  try {
    await bundle.stop();
  } on Object {
    // The teardown ran regardless; the loader is about to drop the isolate.
  }
  request.loader.send(const BundleStopped());
  control.close();
}
