/// Native sensor OSGi service bundles — CAN, LIDAR, IMU.
///
/// All CAN bus access uses can_engine from jwinarske/can_dart exclusively.
/// No other CAN implementation is permitted.
library;

export 'src/can_bus_service_bundle.dart';
export 'src/can_dbc_service_bundle.dart';
export 'src/imu_service_bundle.dart';
export 'src/lidar_service_bundle.dart';
