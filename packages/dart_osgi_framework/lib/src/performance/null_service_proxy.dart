import 'dart:async';
import 'dart:developer';

import 'package:dart_osgi_api/dart_osgi_api.dart';

import '../registry/service_registry.dart';
import '../registry/service_tracker_impl.dart';

/// A proxy returned when a tracked service fails to rebind within
/// the configured timeout.
///
/// Logs all method invocations and returns safe defaults instead of
/// throwing. This prevents cascading failures when a dependency is
/// temporarily unavailable.
///
/// Usage with [ResilientServiceTracker]:
/// ```dart
/// final tracker = ResilientServiceTracker<LocationService>(
///   registry: registry,
///   className: 'com.ivi.LocationService',
///   defaultFactory: () => NullServiceProxy<LocationService>(),
///   rebindTimeout: Duration(seconds: 2),
/// );
/// ```
class NullServiceProxy {
  NullServiceProxy(this.serviceName);

  final String serviceName;

  /// Log a call that was absorbed by the null proxy.
  void logAbsorbed(String method) {
    log(
      'NullServiceProxy($serviceName): absorbed call to $method',
      name: 'osgi.null_proxy',
      level: 900, // WARNING
    );
  }
}

/// A [ServiceTracker] wrapper that returns a fallback service when the
/// real service is unavailable for longer than [rebindTimeout].
///
/// When the tracked service is unregistered:
/// 1. Start a rebind timer ([rebindTimeout], default 2s).
/// 2. If a new matching service appears before timeout → use it (MODIFIED).
/// 3. If timeout expires → switch to [fallback] and log a warning.
/// 4. When the real service reappears → switch back automatically.
class ResilientServiceTracker<T> {
  ResilientServiceTracker({
    required this.registry,
    required this.className,
    required this.fallback,
    this.filter,
    this.rebindTimeout = const Duration(seconds: 2),
  });

  final ServiceRegistry registry;
  final String className;
  final String? filter;
  final T fallback;
  final Duration rebindTimeout;

  ServiceTrackerImpl<T>? _inner;
  T? _current;
  Timer? _rebindTimer;
  bool _usingFallback = false;

  final _controller = StreamController<T>.broadcast();

  /// Stream that emits the current service (real or fallback).
  Stream<T> get service => _controller.stream;

  /// The current service — real if available, fallback otherwise.
  T get current => _current ?? fallback;

  /// Whether the fallback is currently active.
  bool get isFallbackActive => _usingFallback;

  /// Open the tracker and begin monitoring.
  Future<void> open() async {
    _inner = ServiceTrackerImpl<T>(
      registry: registry,
      className: className,
      filter: filter,
    );
    await _inner!.open();

    _inner!.addingService.listen((svc) {
      _cancelRebindTimer();
      _current = svc;
      _usingFallback = false;
      _controller.add(svc);
    });

    _inner!.modifiedService.listen((svc) {
      _current = svc;
      _usingFallback = false;
      _controller.add(svc);
    });

    _inner!.removedService.listen((_) {
      _startRebindTimer();
    });

    // If a service is already available, use it.
    final existing = _inner!.service;
    if (existing != null) {
      _current = existing;
      _controller.add(existing);
    }
  }

  /// Close the tracker and release resources.
  Future<void> close() async {
    _cancelRebindTimer();
    await _inner?.close();
    _inner = null;
    await _controller.close();
  }

  void _startRebindTimer() {
    _cancelRebindTimer();
    _rebindTimer = Timer(rebindTimeout, () {
      _current = fallback;
      _usingFallback = true;
      _controller.add(fallback);
      log(
        'ResilientServiceTracker($className): '
        'service unavailable for ${rebindTimeout.inMilliseconds}ms, '
        'switching to fallback',
        name: 'osgi.resilient_tracker',
        level: 900, // WARNING
      );
    });
  }

  void _cancelRebindTimer() {
    _rebindTimer?.cancel();
    _rebindTimer = null;
  }
}
