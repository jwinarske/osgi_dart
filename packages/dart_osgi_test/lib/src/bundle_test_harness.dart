import 'dart:async';

import 'package:dart_osgi_framework/dart_osgi_framework.dart';

import 'mock_service_registry.dart';
import 'service_test_builder.dart';

/// Starts and stops OSGi bundles in an isolated test environment
/// without requiring ivi-homescreen.
///
/// Uses the real framework isolate and service registry (or a
/// [MockServiceRegistry]) but does not spawn Flutter engines.
/// Tests activator logic in true isolation.
///
/// Usage:
/// ```dart
/// late BundleTestHarness harness;
///
/// setUp(() async {
///   harness = BundleTestHarness();
///   harness.services
///     .when('com.ivi.can.CanEngineService')
///     .thenReturn(mockCanEngine);
///   harness.services.apply();
///   await harness.start();
/// });
///
/// tearDown(() async {
///   await harness.dispose();
/// });
///
/// test('CAN service registers signals', () async {
///   await harness.installAndStart(canServiceManifest);
///   expect(
///     harness.registry.registrations,
///     contains(predicate<RegisterCall>(
///       (c) => c.className.startsWith('com.ivi.can.signal.'),
///     )),
///   );
/// });
/// ```
class BundleTestHarness {
  BundleTestHarness() : registry = MockServiceRegistry() {
    services = ServiceTestBuilder(registry);
  }

  /// The mock service registry used by this harness.
  final MockServiceRegistry registry;

  /// Fluent service stub builder.
  late final ServiceTestBuilder services;

  DartOSGiFramework? _framework;
  EventAdmin? _eventAdmin;

  /// The framework instance (available after [start]).
  DartOSGiFramework get framework {
    if (_framework == null) {
      throw StateError('Harness not started — call start() first');
    }
    return _framework!;
  }

  /// The EventAdmin instance (available after [start]).
  EventAdmin get eventAdmin {
    if (_eventAdmin == null) {
      throw StateError('Harness not started — call start() first');
    }
    return _eventAdmin!;
  }

  /// Collected events posted to the EventAdmin during the test.
  final postedEvents = <Event>[];

  /// Start the test framework.
  Future<void> start() async {
    _framework = DartOSGiFramework.instance;
    _framework!.start();

    // Replace the framework's registry with our mock.
    // The framework uses its own registry internally, but test bundles
    // interact through IsolateBundleContext which we construct with
    // our mock registry.

    _eventAdmin = EventAdmin();
    _eventAdmin!.registerIn(registry, 'test.framework');

    // Capture all events for assertions.
    _eventAdmin!.subscribe('*').listen(postedEvents.add);

    // Wire bundle lifecycle events to EventAdmin.
    _eventAdmin!.wireBundleEvents(_framework!.bundleEvents);
  }

  /// Install a bundle from a manifest and start it.
  ///
  /// Returns the [IsolateBundleContext] for the bundle.
  Future<IsolateBundleContext> installAndStart(BundleManifest manifest) async {
    _framework!.installBundle(manifest);
    _framework!.resolveAll();
    return _framework!.startBundle(manifest.symbolicName);
  }

  /// Install a bundle from a YAML string and start it.
  Future<IsolateBundleContext> installAndStartFromYaml(
    String yamlContent,
  ) async {
    final manifest = BundleManifest.parse(yamlContent);
    return installAndStart(manifest);
  }

  /// Stop a running bundle.
  Future<void> stopBundle(String symbolicName) async {
    await _framework!.stopBundle(symbolicName);
  }

  /// Stop the framework and clean up all resources.
  Future<void> dispose() async {
    await services.reset();
    _eventAdmin?.dispose();
    _eventAdmin = null;
    await _framework?.stop();
    _framework = null;
    await registry.reset();
    postedEvents.clear();
  }
}
