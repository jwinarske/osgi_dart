import 'dart:isolate';

import 'package:dart_osgi_api/dart_osgi_api.dart';

import '../lifecycle/managed_bundle.dart';
import '../registry/service_registry.dart';
import '../registry/service_tracker_impl.dart';
import 'isolate_bus.dart';

/// Concrete [BundleContext] implementation for the OSGi framework.
///
/// Each bundle receives its own [IsolateBundleContext]. Within the single
/// Dart VM, all service operations delegate directly to the shared
/// [ServiceRegistry] — no serialization needed. The [SendPort] to the
/// framework isolate is provided for priority-aware message delivery
/// used by the bus and lifecycle signals.
class IsolateBundleContext implements BundleContext {
  IsolateBundleContext({
    required this.managedBundle,
    required this.registry,
    required this.bus,
    required this.frameworkPort,
    required Stream<BundleEvent> bundleEvents,
    required Stream<ServiceEvent> serviceEvents,
  }) : _bundleEvents = bundleEvents,
       _serviceEvents = serviceEvents;

  final ManagedBundle managedBundle;
  final ServiceRegistry registry;
  final IsolateBus bus;

  /// The [SendPort] to the framework isolate (priority or normal port,
  /// depending on the bundle's priority).
  final SendPort frameworkPort;

  final Stream<BundleEvent> _bundleEvents;
  final Stream<ServiceEvent> _serviceEvents;

  final _bundleListeners = <void Function(BundleEvent)>[];
  final _serviceListeners = <_FilteredServiceListener>[];
  final _trackers = <ServiceTrackerImpl<Object>>[];
  final _registrations = <ServiceRegistration<Object>>[];

  bool _disposed = false;

  // ── Service registration ──────────────────────────────────────────

  @override
  ServiceRegistration<T> registerService<T>(
    String className,
    T service,
    Map<String, Object>? properties,
  ) {
    _checkDisposed();
    final reg = registry.register<T>(
      className,
      service,
      managedBundle.symbolicName,
      properties,
    );
    _registrations.add(reg as ServiceRegistration<Object>);
    return reg;
  }

  // ── Service lookup ────────────────────────────────────────────────

  @override
  ServiceReference<T>? getServiceReference<T>(String className) {
    _checkDisposed();
    return registry.getServiceReference<T>(className);
  }

  @override
  List<ServiceReference<T>> getServiceReferences<T>(
    String className,
    String? filter,
  ) {
    _checkDisposed();
    return registry.getServiceReferences<T>(className, filter);
  }

  @override
  T? getService<T>(ServiceReference<T> reference) {
    _checkDisposed();
    return registry.getService<T>(reference);
  }

  @override
  bool ungetService<T>(ServiceReference<T> reference) {
    _checkDisposed();
    // In a single-VM model, ungetService is a no-op acknowledgement.
    // The reference remains valid until unregistered.
    return true;
  }

  // ── Service tracking ──────────────────────────────────────────────

  @override
  ServiceTracker<T> trackService<T>(String className, {String? filter}) {
    _checkDisposed();
    final tracker = ServiceTrackerImpl<T>(
      registry: registry,
      className: className,
      filter: filter,
    );
    _trackers.add(tracker as ServiceTrackerImpl<Object>);
    return tracker;
  }

  // ── Bundle access ─────────────────────────────────────────────────

  @override
  Bundle get bundle => managedBundle;

  // ── Event listeners ───────────────────────────────────────────────

  @override
  void addBundleListener(void Function(BundleEvent event) listener) {
    _checkDisposed();
    _bundleListeners.add(listener);
    _bundleEvents.listen((event) {
      if (_bundleListeners.contains(listener)) {
        listener(event);
      }
    });
  }

  @override
  void removeBundleListener(void Function(BundleEvent event) listener) {
    _bundleListeners.remove(listener);
  }

  @override
  void addServiceListener(
    void Function(ServiceEvent event) listener, {
    String? filter,
  }) {
    _checkDisposed();
    final filtered = _FilteredServiceListener(listener, filter);
    _serviceListeners.add(filtered);
    _serviceEvents.listen((event) {
      if (_serviceListeners.contains(filtered)) {
        filtered.onEvent(event);
      }
    });
  }

  @override
  void removeServiceListener(void Function(ServiceEvent event) listener) {
    _serviceListeners.removeWhere((f) => f.listener == listener);
  }

  // ── Bus convenience ───────────────────────────────────────────────

  /// Send a message to another bundle via the isolate bus.
  bool sendToBundle(String targetSymbolicName, Object message) {
    _checkDisposed();
    return bus.sendTo(targetSymbolicName, message);
  }

  // ── Lifecycle ─────────────────────────────────────────────────────

  /// Dispose this context. Unregisters all services and closes trackers.
  ///
  /// Called by the framework when the bundle stops.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    // Close all trackers.
    for (final tracker in _trackers) {
      await tracker.close();
    }
    _trackers.clear();

    // Unregister all services registered through this context.
    for (final reg in _registrations) {
      await reg.unregister();
    }
    _registrations.clear();

    _bundleListeners.clear();
    _serviceListeners.clear();
  }

  void _checkDisposed() {
    if (_disposed) {
      throw StateError(
        'BundleContext for "${managedBundle.symbolicName}" has been disposed',
      );
    }
  }
}

/// Wraps a service listener with an optional LDAP filter string.
class _FilteredServiceListener {
  _FilteredServiceListener(this.listener, this.filter);

  final void Function(ServiceEvent event) listener;
  final String? filter;

  void onEvent(ServiceEvent event) {
    // If a filter is specified, only deliver events whose service
    // properties match. For simplicity, we filter on the reference
    // properties using basic string matching on objectClass.
    if (filter != null) {
      final objectClass = event.reference.getProperty('objectClass') as String?;
      if (objectClass == null || !objectClass.contains(filter!)) return;
    }
    listener(event);
  }
}
