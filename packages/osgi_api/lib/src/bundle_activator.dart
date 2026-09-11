import 'bundle_state.dart';

/// A bundle's entry point, in the OSGi sense.
///
/// [start] completing is what ACTIVE means. Not the engine being up, which the
/// shell already knows; not the first frame, which says nothing about whether
/// this code is ready. A critical bundle's startup deadline is running until
/// [start] returns, and the shell holds the reactor for it -- so work that must
/// finish before the bundle is fit to be seen belongs in here, and work that
/// merely should happen soon does not.
abstract interface class BundleActivator {
  Future<void> start(BundleContext context);
  Future<void> stop(BundleContext context);
}

/// What a bundle can see of the framework it is running in.
///
/// Deliberately narrow: a bundle registers services, finds services, and knows
/// its own identity. It does not reach the shell, other bundles' internals, or
/// the framework isolate directly.
abstract interface class BundleContext {
  String get symbolicName;

  BundleState get state;

  /// Publish a service under [interfaceName] with [properties].
  ///
  /// Properties are sent by reference between isolates when they are `const`,
  /// which is why the registry treats them as immutable.
  Future<ServiceRegistration> registerService(
    String interfaceName,
    Object? service, [
    Map<String, Object?> properties,
  ]);

  /// Watch a service by interface name, optionally narrowed by an LDAP
  /// [filter]. A malformed filter throws a [FormatException].
  ServiceTracker trackService(String interfaceName, {String? filter});
}

/// A published service, from the publisher's side.
abstract interface class ServiceRegistration {
  String get interfaceName;
  Map<String, Object?> get properties;
  Future<void> unregister();
}

/// A view onto services matching a query, from the consumer's side.
abstract interface class ServiceTracker {
  /// Each listener first receives the services already tracked, then later
  /// additions -- whether it started listening before or after [open].
  Stream<Object?> get addingService;
  Stream<Object?> get removedService;
  Future<void> open();
  Future<void> close();
}
