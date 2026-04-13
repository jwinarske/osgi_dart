import 'dart:async';

import 'package:dart_osgi_api/dart_osgi_api.dart';

import '../lifecycle/bundle_manager.dart';
import '../lifecycle/managed_bundle.dart';
import '../manifest/bundle_manifest.dart';
import '../manifest/dependency_graph.dart';
import '../registry/service_registry.dart';
import 'framework_isolate.dart';
import 'framework_message.dart';
import 'isolate_bundle_context.dart';
import 'isolate_bus.dart';

/// Top-level singleton that wires together all OSGi framework subsystems.
///
/// Provides a single entry point for:
/// - Installing and resolving bundles
/// - Starting/stopping the framework event loop
/// - Accessing the service registry, bundle manager, and isolate bus
class DartOSGiFramework {
  DartOSGiFramework._();

  static DartOSGiFramework? _instance;

  /// The singleton framework instance.
  static DartOSGiFramework get instance => _instance ??= DartOSGiFramework._();

  final ServiceRegistry _registry = ServiceRegistry();
  final BundleManager _bundleManager = BundleManager();
  final IsolateBus _bus = IsolateBus();
  FrameworkIsolate? _isolate;

  bool _started = false;

  /// The service registry.
  ServiceRegistry get registry => _registry;

  /// The bundle manager.
  BundleManager get bundleManager => _bundleManager;

  /// The isolate message bus.
  IsolateBus get bus => _bus;

  /// Whether the framework has been started.
  bool get isStarted => _started;

  /// Aggregated stream of all bundle lifecycle events.
  Stream<BundleEvent> get bundleEvents => _bundleManager.events;

  /// Aggregated stream of all service registry events.
  Stream<ServiceEvent> get serviceEvents => _registry.events;

  /// Start the framework.
  ///
  /// Creates the framework isolate with dual priority ports and begins
  /// processing messages.
  void start({FrameworkIsolateConfig? config}) {
    if (_started) return;
    _started = true;

    _isolate = FrameworkIsolate.create(config: config);
    _isolate!.start(_handleMessage);
  }

  /// Install a bundle from a [BundleManifest].
  ManagedBundle installBundle(BundleManifest manifest) {
    return _bundleManager.install(manifest);
  }

  /// Install a bundle by loading its manifest from a YAML file.
  Future<ManagedBundle> installBundleFromPath(String yamlPath) {
    return _bundleManager.installFromPath(yamlPath);
  }

  /// Resolve dependencies across all installed bundles.
  DependencyGraph resolveAll() {
    return _bundleManager.resolve();
  }

  /// Start a resolved bundle: transitions through STARTING → ACTIVE
  /// and creates its [IsolateBundleContext].
  ///
  /// Returns the [IsolateBundleContext] assigned to the bundle.
  IsolateBundleContext startBundle(String symbolicName) {
    _ensureStarted();

    final bundle = _bundleManager.getBundle(symbolicName);
    if (bundle == null) {
      throw StateError('No bundle installed with name "$symbolicName"');
    }

    // Determine which framework port this bundle should use.
    final frameworkPort = bundle.priority == BundlePriority.critical
        ? _isolate!.prioritySendPort
        : _isolate!.normalSendPort;

    final context = IsolateBundleContext(
      managedBundle: bundle,
      registry: _registry,
      bus: _bus,
      frameworkPort: frameworkPort,
      bundleEvents: _bundleManager.events,
      serviceEvents: _registry.events,
    );

    bundle.bundleContext = context;
    _bundleManager.starting(symbolicName);
    _bundleManager.started(symbolicName);

    return context;
  }

  /// Stop an active bundle: transitions through STOPPING → RESOLVED,
  /// disposes its context, and unregisters its bus port.
  Future<void> stopBundle(String symbolicName) async {
    final bundle = _bundleManager.getBundle(symbolicName);
    if (bundle == null) return;

    final context = bundle.bundleContext;
    if (context is IsolateBundleContext) {
      await context.dispose();
    }
    bundle.bundleContext = null;

    _bus.unregisterPort(symbolicName);
    _bundleManager.stopping(symbolicName);
    _bundleManager.stopped(symbolicName);
  }

  /// Uninstall a bundle completely.
  Future<void> uninstallBundle(String symbolicName) async {
    await stopBundle(symbolicName);
    _bundleManager.uninstall(symbolicName);
  }

  /// Stop the framework and release all resources.
  Future<void> stop() async {
    if (!_started) return;

    // Stop all active bundles.
    final activeNames = _bundleManager.bundles.keys.toList();
    for (final name in activeNames) {
      final bundle = _bundleManager.getBundle(name);
      if (bundle != null && bundle.state == BundleState.active) {
        await stopBundle(name);
      }
    }

    _isolate?.stop();
    _isolate = null;
    _bus.dispose();
    _registry.dispose();
    _bundleManager.dispose();
    _started = false;
    _instance = null;
  }

  /// Handle a message from the framework isolate's scheduler.
  void _handleMessage(FrameworkMessage message) {
    switch (message.type) {
      case FrameworkMessageType.registerPort:
        final payload = message.payload as RegisterPortPayload;
        _bus.registerPort(payload.bundleSymbolicName, payload.sendPort);

      case FrameworkMessageType.sendToBundle:
        final payload = message.payload as SendToBundlePayload;
        _bus.sendTo(payload.targetBundle, payload.message);

      case FrameworkMessageType.stopBundle:
        stopBundle(message.bundleSymbolicName);

      default:
        // Other message types are handled directly by IsolateBundleContext
        // within the same VM — they don't go through the isolate message loop.
        break;
    }
  }

  void _ensureStarted() {
    if (!_started) {
      throw StateError('Framework has not been started — call start() first');
    }
  }
}
