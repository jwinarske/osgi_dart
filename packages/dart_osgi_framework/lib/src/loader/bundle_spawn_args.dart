import 'dart:isolate';

import 'package:dart_osgi_api/dart_osgi_api.dart';

/// Arguments passed to a bundle isolate at spawn time.
///
/// Carries everything the bundle needs to bootstrap: the framework's
/// [SendPort] for handshake, the bundle's identity, and its manifest
/// metadata.
class BundleSpawnArgs {
  const BundleSpawnArgs({
    required this.frameworkPort,
    required this.symbolicName,
    required this.version,
    required this.activatorClass,
    required this.priority,
    required this.properties,
  });

  /// The framework isolate's [SendPort]. The bundle sends its own
  /// [ReceivePort.sendPort] back through this port to complete the handshake.
  final SendPort frameworkPort;

  /// The bundle's symbolic name (e.g. "com.ivi.can-service").
  final String symbolicName;

  /// The bundle's version string.
  final String version;

  /// The activator class identifier from bundle.yaml.
  final String activatorClass;

  /// The bundle's startup priority.
  final BundlePriority priority;

  /// Manifest headers and extra properties for the bundle.
  final Map<String, Object> properties;
}

/// Messages exchanged during the bundle ↔ framework handshake.
sealed class HandshakeMessage {
  const HandshakeMessage();
}

/// Sent from the bundle isolate to the framework after spawning.
/// Carries the bundle's [SendPort] for bidirectional communication.
class BundleHandshake extends HandshakeMessage {
  const BundleHandshake({required this.symbolicName, required this.bundlePort});

  final String symbolicName;
  final SendPort bundlePort;
}

/// Sent from the framework to the bundle isolate to signal shutdown.
class StopSignal extends HandshakeMessage {
  const StopSignal();
}

/// Sent from the bundle isolate to the framework when the activator
/// has completed [BundleActivator.start].
class BundleReady extends HandshakeMessage {
  const BundleReady({required this.symbolicName});
  final String symbolicName;
}

/// Sent from the bundle isolate to the framework if the activator
/// threw during [BundleActivator.start].
class BundleStartFailed extends HandshakeMessage {
  const BundleStartFailed({
    required this.symbolicName,
    required this.error,
    required this.stackTrace,
  });

  final String symbolicName;
  final Object error;
  final StackTrace stackTrace;
}
