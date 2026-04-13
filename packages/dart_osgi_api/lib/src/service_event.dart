import 'service_reference.dart';

/// Types of service registry events.
enum ServiceEventType {
  registered,
  modified,
  unregistering,
}

/// Fired when a service is registered, modified, or unregistered.
class ServiceEvent {
  ServiceEvent(this.type, this.reference);

  /// The type of registry change.
  final ServiceEventType type;

  /// The service reference affected.
  final ServiceReference<Object> reference;

  @override
  String toString() => 'ServiceEvent($type, ${reference.bundleSymbolicName})';
}
