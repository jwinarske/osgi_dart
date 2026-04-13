import 'dart:io';

import 'package:dart_osgi_api/dart_osgi_api.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

/// The type of a bundle: Flutter UI or pure Dart.
enum BundleType {
  flutter,
  dart;

  static BundleType parse(String value) => switch (value) {
    'flutter' => BundleType.flutter,
    'dart' => BundleType.dart,
    _ => throw ManifestException('Invalid bundle type: "$value"'),
  };
}

/// Startup configuration from bundle.yaml.
class StartupConfig {
  StartupConfig({required this.priority, required this.timeoutMs});

  final BundlePriority priority;
  final int timeoutMs;

  static const defaultTimeoutMs = 5000;

  static StartupConfig parse(YamlMap? map) {
    if (map == null) {
      return StartupConfig(
        priority: BundlePriority.normal,
        timeoutMs: defaultTimeoutMs,
      );
    }
    final priorityStr = map['priority'] as String? ?? 'normal';
    final priority = switch (priorityStr) {
      'critical' => BundlePriority.critical,
      'normal' => BundlePriority.normal,
      'background' => BundlePriority.background,
      _ => throw ManifestException('Invalid startup priority: "$priorityStr"'),
    };
    final timeoutMs = map['timeout_ms'] as int? ?? defaultTimeoutMs;
    if (timeoutMs <= 0 || timeoutMs > 60000) {
      throw ManifestException(
        'timeout_ms must be between 1 and 60000, got $timeoutMs',
      );
    }
    return StartupConfig(priority: priority, timeoutMs: timeoutMs);
  }
}

/// A declared import: a service name with a semver version constraint.
class ImportDeclaration {
  ImportDeclaration({
    required this.serviceName,
    required this.versionConstraint,
  });

  final String serviceName;
  final VersionConstraint versionConstraint;

  static ImportDeclaration parse(Object entry) {
    if (entry is YamlMap && entry.length == 1) {
      final serviceName = entry.keys.first as String;
      final constraint = entry.values.first as String;
      return ImportDeclaration(
        serviceName: serviceName,
        versionConstraint: VersionConstraint.parse(constraint),
      );
    }
    throw ManifestException('Invalid import entry: $entry');
  }

  @override
  String toString() => '$serviceName: $versionConstraint';
}

/// Parsed and validated representation of a bundle.yaml manifest.
class BundleManifest {
  BundleManifest._({
    required this.symbolicName,
    required this.version,
    required this.type,
    required this.activator,
    required this.startup,
    required this.imports,
    required this.exports,
    required this.vmArgs,
    this.flutterAsset,
    this.cpuAffinity,
    this.priorityPort = false,
  });

  final String symbolicName;
  final Version version;
  final BundleType type;
  final String activator;
  final String? flutterAsset;
  final StartupConfig startup;
  final List<ImportDeclaration> imports;
  final List<String> exports;
  final List<String> vmArgs;

  /// CPU core to pin the bundle's isolate to via pthread_setaffinity.
  /// `null` means no affinity — OS scheduler decides.
  final int? cpuAffinity;

  /// Whether this bundle accesses the framework's critical priority port.
  /// Only instrument cluster and safety-critical bundles should set this.
  final bool priorityPort;

  /// Parse a [BundleManifest] from a bundle.yaml file at [path].
  static Future<BundleManifest> load(String path) async {
    final content = await File(path).readAsString();
    return parse(content, sourcePath: path);
  }

  /// Parse a [BundleManifest] from a YAML string.
  static BundleManifest parse(String yamlContent, {String? sourcePath}) {
    final doc = loadYaml(yamlContent) as YamlMap?;
    if (doc == null) {
      throw ManifestException(
        'Empty manifest${sourcePath != null ? ' at $sourcePath' : ''}',
      );
    }

    final bundle = doc['bundle'] as YamlMap?;
    if (bundle == null) {
      throw ManifestException(
        'Missing "bundle" key${sourcePath != null ? ' in $sourcePath' : ''}',
      );
    }

    return _parseBundle(bundle, sourcePath);
  }

  static BundleManifest _parseBundle(YamlMap bundle, String? sourcePath) {
    final symbolicName = _requireString(bundle, 'symbolicName', sourcePath);
    final versionStr = _requireString(bundle, 'version', sourcePath);
    final typeStr = _requireString(bundle, 'type', sourcePath);
    final activator = _requireString(bundle, 'activator', sourcePath);

    final version = Version.parse(versionStr);
    final type = BundleType.parse(typeStr);

    final flutterAsset = bundle['flutterAsset'] as String?;
    if (type == BundleType.flutter && flutterAsset == null) {
      throw ManifestException(
        'Flutter bundle "$symbolicName" must declare flutterAsset',
      );
    }

    final startup = StartupConfig.parse(bundle['startup'] as YamlMap?);

    final rawImports = bundle['imports'] as YamlList?;
    final imports =
        rawImports
            ?.map<ImportDeclaration>(
              (dynamic e) => ImportDeclaration.parse(e as Object),
            )
            .toList() ??
        <ImportDeclaration>[];

    final rawExports = bundle['exports'] as YamlList?;
    final exports =
        rawExports?.map<String>((dynamic e) => e as String).toList() ??
        <String>[];

    final rawVmArgs = bundle['vm_args'] as YamlList?;
    final vmArgs =
        rawVmArgs?.map<String>((dynamic e) => e as String).toList() ??
        <String>[];

    final cpuAffinity = bundle['cpu_affinity'] as int?;
    final priorityPort = bundle['priority_port'] as bool? ?? false;

    return BundleManifest._(
      symbolicName: symbolicName,
      version: version,
      type: type,
      activator: activator,
      flutterAsset: flutterAsset,
      startup: startup,
      imports: imports,
      exports: exports,
      vmArgs: vmArgs,
      cpuAffinity: cpuAffinity,
      priorityPort: priorityPort,
    );
  }

  static String _requireString(YamlMap map, String key, String? sourcePath) {
    final value = map[key];
    if (value == null) {
      throw ManifestException(
        'Missing required field "$key"'
        '${sourcePath != null ? ' in $sourcePath' : ''}',
      );
    }
    if (value is! String) {
      throw ManifestException(
        'Field "$key" must be a string, got ${value.runtimeType}'
        '${sourcePath != null ? ' in $sourcePath' : ''}',
      );
    }
    return value;
  }

  @override
  String toString() => 'BundleManifest($symbolicName@$version)';
}

/// Thrown when a bundle.yaml manifest is invalid.
class ManifestException implements Exception {
  ManifestException(this.message);

  final String message;

  @override
  String toString() => 'ManifestException: $message';
}
