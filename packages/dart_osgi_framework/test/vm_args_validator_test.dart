import 'package:dart_osgi_framework/dart_osgi_framework.dart';
import 'package:test/test.dart';

/// Helper: build a Dart bundle YAML with optional vm_args and priority.
String _bundleYaml({
  String priority = 'normal',
  List<String> vmArgs = const [],
}) {
  final buf = StringBuffer()
    ..writeln('bundle:')
    ..writeln('  symbolicName: com.test.bundle')
    ..writeln('  version: "1.0.0"')
    ..writeln('  type: dart')
    ..writeln('  activator: package:test/activator.dart')
    ..writeln('  startup:')
    ..writeln('    priority: $priority')
    ..writeln('    timeout_ms: 5000');
  if (vmArgs.isNotEmpty) {
    buf.writeln('  vm_args:');
    for (final arg in vmArgs) {
      buf.writeln('    - "$arg"');
    }
  }
  return buf.toString();
}

void main() {
  group('VmArgsValidator', () {
    group('validate()', () {
      test('returns empty list when manifest has no vm_args', () {
        final manifest = BundleManifest.parse(_bundleYaml());
        expect(VmArgsValidator.validate(manifest), isEmpty);
      });

      test('accepts --old_gen_heap_size=', () {
        final manifest = BundleManifest.parse(
          _bundleYaml(vmArgs: ['--old_gen_heap_size=64']),
        );
        expect(VmArgsValidator.validate(manifest), isEmpty);
      });

      test('accepts --new_gen_semi_max_size=', () {
        final manifest = BundleManifest.parse(
          _bundleYaml(vmArgs: ['--new_gen_semi_max_size=8']),
        );
        expect(VmArgsValidator.validate(manifest), isEmpty);
      });

      test('accepts --concurrent_mark', () {
        final manifest = BundleManifest.parse(
          _bundleYaml(vmArgs: ['--concurrent_mark']),
        );
        expect(VmArgsValidator.validate(manifest), isEmpty);
      });

      test('accepts --enable_serial_gc', () {
        final manifest = BundleManifest.parse(
          _bundleYaml(vmArgs: ['--enable_serial_gc']),
        );
        expect(VmArgsValidator.validate(manifest), isEmpty);
      });

      test('accepts --no_concurrent_mark', () {
        final manifest = BundleManifest.parse(
          _bundleYaml(vmArgs: ['--no_concurrent_mark']),
        );
        expect(VmArgsValidator.validate(manifest), isEmpty);
      });

      test('accepts --no_concurrent_sweep', () {
        final manifest = BundleManifest.parse(
          _bundleYaml(vmArgs: ['--no_concurrent_sweep']),
        );
        expect(VmArgsValidator.validate(manifest), isEmpty);
      });

      test('accepts --compactor_task_limit=', () {
        final manifest = BundleManifest.parse(
          _bundleYaml(vmArgs: ['--compactor_task_limit=2']),
        );
        expect(VmArgsValidator.validate(manifest), isEmpty);
      });

      test('accepts --marker_task_limit=', () {
        final manifest = BundleManifest.parse(
          _bundleYaml(vmArgs: ['--marker_task_limit=4']),
        );
        expect(VmArgsValidator.validate(manifest), isEmpty);
      });

      test('accepts --verify_after_gc', () {
        final manifest = BundleManifest.parse(
          _bundleYaml(vmArgs: ['--verify_after_gc']),
        );
        expect(VmArgsValidator.validate(manifest), isEmpty);
      });

      test('accepts all allowed prefixes together', () {
        final manifest = BundleManifest.parse(
          _bundleYaml(
            vmArgs: [
              '--old_gen_heap_size=32',
              '--new_gen_semi_max_size=4',
              '--concurrent_mark',
              '--enable_serial_gc',
              '--no_concurrent_mark',
              '--no_concurrent_sweep',
              '--compactor_task_limit=2',
              '--marker_task_limit=4',
              '--verify_after_gc',
            ],
          ),
        );
        expect(VmArgsValidator.validate(manifest), isEmpty);
      });

      test('rejects unknown flags', () {
        final manifest = BundleManifest.parse(
          _bundleYaml(vmArgs: ['--unknown_flag']),
        );
        final invalid = VmArgsValidator.validate(manifest);
        expect(invalid, hasLength(1));
        expect(invalid.first, equals('--unknown_flag'));
      });

      test('rejects multiple unknown flags', () {
        final manifest = BundleManifest.parse(
          _bundleYaml(vmArgs: ['--bad1', '--bad2']),
        );
        final invalid = VmArgsValidator.validate(manifest);
        expect(invalid, hasLength(2));
        expect(invalid, containsAll(['--bad1', '--bad2']));
      });

      test('returns only invalid args when mixed with valid', () {
        final manifest = BundleManifest.parse(
          _bundleYaml(
            vmArgs: [
              '--old_gen_heap_size=32',
              '--unknown',
              '--enable_serial_gc',
            ],
          ),
        );
        final invalid = VmArgsValidator.validate(manifest);
        expect(invalid, hasLength(1));
        expect(invalid.first, equals('--unknown'));
      });
    });

    group('presets', () {
      test('criticalPreset has correct values', () {
        expect(VmArgsValidator.criticalPreset, [
          '--old_gen_heap_size=32',
          '--new_gen_semi_max_size=4',
        ]);
      });

      test('normalPreset has correct values', () {
        expect(VmArgsValidator.normalPreset, [
          '--old_gen_heap_size=64',
          '--new_gen_semi_max_size=8',
        ]);
      });

      test('backgroundPreset has correct values', () {
        expect(VmArgsValidator.backgroundPreset, [
          '--old_gen_heap_size=16',
          '--enable_serial_gc',
        ]);
      });
    });

    group('presetFor()', () {
      test('returns criticalPreset for critical priority', () {
        final manifest = BundleManifest.parse(
          _bundleYaml(priority: 'critical'),
        );
        expect(
          VmArgsValidator.presetFor(manifest),
          same(VmArgsValidator.criticalPreset),
        );
      });

      test('returns normalPreset for normal priority', () {
        final manifest = BundleManifest.parse(_bundleYaml(priority: 'normal'));
        expect(
          VmArgsValidator.presetFor(manifest),
          same(VmArgsValidator.normalPreset),
        );
      });

      test('returns backgroundPreset for background priority', () {
        final manifest = BundleManifest.parse(
          _bundleYaml(priority: 'background'),
        );
        expect(
          VmArgsValidator.presetFor(manifest),
          same(VmArgsValidator.backgroundPreset),
        );
      });
    });
  });
}
