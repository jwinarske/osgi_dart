import 'service_reference.dart';

/// Returned when a service is registered with the framework.
///
/// Holds a [reference] to the service and allows updating properties
/// or withdrawing the service via [unregister].
abstract class ServiceRegistration<T> {
  /// The [ServiceReference] for this registration.
  ServiceReference<T> get reference;

  /// Replaces the service properties.
  ///
  /// Notifies all [ServiceTracker]s with a MODIFIED event.
  void setProperties(Map<String, Object> properties);

  /// Withdraws this service from the registry.
  ///
  /// After this call the [ServiceReference] is no longer valid.
  Future<void> unregister();
}
