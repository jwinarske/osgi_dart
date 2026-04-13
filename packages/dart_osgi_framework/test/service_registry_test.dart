import 'dart:async';

import 'package:dart_osgi_framework/dart_osgi_framework.dart';
import 'package:test/test.dart';

void main() {
  late ServiceRegistry registry;

  setUp(() {
    registry = ServiceRegistry();
  });

  tearDown(() {
    registry.dispose();
  });

  group('register()', () {
    test('returns registration with correct serviceId starting at 1', () {
      final reg = registry.register('Foo', 'svc', 'bundle.a', null);
      expect(reg.reference.serviceId, equals(1));
    });

    test('increments serviceId on successive registrations', () {
      final reg1 = registry.register('Foo', 'svc1', 'bundle.a', null);
      final reg2 = registry.register('Foo', 'svc2', 'bundle.a', null);
      expect(reg1.reference.serviceId, equals(1));
      expect(reg2.reference.serviceId, equals(2));
    });

    test('adds objectClass and bundleSymbolicName properties', () {
      final reg = registry.register('Foo', 'svc', 'bundle.a', {'extra': 'val'});
      final ref = reg.reference;
      expect(ref.getProperty('objectClass'), equals('Foo'));
      expect(ref.getProperty('service.bundleSymbolicName'), equals('bundle.a'));
      expect(ref.getProperty('extra'), equals('val'));
    });
  });

  group('getServiceReference()', () {
    test('returns best-ranked reference', () {
      registry.register('Foo', 'low', 'b', {'service.ranking': 1});
      registry.register('Foo', 'high', 'b', {'service.ranking': 10});
      final ref = registry.getServiceReference<String>('Foo');
      expect(ref, isNotNull);
      expect(ref!.ranking, equals(10));
    });

    test('returns null when no services registered', () {
      final ref = registry.getServiceReference<String>('Foo');
      expect(ref, isNull);
    });
  });

  group('getServiceReferences()', () {
    test('filters by LDAP filter', () {
      registry.register('Foo', 'svcA', 'b', {'color': 'red'});
      registry.register('Foo', 'svcB', 'b', {'color': 'blue'});
      final refs = registry.getServiceReferences<String>('Foo', '(color=red)');
      expect(refs, hasLength(1));
      expect(refs.first.getProperty('color'), equals('red'));
    });

    test('sorted by ranking descending then serviceId ascending', () {
      registry.register('Foo', 'first', 'b', {'service.ranking': 5});
      registry.register('Foo', 'second', 'b', {'service.ranking': 10});
      registry.register('Foo', 'third', 'b', {'service.ranking': 5});

      final refs = registry.getServiceReferences<String>('Foo', null);
      expect(refs, hasLength(3));
      // highest ranking first
      expect(refs[0].ranking, equals(10));
      // same ranking: lower serviceId first
      expect(refs[1].serviceId, lessThan(refs[2].serviceId));
      expect(refs[1].ranking, equals(5));
      expect(refs[2].ranking, equals(5));
    });

    test('returns empty list for unknown className', () {
      final refs = registry.getServiceReferences<String>('NoSuch', null);
      expect(refs, isEmpty);
    });
  });

  group('getService()', () {
    test('returns the service object', () {
      final reg = registry.register('Foo', 'myService', 'b', null);
      final svc = registry.getService<String>(reg.reference);
      expect(svc, equals('myService'));
    });

    test('returns null for unknown reference', () {
      // Create a reference that is not in the registry.
      final ref = RegistryServiceReference<String>(
        serviceId: 999,
        bundleSymbolicName: 'unknown',
        initialProperties: {'objectClass': 'Foo'},
        ranking: 0,
      );
      final svc = registry.getService<String>(ref);
      expect(svc, isNull);
    });

    test('returns null when objectClass property is missing', () {
      final ref = RegistryServiceReference<String>(
        serviceId: 999,
        bundleSymbolicName: 'unknown',
        initialProperties: {},
        ranking: 0,
      );
      final svc = registry.getService<String>(ref);
      expect(svc, isNull);
    });
  });

  group('setProperties()', () {
    test('updates reference properties and fires MODIFIED event', () async {
      final reg = registry.register('Foo', 'svc', 'b', {'color': 'red'});

      final events = <ServiceEvent>[];
      final sub = registry.events.listen(events.add);

      reg.setProperties({'color': 'blue'});

      // Allow event to propagate.
      await Future<void>.delayed(Duration.zero);

      expect(reg.reference.getProperty('color'), equals('blue'));
      // objectClass and bundleSymbolicName are preserved.
      expect(reg.reference.getProperty('objectClass'), equals('Foo'));
      expect(
        reg.reference.getProperty('service.bundleSymbolicName'),
        equals('b'),
      );

      expect(events, hasLength(1));
      expect(events.first.type, equals(ServiceEventType.modified));

      await sub.cancel();
    });

    test('throws StateError after unregister', () async {
      final reg = registry.register('Foo', 'svc', 'b', null);
      await reg.unregister();

      expect(
        () => reg.setProperties({'key': 'val'}),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('unregister()', () {
    test('removes from registry and fires UNREGISTERING event', () async {
      final reg = registry.register('Foo', 'svc', 'b', null);

      final events = <ServiceEvent>[];
      final sub = registry.events.listen(events.add);

      await reg.unregister();
      await Future<void>.delayed(Duration.zero);

      // Service should no longer be found.
      expect(registry.getServiceReference<String>('Foo'), isNull);

      expect(events, hasLength(1));
      expect(events.first.type, equals(ServiceEventType.unregistering));

      await sub.cancel();
    });

    test('calling unregister twice is safe (no-op on second call)', () async {
      final reg = registry.register('Foo', 'svc', 'b', null);
      await reg.unregister();
      // Second call should not throw.
      await reg.unregister();
    });
  });

  group('service.ranking property', () {
    test('affects ordering of getServiceReference', () {
      registry.register('Foo', 'lowRank', 'b', {'service.ranking': 1});
      registry.register('Foo', 'highRank', 'b', {'service.ranking': 100});

      final ref = registry.getServiceReference<String>('Foo');
      expect(ref, isNotNull);
      // The high-ranked service should be returned.
      final svc = registry.getService<String>(ref!);
      expect(svc, equals('highRank'));
    });

    test('default ranking is 0 when not provided', () {
      final reg = registry.register('Foo', 'svc', 'b', null);
      expect(reg.reference.ranking, equals(0));
    });
  });

  group('events stream', () {
    test('fires REGISTERED on register', () async {
      final events = <ServiceEvent>[];
      final sub = registry.events.listen(events.add);

      registry.register('Foo', 'svc', 'b', null);
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.first.type, equals(ServiceEventType.registered));

      await sub.cancel();
    });

    test('fires MODIFIED on setProperties', () async {
      final reg = registry.register('Foo', 'svc', 'b', null);

      final events = <ServiceEvent>[];
      final sub = registry.events.listen(events.add);

      reg.setProperties({'key': 'val'});
      await Future<void>.delayed(Duration.zero);

      expect(events.any((e) => e.type == ServiceEventType.modified), isTrue);

      await sub.cancel();
    });

    test('fires UNREGISTERING on unregister', () async {
      final reg = registry.register('Foo', 'svc', 'b', null);

      final events = <ServiceEvent>[];
      final sub = registry.events.listen(events.add);

      await reg.unregister();
      await Future<void>.delayed(Duration.zero);

      expect(
        events.any((e) => e.type == ServiceEventType.unregistering),
        isTrue,
      );

      await sub.cancel();
    });
  });

  group('dispose()', () {
    test('closes event stream', () async {
      final done = Completer<void>();
      registry.events.listen(null, onDone: done.complete);

      registry.dispose();

      await done.future;
      // If we reach here, the stream was closed.
    });
  });

  group('RegistryServiceReference', () {
    test('properties map is unmodifiable', () {
      final reg = registry.register('Foo', 'svc', 'b', null);
      expect(
        () => (reg.reference.properties as Map)['hack'] = 'bad',
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('compareTo sorts by ranking then serviceId', () {
      final refA = RegistryServiceReference<String>(
        serviceId: 1,
        bundleSymbolicName: 'b',
        initialProperties: {},
        ranking: 10,
      );
      final refB = RegistryServiceReference<String>(
        serviceId: 2,
        bundleSymbolicName: 'b',
        initialProperties: {},
        ranking: 5,
      );
      // A has higher ranking, so compareTo should sort A before B (negative).
      expect(refA.compareTo(refB), lessThan(0));
    });

    test('compareTo breaks tie by serviceId (lower wins)', () {
      final refA = RegistryServiceReference<String>(
        serviceId: 1,
        bundleSymbolicName: 'b',
        initialProperties: {},
        ranking: 5,
      );
      final refB = RegistryServiceReference<String>(
        serviceId: 2,
        bundleSymbolicName: 'b',
        initialProperties: {},
        ranking: 5,
      );
      expect(refA.compareTo(refB), lessThan(0));
    });

    test('toString() includes type, id, bundle, and ranking', () {
      final ref = RegistryServiceReference<String>(
        serviceId: 42,
        bundleSymbolicName: 'my.bundle',
        initialProperties: {},
        ranking: 7,
      );
      final s = ref.toString();
      expect(s, contains('42'));
      expect(s, contains('my.bundle'));
      expect(s, contains('7'));
    });

    test('updateProperties updates ranking from new properties', () {
      final ref = RegistryServiceReference<String>(
        serviceId: 1,
        bundleSymbolicName: 'b',
        initialProperties: {'service.ranking': 5},
        ranking: 5,
      );
      ref.updateProperties({'service.ranking': 20});
      expect(ref.ranking, equals(20));
    });

    test('updateProperties keeps old ranking when new props lack it', () {
      final ref = RegistryServiceReference<String>(
        serviceId: 1,
        bundleSymbolicName: 'b',
        initialProperties: {'service.ranking': 5},
        ranking: 5,
      );
      ref.updateProperties({'color': 'red'});
      expect(ref.ranking, equals(5));
    });
  });
}
