import 'package:dart_osgi_api/dart_osgi_api.dart';

import '../manifest/bundle_manifest.dart';

/// Validates and provides recommended Dart VM arguments for bundles.
///
/// VM args from bundle.yaml are passed directly to Dart_CreateIsolate
/// flags, enabling per-bundle heap tuning. This validator ensures
/// args are well-formed and provides preset configurations.
///
/// Platform channel elimination note:
/// Dart-to-Dart calls between bundles use SendPort directly (single VM).
/// Platform channels are ONLY for C++ plugin calls (GStreamer, Filament,
/// Wayland surface ops). The platform channel mutex is shared across all
/// Flutter engines — high-frequency calls from multiple bundles contend.
/// Avoid platform channels on hot paths.
class VmArgsValidator {
  VmArgsValidator._();

  /// Allowed VM arg prefixes. Rejects unknown flags to prevent
  /// accidental misconfiguration.
  static const _allowedPrefixes = [
    '--old_gen_heap_size=',
    '--new_gen_semi_max_size=',
    '--concurrent_mark',
    '--enable_serial_gc',
    '--no_concurrent_mark',
    '--no_concurrent_sweep',
    '--compactor_task_limit=',
    '--marker_task_limit=',
    '--verify_after_gc',
  ];

  /// Validate that all VM args in a manifest are recognized.
  ///
  /// Returns a list of invalid args (empty if all are valid).
  static List<String> validate(BundleManifest manifest) {
    final invalid = <String>[];
    for (final arg in manifest.vmArgs) {
      if (!_allowedPrefixes.any(arg.startsWith)) {
        invalid.add(arg);
      }
    }
    return invalid;
  }

  /// Recommended VM args for critical bundles (instrument cluster).
  ///
  /// Small heap, concurrent marking for low-latency GC pauses.
  static const criticalPreset = [
    '--old_gen_heap_size=32',
    '--new_gen_semi_max_size=4',
  ];

  /// Recommended VM args for normal bundles (navigation, media).
  static const normalPreset = [
    '--old_gen_heap_size=64',
    '--new_gen_semi_max_size=8',
  ];

  /// Recommended VM args for background service bundles.
  ///
  /// Serial GC for predictable (if longer) pause times —
  /// background bundles can tolerate it.
  static const backgroundPreset = [
    '--old_gen_heap_size=16',
    '--enable_serial_gc',
  ];

  /// Return the recommended preset for a bundle's priority.
  static List<String> presetFor(BundleManifest manifest) {
    return switch (manifest.startup.priority) {
      BundlePriority.critical => criticalPreset,
      BundlePriority.normal => normalPreset,
      BundlePriority.background => backgroundPreset,
    };
  }
}
