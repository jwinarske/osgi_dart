import 'dart:async';

import 'package:dart_osgi_framework/dart_osgi_framework.dart';

/// Injectable test registry with pre-seeded services and call tracking.
///
/// Use [seed] to pre-register services before bundles start, and
/// inspect [registrations], [lookups], and [unregistrations] after
/// tests to verify bundle behavior.
class MockServiceRegistry extends ServiceRegistry {
  final _seededServices = <String, _SeededService>{};
  final registrations = <RegisterCall>[];
  final lookups = <LookupCall>[];
  final unregistrations = <String>[];

  /// Pre-seed a service so bundles find it immediately on lookup.
  void seed<T>(
    String className,
    T service, {
    String bundleSymbolicName = 'test.bundle',
    Map<String, Object>? properties,
  }) {
    final reg = register<T>(className, service, bundleSymbolicName, properties);
    _seededServices[className] = _SeededService(
      className: className,
      registration: reg as ServiceRegistration<Object>,
    );
  }

  /// Remove a previously seeded service.
  Future<void> unseed(String className) async {
    final seeded = _seededServices.remove(className);
    if (seeded != null) {
      await seeded.registration.unregister();
    }
  }

  /// All currently seeded service class names.
  Iterable<String> get seededClassNames => _seededServices.keys;

  @override
  RegistryServiceRegistration<T> register<T>(
    String className,
    T service,
    String bundleSymbolicName,
    Map<String, Object>? properties,
  ) {
    registrations.add(
      RegisterCall(
        className: className,
        bundleSymbolicName: bundleSymbolicName,
      ),
    );
    return super.register(className, service, bundleSymbolicName, properties);
  }

  @override
  ServiceReference<T>? getServiceReference<T>(String className) {
    lookups.add(LookupCall(className: className));
    return super.getServiceReference<T>(className);
  }

  @override
  void unregisterService<T>(RegistryServiceRegistration<T> registration) {
    unregistrations.add(registration.className);
    super.unregisterService(registration);
  }

  /// Reset all tracking lists (does not remove seeded services).
  void resetTracking() {
    registrations.clear();
    lookups.clear();
    unregistrations.clear();
  }

  /// Remove all seeded services and reset tracking.
  Future<void> reset() async {
    for (final seeded in _seededServices.values) {
      await seeded.registration.unregister();
    }
    _seededServices.clear();
    resetTracking();
  }
}

class _SeededService {
  _SeededService({required this.className, required this.registration});
  final String className;
  final ServiceRegistration<Object> registration;
}

/// Records a service registration call for test assertions.
class RegisterCall {
  const RegisterCall({
    required this.className,
    required this.bundleSymbolicName,
  });
  final String className;
  final String bundleSymbolicName;

  @override
  String toString() => 'RegisterCall($className, $bundleSymbolicName)';
}

/// Records a service lookup call for test assertions.
class LookupCall {
  const LookupCall({required this.className});
  final String className;

  @override
  String toString() => 'LookupCall($className)';
}
