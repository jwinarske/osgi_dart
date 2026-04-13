import 'package:dart_osgi_framework/dart_osgi_framework.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Helper: valid Flutter bundle YAML with all fields populated.
String flutterBundleYaml({
  String symbolicName = 'com.ivi.cluster',
  String version = '1.0.0',
  String type = 'flutter',
  String activator = 'package:cluster/activator.dart',
  String flutterAsset = 'assets/cluster.aot',
  String priority = 'critical',
  int timeoutMs = 3000,
  List<String>? imports,
  List<String>? exports,
  List<String>? vmArgs,
  int? cpuAffinity,
  bool? priorityPort,
}) {
  final buf = StringBuffer()
    ..writeln('bundle:')
    ..writeln('  symbolicName: $symbolicName')
    ..writeln('  version: "$version"')
    ..writeln('  type: $type')
    ..writeln('  activator: $activator');
  if (type == 'flutter') {
    buf.writeln('  flutterAsset: $flutterAsset');
  }
  buf
    ..writeln('  startup:')
    ..writeln('    priority: $priority')
    ..writeln('    timeout_ms: $timeoutMs');
  if (imports != null && imports.isNotEmpty) {
    buf.writeln('  imports:');
    for (final imp in imports) {
      buf.writeln('    - $imp');
    }
  }
  if (exports != null && exports.isNotEmpty) {
    buf.writeln('  exports:');
    for (final exp in exports) {
      buf.writeln('    - $exp');
    }
  }
  if (vmArgs != null && vmArgs.isNotEmpty) {
    buf.writeln('  vm_args:');
    for (final arg in vmArgs) {
      buf.writeln('    - "$arg"');
    }
  }
  if (cpuAffinity != null) {
    buf.writeln('  cpu_affinity: $cpuAffinity');
  }
  if (priorityPort != null) {
    buf.writeln('  priority_port: $priorityPort');
  }
  return buf.toString();
}

/// Helper: minimal Dart bundle YAML.
String dartBundleYaml({
  String symbolicName = 'com.ivi.service',
  String version = '2.0.0',
  String activator = 'package:svc/activator.dart',
  String priority = 'normal',
  int timeoutMs = 5000,
}) {
  return '''
bundle:
  symbolicName: $symbolicName
  version: "$version"
  type: dart
  activator: $activator
  startup:
    priority: $priority
    timeout_ms: $timeoutMs
''';
}

void main() {
  group('BundleType', () {
    test('parse "flutter" returns BundleType.flutter', () {
      expect(BundleType.parse('flutter'), BundleType.flutter);
    });

    test('parse "dart" returns BundleType.dart', () {
      expect(BundleType.parse('dart'), BundleType.dart);
    });

    test('parse invalid type throws ManifestException', () {
      expect(
        () => BundleType.parse('python'),
        throwsA(
          isA<ManifestException>().having(
            (e) => e.message,
            'message',
            contains('Invalid bundle type'),
          ),
        ),
      );
    });
  });

  group('StartupConfig', () {
    test('parse null returns defaults (normal priority, 5000ms)', () {
      final config = StartupConfig.parse(null);
      expect(config.priority, BundlePriority.normal);
      expect(config.timeoutMs, StartupConfig.defaultTimeoutMs);
    });

    test('parse valid critical priority', () {
      final yaml = _parseYamlMap('priority: critical\ntimeout_ms: 2000');
      final config = StartupConfig.parse(yaml);
      expect(config.priority, BundlePriority.critical);
      expect(config.timeoutMs, 2000);
    });

    test('parse valid background priority', () {
      final yaml = _parseYamlMap('priority: background\ntimeout_ms: 10000');
      final config = StartupConfig.parse(yaml);
      expect(config.priority, BundlePriority.background);
      expect(config.timeoutMs, 10000);
    });

    test('invalid priority throws ManifestException', () {
      final yaml = _parseYamlMap('priority: ultra');
      expect(
        () => StartupConfig.parse(yaml),
        throwsA(
          isA<ManifestException>().having(
            (e) => e.message,
            'message',
            contains('Invalid startup priority'),
          ),
        ),
      );
    });

    test('timeout_ms <= 0 throws ManifestException', () {
      final yaml = _parseYamlMap('priority: normal\ntimeout_ms: 0');
      expect(
        () => StartupConfig.parse(yaml),
        throwsA(
          isA<ManifestException>().having(
            (e) => e.message,
            'message',
            contains('timeout_ms must be between 1 and 60000'),
          ),
        ),
      );
    });

    test('timeout_ms negative throws ManifestException', () {
      final yaml = _parseYamlMap('priority: normal\ntimeout_ms: -1');
      expect(
        () => StartupConfig.parse(yaml),
        throwsA(isA<ManifestException>()),
      );
    });

    test('timeout_ms > 60000 throws ManifestException', () {
      final yaml = _parseYamlMap('priority: normal\ntimeout_ms: 60001');
      expect(
        () => StartupConfig.parse(yaml),
        throwsA(
          isA<ManifestException>().having(
            (e) => e.message,
            'message',
            contains('timeout_ms must be between 1 and 60000'),
          ),
        ),
      );
    });

    test('timeout_ms at boundary 1 is valid', () {
      final yaml = _parseYamlMap('priority: normal\ntimeout_ms: 1');
      final config = StartupConfig.parse(yaml);
      expect(config.timeoutMs, 1);
    });

    test('timeout_ms at boundary 60000 is valid', () {
      final yaml = _parseYamlMap('priority: normal\ntimeout_ms: 60000');
      final config = StartupConfig.parse(yaml);
      expect(config.timeoutMs, 60000);
    });

    test('missing priority defaults to normal', () {
      final yaml = _parseYamlMap('timeout_ms: 4000');
      final config = StartupConfig.parse(yaml);
      expect(config.priority, BundlePriority.normal);
    });

    test('missing timeout_ms defaults to 5000', () {
      final yaml = _parseYamlMap('priority: critical');
      final config = StartupConfig.parse(yaml);
      expect(config.timeoutMs, StartupConfig.defaultTimeoutMs);
    });
  });

  group('ImportDeclaration', () {
    test('parse valid import with version constraint', () {
      final yaml = _parseYamlList('- nav.service: "^1.0.0"');
      final imp = ImportDeclaration.parse(yaml.first as Object);
      expect(imp.serviceName, 'nav.service');
      expect(imp.versionConstraint.allows(_v('1.2.0')), isTrue);
      expect(imp.versionConstraint.allows(_v('2.0.0')), isFalse);
    });

    test('parse import with range constraint', () {
      final yaml = _parseYamlList('- media.service: ">=1.0.0 <3.0.0"');
      final imp = ImportDeclaration.parse(yaml.first as Object);
      expect(imp.serviceName, 'media.service');
      expect(imp.versionConstraint.allows(_v('2.5.0')), isTrue);
      expect(imp.versionConstraint.allows(_v('3.0.0')), isFalse);
    });

    test('parse invalid import (plain string) throws ManifestException', () {
      expect(
        () => ImportDeclaration.parse('just-a-string'),
        throwsA(isA<ManifestException>()),
      );
    });

    test('toString returns "serviceName: constraint"', () {
      final yaml = _parseYamlList('- foo.svc: "^2.0.0"');
      final imp = ImportDeclaration.parse(yaml.first as Object);
      expect(imp.toString(), contains('foo.svc'));
    });
  });

  group('BundleManifest.parse', () {
    test('parse valid Flutter bundle with all fields', () {
      final yaml = flutterBundleYaml(
        imports: ['nav.service: "^1.0.0"'],
        exports: ['cluster.service'],
        vmArgs: ['--enable-asserts'],
        cpuAffinity: 2,
        priorityPort: true,
      );
      final m = BundleManifest.parse(yaml);

      expect(m.symbolicName, 'com.ivi.cluster');
      expect(m.version.toString(), '1.0.0');
      expect(m.type, BundleType.flutter);
      expect(m.activator, 'package:cluster/activator.dart');
      expect(m.flutterAsset, 'assets/cluster.aot');
      expect(m.startup.priority, BundlePriority.critical);
      expect(m.startup.timeoutMs, 3000);
      expect(m.imports, hasLength(1));
      expect(m.imports.first.serviceName, 'nav.service');
      expect(m.exports, ['cluster.service']);
      expect(m.vmArgs, ['--enable-asserts']);
      expect(m.cpuAffinity, 2);
      expect(m.priorityPort, isTrue);
    });

    test('parse valid Dart bundle (no flutterAsset)', () {
      final yaml = dartBundleYaml();
      final m = BundleManifest.parse(yaml);

      expect(m.symbolicName, 'com.ivi.service');
      expect(m.version.toString(), '2.0.0');
      expect(m.type, BundleType.dart);
      expect(m.flutterAsset, isNull);
      expect(m.imports, isEmpty);
      expect(m.exports, isEmpty);
      expect(m.vmArgs, isEmpty);
      expect(m.cpuAffinity, isNull);
      expect(m.priorityPort, isFalse);
    });

    test('missing symbolicName throws ManifestException', () {
      final yaml = '''
bundle:
  version: "1.0.0"
  type: dart
  activator: pkg.dart
''';
      expect(
        () => BundleManifest.parse(yaml),
        throwsA(
          isA<ManifestException>().having(
            (e) => e.message,
            'message',
            contains('Missing required field "symbolicName"'),
          ),
        ),
      );
    });

    test('missing version throws ManifestException', () {
      final yaml = '''
bundle:
  symbolicName: com.test
  type: dart
  activator: pkg.dart
''';
      expect(
        () => BundleManifest.parse(yaml),
        throwsA(
          isA<ManifestException>().having(
            (e) => e.message,
            'message',
            contains('Missing required field "version"'),
          ),
        ),
      );
    });

    test('missing type throws ManifestException', () {
      final yaml = '''
bundle:
  symbolicName: com.test
  version: "1.0.0"
  activator: pkg.dart
''';
      expect(
        () => BundleManifest.parse(yaml),
        throwsA(
          isA<ManifestException>().having(
            (e) => e.message,
            'message',
            contains('Missing required field "type"'),
          ),
        ),
      );
    });

    test('missing activator throws ManifestException', () {
      final yaml = '''
bundle:
  symbolicName: com.test
  version: "1.0.0"
  type: dart
''';
      expect(
        () => BundleManifest.parse(yaml),
        throwsA(
          isA<ManifestException>().having(
            (e) => e.message,
            'message',
            contains('Missing required field "activator"'),
          ),
        ),
      );
    });

    test('invalid bundle type throws ManifestException', () {
      final yaml = '''
bundle:
  symbolicName: com.test
  version: "1.0.0"
  type: python
  activator: pkg.dart
''';
      expect(
        () => BundleManifest.parse(yaml),
        throwsA(
          isA<ManifestException>().having(
            (e) => e.message,
            'message',
            contains('Invalid bundle type'),
          ),
        ),
      );
    });

    test('Flutter bundle missing flutterAsset throws ManifestException', () {
      final yaml = '''
bundle:
  symbolicName: com.test.flutter
  version: "1.0.0"
  type: flutter
  activator: pkg.dart
''';
      expect(
        () => BundleManifest.parse(yaml),
        throwsA(
          isA<ManifestException>().having(
            (e) => e.message,
            'message',
            contains('must declare flutterAsset'),
          ),
        ),
      );
    });

    test('invalid startup priority in full manifest', () {
      final yaml = '''
bundle:
  symbolicName: com.test
  version: "1.0.0"
  type: dart
  activator: pkg.dart
  startup:
    priority: mega
''';
      expect(
        () => BundleManifest.parse(yaml),
        throwsA(
          isA<ManifestException>().having(
            (e) => e.message,
            'message',
            contains('Invalid startup priority'),
          ),
        ),
      );
    });

    test('default startup config when startup section absent', () {
      final yaml = '''
bundle:
  symbolicName: com.test
  version: "1.0.0"
  type: dart
  activator: pkg.dart
''';
      final m = BundleManifest.parse(yaml);
      expect(m.startup.priority, BundlePriority.normal);
      expect(m.startup.timeoutMs, StartupConfig.defaultTimeoutMs);
    });

    test('empty manifest throws ManifestException', () {
      expect(
        () => BundleManifest.parse(''),
        throwsA(
          isA<ManifestException>().having(
            (e) => e.message,
            'message',
            contains('Empty manifest'),
          ),
        ),
      );
    });

    test('missing bundle key throws ManifestException', () {
      final yaml = '''
other_key:
  symbolicName: com.test
''';
      expect(
        () => BundleManifest.parse(yaml),
        throwsA(
          isA<ManifestException>().having(
            (e) => e.message,
            'message',
            contains('Missing "bundle" key'),
          ),
        ),
      );
    });

    test('sourcePath appears in error messages', () {
      expect(
        () => BundleManifest.parse('', sourcePath: '/tmp/bad.yaml'),
        throwsA(
          isA<ManifestException>().having(
            (e) => e.message,
            'message',
            contains('/tmp/bad.yaml'),
          ),
        ),
      );
    });

    test('sourcePath in missing bundle key error', () {
      expect(
        () => BundleManifest.parse('foo: bar', sourcePath: '/some/path.yaml'),
        throwsA(
          isA<ManifestException>().having(
            (e) => e.message,
            'message',
            contains('/some/path.yaml'),
          ),
        ),
      );
    });

    test('sourcePath in missing required field error', () {
      final yaml = '''
bundle:
  version: "1.0.0"
  type: dart
  activator: pkg.dart
''';
      expect(
        () => BundleManifest.parse(yaml, sourcePath: '/p.yaml'),
        throwsA(
          isA<ManifestException>().having(
            (e) => e.message,
            'message',
            allOf(contains('Missing required field'), contains('/p.yaml')),
          ),
        ),
      );
    });

    test('vm_args parsing produces list of strings', () {
      final yaml = '''
bundle:
  symbolicName: com.test
  version: "1.0.0"
  type: dart
  activator: pkg.dart
  vm_args:
    - "--enable-asserts"
    - "--verbose"
''';
      final m = BundleManifest.parse(yaml);
      expect(m.vmArgs, ['--enable-asserts', '--verbose']);
    });

    test('cpu_affinity parsed as integer', () {
      final yaml = '''
bundle:
  symbolicName: com.test
  version: "1.0.0"
  type: dart
  activator: pkg.dart
  cpu_affinity: 3
''';
      final m = BundleManifest.parse(yaml);
      expect(m.cpuAffinity, 3);
    });

    test('priority_port parsed as bool', () {
      final yaml = '''
bundle:
  symbolicName: com.test
  version: "1.0.0"
  type: dart
  activator: pkg.dart
  priority_port: true
''';
      final m = BundleManifest.parse(yaml);
      expect(m.priorityPort, isTrue);
    });

    test('priority_port defaults to false', () {
      final yaml = dartBundleYaml();
      final m = BundleManifest.parse(yaml);
      expect(m.priorityPort, isFalse);
    });

    test('multiple imports parsed correctly', () {
      final yaml = '''
bundle:
  symbolicName: com.test
  version: "1.0.0"
  type: dart
  activator: pkg.dart
  imports:
    - nav.service: "^1.0.0"
    - media.service: ">=2.0.0 <3.0.0"
''';
      final m = BundleManifest.parse(yaml);
      expect(m.imports, hasLength(2));
      expect(m.imports[0].serviceName, 'nav.service');
      expect(m.imports[1].serviceName, 'media.service');
    });

    test('multiple exports parsed correctly', () {
      final yaml = '''
bundle:
  symbolicName: com.test
  version: "1.0.0"
  type: dart
  activator: pkg.dart
  exports:
    - foo.service
    - bar.service
''';
      final m = BundleManifest.parse(yaml);
      expect(m.exports, ['foo.service', 'bar.service']);
    });

    test('version constraint with exact version', () {
      final yaml = '''
bundle:
  symbolicName: com.test
  version: "1.0.0"
  type: dart
  activator: pkg.dart
  imports:
    - svc: "1.0.0"
''';
      final m = BundleManifest.parse(yaml);
      expect(m.imports.first.versionConstraint.allows(_v('1.0.0')), isTrue);
      expect(m.imports.first.versionConstraint.allows(_v('1.0.1')), isFalse);
    });

    test('toString returns BundleManifest(name@version)', () {
      final yaml = dartBundleYaml(symbolicName: 'com.x', version: '3.1.4');
      final m = BundleManifest.parse(yaml);
      expect(m.toString(), 'BundleManifest(com.x@3.1.4)');
    });
  });

  group('ManifestException', () {
    test('toString includes message', () {
      final e = ManifestException('something went wrong');
      expect(e.toString(), 'ManifestException: something went wrong');
    });

    test('message is accessible', () {
      final e = ManifestException('test');
      expect(e.message, 'test');
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

YamlMap _parseYamlMap(String content) => loadYaml(content) as YamlMap;
YamlList _parseYamlList(String content) => loadYaml(content) as YamlList;
Version _v(String v) => Version.parse(v);
