/// Abstract interfaces for a Dart-native OSGi framework.
///
/// Pure Dart by design: a headless service bundle (a CAN decoder, a telemetry
/// sink) and the test harness both depend on this without pulling in Flutter.
/// Anything that needs a widget tree lives in `osgi_flutter`.
library;

export 'src/bundle_activator.dart';
export 'src/bundle_state.dart';
export 'src/shell_transport.dart';
