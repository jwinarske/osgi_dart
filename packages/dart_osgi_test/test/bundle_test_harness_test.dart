import 'package:dart_osgi_framework/dart_osgi_framework.dart';
import 'package:dart_osgi_test/dart_osgi_test.dart';
import 'package:test/test.dart';

/// Minimal Dart bundle YAML for testing.
const _dartBundleYaml = '''
bundle:
  symbolicName: com.test.sample
  version: "1.0.0"
  type: dart
  activator: package:sample/activator.dart
  startup:
    priority: normal
    timeout_ms: 5000
''';

const _criticalBundleYaml = '''
bundle:
  symbolicName: com.test.critical
  version: "2.0.0"
  type: dart
  activator: package:critical/activator.dart
  startup:
    priority: critical
    timeout_ms: 3000
''';

void main() {
  group('BundleTestHarness', () {
    late BundleTestHarness harness;

    group('before start()', () {
      setUp(() {
        harness = BundleTestHarness();
      });

      tearDown(() async {
        await harness.dispose();
      });

      test('framework getter throws before start', () {
        expect(() => harness.framework, throwsA(isA<StateError>()));
      });

      test('eventAdmin getter throws before start', () {
        expect(() => harness.eventAdmin, throwsA(isA<StateError>()));
      });

      test('registry is available immediately', () {
        expect(harness.registry, isA<MockServiceRegistry>());
      });

      test('services builder is available immediately', () {
        // The services field should be accessible and usable.
        harness.services.when('com.test.Svc').thenReturn<String>('test');
        // No error means it works.
      });
    });

    group('after start()', () {
      setUp(() async {
        harness = BundleTestHarness();
        await harness.start();
      });

      tearDown(() async {
        await harness.dispose();
      });

      test('start() initializes framework', () {
        expect(harness.framework, isA<DartOSGiFramework>());
        expect(harness.framework.isStarted, isTrue);
      });

      test('start() initializes eventAdmin', () {
        expect(harness.eventAdmin, isA<EventAdmin>());
      });

      test('eventAdmin is registered as service', () {
        final ref = harness.registry.getServiceReference<EventAdmin>(
          EventAdmin.serviceName,
        );
        expect(ref, isNotNull);
      });
    });

    group('installAndStart()', () {
      setUp(() async {
        harness = BundleTestHarness();
        await harness.start();
      });

      tearDown(() async {
        await harness.dispose();
      });

      test('installs, resolves, and starts a bundle', () async {
        final manifest = BundleManifest.parse(_dartBundleYaml);
        final context = await harness.installAndStart(manifest);

        expect(context, isA<IsolateBundleContext>());

        final bundle = harness.framework.bundleManager.getBundle(
          'com.test.sample',
        );
        expect(bundle, isNotNull);
        expect(bundle!.state, equals(BundleState.active));
      });
    });

    group('installAndStartFromYaml()', () {
      setUp(() async {
        harness = BundleTestHarness();
        await harness.start();
      });

      tearDown(() async {
        await harness.dispose();
      });

      test('parses YAML and starts the bundle', () async {
        final context = await harness.installAndStartFromYaml(
          _criticalBundleYaml,
        );

        expect(context, isA<IsolateBundleContext>());

        final bundle = harness.framework.bundleManager.getBundle(
          'com.test.critical',
        );
        expect(bundle, isNotNull);
        expect(bundle!.state, equals(BundleState.active));
      });
    });

    group('dispose()', () {
      test('cleans up framework and registry', () async {
        harness = BundleTestHarness();
        await harness.start();

        // Install a bundle so there is something to clean up.
        await harness.installAndStartFromYaml(_dartBundleYaml);

        await harness.dispose();

        // After dispose, framework and eventAdmin getters should throw
        // because the harness nulls them out.
        expect(() => harness.framework, throwsA(isA<StateError>()));
        expect(() => harness.eventAdmin, throwsA(isA<StateError>()));
      });

      test('clears postedEvents', () async {
        harness = BundleTestHarness();
        await harness.start();

        // Post an event.
        harness.eventAdmin.post('com/test/EVENT', {'key': 'value'});
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(harness.postedEvents, isNotEmpty);

        await harness.dispose();
        expect(harness.postedEvents, isEmpty);
      });

      test('dispose() can be called multiple times safely', () async {
        harness = BundleTestHarness();
        await harness.start();

        await harness.dispose();
        // Second dispose should not throw.
        await harness.dispose();
      });
    });

    group('service stubs integration', () {
      setUp(() async {
        harness = BundleTestHarness();
      });

      tearDown(() async {
        await harness.dispose();
      });

      test('services seeded before start are available to bundles', () async {
        harness.services
            .when('com.test.CanEngine')
            .thenReturn<String>('MockEngine');
        harness.services.apply();

        await harness.start();

        final ref = harness.registry.getServiceReference<String>(
          'com.test.CanEngine',
        );
        expect(ref, isNotNull);
        final svc = harness.registry.getService<String>(ref!);
        expect(svc, equals('MockEngine'));
      });
    });

    group('postedEvents', () {
      setUp(() async {
        harness = BundleTestHarness();
        await harness.start();
      });

      tearDown(() async {
        await harness.dispose();
      });

      test('captures events posted to eventAdmin', () async {
        harness.eventAdmin.post('com/test/MY_EVENT', {'data': 'hello'});

        // Allow async event propagation.
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(harness.postedEvents, hasLength(greaterThanOrEqualTo(1)));
        expect(
          harness.postedEvents.any((e) => e.topic == 'com/test/MY_EVENT'),
          isTrue,
        );
      });
    });
  });
}
