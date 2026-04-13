/// Test harness and mock utilities for OSGi bundles.
///
/// Provides [BundleTestHarness] for isolated bundle testing without
/// ivi-homescreen, [MockServiceRegistry] for pre-seeding services,
/// [ServiceTestBuilder] for fluent mock configuration, [DltLogger]
/// for DLT integration, and [BundleUpdateSmokeTest] for OTA validation.
library;

export 'package:dart_osgi_api/dart_osgi_api.dart';

export 'src/bundle_test_harness.dart';
export 'src/bundle_update_smoke_test.dart';
export 'src/dlt_logger.dart';
export 'src/mock_service_registry.dart';
export 'src/service_test_builder.dart';
