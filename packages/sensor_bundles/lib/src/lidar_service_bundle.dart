import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:dart_osgi_framework/dart_osgi_framework.dart';

/// OSGi service bundle for LIDAR point cloud data.
///
/// Uses the zero-copy Pointer address protocol:
/// - C++/Rust native plugin allocates a point cloud buffer
/// - Posts `Pointer<Float>.address` as `int` via [SendPort]
/// - Consumer isolate reconstructs `Pointer<Float>.fromAddress(addr)`
/// - No data is copied across the isolate boundary
///
/// Critical caveat: `Pointer.asTypedList(finalizer:)` is isolate-bound
/// (dart-lang/sdk #55800). Always use raw `Pointer.address` as int.
class LidarActivator implements BundleActivator {
  static const serviceName = 'com.ivi.sensor.LidarService';

  /// Expected number of floats per point (x, y, z, intensity).
  static const floatsPerPoint = 4;

  final _notifyPort = ReceivePort('lidar.notify');
  final _releasePort = ReceivePort('lidar.release');
  StreamSubscription<dynamic>? _notifySub;
  ServiceRegistration<LidarService>? _registration;

  @override
  Future<void> start(BundleContext ctx) async {
    final service = LidarService(
      notifyPort: _notifyPort,
      releasePort: _releasePort,
    );

    // Listen for point cloud addresses from the native plugin.
    _notifySub = _notifyPort.listen((dynamic msg) {
      if (msg is int) {
        service._onPointCloud(msg);
      }
    });

    _registration = ctx.registerService<LidarService>(serviceName, service, {
      'notify.port': _notifyPort.sendPort.hashCode,
      'release.port': _releasePort.sendPort.hashCode,
      'floats.per.point': floatsPerPoint,
      'transport': 'pointer_address',
    });
  }

  @override
  Future<void> stop(BundleContext ctx) async {
    await _registration?.unregister();
    _registration = null;
    await _notifySub?.cancel();
    _notifySub = null;
    _notifyPort.close();
    _releasePort.close();
  }
}

/// LIDAR service interface exposed to consumer bundles.
///
/// Consumers listen to [pointClouds] for new point cloud addresses.
/// After processing, send the address back via [releaseSendPort] to
/// return the buffer slot to the native ring.
class LidarService {
  LidarService({
    required ReceivePort notifyPort,
    required ReceivePort releasePort,
  }) : releaseSendPort = releasePort.sendPort;

  /// SendPort for consumers to return processed buffer addresses.
  final SendPort releaseSendPort;

  final _controller = StreamController<PointCloudFrame>.broadcast();

  /// Stream of incoming point cloud frames.
  Stream<PointCloudFrame> get pointClouds => _controller.stream;

  void _onPointCloud(int address) {
    _controller.add(PointCloudFrame(address: address));
  }

  void dispose() {
    _controller.close();
  }
}

/// A single LIDAR point cloud frame delivered by address.
class PointCloudFrame {
  const PointCloudFrame({required this.address});

  /// The native memory address of the point cloud buffer.
  /// Reconstruct with `Pointer<Float>.fromAddress(address)`.
  final int address;

  /// Access the point cloud data as a [Pointer<Float>].
  ///
  /// The pointer is valid until the address is returned via
  /// [LidarService.releaseSendPort].
  Pointer<Float> get pointer => Pointer<Float>.fromAddress(address);
}
