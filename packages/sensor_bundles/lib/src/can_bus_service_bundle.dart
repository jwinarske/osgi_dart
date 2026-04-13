import 'dart:async';

import 'package:can_engine/can_engine.dart';
import 'package:dart_osgi_framework/dart_osgi_framework.dart';

/// OSGi service bundle wrapping [CanEngine] from jwinarske/can_dart.
///
/// All CAN bus access in this codebase goes through can_engine exclusively.
/// No other CAN implementation (linux_can, socketcan, etc.) is permitted.
///
/// Registers the [CanEngine] instance as an OSGi service so other bundles
/// can look it up for frame TX, signal reading, and ISO-TP.
class CanBusActivator implements BundleActivator {
  /// The OSGi service name for the CAN engine.
  static const serviceName = 'com.ivi.can.CanEngineService';

  CanEngine? _engine;
  ServiceRegistration<CanEngine>? _registration;

  /// CAN interface name (e.g. "vcan0", "can0").
  final String interfaceName;

  /// Path to the native can_engine shared library.
  final String libraryPath;

  CanBusActivator({
    required this.interfaceName,
    this.libraryPath = 'libcan_engine.so',
  });

  @override
  Future<void> start(BundleContext ctx) async {
    _engine = CanEngine(libraryPath: libraryPath);
    final result = _engine!.start(interfaceName);
    if (result != 0) {
      _engine!.dispose();
      _engine = null;
      throw StateError(
        'CanEngine.start("$interfaceName") failed with code $result',
      );
    }

    _registration = ctx.registerService<CanEngine>(serviceName, _engine!, {
      'interface': interfaceName,
      'bus.load.percent': _engine!.busLoadPercent,
      'frames.per.second': _engine!.framesPerSecond,
    });
  }

  @override
  Future<void> stop(BundleContext ctx) async {
    await _registration?.unregister();
    _registration = null;
    _engine?.stop();
    _engine?.dispose();
    _engine = null;
  }
}
