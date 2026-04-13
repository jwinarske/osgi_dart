import 'package:dart_osgi_test/dart_osgi_test.dart';
import 'package:test/test.dart';

void main() {
  group('MockServiceRegistry', () {
    late MockServiceRegistry registry;

    setUp(() {
      registry = MockServiceRegistry();
    });

    tearDown(() async {
      await registry.reset();
      registry.dispose();
    });

    group('seed() and getServiceReference()', () {
      test('seed() pre-registers a service that can be found', () {
        registry.seed<String>('com.test.Greeter', 'Hello');

        final ref = registry.getServiceReference<String>('com.test.Greeter');
        expect(ref, isNotNull);

        final svc = registry.getService<String>(ref!);
        expect(svc, equals('Hello'));
      });

      test('seed() with custom bundleSymbolicName', () {
        registry.seed<String>(
          'com.test.Svc',
          'value',
          bundleSymbolicName: 'custom.bundle',
        );

        final ref = registry.getServiceReference<String>('com.test.Svc');
        expect(ref, isNotNull);
        expect(ref!.bundleSymbolicName, equals('custom.bundle'));
      });

      test('seed() with properties', () {
        registry.seed<String>(
          'com.test.Svc',
          'value',
          properties: {'key': 'val'},
        );

        final ref = registry.getServiceReference<String>('com.test.Svc');
        expect(ref, isNotNull);
        expect(ref!.getProperty('key'), equals('val'));
      });
    });

    group('unseed()', () {
      test('removes a previously seeded service', () async {
        registry.seed<String>('com.test.Svc', 'Hello');

        await registry.unseed('com.test.Svc');

        final ref = registry.getServiceReference<String>('com.test.Svc');
        expect(ref, isNull);
      });

      test('unseed() of non-existent className does not throw', () async {
        await expectLater(registry.unseed('com.test.NonExistent'), completes);
      });
    });

    group('tracking lists', () {
      test('registrations list tracks register calls', () {
        registry.register<String>('com.test.A', 'a', 'bundle.a', null);
        registry.register<int>('com.test.B', 42, 'bundle.b', null);

        expect(registry.registrations, hasLength(2));
        expect(registry.registrations[0].className, equals('com.test.A'));
        expect(
          registry.registrations[0].bundleSymbolicName,
          equals('bundle.a'),
        );
        expect(registry.registrations[1].className, equals('com.test.B'));
        expect(
          registry.registrations[1].bundleSymbolicName,
          equals('bundle.b'),
        );
      });

      test('lookups list tracks getServiceReference calls', () {
        registry.getServiceReference<String>('com.test.A');
        registry.getServiceReference<int>('com.test.B');

        expect(registry.lookups, hasLength(2));
        expect(registry.lookups[0].className, equals('com.test.A'));
        expect(registry.lookups[1].className, equals('com.test.B'));
      });

      test('unregistrations list tracks unregister calls', () {
        final reg = registry.register<String>(
          'com.test.Svc',
          'value',
          'test.bundle',
          null,
        );
        registry.unregisterService(reg);

        expect(registry.unregistrations, hasLength(1));
        expect(registry.unregistrations.first, equals('com.test.Svc'));
      });

      test('seed() is tracked in registrations', () {
        registry.seed<String>('com.test.Svc', 'value');

        expect(registry.registrations, hasLength(1));
        expect(registry.registrations.first.className, equals('com.test.Svc'));
      });
    });

    group('resetTracking()', () {
      test('clears tracking lists but keeps seeded services', () {
        registry.seed<String>('com.test.Svc', 'Hello');
        registry.getServiceReference<String>('com.test.Svc');

        expect(registry.registrations, isNotEmpty);
        expect(registry.lookups, isNotEmpty);

        registry.resetTracking();

        expect(registry.registrations, isEmpty);
        expect(registry.lookups, isEmpty);
        expect(registry.unregistrations, isEmpty);

        // Seeded service is still available.
        final ref = registry.getServiceReference<String>('com.test.Svc');
        expect(ref, isNotNull);
      });
    });

    group('reset()', () {
      test('clears everything including seeded services', () async {
        registry.seed<String>('com.test.A', 'a');
        registry.seed<int>('com.test.B', 42);
        registry.getServiceReference<String>('com.test.A');

        await registry.reset();

        expect(registry.registrations, isEmpty);
        expect(registry.lookups, isEmpty);
        expect(registry.unregistrations, isEmpty);
        expect(registry.seededClassNames, isEmpty);

        final ref = registry.getServiceReference<String>('com.test.A');
        expect(ref, isNull);
      });
    });

    group('seededClassNames', () {
      test('returns correct set of seeded class names', () {
        registry.seed<String>('com.test.A', 'a');
        registry.seed<int>('com.test.B', 42);

        expect(
          registry.seededClassNames,
          containsAll(['com.test.A', 'com.test.B']),
        );
      });

      test('is empty when nothing seeded', () {
        expect(registry.seededClassNames, isEmpty);
      });

      test('reflects unseed operations', () async {
        registry.seed<String>('com.test.A', 'a');
        registry.seed<int>('com.test.B', 42);

        await registry.unseed('com.test.A');

        expect(registry.seededClassNames, contains('com.test.B'));
        expect(registry.seededClassNames, isNot(contains('com.test.A')));
      });
    });

    group('RegisterCall and LookupCall', () {
      test('RegisterCall.toString() is readable', () {
        const call = RegisterCall(
          className: 'com.test.Svc',
          bundleSymbolicName: 'test.bundle',
        );
        expect(call.toString(), contains('com.test.Svc'));
        expect(call.toString(), contains('test.bundle'));
      });

      test('LookupCall.toString() is readable', () {
        const call = LookupCall(className: 'com.test.Svc');
        expect(call.toString(), contains('com.test.Svc'));
      });
    });
  });
}
