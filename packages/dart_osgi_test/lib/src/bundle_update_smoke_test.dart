import 'dart:async';

import 'package:dart_osgi_framework/dart_osgi_framework.dart';

import 'bundle_test_harness.dart';

/// Automated OTA simulation: stop, replace, restart, verify services.
///
/// Required before any OTA deployment — validates DBC changes, signal
/// renames, and service compatibility.
///
/// Usage:
/// ```dart
/// final smokeTest = BundleUpdateSmokeTest(harness);
/// final result = await smokeTest.run(
///   bundleName: 'com.ivi.can-service',
///   oldManifest: oldManifest,
///   newManifest: newManifest,
///   verifyServices: ['com.ivi.can.CanEngineService'],
/// );
/// expect(result.passed, isTrue);
/// ```
class BundleUpdateSmokeTest {
  BundleUpdateSmokeTest(this._harness);

  final BundleTestHarness _harness;

  /// Run the full OTA smoke test sequence.
  ///
  /// 1. Install and start the old bundle version.
  /// 2. Verify all [verifyServices] are registered.
  /// 3. Stop the old bundle.
  /// 4. Verify services are unregistered.
  /// 5. Install and start the new bundle version.
  /// 6. Verify all [verifyServices] are registered again.
  /// 7. Optionally verify service properties match [expectedProperties].
  Future<SmokeTestResult> run({
    required String bundleName,
    required BundleManifest oldManifest,
    required BundleManifest newManifest,
    required List<String> verifyServices,
    Map<String, Map<String, Object>>? expectedProperties,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final steps = <SmokeTestStep>[];

    // 1. Install and start old version.
    try {
      await _harness.installAndStart(oldManifest);
      steps.add(SmokeTestStep.passed('install_old', 'Old version started'));
    } catch (e) {
      steps.add(SmokeTestStep.failed('install_old', 'Failed: $e'));
      return SmokeTestResult(steps: steps);
    }

    // 2. Verify services registered.
    for (final svcName in verifyServices) {
      final ref = _harness.registry.getServiceReference<Object>(svcName);
      if (ref != null) {
        steps.add(
          SmokeTestStep.passed('verify_old_$svcName', 'Service registered'),
        );
      } else {
        steps.add(
          SmokeTestStep.failed(
            'verify_old_$svcName',
            'Service not found after old bundle start',
          ),
        );
      }
    }

    // 3. Stop old bundle.
    try {
      await _harness.stopBundle(bundleName);
      steps.add(SmokeTestStep.passed('stop_old', 'Old version stopped'));
    } catch (e) {
      steps.add(SmokeTestStep.failed('stop_old', 'Failed: $e'));
      return SmokeTestResult(steps: steps);
    }

    // 4. Verify services unregistered.
    for (final svcName in verifyServices) {
      final ref = _harness.registry.getServiceReference<Object>(svcName);
      if (ref == null) {
        steps.add(
          SmokeTestStep.passed(
            'unregister_$svcName',
            'Service properly unregistered',
          ),
        );
      } else {
        steps.add(
          SmokeTestStep.failed(
            'unregister_$svcName',
            'Service still registered after stop',
          ),
        );
      }
    }

    // 5. Install and start new version.
    try {
      await _harness.installAndStart(newManifest);
      steps.add(SmokeTestStep.passed('install_new', 'New version started'));
    } catch (e) {
      steps.add(SmokeTestStep.failed('install_new', 'Failed: $e'));
      return SmokeTestResult(steps: steps);
    }

    // 6. Verify services registered again.
    for (final svcName in verifyServices) {
      final ref = _harness.registry.getServiceReference<Object>(svcName);
      if (ref != null) {
        steps.add(
          SmokeTestStep.passed(
            'verify_new_$svcName',
            'Service registered after update',
          ),
        );

        // 7. Verify properties if specified.
        if (expectedProperties != null &&
            expectedProperties.containsKey(svcName)) {
          final expected = expectedProperties[svcName]!;
          final actual = ref.properties;
          final mismatches = <String>[];
          for (final entry in expected.entries) {
            if (actual[entry.key] != entry.value) {
              mismatches.add(
                '${entry.key}: expected ${entry.value}, '
                'got ${actual[entry.key]}',
              );
            }
          }
          if (mismatches.isEmpty) {
            steps.add(
              SmokeTestStep.passed('props_$svcName', 'Properties match'),
            );
          } else {
            steps.add(
              SmokeTestStep.failed(
                'props_$svcName',
                'Property mismatches: ${mismatches.join('; ')}',
              ),
            );
          }
        }
      } else {
        steps.add(
          SmokeTestStep.failed(
            'verify_new_$svcName',
            'Service not found after new bundle start',
          ),
        );
      }
    }

    return SmokeTestResult(steps: steps);
  }
}

/// Result of a bundle update smoke test.
class SmokeTestResult {
  const SmokeTestResult({required this.steps});

  final List<SmokeTestStep> steps;

  /// Whether all steps passed.
  bool get passed => steps.every((s) => s.passed);

  /// Steps that failed.
  List<SmokeTestStep> get failures => steps.where((s) => !s.passed).toList();

  @override
  String toString() {
    final status = passed ? 'PASSED' : 'FAILED';
    final detail = steps
        .map((s) => '  ${s.passed ? '✓' : '✗'} ${s.name}: ${s.message}')
        .join('\n');
    return 'SmokeTestResult($status)\n$detail';
  }
}

/// A single step in the smoke test.
class SmokeTestStep {
  const SmokeTestStep._({
    required this.name,
    required this.message,
    required this.passed,
  });

  factory SmokeTestStep.passed(String name, String message) =>
      SmokeTestStep._(name: name, message: message, passed: true);

  factory SmokeTestStep.failed(String name, String message) =>
      SmokeTestStep._(name: name, message: message, passed: false);

  final String name;
  final String message;
  final bool passed;
}
