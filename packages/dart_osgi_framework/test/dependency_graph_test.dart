import 'package:dart_osgi_framework/dart_osgi_framework.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

/// Helper: create a BundleManifest from minimal parameters.
BundleManifest _manifest({
  required String name,
  String version = '1.0.0',
  String priority = 'normal',
  List<String> imports = const [],
  List<String> exports = const [],
}) {
  final buf = StringBuffer()
    ..writeln('bundle:')
    ..writeln('  symbolicName: $name')
    ..writeln('  version: "$version"')
    ..writeln('  type: dart')
    ..writeln('  activator: pkg.dart')
    ..writeln('  startup:')
    ..writeln('    priority: $priority');
  if (imports.isNotEmpty) {
    buf.writeln('  imports:');
    for (final imp in imports) {
      buf.writeln('    - $imp');
    }
  }
  if (exports.isNotEmpty) {
    buf.writeln('  exports:');
    for (final exp in exports) {
      buf.writeln('    - $exp');
    }
  }
  return BundleManifest.parse(buf.toString());
}

void main() {
  group('DependencyGraph', () {
    test('single bundle with no imports/exports resolves', () {
      final a = _manifest(name: 'a');
      final graph = DependencyGraph.resolve([a]);

      expect(graph.isFullyResolved, isTrue);
      expect(graph.resolved, hasLength(1));
      expect(graph.resolved.first.symbolicName, 'a');
      expect(graph.errors, isEmpty);
    });

    test('two bundles with satisfied import/export', () {
      final provider = _manifest(
        name: 'provider',
        version: '1.2.0',
        exports: ['nav.service'],
      );
      final consumer = _manifest(
        name: 'consumer',
        imports: ['nav.service: "^1.0.0"'],
      );
      final graph = DependencyGraph.resolve([consumer, provider]);

      expect(graph.isFullyResolved, isTrue);
      // Provider should come before consumer in resolved order.
      final names = graph.resolved.map((m) => m.symbolicName).toList();
      expect(names.indexOf('provider'), lessThan(names.indexOf('consumer')));
    });

    test('unmet import produces error', () {
      final consumer = _manifest(
        name: 'consumer',
        imports: ['missing.service: "^1.0.0"'],
      );
      final graph = DependencyGraph.resolve([consumer]);

      expect(graph.isFullyResolved, isFalse);
      expect(graph.errors, hasLength(1));
      expect(graph.errors.first.type, DependencyErrorType.unmetImport);
      expect(graph.errors.first.message, contains('missing.service'));
    });

    test('version mismatch produces error', () {
      final provider = _manifest(
        name: 'provider',
        version: '3.0.0',
        exports: ['svc'],
      );
      final consumer = _manifest(name: 'consumer', imports: ['svc: "^1.0.0"']);
      final graph = DependencyGraph.resolve([consumer, provider]);

      expect(graph.isFullyResolved, isFalse);
      final err = graph.errors.firstWhere(
        (e) => e.type == DependencyErrorType.versionMismatch,
      );
      expect(err.message, contains('svc'));
      expect(err.message, contains('3.0.0'));
    });

    test('duplicate export produces error', () {
      final a = _manifest(name: 'a', exports: ['dup.svc']);
      final b = _manifest(name: 'b', exports: ['dup.svc']);
      final graph = DependencyGraph.resolve([a, b]);

      expect(
        graph.errors.any((e) => e.type == DependencyErrorType.duplicateExport),
        isTrue,
      );
      expect(graph.errors.first.message, contains('dup.svc'));
    });

    test('cycle detection', () {
      // A imports from B, B imports from A.
      final a = _manifest(
        name: 'a',
        exports: ['a.svc'],
        imports: ['b.svc: "^1.0.0"'],
      );
      final b = _manifest(
        name: 'b',
        exports: ['b.svc'],
        imports: ['a.svc: "^1.0.0"'],
      );
      final graph = DependencyGraph.resolve([a, b]);

      expect(graph.isFullyResolved, isFalse);
      expect(
        graph.errors.any((e) => e.type == DependencyErrorType.cycle),
        isTrue,
      );
    });

    test('priority ordering: critical before normal before background', () {
      // Three independent bundles with different priorities.
      final bg = _manifest(name: 'bg', priority: 'background');
      final norm = _manifest(name: 'norm', priority: 'normal');
      final crit = _manifest(name: 'crit', priority: 'critical');
      final graph = DependencyGraph.resolve([bg, norm, crit]);

      expect(graph.isFullyResolved, isTrue);
      final names = graph.resolved.map((m) => m.symbolicName).toList();
      expect(names.indexOf('crit'), lessThan(names.indexOf('norm')));
      expect(names.indexOf('norm'), lessThan(names.indexOf('bg')));
    });

    test('complex dependency chain A depends on B depends on C', () {
      final c = _manifest(name: 'c', exports: ['c.svc']);
      final b = _manifest(
        name: 'b',
        exports: ['b.svc'],
        imports: ['c.svc: "^1.0.0"'],
      );
      final a = _manifest(name: 'a', imports: ['b.svc: "^1.0.0"']);
      final graph = DependencyGraph.resolve([a, b, c]);

      expect(graph.isFullyResolved, isTrue);
      final names = graph.resolved.map((m) => m.symbolicName).toList();
      expect(names.indexOf('c'), lessThan(names.indexOf('b')));
      expect(names.indexOf('b'), lessThan(names.indexOf('a')));
    });

    test('isFullyResolved true when no errors', () {
      final graph = DependencyGraph.resolve([_manifest(name: 'solo')]);
      expect(graph.isFullyResolved, isTrue);
    });

    test('isFullyResolved false when errors exist', () {
      final consumer = _manifest(name: 'c', imports: ['nope: "^1.0.0"']);
      final graph = DependencyGraph.resolve([consumer]);
      expect(graph.isFullyResolved, isFalse);
    });

    test('self-import does not create self-edge', () {
      // Bundle exports and imports the same service.
      final a = _manifest(
        name: 'a',
        version: '1.0.0',
        exports: ['self.svc'],
        imports: ['self.svc: "^1.0.0"'],
      );
      final graph = DependencyGraph.resolve([a]);
      expect(graph.isFullyResolved, isTrue);
      expect(graph.resolved, hasLength(1));
    });

    test('resolved list is unmodifiable', () {
      final graph = DependencyGraph.resolve([_manifest(name: 'x')]);
      expect(
        () => graph.resolved.add(_manifest(name: 'y')),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('errors list is unmodifiable', () {
      final graph = DependencyGraph.resolve([_manifest(name: 'x')]);
      expect(
        () => graph.errors.add(DependencyError.cycle(['z'])),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  group('DependencyError', () {
    test('toString includes type and message', () {
      final err = DependencyError.unmetImport(
        'bundle',
        'svc',
        _parseConstraint('^1.0.0'),
      );
      expect(err.toString(), contains('DependencyError'));
      expect(err.toString(), contains('unmetImport'));
      expect(err.toString(), contains('svc'));
    });

    test('cycle error lists members', () {
      final err = DependencyError.cycle(['a', 'b', 'c']);
      expect(err.message, contains('a'));
      expect(err.message, contains('b'));
      expect(err.message, contains('c'));
      expect(err.type, DependencyErrorType.cycle);
    });

    test('duplicateExport error names both bundles', () {
      final err = DependencyError.duplicateExport('svc', 'first', 'second');
      expect(err.message, contains('first'));
      expect(err.message, contains('second'));
      expect(err.type, DependencyErrorType.duplicateExport);
    });

    test('versionMismatch error shows constraint and actual', () {
      final err = DependencyError.versionMismatch(
        'consumer',
        'svc',
        _parseConstraint('^1.0.0'),
        _parseVersion('3.0.0'),
      );
      expect(err.message, contains('^1.0.0'));
      expect(err.message, contains('3.0.0'));
      expect(err.type, DependencyErrorType.versionMismatch);
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

VersionConstraint _parseConstraint(String s) => VersionConstraint.parse(s);
Version _parseVersion(String s) => Version.parse(s);
