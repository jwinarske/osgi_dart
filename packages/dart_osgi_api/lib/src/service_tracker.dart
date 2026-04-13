/// Tracks the availability of services matching a given interface and filter.
///
/// Opens a live stream of adding/modified/removed events. The framework
/// applies a 50ms debounce window to coalesce rapid UNREGISTERING + REGISTERED
/// pairs into a single MODIFIED event.
abstract class ServiceTracker<T> {
  /// Begin tracking. Must be called before listening to streams.
  Future<void> open();

  /// Stop tracking and release resources.
  Future<void> close();

  /// Fires when a matching service is registered.
  Stream<T> get addingService;

  /// Fires when a tracked service's properties are modified.
  Stream<T> get modifiedService;

  /// Fires when a tracked service is unregistered.
  Stream<T> get removedService;

  /// The current best-ranked tracked service, or `null` if none.
  T? get service;

  /// All currently tracked services.
  List<T> get services;
}
