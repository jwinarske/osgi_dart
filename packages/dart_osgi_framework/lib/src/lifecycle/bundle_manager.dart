import 'dart:async';

import 'package:dart_osgi_api/dart_osgi_api.dart';

import '../manifest/bundle_manifest.dart';
import '../manifest/dependency_graph.dart';
import 'managed_bundle.dart';

/// Orchestrates bundle installation, dependency resolution, and lifecycle
/// transitions.
///
/// Loads [BundleManifest]s, builds a [DependencyGraph], and drives bundles
/// through the INSTALLED → RESOLVED → STARTING → ACTIVE lifecycle.
/// Actual isolate/engine spawning is delegated to a [BundleLoader] (Phase 4/5).
class BundleManager {
  BundleManager();

  final _bundles = <String, ManagedBundle>{};
  final _bundleEventSubs = <String, StreamSubscription<BundleEvent>>{};

  final _eventController = StreamController<BundleEvent>.broadcast();

  /// Aggregated lifecycle event stream across all managed bundles.
  Stream<BundleEvent> get events => _eventController.stream;

  /// All currently managed bundles, keyed by symbolic name.
  Map<String, Bundle> get bundles => Map.unmodifiable(_bundles);

  /// Install a bundle from a parsed [BundleManifest].
  ///
  /// The bundle enters the INSTALLED state. Call [resolve] to attempt
  /// dependency resolution across all installed bundles.
  ManagedBundle install(BundleManifest manifest) {
    if (_bundles.containsKey(manifest.symbolicName)) {
      throw StateError(
        'Bundle "${manifest.symbolicName}" is already installed',
      );
    }

    final bundle = ManagedBundle(manifest);
    _bundles[manifest.symbolicName] = bundle;

    // Forward per-bundle events to the aggregate stream.
    _bundleEventSubs[manifest.symbolicName] =
        bundle.stateManager.events.listen(_eventController.add);

    return bundle;
  }

  /// Install a bundle by loading its manifest from [yamlPath].
  Future<ManagedBundle> installFromPath(String yamlPath) async {
    final manifest = await BundleManifest.load(yamlPath);
    return install(manifest);
  }

  /// Resolve dependencies across all installed bundles.
  ///
  /// Returns the [DependencyGraph] result. Bundles whose imports are
  /// satisfied transition from INSTALLED to RESOLVED.
  DependencyGraph resolve() {
    final manifests = _bundles.values.map((b) => b.manifest).toList();
    final graph = DependencyGraph.resolve(manifests);

    // Transition resolved bundles from INSTALLED to RESOLVED.
    for (final manifest in graph.resolved) {
      final bundle = _bundles[manifest.symbolicName]!;
      if (bundle.state == BundleState.installed) {
        bundle.stateManager.transition(BundleState.resolved);
      }
    }

    return graph;
  }

  /// Returns bundles in dependency-resolved startup order, grouped by
  /// priority. Critical bundles come first.
  List<ManagedBundle> startupOrder() {
    final manifests = _bundles.values.map((b) => b.manifest).toList();
    final graph = DependencyGraph.resolve(manifests);
    return [for (final m in graph.resolved) _bundles[m.symbolicName]!];
  }

  /// Transition a bundle to STARTING state.
  ///
  /// The bundle must be in RESOLVED state. The actual activator invocation
  /// is handled by the bundle loader (Phase 4/5).
  void starting(String symbolicName) {
    final bundle = _requireBundle(symbolicName);
    bundle.stateManager.transition(BundleState.starting);
  }

  /// Transition a bundle to ACTIVE state.
  void started(String symbolicName) {
    final bundle = _requireBundle(symbolicName);
    bundle.stateManager.transition(BundleState.active);
  }

  /// Transition a bundle to STOPPING state.
  void stopping(String symbolicName) {
    final bundle = _requireBundle(symbolicName);
    bundle.stateManager.transition(BundleState.stopping);
  }

  /// Transition a stopped bundle back to RESOLVED (restartable) or
  /// UNINSTALLED (terminal).
  void stopped(String symbolicName, {bool uninstall = false}) {
    final bundle = _requireBundle(symbolicName);
    if (uninstall) {
      bundle.stateManager.transition(BundleState.uninstalled);
      _bundles.remove(symbolicName);
      bundle.stateManager.dispose();
    } else {
      bundle.stateManager.transition(BundleState.resolved);
    }
  }

  /// Uninstall a bundle from any state.
  void uninstall(String symbolicName) {
    final bundle = _requireBundle(symbolicName);
    if (bundle.state == BundleState.active) {
      bundle.stateManager.transition(BundleState.stopping);
    }
    if (bundle.state != BundleState.uninstalled) {
      bundle.stateManager.transition(BundleState.uninstalled);
    }
    _bundles.remove(symbolicName);
    _bundleEventSubs.remove(symbolicName)?.cancel();
    bundle.stateManager.dispose();
  }

  /// Look up a managed bundle by symbolic name.
  ManagedBundle? getBundle(String symbolicName) => _bundles[symbolicName];

  ManagedBundle _requireBundle(String symbolicName) {
    final bundle = _bundles[symbolicName];
    if (bundle == null) {
      throw StateError('No bundle installed with name "$symbolicName"');
    }
    return bundle;
  }

  /// Dispose all bundles and close the event stream.
  void dispose() {
    for (final sub in _bundleEventSubs.values) {
      sub.cancel();
    }
    _bundleEventSubs.clear();
    for (final bundle in _bundles.values) {
      bundle.stateManager.dispose();
    }
    _bundles.clear();
    _eventController.close();
  }
}
