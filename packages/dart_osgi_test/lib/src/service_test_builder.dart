import 'dart:async';

import 'mock_service_registry.dart';

/// Fluent API for building service mocks in tests.
///
/// Usage:
/// ```dart
/// final builder = ServiceTestBuilder(registry);
/// builder
///   .when('com.ivi.can.CanEngineService')
///   .thenReturn(mockCanEngine)
///   .when('com.ivi.sensor.ImuService')
///   .thenReturn(mockImu);
///
/// await builder.apply();
/// ```
class ServiceTestBuilder {
  ServiceTestBuilder(this._registry);

  final MockServiceRegistry _registry;
  final _stubs = <_ServiceStub>[];

  /// Begin stubbing a service by class name.
  ServiceStubBuilder when(String className) {
    return ServiceStubBuilder._(this, className);
  }

  void _addStub(_ServiceStub stub) => _stubs.add(stub);

  /// Apply all stubs to the registry.
  void apply() {
    for (final stub in _stubs) {
      stub.applyTo(_registry);
    }
  }

  /// Remove all stubs from the registry.
  Future<void> reset() async {
    for (final stub in _stubs) {
      await _registry.unseed(stub.className);
    }
    _stubs.clear();
  }
}

/// Builder for a single service stub.
class ServiceStubBuilder {
  ServiceStubBuilder._(this._parent, this._className);

  final ServiceTestBuilder _parent;
  final String _className;

  /// Return a fixed value when the service is looked up.
  ServiceTestBuilder thenReturn<T>(
    T service, {
    String bundleSymbolicName = 'test.mock',
    Map<String, Object>? properties,
  }) {
    _parent._addStub(
      _ValueStub<T>(
        className: _className,
        service: service,
        bundleSymbolicName: bundleSymbolicName,
        properties: properties,
      ),
    );
    return _parent;
  }

  /// Return a stream service.
  ServiceTestBuilder thenStream<T>(
    Stream<T> stream, {
    String bundleSymbolicName = 'test.mock',
    Map<String, Object>? properties,
  }) {
    _parent._addStub(
      _ValueStub<Stream<T>>(
        className: _className,
        service: stream,
        bundleSymbolicName: bundleSymbolicName,
        properties: properties,
      ),
    );
    return _parent;
  }

  /// Register the service and immediately unregister it to simulate
  /// a flapping dependency.
  ServiceTestBuilder thenFlap<T>(
    T service, {
    Duration interval = const Duration(milliseconds: 100),
    String bundleSymbolicName = 'test.mock',
  }) {
    _parent._addStub(
      _FlapStub<T>(
        className: _className,
        service: service,
        bundleSymbolicName: bundleSymbolicName,
        interval: interval,
      ),
    );
    return _parent;
  }
}

sealed class _ServiceStub {
  String get className;
  void applyTo(MockServiceRegistry registry);
}

class _ValueStub<T> extends _ServiceStub {
  _ValueStub({
    required this.className,
    required this.service,
    required this.bundleSymbolicName,
    this.properties,
  });

  @override
  final String className;
  final T service;
  final String bundleSymbolicName;
  final Map<String, Object>? properties;

  @override
  void applyTo(MockServiceRegistry registry) {
    registry.seed<T>(
      className,
      service,
      bundleSymbolicName: bundleSymbolicName,
      properties: properties,
    );
  }
}

class _FlapStub<T> extends _ServiceStub {
  _FlapStub({
    required this.className,
    required this.service,
    required this.bundleSymbolicName,
    required this.interval,
  });

  @override
  final String className;
  final T service;
  final String bundleSymbolicName;
  final Duration interval;

  @override
  void applyTo(MockServiceRegistry registry) {
    // Register the service, then set up a timer to unregister/re-register.
    registry.seed<T>(
      className,
      service,
      bundleSymbolicName: bundleSymbolicName,
    );
    Timer.periodic(interval, (timer) async {
      await registry.unseed(className);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      registry.seed<T>(
        className,
        service,
        bundleSymbolicName: bundleSymbolicName,
      );
    });
  }
}
