import 'dart:async';

import 'package:dart_osgi_framework/dart_osgi_framework.dart';
import 'package:test/test.dart';

/// Helper: parse a BundleManifest from minimal YAML.
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
  late BundleManager manager;

  setUp(() {
    manager = BundleManager();
  });

  tearDown(() {
    manager.dispose();
  });

  group('BundleManager', () {
    group('install', () {
      test('creates ManagedBundle in installed state', () {
        final manifest = _manifest(name: 'com.test');
        final bundle = manager.install(manifest);

        expect(bundle, isA<ManagedBundle>());
        expect(bundle.symbolicName, 'com.test');
        expect(bundle.state, BundleState.installed);
        expect(bundle.version, '1.0.0');
      });

      test('duplicate install throws StateError', () {
        final manifest = _manifest(name: 'com.dup');
        manager.install(manifest);
        expect(
          () => manager.install(manifest),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('already installed'),
            ),
          ),
        );
      });

      test('bundle appears in bundles map', () {
        final manifest = _manifest(name: 'com.registered');
        manager.install(manifest);
        expect(manager.bundles, contains('com.registered'));
      });

      test('bundles map is unmodifiable', () {
        expect(
          () => (manager.bundles as dynamic)['foo'] = null,
          throwsA(anything),
        );
      });
    });

    group('resolve', () {
      test('transitions installed bundles to resolved', () {
        final manifest = _manifest(name: 'com.resolve');
        manager.install(manifest);
        final graph = manager.resolve();

        expect(graph.isFullyResolved, isTrue);
        expect(manager.getBundle('com.resolve')!.state, BundleState.resolved);
      });

      test('resolves multiple bundles with dependencies', () {
        final provider = _manifest(name: 'provider', exports: ['svc']);
        final consumer = _manifest(
          name: 'consumer',
          imports: ['svc: "^1.0.0"'],
        );
        manager.install(provider);
        manager.install(consumer);
        final graph = manager.resolve();

        expect(graph.isFullyResolved, isTrue);
        expect(manager.getBundle('provider')!.state, BundleState.resolved);
        expect(manager.getBundle('consumer')!.state, BundleState.resolved);
      });

      test('does not re-resolve already resolved bundles', () {
        final manifest = _manifest(name: 'com.once');
        manager.install(manifest);
        manager.resolve();
        // Resolve again should not throw (state is already resolved).
        final graph = manager.resolve();
        expect(graph.isFullyResolved, isTrue);
        expect(manager.getBundle('com.once')!.state, BundleState.resolved);
      });
    });

    group('startupOrder', () {
      test('returns priority-sorted order', () {
        manager.install(_manifest(name: 'bg', priority: 'background'));
        manager.install(_manifest(name: 'norm', priority: 'normal'));
        manager.install(_manifest(name: 'crit', priority: 'critical'));

        final order = manager.startupOrder();
        final names = order.map((b) => b.symbolicName).toList();

        expect(names.indexOf('crit'), lessThan(names.indexOf('norm')));
        expect(names.indexOf('norm'), lessThan(names.indexOf('bg')));
      });

      test('respects dependency order over priority', () {
        manager.install(
          _manifest(
            name: 'consumer',
            priority: 'critical',
            imports: ['svc: "^1.0.0"'],
          ),
        );
        manager.install(
          _manifest(name: 'provider', priority: 'background', exports: ['svc']),
        );

        final order = manager.startupOrder();
        final names = order.map((b) => b.symbolicName).toList();
        // Provider must come before consumer regardless of priority.
        expect(names.indexOf('provider'), lessThan(names.indexOf('consumer')));
      });
    });

    group('lifecycle transitions', () {
      test('starting transitions resolved -> starting', () {
        manager.install(_manifest(name: 'b'));
        manager.resolve();
        manager.starting('b');
        expect(manager.getBundle('b')!.state, BundleState.starting);
      });

      test('started transitions starting -> active', () {
        manager.install(_manifest(name: 'b'));
        manager.resolve();
        manager.starting('b');
        manager.started('b');
        expect(manager.getBundle('b')!.state, BundleState.active);
      });

      test('stopping transitions active -> stopping', () {
        manager.install(_manifest(name: 'b'));
        manager.resolve();
        manager.starting('b');
        manager.started('b');
        manager.stopping('b');
        expect(manager.getBundle('b')!.state, BundleState.stopping);
      });

      test('stopped without uninstall transitions stopping -> resolved', () {
        manager.install(_manifest(name: 'b'));
        manager.resolve();
        manager.starting('b');
        manager.started('b');
        manager.stopping('b');
        manager.stopped('b');
        expect(manager.getBundle('b')!.state, BundleState.resolved);
      });

      test('stopped with uninstall=true removes bundle', () {
        manager.install(_manifest(name: 'b'));
        manager.resolve();
        manager.starting('b');
        manager.started('b');
        manager.stopping('b');
        manager.stopped('b', uninstall: true);
        expect(manager.getBundle('b'), isNull);
        expect(manager.bundles, isEmpty);
      });
    });

    group('uninstall', () {
      test('from active state goes through stopping then uninstalled', () {
        final events = <BundleEventType>[];
        manager.events.listen((e) => events.add(e.type));

        manager.install(_manifest(name: 'b'));
        manager.resolve();
        manager.starting('b');
        manager.started('b');
        events.clear();

        manager.uninstall('b');

        expect(events, contains(BundleEventType.stopping));
        expect(events, contains(BundleEventType.uninstalled));
        expect(manager.getBundle('b'), isNull);
      });

      test('from resolved state goes straight to uninstalled', () {
        manager.install(_manifest(name: 'b'));
        manager.resolve();
        manager.uninstall('b');
        expect(manager.getBundle('b'), isNull);
      });

      test('from installed state goes to uninstalled', () {
        manager.install(_manifest(name: 'b'));
        manager.uninstall('b');
        expect(manager.getBundle('b'), isNull);
      });

      test('unknown bundle throws StateError', () {
        expect(
          () => manager.uninstall('nonexistent'),
          throwsA(isA<StateError>()),
        );
      });
    });

    group('getBundle', () {
      test('returns ManagedBundle when found', () {
        manager.install(_manifest(name: 'found'));
        expect(manager.getBundle('found'), isNotNull);
        expect(manager.getBundle('found')!.symbolicName, 'found');
      });

      test('returns null when not found', () {
        expect(manager.getBundle('ghost'), isNull);
      });
    });

    group('events stream', () {
      test('aggregates per-bundle events', () async {
        final events = <BundleEvent>[];
        manager.events.listen(events.add);

        manager.install(_manifest(name: 'a'));
        manager.install(_manifest(name: 'b'));
        manager.resolve();
        await Future<void>.delayed(Duration.zero);

        // Should have resolved events for both bundles.
        expect(events.length, greaterThanOrEqualTo(2));
        final names = events.map((e) => e.bundle.symbolicName).toSet();
        expect(names, containsAll(['a', 'b']));
      });

      test('events from different bundles interleave correctly', () async {
        final types = <String>[];
        manager.events.listen(
          (e) => types.add('${e.bundle.symbolicName}:${e.type}'),
        );

        manager.install(_manifest(name: 'x'));
        manager.install(_manifest(name: 'y'));
        manager.resolve();
        manager.starting('x');
        manager.starting('y');
        await Future<void>.delayed(Duration.zero);

        expect(types, contains('x:${BundleEventType.resolved}'));
        expect(types, contains('y:${BundleEventType.resolved}'));
        expect(types, contains('x:${BundleEventType.starting}'));
        expect(types, contains('y:${BundleEventType.starting}'));
      });
    });

    group('_requireBundle', () {
      test('starting unknown bundle throws StateError', () {
        expect(
          () => manager.starting('missing'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('No bundle installed'),
            ),
          ),
        );
      });

      test('started unknown bundle throws StateError', () {
        expect(() => manager.started('missing'), throwsA(isA<StateError>()));
      });

      test('stopping unknown bundle throws StateError', () {
        expect(() => manager.stopping('missing'), throwsA(isA<StateError>()));
      });

      test('stopped unknown bundle throws StateError', () {
        expect(() => manager.stopped('missing'), throwsA(isA<StateError>()));
      });
    });

    group('dispose', () {
      test('clears all bundles', () {
        manager.install(_manifest(name: 'a'));
        manager.install(_manifest(name: 'b'));
        manager.dispose();
        expect(manager.bundles, isEmpty);
      });

      test('closes event stream', () async {
        final done = Completer<void>();
        manager.events.listen(null, onDone: done.complete);
        manager.dispose();
        await done.future;
      });
    });
  });

  group('ManagedBundle', () {
    test('headers include core fields', () {
      final manifest = _manifest(name: 'com.hdr');
      final bundle = ManagedBundle(manifest);

      expect(bundle.headers['symbolicName'], 'com.hdr');
      expect(bundle.headers['version'], '1.0.0');
      expect(bundle.headers['type'], 'dart');
      expect(bundle.headers['activator'], 'pkg.dart');
    });

    test('headers include flutterAsset for flutter bundles', () {
      final yaml = '''
bundle:
  symbolicName: com.flutter
  version: "1.0.0"
  type: flutter
  activator: pkg.dart
  flutterAsset: assets/app.aot
''';
      final manifest = BundleManifest.parse(yaml);
      final bundle = ManagedBundle(manifest);

      expect(bundle.headers['flutterAsset'], 'assets/app.aot');
    });

    test('headers omit flutterAsset for dart bundles', () {
      final manifest = _manifest(name: 'com.dart');
      final bundle = ManagedBundle(manifest);

      expect(bundle.headers.containsKey('flutterAsset'), isFalse);
    });

    test('priority reflects manifest startup priority', () {
      final crit = _manifest(name: 'c', priority: 'critical');
      expect(ManagedBundle(crit).priority, BundlePriority.critical);

      final bg = _manifest(name: 'b', priority: 'background');
      expect(ManagedBundle(bg).priority, BundlePriority.background);
    });

    test('bundleContext is initially null', () {
      final bundle = ManagedBundle(_manifest(name: 'ctx'));
      expect(bundle.bundleContext, isNull);
    });

    test('state delegates to stateManager', () {
      final bundle = ManagedBundle(_manifest(name: 'st'));
      expect(bundle.state, BundleState.installed);
      bundle.stateManager.transition(BundleState.resolved);
      expect(bundle.state, BundleState.resolved);
      bundle.stateManager.dispose();
    });
  });
}
