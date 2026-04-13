import 'dart:async';

import 'package:dart_osgi_api/dart_osgi_api.dart';

import 'ldap_filter.dart';
import 'service_registry.dart';

/// Concrete [ServiceTracker] implementation.
///
/// Listens to [ServiceRegistry.events] and filters by class name and
/// optional LDAP filter. Applies a 50ms debounce window to coalesce
/// rapid UNREGISTERING + REGISTERED pairs into a single MODIFIED event.
class ServiceTrackerImpl<T> implements ServiceTracker<T> {
  ServiceTrackerImpl({
    required this.registry,
    required this.className,
    String? filter,
  }) : _ldapFilter = filter != null ? LdapFilter.parse(filter) : null;

  final ServiceRegistry registry;
  final String className;
  final LdapFilter? _ldapFilter;

  final _addingController = StreamController<T>.broadcast();
  final _modifiedController = StreamController<T>.broadcast();
  final _removedController = StreamController<T>.broadcast();

  final _tracked = <int, T>{};
  StreamSubscription<ServiceEvent>? _subscription;

  // Debounce state: tracks services that were recently unregistered,
  // so a rapid re-registration can be coalesced into MODIFIED.
  final _pendingRemovals = <int, Timer>{};
  static const _debounceWindow = Duration(milliseconds: 50);

  @override
  Stream<T> get addingService => _addingController.stream;

  @override
  Stream<T> get modifiedService => _modifiedController.stream;

  @override
  Stream<T> get removedService => _removedController.stream;

  @override
  T? get service {
    if (_tracked.isEmpty) return null;
    // Return the service from the best-ranked reference.
    final ref = registry.getServiceReference<T>(className);
    if (ref == null) return null;
    return _tracked[ref.serviceId];
  }

  @override
  List<T> get services => List.unmodifiable(_tracked.values);

  @override
  Future<void> open() async {
    // Snapshot existing matches.
    final refs = registry.getServiceReferences<T>(className, null);
    for (final ref in refs) {
      if (!_matchesFilter(ref)) continue;
      final svc = registry.getService<T>(ref);
      if (svc != null) {
        _tracked[ref.serviceId] = svc;
        _addingController.add(svc);
      }
    }

    // Listen for future changes.
    _subscription = registry.events.listen(_onEvent);
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    for (final timer in _pendingRemovals.values) {
      timer.cancel();
    }
    _pendingRemovals.clear();
    _tracked.clear();
    await _addingController.close();
    await _modifiedController.close();
    await _removedController.close();
  }

  void _onEvent(ServiceEvent event) {
    final ref = event.reference;
    final objectClass = ref.getProperty('objectClass') as String?;
    if (objectClass != className) return;
    if (!_matchesFilter(ref)) return;

    switch (event.type) {
      case ServiceEventType.registered:
        _onRegistered(ref);
      case ServiceEventType.modified:
        _onModified(ref);
      case ServiceEventType.unregistering:
        _onUnregistering(ref);
    }
  }

  void _onRegistered(ServiceReference<Object> ref) {
    final id = ref.serviceId;

    // Check if this is a rapid re-registration (debounce → MODIFIED).
    final pendingTimer = _pendingRemovals.remove(id);
    if (pendingTimer != null) {
      pendingTimer.cancel();
      // The service was unregistered and re-registered within the debounce
      // window — coalesce into a MODIFIED event.
      final svc = registry.getService<T>(ref as ServiceReference<T>);
      if (svc != null) {
        _tracked[id] = svc;
        _modifiedController.add(svc);
      }
      return;
    }

    final svc = registry.getService<T>(ref as ServiceReference<T>);
    if (svc != null) {
      _tracked[id] = svc;
      _addingController.add(svc);
    }
  }

  void _onModified(ServiceReference<Object> ref) {
    final id = ref.serviceId;
    final svc = _tracked[id];
    if (svc != null) {
      _modifiedController.add(svc);
    }
  }

  void _onUnregistering(ServiceReference<Object> ref) {
    final id = ref.serviceId;
    final svc = _tracked[id];
    if (svc == null) return;

    // Start debounce timer — if no re-registration arrives within 50ms,
    // emit the removal.
    _pendingRemovals[id] = Timer(_debounceWindow, () {
      _pendingRemovals.remove(id);
      final removed = _tracked.remove(id);
      if (removed != null) {
        _removedController.add(removed);
      }
    });
  }

  bool _matchesFilter(ServiceReference<dynamic> ref) {
    if (_ldapFilter == null) return true;
    return _ldapFilter.matches(ref.properties);
  }
}
