import 'dart:async';
import 'dart:isolate';

import '../framework/dart_osgi_framework.dart';
import '../lifecycle/managed_bundle.dart';
import '../manifest/bundle_manifest.dart';
import 'bundle_main.dart';
import 'bundle_spawn_args.dart';

/// Spawns a Dart [Isolate] for each pure Dart bundle, performs the
/// handshake, invokes the activator, and manages restart on failure.
///
/// Uses [Isolate.spawn] which shares the isolate group (same compiled
/// code heap) — saves ~10–20MB per bundle vs. [Isolate.spawnUri].
class IsolateBundleLoader {
  IsolateBundleLoader({
    required this.framework,
    required this.activatorFactory,
  });

  final DartOSGiFramework framework;
  final ActivatorFactory activatorFactory;

  /// Tracks running bundle isolates and their restart state.
  final _running = <String, _BundleIsolateEntry>{};

  /// Load and start a pure Dart bundle.
  ///
  /// Spawns the bundle isolate, performs the handshake (waits for the
  /// bundle's [SendPort]), registers it on the [IsolateBus], and
  /// transitions the bundle through STARTING → ACTIVE.
  ///
  /// Throws [TimeoutException] if the bundle doesn't complete the
  /// handshake within its configured [StartupConfig.timeoutMs].
  Future<void> loadBundle(ManagedBundle bundle) async {
    if (bundle.manifest.type != BundleType.dart) {
      throw ArgumentError(
        'IsolateBundleLoader only handles dart-type bundles, '
        'got ${bundle.manifest.type} for "${bundle.symbolicName}"',
      );
    }

    await _spawnBundle(bundle, restartCount: 0);
  }

  /// Stop a running bundle isolate.
  Future<void> stopBundle(String symbolicName) async {
    final entry = _running.remove(symbolicName);
    if (entry == null) return;

    // Send stop signal to the bundle.
    entry.bundlePort?.send(const StopSignal());

    // Give the bundle a grace period to shut down.
    await Future<void>.delayed(const Duration(milliseconds: 500));

    entry.isolate.kill(priority: Isolate.beforeNextEvent);
    entry.handshakePort.close();
    entry.errorPort.close();
    entry.exitPort.close();
  }

  /// Spawn (or re-spawn) a bundle isolate.
  Future<void> _spawnBundle(
    ManagedBundle bundle, {
    required int restartCount,
  }) async {
    final handshakePort = ReceivePort('handshake.${bundle.symbolicName}');
    final errorPort = ReceivePort('error.${bundle.symbolicName}');
    final exitPort = ReceivePort('exit.${bundle.symbolicName}');

    final args = BundleSpawnArgs(
      frameworkPort: handshakePort.sendPort,
      symbolicName: bundle.symbolicName,
      version: bundle.version,
      activatorClass: bundle.manifest.activator,
      priority: bundle.priority,
      properties: bundle.headers,
    );

    final config = BundleMainConfig(
      args: args,
      activatorFactory: activatorFactory,
    );

    // Spawn in the same isolate group for code heap sharing.
    final isolate = await Isolate.spawn(
      bundleMain,
      config,
      debugName: 'bundle.${bundle.symbolicName}',
      errorsAreFatal: false,
      onError: errorPort.sendPort,
      onExit: exitPort.sendPort,
    );

    final entry = _BundleIsolateEntry(
      isolate: isolate,
      handshakePort: handshakePort,
      errorPort: errorPort,
      exitPort: exitPort,
      restartCount: restartCount,
    );
    _running[bundle.symbolicName] = entry;

    // Wait for handshake with timeout.
    final timeoutMs = bundle.manifest.startup.timeoutMs;
    final handshakeCompleter = Completer<void>();

    late final StreamSubscription<dynamic> handshakeSub;
    handshakeSub = handshakePort.listen((dynamic msg) {
      if (msg is BundleHandshake) {
        entry.bundlePort = msg.bundlePort;
        framework.bus.registerPort(bundle.symbolicName, msg.bundlePort);
      } else if (msg is BundleReady) {
        if (!handshakeCompleter.isCompleted) {
          handshakeCompleter.complete();
        }
      } else if (msg is BundleStartFailed) {
        if (!handshakeCompleter.isCompleted) {
          handshakeCompleter.completeError(
            BundleLoadException(bundle.symbolicName, msg.error, msg.stackTrace),
          );
        }
      }
    });

    // Listen for isolate errors and exits for restart policy.
    errorPort.listen((dynamic error) {
      _onBundleError(bundle, error);
    });

    exitPort.listen((_) {
      _onBundleExit(bundle);
    });

    try {
      await handshakeCompleter.future.timeout(
        Duration(milliseconds: timeoutMs),
        onTimeout: () {
          throw TimeoutException(
            'Bundle "${bundle.symbolicName}" did not complete startup '
            'within ${timeoutMs}ms',
            Duration(milliseconds: timeoutMs),
          );
        },
      );
    } catch (e) {
      // Clean up on failure.
      await handshakeSub.cancel();
      isolate.kill(priority: Isolate.beforeNextEvent);
      handshakePort.close();
      errorPort.close();
      exitPort.close();
      _running.remove(bundle.symbolicName);
      rethrow;
    }

    await handshakeSub.cancel();
  }

  /// Handle a bundle isolate error — schedule restart if policy allows.
  void _onBundleError(ManagedBundle bundle, Object error) {
    final entry = _running[bundle.symbolicName];
    if (entry == null) return;

    final delay = _restartDelay(entry.restartCount);
    if (delay == null) {
      // Give up — max retries exceeded.
      _running.remove(bundle.symbolicName);
      return;
    }

    // Schedule restart after backoff.
    Timer(delay, () {
      _running.remove(bundle.symbolicName);
      _spawnBundle(bundle, restartCount: entry.restartCount + 1);
    });
  }

  /// Handle a bundle isolate exit — restart if it wasn't a clean shutdown.
  void _onBundleExit(ManagedBundle bundle) {
    final entry = _running.remove(bundle.symbolicName);
    if (entry == null) return;

    // If the bundle was explicitly stopped (removed from _running by
    // stopBundle), this listener won't fire. An unexpected exit triggers
    // restart.
    if (entry.bundlePort != null) {
      framework.bus.unregisterPort(bundle.symbolicName);
    }

    final delay = _restartDelay(entry.restartCount);
    if (delay == null) return;

    Timer(delay, () {
      _spawnBundle(bundle, restartCount: entry.restartCount + 1);
    });
  }

  /// Exponential backoff delays: 0ms, 100ms, 500ms, 2s, 10s, then give up.
  static Duration? _restartDelay(int restartCount) {
    return switch (restartCount) {
      0 => Duration.zero,
      1 => const Duration(milliseconds: 100),
      2 => const Duration(milliseconds: 500),
      3 => const Duration(seconds: 2),
      4 => const Duration(seconds: 10),
      _ => null, // give up
    };
  }

  /// Stop all running bundle isolates.
  Future<void> dispose() async {
    final names = _running.keys.toList();
    for (final name in names) {
      await stopBundle(name);
    }
  }
}

/// Tracks a running bundle isolate and its communication ports.
class _BundleIsolateEntry {
  _BundleIsolateEntry({
    required this.isolate,
    required this.handshakePort,
    required this.errorPort,
    required this.exitPort,
    required this.restartCount,
  });

  final Isolate isolate;
  final ReceivePort handshakePort;
  final ReceivePort errorPort;
  final ReceivePort exitPort;
  final int restartCount;

  /// The bundle's SendPort, set after handshake completes.
  SendPort? bundlePort;
}

/// Thrown when a bundle fails to load.
class BundleLoadException implements Exception {
  BundleLoadException(this.symbolicName, this.error, this.stackTrace);

  final String symbolicName;
  final Object error;
  final StackTrace stackTrace;

  @override
  String toString() =>
      'BundleLoadException: bundle "$symbolicName" failed to start: $error';
}
