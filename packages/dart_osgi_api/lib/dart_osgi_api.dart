/// Abstract OSGi interfaces for Dart.
///
/// This package defines the contracts for the OSGi framework.
/// It is pure Dart with no Flutter dependency, enabling both
/// headless Dart bundles and Flutter UI bundles to depend on it.
library;

export 'src/bundle.dart';
export 'src/bundle_activator.dart';
export 'src/bundle_context.dart';
export 'src/bundle_event.dart';
export 'src/bundle_state.dart';
export 'src/service_event.dart';
export 'src/service_reference.dart';
export 'src/service_registration.dart';
export 'src/service_tracker.dart';
