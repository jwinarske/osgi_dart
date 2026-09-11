import 'dart:async';

import 'package:osgi_api/osgi_api.dart';

import 'ldap_filter.dart';

/// The service registry, as seen from inside the framework isolate.
///
/// Deliberately not distributed. All engines in an ivi-homescreen process share
/// one Dart VM, so bundles are isolates in one address space and the registry is
/// plain Dart objects behind a single owner. Service *references* cross isolate
/// boundaries as ports; the registry itself does not move.
///
/// Ordering follows the OSGi core specification, and the reason is practical
/// rather than pedantic: `getService` must be deterministic when several bundles
/// publish the same interface, or which implementation a bundle gets depends on
/// bundle start order, which depends on how fast each activator ran.
///
/// Filters are LDAP filters (see [LdapFilter]). A malformed filter throws
/// [FilterParseException] rather than matching nothing: matching nothing is
/// safe but silent -- the bundle simply never finds its service -- while a
/// throw puts the mistake where it was made.
class ServiceRegistry {
  final Map<String, List<_Entry>> _byInterface = <String, List<_Entry>>{};
  final List<_Tracker> _trackers = <_Tracker>[];

  /// Monotonic, assigned on registration. Ties in ranking break by this, oldest
  /// first, exactly as the specification requires.
  int _nextServiceId = 1;

  /// Publish [service] under [interfaceName].
  ///
  /// `service.ranking` in [properties] orders results: higher wins. A bundle
  /// that means to override a default publishes with a ranking above it rather
  /// than racing to register first.
  ServiceRegistration register(
    String interfaceName,
    Object? service, [
    Map<String, Object?> properties = const <String, Object?>{},
  ]) {
    final _Entry entry = _Entry(
      interfaceName: interfaceName,
      service: service,
      // Copied, not aliased: a caller that mutates the map it passed in would
      // otherwise silently change the registry's view, and re-sorting does not
      // happen on mutation.
      properties: Map<String, Object?>.unmodifiable(<String, Object?>{
        ...properties,
      }),
      serviceId: _nextServiceId++,
      registry: this,
    );

    final List<_Entry> entries = _byInterface.putIfAbsent(
      interfaceName,
      () => <_Entry>[],
    );
    entries.add(entry);
    entries.sort(_Entry.byRankingThenAge);

    for (final _Tracker tracker in List<_Tracker>.of(_trackers)) {
      if (tracker.matches(entry)) tracker.notifyAdded(entry.service);
    }
    return entry;
  }

  /// The highest-ranked service under [interfaceName] whose properties match
  /// [filter], or null.
  ///
  /// Throws [FilterParseException] for a malformed [filter].
  Object? getService(String interfaceName, {String? filter}) {
    final LdapFilter? parsed = _parse(filter);
    final List<_Entry>? entries = _byInterface[interfaceName];
    if (entries == null) return null;
    for (final _Entry entry in entries) {
      if (parsed == null || parsed.matches(entry.properties)) {
        return entry.service;
      }
    }
    return null;
  }

  /// Every service under [interfaceName] matching [filter], highest-ranked
  /// first.
  ///
  /// Throws [FilterParseException] for a malformed [filter].
  List<Object?> getServices(String interfaceName, {String? filter}) {
    final LdapFilter? parsed = _parse(filter);
    final List<_Entry> entries =
        _byInterface[interfaceName] ?? const <_Entry>[];
    return entries
        .where((_Entry e) => parsed == null || parsed.matches(e.properties))
        .map((_Entry e) => e.service)
        .toList(growable: false);
  }

  /// Watch [interfaceName], optionally narrowed by [filter].
  ///
  /// Each listener on [ServiceTracker.addingService] first receives the
  /// matching services already registered -- whether it started listening
  /// before or after [ServiceTracker.open], and whether `open()` was awaited --
  /// then later registrations. Bundle start order does not decide what a
  /// tracker sees.
  ///
  /// Throws [FilterParseException] for a malformed [filter].
  ServiceTracker track(String interfaceName, {String? filter}) {
    final _Tracker tracker = _Tracker(
      interfaceName: interfaceName,
      filter: _parse(filter),
      registry: this,
    );
    _trackers.add(tracker);
    return tracker;
  }

  void _unregister(_Entry entry) {
    final List<_Entry>? entries = _byInterface[entry.interfaceName];
    if (entries == null) return;
    if (!entries.remove(entry)) return;
    if (entries.isEmpty) _byInterface.remove(entry.interfaceName);

    for (final _Tracker tracker in List<_Tracker>.of(_trackers)) {
      if (tracker.matches(entry)) tracker.notifyRemoved(entry.service);
    }
  }

  void _removeTracker(_Tracker tracker) => _trackers.remove(tracker);

  Iterable<_Entry> _entriesFor(_Tracker tracker) =>
      (_byInterface[tracker.interfaceName] ?? const <_Entry>[]).where(
        tracker.matches,
      );
}

LdapFilter? _parse(String? filter) =>
    filter == null ? null : LdapFilter.parse(filter);

class _Entry implements ServiceRegistration {
  _Entry({
    required this.interfaceName,
    required this.service,
    required this.properties,
    required this.serviceId,
    required this.registry,
  });

  @override
  final String interfaceName;

  @override
  final Map<String, Object?> properties;

  final Object? service;
  final int serviceId;

  /// Private class, so this is not part of the ServiceRegistration surface.
  final ServiceRegistry registry;

  bool _unregistered = false;

  int get ranking {
    final Object? value = properties['service.ranking'];
    return value is int ? value : 0;
  }

  @override
  Future<void> unregister() async {
    // Idempotent on purpose: unregister runs from activator `stop()`, which
    // also runs when a start failed partway. Making a second call an error
    // would mean every teardown path needs to know how far the first got.
    if (_unregistered) return;
    _unregistered = true;
    registry._unregister(this);
  }

  /// Higher ranking first; equal ranking, lower service id first -- so the
  /// result does not depend on which activator happened to finish sooner.
  static int byRankingThenAge(_Entry a, _Entry b) {
    final int byRanking = b.ranking.compareTo(a.ranking);
    return byRanking != 0 ? byRanking : a.serviceId.compareTo(b.serviceId);
  }
}

class _Tracker implements ServiceTracker {
  _Tracker({
    required this.interfaceName,
    required this.filter,
    required this.registry,
  });

  final String interfaceName;
  final LdapFilter? filter;
  final ServiceRegistry registry;

  /// One controller per listener on [addingService], so each listener can be
  /// handed what is already tracked at the moment it needs it. A single
  /// broadcast controller cannot do that: it drops events sent while nobody is
  /// listening, which made the replay depend on whether `open()` was awaited.
  final Set<MultiStreamController<Object?>> _addListeners =
      <MultiStreamController<Object?>>{};

  late final Stream<Object?> _adding = Stream<Object?>.multi(
    _onAddListen,
    isBroadcast: true,
  );

  final StreamController<Object?> _removed =
      StreamController<Object?>.broadcast();

  bool _open = false;
  bool _closed = false;

  @override
  Stream<Object?> get addingService => _adding;

  @override
  Stream<Object?> get removedService => _removed.stream;

  @override
  Future<void> open() async {
    if (_open || _closed) return;
    _open = true;
    // Replay the registry as it is now, not a snapshot delivered later: from
    // here on a registration or removal arrives as a live event, so a service
    // is neither reported twice nor reported added after it was removed.
    for (final MultiStreamController<Object?> listener
        in List<MultiStreamController<Object?>>.of(_addListeners)) {
      _replayTo(listener);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _open = false;
    registry._removeTracker(this);
    for (final MultiStreamController<Object?> listener
        in List<MultiStreamController<Object?>>.of(_addListeners)) {
      unawaited(listener.close());
    }
    _addListeners.clear();
    await _removed.close();
  }

  bool matches(_Entry entry) =>
      entry.interfaceName == interfaceName &&
      (filter?.matches(entry.properties) ?? true);

  void notifyAdded(Object? service) {
    if (!_open || _closed) return;
    for (final MultiStreamController<Object?> listener
        in List<MultiStreamController<Object?>>.of(_addListeners)) {
      listener.add(service);
    }
  }

  void notifyRemoved(Object? service) {
    if (_open && !_closed) _removed.add(service);
  }

  void _onAddListen(MultiStreamController<Object?> listener) {
    if (_closed) {
      unawaited(listener.close());
      return;
    }
    _addListeners.add(listener);
    listener.onCancel = () {
      _addListeners.remove(listener);
    };
    // Arriving after open() is normal -- `await tracker.open()` and then
    // listen is the natural way to write it -- so start from what is tracked.
    if (_open) _replayTo(listener);
  }

  void _replayTo(MultiStreamController<Object?> listener) {
    for (final _Entry entry in registry._entriesFor(this)) {
      listener.add(entry.service);
    }
  }
}
