import 'package:pub_semver/pub_semver.dart';

import 'bundle_manifest.dart';

/// Topological sort of bundle manifests based on import/export declarations
/// with semver range matching.
class DependencyGraph {
  DependencyGraph._(this._resolved, this._errors);

  /// The resolved startup order (topologically sorted).
  final List<BundleManifest> _resolved;

  /// Resolution errors (unmet imports, cycles).
  final List<DependencyError> _errors;

  /// Bundles in dependency order — dependencies come before dependents.
  List<BundleManifest> get resolved => List.unmodifiable(_resolved);

  /// Errors encountered during resolution.
  List<DependencyError> get errors => List.unmodifiable(_errors);

  /// Whether all imports were satisfied and no cycles were detected.
  bool get isFullyResolved => _errors.isEmpty;

  /// Resolve a set of bundle manifests into dependency order.
  ///
  /// Builds an export→manifest index, validates that every import is
  /// satisfied by an export with a compatible version, then performs
  /// a topological sort with cycle detection.
  static DependencyGraph resolve(List<BundleManifest> manifests) {
    final errors = <DependencyError>[];

    // Index: exported service name → (manifest, version).
    final exportIndex = <String, _ExportEntry>{};
    for (final m in manifests) {
      for (final exportName in m.exports) {
        if (exportIndex.containsKey(exportName)) {
          errors.add(
            DependencyError.duplicateExport(
              exportName,
              exportIndex[exportName]!.manifest.symbolicName,
              m.symbolicName,
            ),
          );
        } else {
          exportIndex[exportName] = _ExportEntry(m, m.version);
        }
      }
    }

    // Adjacency: manifest symbolicName → set of symbolicNames it depends on.
    final adj = <String, Set<String>>{};
    final byName = <String, BundleManifest>{};
    for (final m in manifests) {
      byName[m.symbolicName] = m;
      adj[m.symbolicName] = {};
    }

    // Validate imports and build edges.
    for (final m in manifests) {
      for (final imp in m.imports) {
        final export = exportIndex[imp.serviceName];
        if (export == null) {
          errors.add(
            DependencyError.unmetImport(
              m.symbolicName,
              imp.serviceName,
              imp.versionConstraint,
            ),
          );
          continue;
        }
        if (!imp.versionConstraint.allows(export.version)) {
          errors.add(
            DependencyError.versionMismatch(
              m.symbolicName,
              imp.serviceName,
              imp.versionConstraint,
              export.version,
            ),
          );
          continue;
        }
        // m depends on the bundle that exports this service.
        if (export.manifest.symbolicName != m.symbolicName) {
          adj[m.symbolicName]!.add(export.manifest.symbolicName);
        }
      }
    }

    // Topological sort (Kahn's algorithm) with cycle detection.
    // adj[m] = set of bundles m depends on. Edge: dep → m.
    // In-degree of m = number of its dependencies = adj[m].length.
    final inDegree = <String, int>{
      for (final entry in adj.entries) entry.key: entry.value.length,
    };

    final queue = <String>[
      for (final entry in inDegree.entries)
        if (entry.value == 0) entry.key,
    ];
    final sorted = <BundleManifest>[];

    while (queue.isNotEmpty) {
      // Sort the ready set so critical bundles come first at each level.
      queue.sort((a, b) {
        final pa = byName[a]!.startup.priority.index;
        final pb = byName[b]!.startup.priority.index;
        return pa.compareTo(pb);
      });
      final name = queue.removeAt(0);
      sorted.add(byName[name]!);
      for (final dependent in adj.keys) {
        if (adj[dependent]!.contains(name)) {
          inDegree[dependent] = inDegree[dependent]! - 1;
          if (inDegree[dependent] == 0) {
            queue.add(dependent);
          }
        }
      }
    }

    if (sorted.length != manifests.length) {
      final resolved = sorted.map((m) => m.symbolicName).toSet();
      final cycleMembers = manifests
          .where((m) => !resolved.contains(m.symbolicName))
          .map((m) => m.symbolicName)
          .toList();
      errors.add(DependencyError.cycle(cycleMembers));
    }

    return DependencyGraph._(sorted, errors);
  }
}

class _ExportEntry {
  _ExportEntry(this.manifest, this.version);
  final BundleManifest manifest;
  final Version version;
}

/// Describes a dependency resolution error.
class DependencyError {
  DependencyError._(this.type, this.message);

  factory DependencyError.unmetImport(
    String bundleName,
    String serviceName,
    VersionConstraint constraint,
  ) => DependencyError._(
    DependencyErrorType.unmetImport,
    'Bundle "$bundleName" imports "$serviceName" ($constraint) '
    'but no bundle exports it',
  );

  factory DependencyError.versionMismatch(
    String bundleName,
    String serviceName,
    VersionConstraint constraint,
    Version actual,
  ) => DependencyError._(
    DependencyErrorType.versionMismatch,
    'Bundle "$bundleName" imports "$serviceName" ($constraint) '
    'but the export provides $actual',
  );

  factory DependencyError.duplicateExport(
    String serviceName,
    String first,
    String second,
  ) => DependencyError._(
    DependencyErrorType.duplicateExport,
    'Service "$serviceName" exported by both "$first" and "$second"',
  );

  factory DependencyError.cycle(List<String> members) => DependencyError._(
    DependencyErrorType.cycle,
    'Dependency cycle detected among: ${members.join(', ')}',
  );

  final DependencyErrorType type;
  final String message;

  @override
  String toString() => 'DependencyError($type): $message';
}

enum DependencyErrorType {
  unmetImport,
  versionMismatch,
  duplicateExport,
  cycle,
}
