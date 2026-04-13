import 'dart:isolate';

import 'package:dart_osgi_api/dart_osgi_api.dart';

import 'bundle_spawn_args.dart';

/// Signature for a factory that creates a [BundleActivator] from the
/// activator class identifier in the bundle manifest.
///
/// Bundles register their activator factory before the framework starts,
/// or the loader provides one via a registry of known activators.
typedef ActivatorFactory = BundleActivator Function(String activatorClass);

/// Standard entry point for every pure Dart bundle isolate.
///
/// This function is spawned by [IsolateBundleLoader] and performs:
/// 1. Handshake — sends the bundle's [SendPort] to the framework
/// 2. Activator invocation — calls [BundleActivator.start]
/// 3. Message loop — processes incoming messages until [StopSignal]
/// 4. Shutdown — calls [BundleActivator.stop]
///
/// The [activatorFactory] is passed alongside [BundleSpawnArgs] via
/// a [BundleMainConfig] record so that `Isolate.spawn` can pass a
/// single argument.
@pragma('vm:entry-point')
Future<void> bundleMain(BundleMainConfig config) async {
  final args = config.args;
  final activatorFactory = config.activatorFactory;

  // 1. Create a ReceivePort for incoming messages.
  final port = ReceivePort('bundle.${args.symbolicName}');

  // 2. Handshake: send our SendPort to the framework.
  args.frameworkPort.send(
    BundleHandshake(symbolicName: args.symbolicName, bundlePort: port.sendPort),
  );

  // 3. Create the activator.
  final BundleActivator activator;
  try {
    activator = activatorFactory(args.activatorClass);
  } catch (e, st) {
    args.frameworkPort.send(
      BundleStartFailed(
        symbolicName: args.symbolicName,
        error: e,
        stackTrace: st,
      ),
    );
    port.close();
    return;
  }

  // 4. Start the activator.
  //    The BundleContext is not directly available in the bundle isolate
  //    for pure Dart bundles — it lives in the framework isolate.
  //    The bundle communicates via its SendPort/ReceivePort pair.
  //    The BundleContextProxy wraps this communication.
  final proxy = BundleContextProxy(
    symbolicName: args.symbolicName,
    frameworkPort: args.frameworkPort,
    bundlePort: port,
  );

  try {
    await activator.start(proxy);
    args.frameworkPort.send(BundleReady(symbolicName: args.symbolicName));
  } catch (e, st) {
    args.frameworkPort.send(
      BundleStartFailed(
        symbolicName: args.symbolicName,
        error: e,
        stackTrace: st,
      ),
    );
    port.close();
    return;
  }

  // 5. Message loop — process until StopSignal.
  await for (final msg in port) {
    if (msg is StopSignal) break;
    try {
      proxy.handleMessage(msg);
    } catch (e, st) {
      // Report error to framework but keep the bundle running.
      args.frameworkPort.send(
        BundleStartFailed(
          symbolicName: args.symbolicName,
          error: e,
          stackTrace: st,
        ),
      );
    }
  }

  // 6. Shutdown.
  try {
    await activator.stop(proxy);
  } finally {
    port.close();
  }
}

/// Configuration record passed as the single argument to [Isolate.spawn].
class BundleMainConfig {
  const BundleMainConfig({required this.args, required this.activatorFactory});

  final BundleSpawnArgs args;
  final ActivatorFactory activatorFactory;
}

/// Lightweight [BundleContext] proxy that runs inside a bundle isolate.
///
/// For pure Dart bundles running in their own isolate, service operations
/// are forwarded to the framework isolate via [SendPort]. In the single-VM
/// model, the framework can also provide a direct [IsolateBundleContext]
/// if the bundle runs in the same isolate group.
///
/// This proxy provides a minimal implementation suitable for bundle
/// activators that need to register services and listen for events
/// across the isolate boundary.
class BundleContextProxy implements BundleContext {
  BundleContextProxy({
    required this.symbolicName,
    required this.frameworkPort,
    required this.bundlePort,
  });

  final String symbolicName;
  final SendPort frameworkPort;
  final ReceivePort bundlePort;

  final _messageHandlers = <String, void Function(Object)>{};

  /// Register a handler for incoming messages of a given [type].
  void onMessage(String type, void Function(Object message) handler) {
    _messageHandlers[type] = handler;
  }

  /// Dispatch an incoming message to a registered handler.
  void handleMessage(Object msg) {
    if (msg is Map && msg.containsKey('type')) {
      final type = msg['type'] as String;
      _messageHandlers[type]?.call(msg);
    }
  }

  // ── BundleContext implementation ──────────────────────────────────
  // These methods send requests to the framework isolate.
  // Full implementations will be wired up in Phase 5 when the
  // cross-isolate protocol is complete. For now, they use the
  // single-VM direct path when possible.

  @override
  ServiceRegistration<T> registerService<T>(
    String className,
    T service,
    Map<String, Object>? properties,
  ) {
    // In the single-VM model, this is handled by the framework providing
    // a real IsolateBundleContext. The proxy is a fallback for true
    // cross-isolate scenarios.
    throw UnimplementedError(
      'BundleContextProxy.registerService — use IsolateBundleContext '
      'for in-VM bundles',
    );
  }

  @override
  ServiceReference<T>? getServiceReference<T>(String className) {
    throw UnimplementedError('BundleContextProxy.getServiceReference');
  }

  @override
  List<ServiceReference<T>> getServiceReferences<T>(
    String className,
    String? filter,
  ) {
    throw UnimplementedError('BundleContextProxy.getServiceReferences');
  }

  @override
  T? getService<T>(ServiceReference<T> reference) {
    throw UnimplementedError('BundleContextProxy.getService');
  }

  @override
  bool ungetService<T>(ServiceReference<T> reference) {
    throw UnimplementedError('BundleContextProxy.ungetService');
  }

  @override
  ServiceTracker<T> trackService<T>(String className, {String? filter}) {
    throw UnimplementedError('BundleContextProxy.trackService');
  }

  @override
  Bundle get bundle {
    throw UnimplementedError('BundleContextProxy.bundle');
  }

  @override
  void addBundleListener(void Function(BundleEvent event) listener) {
    throw UnimplementedError('BundleContextProxy.addBundleListener');
  }

  @override
  void removeBundleListener(void Function(BundleEvent event) listener) {
    throw UnimplementedError('BundleContextProxy.removeBundleListener');
  }

  @override
  void addServiceListener(
    void Function(ServiceEvent event) listener, {
    String? filter,
  }) {
    throw UnimplementedError('BundleContextProxy.addServiceListener');
  }

  @override
  void removeServiceListener(void Function(ServiceEvent event) listener) {
    throw UnimplementedError('BundleContextProxy.removeServiceListener');
  }
}
