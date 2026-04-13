import 'dart:async';

import 'package:dart_osgi_api/dart_osgi_api.dart';

import 'ldap_filter.dart';

/// Concrete service registry implementation.
///
/// All mutations are designed to be called from a single isolate
/// (the framework isolate) — no locks needed.
class ServiceRegistry {
  int _nextServiceId = 1;

  /// className → list of registrations for that class.
  final _registrations = <String, List<RegistryServiceRegistration<Object>>>{};

  final _eventController = StreamController<ServiceEvent>.broadcast();

  /// Stream of all service registry events.
  Stream<ServiceEvent> get events => _eventController.stream;

  /// Register a service under [className] with optional [properties].
  RegistryServiceRegistration<T> register<T>(
    String className,
    T service,
    String bundleSymbolicName,
    Map<String, Object>? properties,
  ) {
    final props = <String, Object>{
      ...?properties,
      'objectClass': className,
      'service.bundleSymbolicName': bundleSymbolicName,
    };

    final id = _nextServiceId++;
    final ranking = (props['service.ranking'] as num?)?.toInt() ?? 0;

    final ref = RegistryServiceReference<T>(
      serviceId: id,
      bundleSymbolicName: bundleSymbolicName,
      initialProperties: props,
      ranking: ranking,
    );

    final registration = RegistryServiceRegistration<T>(
      registry: this,
      className: className,
      service: service,
      reference: ref,
    );

    _registrations.putIfAbsent(className, () => []);
    _registrations[className]!.add(
      registration as RegistryServiceRegistration<Object>,
    );

    _eventController.add(
      ServiceEvent(
        ServiceEventType.registered,
        ref as ServiceReference<Object>,
      ),
    );

    return registration;
  }

  /// Unregister a service. Called by [RegistryServiceRegistration.unregister].
  void unregisterService<T>(RegistryServiceRegistration<T> registration) {
    final list = _registrations[registration.className];
    if (list == null) return;
    list.remove(registration);
    if (list.isEmpty) _registrations.remove(registration.className);

    _eventController.add(
      ServiceEvent(
        ServiceEventType.unregistering,
        registration.reference as ServiceReference<Object>,
      ),
    );
  }

  /// Notify that a registration's properties have been modified.
  void notifyModified<T>(RegistryServiceRegistration<T> registration) {
    _eventController.add(
      ServiceEvent(
        ServiceEventType.modified,
        registration.reference as ServiceReference<Object>,
      ),
    );
  }

  /// Get the best-ranked [ServiceReference] for [className], or `null`.
  ServiceReference<T>? getServiceReference<T>(String className) {
    final refs = getServiceReferences<T>(className, null);
    return refs.isEmpty ? null : refs.first;
  }

  /// Get all [ServiceReference]s for [className], optionally filtered,
  /// sorted by ranking (highest first), then by service ID (lowest first).
  List<ServiceReference<T>> getServiceReferences<T>(
    String className,
    String? filter,
  ) {
    final list = _registrations[className];
    if (list == null) return [];

    final ldap = filter != null ? LdapFilter.parse(filter) : null;

    final refs = <RegistryServiceReference<T>>[];
    for (final reg in list) {
      final ref = reg.reference as RegistryServiceReference<T>;
      if (ldap != null && !ldap.matches(ref.properties)) continue;
      refs.add(ref);
    }

    // Sort: highest ranking first, then lowest serviceId first (oldest wins ties).
    refs.sort((a, b) {
      final rankCmp = b.ranking.compareTo(a.ranking);
      if (rankCmp != 0) return rankCmp;
      return a.serviceId.compareTo(b.serviceId);
    });

    return refs;
  }

  /// Get the service object for a [ServiceReference].
  T? getService<T>(ServiceReference<T> reference) {
    final className = reference.getProperty('objectClass') as String?;
    if (className == null) return null;
    final list = _registrations[className];
    if (list == null) return null;
    for (final reg in list) {
      if (reg.reference.serviceId == reference.serviceId) {
        return reg.service as T;
      }
    }
    return null;
  }

  void dispose() {
    _eventController.close();
  }
}

/// Concrete [ServiceReference] implementation.
class RegistryServiceReference<T> implements ServiceReference<T> {
  RegistryServiceReference({
    required this.serviceId,
    required this.bundleSymbolicName,
    required Map<String, Object> initialProperties,
    required this.ranking,
  }) : _properties = Map.of(initialProperties);

  @override
  final int serviceId;

  @override
  final String bundleSymbolicName;

  @override
  int ranking;

  Map<String, Object> _properties;

  @override
  Map<String, Object> get properties => Map.unmodifiable(_properties);

  @override
  Object? getProperty(String key) => _properties[key];

  void updateProperties(Map<String, Object> newProperties) {
    _properties = Map.of(newProperties);
    ranking = (newProperties['service.ranking'] as num?)?.toInt() ?? ranking;
  }

  @override
  int compareTo(ServiceReference<T> other) {
    // Higher ranking wins (sorts first).
    final rankCmp = other.ranking.compareTo(ranking);
    if (rankCmp != 0) return rankCmp;
    // Lower service ID wins ties (older registration).
    return serviceId.compareTo(other.serviceId);
  }

  @override
  String toString() =>
      'ServiceReference<$T>(id=$serviceId, bundle=$bundleSymbolicName, '
      'ranking=$ranking)';
}

/// Concrete [ServiceRegistration] implementation.
class RegistryServiceRegistration<T> implements ServiceRegistration<T> {
  RegistryServiceRegistration({
    required this.registry,
    required this.className,
    required this.service,
    required RegistryServiceReference<T> reference,
  }) : _reference = reference;

  final ServiceRegistry registry;
  final String className;
  final T service;
  final RegistryServiceReference<T> _reference;
  bool _unregistered = false;

  @override
  ServiceReference<T> get reference => _reference;

  @override
  void setProperties(Map<String, Object> properties) {
    if (_unregistered) {
      throw StateError('Cannot modify an unregistered service');
    }
    _reference.updateProperties({
      ...properties,
      'objectClass': className,
      'service.bundleSymbolicName': _reference.bundleSymbolicName,
    });
    registry.notifyModified(this);
  }

  @override
  Future<void> unregister() async {
    if (_unregistered) return;
    _unregistered = true;
    registry.unregisterService(this);
  }
}
