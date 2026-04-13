import 'dart:async';

import 'package:dart_osgi_api/dart_osgi_api.dart';

import '../framework/dart_osgi_framework.dart';
import '../framework/isolate_bundle_context.dart';
import '../lifecycle/managed_bundle.dart';

/// Dart-side startup orchestrator that enforces priority-ordered
/// bundle startup with staggered delays.
///
/// Startup sequence:
/// 1. Start all **critical** bundles synchronously — block until each
///    is ACTIVE (max timeout per bundle from manifest).
/// 2. Start **normal** bundles staggered 50ms apart.
/// 3. Start **background** bundles after all normal bundles.
class StartupOrchestrator {
  StartupOrchestrator(this._framework);

  final DartOSGiFramework _framework;

  /// Delay between starting normal-priority bundles.
  static const normalStaggerDelay = Duration(milliseconds: 50);

  /// Execute the full startup sequence for all installed bundles.
  ///
  /// Returns the list of bundles that failed to start (empty on success).
  Future<List<StartupFailure>> executeStartup() async {
    final order = _framework.bundleManager.startupOrder();
    final failures = <StartupFailure>[];

    final critical = order.where(
      (b) => b.manifest.startup.priority == BundlePriority.critical,
    );
    final normal = order.where(
      (b) => b.manifest.startup.priority == BundlePriority.normal,
    );
    final background = order.where(
      (b) => b.manifest.startup.priority == BundlePriority.background,
    );

    // 1. Critical bundles — synchronous, blocking.
    for (final bundle in critical) {
      final failure = await _startWithTimeout(bundle);
      if (failure != null) failures.add(failure);
    }

    // 2. Normal bundles — staggered 50ms apart.
    for (final bundle in normal) {
      final failure = await _startWithTimeout(bundle);
      if (failure != null) failures.add(failure);
      await Future<void>.delayed(normalStaggerDelay);
    }

    // 3. Background bundles — after all normal.
    for (final bundle in background) {
      final failure = await _startWithTimeout(bundle);
      if (failure != null) failures.add(failure);
    }

    return failures;
  }

  /// Start a single bundle with its configured timeout.
  Future<StartupFailure?> _startWithTimeout(ManagedBundle bundle) async {
    final timeoutMs = bundle.manifest.startup.timeoutMs;
    try {
      await Future<IsolateBundleContext>(
        () => _framework.startBundle(bundle.symbolicName),
      ).timeout(
        Duration(milliseconds: timeoutMs),
        onTimeout: () => throw TimeoutException(
          'Bundle "${bundle.symbolicName}" did not start within ${timeoutMs}ms',
          Duration(milliseconds: timeoutMs),
        ),
      );
      // Verify the bundle reached ACTIVE state.
      if (bundle.state != BundleState.active) {
        return StartupFailure(
          symbolicName: bundle.symbolicName,
          reason: 'Bundle is in ${bundle.state} state, expected active',
        );
      }
      return null;
    } on TimeoutException catch (e) {
      return StartupFailure(
        symbolicName: bundle.symbolicName,
        reason: e.message ?? 'Startup timeout',
      );
    } catch (e) {
      return StartupFailure(
        symbolicName: bundle.symbolicName,
        reason: e.toString(),
      );
    }
  }
}

/// Records a bundle that failed to start during orchestrated startup.
class StartupFailure {
  const StartupFailure({required this.symbolicName, required this.reason});

  final String symbolicName;
  final String reason;

  @override
  String toString() => 'StartupFailure($symbolicName: $reason)';
}
