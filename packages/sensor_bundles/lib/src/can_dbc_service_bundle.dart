import 'dart:async';

import 'package:can_dbc/can_dbc.dart';
import 'package:can_engine/can_engine.dart';
import 'package:dart_osgi_framework/dart_osgi_framework.dart';

import 'can_bus_service_bundle.dart';

/// OSGi service bundle that parses DBC files and registers per-signal
/// [Stream] services keyed by `com.ivi.can.signal.{SignalName}`.
///
/// Uses [DbcParser] and [SignalCompiler] from can_dbc to compile
/// signal definitions, then loads them into the [CanEngine] via
/// [loadSignals]. Polls the engine's shared-memory snapshot at a
/// configurable rate and emits decoded signal values.
class CanDbcActivator implements BundleActivator {
  /// Service name prefix: each signal is registered as
  /// `com.ivi.can.signal.{signalName}`.
  static const servicePrefix = 'com.ivi.can.signal';

  /// Path to the DBC file to load.
  final String dbcPath;

  /// Poll interval for reading the snapshot.
  final Duration pollInterval;

  CanDbcActivator({
    required this.dbcPath,
    this.pollInterval = const Duration(milliseconds: 10),
  });

  CanEngine? _engine;
  DbcDatabase? _database;
  CompiledSignalDb? _compiledDb;
  Timer? _pollTimer;
  final _signalRegistrations = <String, ServiceRegistration<Stream<double>>>{};
  final _signalControllers = <String, StreamController<double>>{};
  int _lastSequence = -1;

  @override
  Future<void> start(BundleContext ctx) async {
    // 1. Look up the CanEngine service registered by CanBusActivator.
    final engineRef = ctx.getServiceReference<CanEngine>(
      CanBusActivator.serviceName,
    );
    if (engineRef == null) {
      throw StateError(
        'CanDbcActivator requires CanEngineService — '
        'ensure CanBusServiceBundle is started first',
      );
    }
    _engine = ctx.getService(engineRef);
    if (_engine == null) {
      throw StateError('CanEngineService reference resolved to null');
    }

    // 2. Parse DBC and compile signal definitions.
    final parser = DbcParser();
    _database = await parser.parseFile(dbcPath);

    final compiler = SignalCompiler();
    _compiledDb = compiler.compile(_database!);

    // 3. Load compiled signals into the engine.
    _engine!.loadSignals(_compiledDb!);

    // 4. Create a stream controller + registration per signal.
    final allSignals = _database!.messages.expand((msg) => msg.signals);
    for (var i = 0; i < allSignals.length; i++) {
      final signal = allSignals.elementAt(i);
      final name = signal.name;
      final controller = StreamController<double>.broadcast();
      _signalControllers[name] = controller;

      final serviceName = '$servicePrefix.$name';
      _signalRegistrations[name] = ctx
          .registerService<Stream<double>>(serviceName, controller.stream, {
            'signal.name': name,
            'signal.unit': signal.unit,
            'signal.min': signal.minimum,
            'signal.max': signal.maximum,
            'signal.index': i,
          });
    }

    // 5. Start polling the snapshot for value changes.
    _pollTimer = Timer.periodic(pollInterval, (_) => _pollSnapshot());
  }

  void _pollSnapshot() {
    if (_engine == null || !_engine!.isRunning) return;

    // Check if the snapshot has been updated by the native thread.
    final seq = _engine!.sequence;
    if (seq == _lastSequence) return;
    _lastSequence = seq;

    // Read each signal value and push to its stream.
    final allSignals = _database!.messages.expand((msg) => msg.signals);
    for (var i = 0; i < allSignals.length; i++) {
      final signal = allSignals.elementAt(i);
      final value = _engine!.readSignalValue(i);
      _signalControllers[signal.name]?.add(value);
    }
  }

  @override
  Future<void> stop(BundleContext ctx) async {
    _pollTimer?.cancel();
    _pollTimer = null;

    for (final reg in _signalRegistrations.values) {
      await reg.unregister();
    }
    _signalRegistrations.clear();

    for (final controller in _signalControllers.values) {
      await controller.close();
    }
    _signalControllers.clear();

    _compiledDb?.dispose();
    _compiledDb = null;
    _database = null;
    _engine = null;
  }
}
