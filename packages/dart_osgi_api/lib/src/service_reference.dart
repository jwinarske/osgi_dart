/// A reference to a registered service.
///
/// Provides access to service properties and metadata without
/// holding a direct reference to the service object.
abstract class ServiceReference<T> implements Comparable<ServiceReference<T>> {
  /// The service property map.
  Map<String, Object> get properties;

  /// Returns the value of a named service property, or `null` if absent.
  Object? getProperty(String key);

  /// The symbolic name of the bundle that registered this service.
  String get bundleSymbolicName;

  /// The service ranking. Higher ranking wins when multiple services
  /// match the same interface. Default is 0.
  int get ranking;

  /// The unique service ID assigned by the framework at registration time.
  int get serviceId;
}
