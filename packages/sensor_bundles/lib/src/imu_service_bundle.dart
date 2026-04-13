import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dart_osgi_framework/dart_osgi_framework.dart';

/// OSGi service bundle for IMU (Inertial Measurement Unit) data.
///
/// Uses a Rust SPSC (single-producer, single-consumer) mmap ring buffer
/// for zero-copy delivery. Dart drains the ring via FFI at a configurable
/// rate using a pre-allocated batch buffer — zero Dart heap allocation
/// on the hot path.
///
/// Layout of one IMU sample in the ring (7 doubles = 56 bytes):
///   [accel_x, accel_y, accel_z, gyro_x, gyro_y, gyro_z, timestamp_us]
class ImuActivator implements BundleActivator {
  static const serviceName = 'com.ivi.sensor.ImuService';

  /// Floats per IMU sample.
  static const doublesPerSample = 7;

  /// Default drain rate.
  final Duration drainInterval;

  /// Maximum samples to drain per tick.
  final int batchSize;

  ImuActivator({
    this.drainInterval = const Duration(milliseconds: 10),
    this.batchSize = 16,
  });

  Timer? _drainTimer;
  ServiceRegistration<ImuService>? _registration;
  ImuService? _service;

  @override
  Future<void> start(BundleContext ctx) async {
    _service = ImuService(batchSize: batchSize);

    _registration = ctx.registerService<ImuService>(serviceName, _service!, {
      'doubles.per.sample': doublesPerSample,
      'drain.interval.ms': drainInterval.inMilliseconds,
      'batch.size': batchSize,
      'transport': 'spsc_ring_buffer',
    });

    // Start the drain timer.
    _drainTimer = Timer.periodic(drainInterval, (_) {
      _service!.drain();
    });
  }

  @override
  Future<void> stop(BundleContext ctx) async {
    _drainTimer?.cancel();
    _drainTimer = null;
    await _registration?.unregister();
    _registration = null;
    _service?.dispose();
    _service = null;
  }
}

/// IMU service providing a stream of batched sensor readings.
///
/// The ring buffer is mapped by the Rust producer. Dart reads via
/// a [Pointer<Double>] view into the shared mmap region.
class ImuService {
  ImuService({required this.batchSize})
    : _batchBuffer = Float64List(batchSize * ImuActivator.doublesPerSample);

  final int batchSize;

  /// Pre-allocated batch buffer — avoids Dart heap allocation on hot path.
  final Float64List _batchBuffer;

  final _controller = StreamController<ImuBatch>.broadcast();

  /// Stream of IMU sample batches.
  Stream<ImuBatch> get samples => _controller.stream;

  /// The ring buffer base address, set by the native Rust producer.
  int _ringAddr = 0;

  /// Total number of samples in the ring.
  int _ringCapacity = 0;

  /// Current read cursor.
  int _readCursor = 0;

  /// Configure the ring buffer address and capacity.
  ///
  /// Called once during initialization by the native plugin.
  void configureRing({required int ringAddr, required int capacity}) {
    _ringAddr = ringAddr;
    _ringCapacity = capacity;
    _readCursor = 0;
  }

  /// The notify [SendPort] for the native producer to signal new data.
  final notifyPort = ReceivePort('imu.notify');

  /// Drain available samples from the ring buffer.
  ///
  /// Reads up to [batchSize] samples per call. Uses raw [Pointer] access
  /// into the mmap'd region — no copies until the batch is published.
  void drain() {
    if (_ringAddr == 0) return;

    final ringPtr = Pointer<Double>.fromAddress(_ringAddr);
    var samplesRead = 0;

    for (var i = 0; i < batchSize; i++) {
      final offset =
          (_readCursor % _ringCapacity) * ImuActivator.doublesPerSample;

      // Copy one sample into the pre-allocated batch buffer.
      for (var j = 0; j < ImuActivator.doublesPerSample; j++) {
        _batchBuffer[i * ImuActivator.doublesPerSample + j] =
            (ringPtr + offset + j).value;
      }

      _readCursor++;
      samplesRead++;
    }

    if (samplesRead > 0) {
      _controller.add(
        ImuBatch(
          data: Float64List.view(
            _batchBuffer.buffer,
            0,
            samplesRead * ImuActivator.doublesPerSample,
          ),
          sampleCount: samplesRead,
        ),
      );
    }
  }

  void dispose() {
    notifyPort.close();
    _controller.close();
  }
}

/// A batch of IMU samples.
class ImuBatch {
  const ImuBatch({required this.data, required this.sampleCount});

  /// Raw sample data: [accel_x, accel_y, accel_z, gyro_x, gyro_y, gyro_z, timestamp_us]
  /// repeated [sampleCount] times.
  final Float64List data;

  /// Number of samples in this batch.
  final int sampleCount;

  /// Access a single sample by index.
  ImuSample operator [](int index) {
    final offset = index * ImuActivator.doublesPerSample;
    return ImuSample(
      accelX: data[offset],
      accelY: data[offset + 1],
      accelZ: data[offset + 2],
      gyroX: data[offset + 3],
      gyroY: data[offset + 4],
      gyroZ: data[offset + 5],
      timestampUs: data[offset + 6],
    );
  }
}

/// A single IMU reading.
class ImuSample {
  const ImuSample({
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
    required this.timestampUs,
  });

  final double accelX, accelY, accelZ;
  final double gyroX, gyroY, gyroZ;
  final double timestampUs;
}
