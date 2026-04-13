import 'bundle.dart';
import 'bundle_event.dart';
import 'service_event.dart';
import 'service_reference.dart';
import 'service_registration.dart';
import 'service_tracker.dart';

/// Per-bundle execution context provided by the framework.
///
/// A bundle uses its [BundleContext] to interact with the OSGi framework:
/// registering services, looking up services, tracking services, and
/// listening to lifecycle events.
abstract class BundleContext {
  // ── Service registration ──────────────────────────────────────────

  /// Registers a service under [className] with optional [properties].
  ///
  /// Returns a [ServiceRegistration] that can be used to update properties
  /// or withdraw the service.
  ServiceRegistration<T> registerService<T>(
    String className,
    T service,
    Map<String, Object>? properties,
  );

  // ── Service lookup ────────────────────────────────────────────────

  /// Returns the best-ranked [ServiceReference] for [className], or `null`.
  ServiceReference<T>? getServiceReference<T>(String className);

  /// Returns all [ServiceReference]s for [className], optionally filtered
  /// by an LDAP-style [filter] string.
  List<ServiceReference<T>> getServiceReferences<T>(
    String className,
    String? filter,
  );

  /// Returns the service object for a [ServiceReference].
  T? getService<T>(ServiceReference<T> reference);

  /// Releases a service obtained via [getService].
  bool ungetService<T>(ServiceReference<T> reference);

  // ── Service tracking ──────────────────────────────────────────────

  /// Creates a [ServiceTracker] for [className] with an optional
  /// LDAP-style [filter].
  ServiceTracker<T> trackService<T>(String className, {String? filter});

  // ── Bundle access ─────────────────────────────────────────────────

  /// The [Bundle] that owns this context.
  Bundle get bundle;

  // ── Event listeners ───────────────────────────────────────────────

  /// Registers a listener for bundle lifecycle events.
  void addBundleListener(void Function(BundleEvent event) listener);

  /// Removes a previously registered bundle listener.
  void removeBundleListener(void Function(BundleEvent event) listener);

  /// Registers a listener for service registry events, optionally filtered
  /// by an LDAP-style [filter] string.
  void addServiceListener(
    void Function(ServiceEvent event) listener, {
    String? filter,
  });

  /// Removes a previously registered service listener.
  void removeServiceListener(void Function(ServiceEvent event) listener);
}
