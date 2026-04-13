import 'dart:isolate';

/// Message types exchanged between bundle isolates and the framework isolate.
enum FrameworkMessageType {
  // Service registry operations
  registerService,
  unregisterService,
  setServiceProperties,
  getServiceReference,
  getServiceReferences,
  getService,
  ungetService,

  // Event listener operations
  addBundleListener,
  removeBundleListener,
  addServiceListener,
  removeServiceListener,

  // Service tracking
  openTracker,
  closeTracker,

  // Bus operations
  registerPort,
  sendToBundle,

  // Lifecycle
  bundleReady,
  stopBundle,

  // Responses
  response,
  event,
}

/// A message sent between bundle isolates and the framework isolate.
///
/// Uses a flat structure to avoid allocation on the hot path.
/// The [payload] is typed per [type] — see each handler for the expected shape.
class FrameworkMessage {
  const FrameworkMessage({
    required this.type,
    required this.bundleSymbolicName,
    this.payload,
    this.replyPort,
    this.requestId,
  });

  final FrameworkMessageType type;
  final String bundleSymbolicName;
  final Object? payload;
  final SendPort? replyPort;
  final int? requestId;
}

/// Payload for [FrameworkMessageType.registerService].
class RegisterServicePayload {
  const RegisterServicePayload({
    required this.className,
    required this.service,
    this.properties,
  });

  final String className;
  final Object service;
  final Map<String, Object>? properties;
}

/// Payload for [FrameworkMessageType.getServiceReferences].
class GetServiceReferencesPayload {
  const GetServiceReferencesPayload({required this.className, this.filter});

  final String className;
  final String? filter;
}

/// Payload for [FrameworkMessageType.sendToBundle].
class SendToBundlePayload {
  const SendToBundlePayload({
    required this.targetBundle,
    required this.message,
  });

  final String targetBundle;
  final Object message;
}

/// Payload for [FrameworkMessageType.registerPort].
class RegisterPortPayload {
  const RegisterPortPayload({
    required this.bundleSymbolicName,
    required this.sendPort,
  });

  final String bundleSymbolicName;
  final SendPort sendPort;
}
