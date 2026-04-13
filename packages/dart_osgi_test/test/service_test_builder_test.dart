import 'dart:async';

import 'package:dart_osgi_test/dart_osgi_test.dart';
import 'package:test/test.dart';

void main() {
  group('ServiceTestBuilder', () {
    late MockServiceRegistry registry;
    late ServiceTestBuilder builder;

    setUp(() {
      registry = MockServiceRegistry();
      builder = ServiceTestBuilder(registry);
    });

    tearDown(() async {
      await builder.reset();
      await registry.reset();
      registry.dispose();
    });

    group('when().thenReturn()', () {
      test('seeds a service that can be looked up', () {
        builder.when('com.test.Greeter').thenReturn<String>('Hello');
        builder.apply();

        final ref = registry.getServiceReference<String>('com.test.Greeter');
        expect(ref, isNotNull);
        final svc = registry.getService<String>(ref!);
        expect(svc, equals('Hello'));
      });

      test('uses custom bundleSymbolicName', () {
        builder
            .when('com.test.Svc')
            .thenReturn<String>('value', bundleSymbolicName: 'my.bundle');
        builder.apply();

        final ref = registry.getServiceReference<String>('com.test.Svc');
        expect(ref, isNotNull);
        expect(ref!.bundleSymbolicName, equals('my.bundle'));
      });

      test('uses custom properties', () {
        builder
            .when('com.test.Svc')
            .thenReturn<String>(
              'value',
              properties: {'custom.key': 'custom.val'},
            );
        builder.apply();

        final ref = registry.getServiceReference<String>('com.test.Svc');
        expect(ref, isNotNull);
        expect(ref!.getProperty('custom.key'), equals('custom.val'));
      });
    });

    group('when().thenStream()', () {
      test('seeds a stream service', () {
        final controller = StreamController<int>.broadcast();
        addTearDown(controller.close);

        builder.when('com.test.DataStream').thenStream<int>(controller.stream);
        builder.apply();

        final ref = registry.getServiceReference<Stream<int>>(
          'com.test.DataStream',
        );
        expect(ref, isNotNull);
        final svc = registry.getService<Stream<int>>(ref!);
        expect(svc, isNotNull);
      });
    });

    group('apply()', () {
      test('registers all stubs at once', () {
        builder
            .when('com.test.A')
            .thenReturn<String>('a')
            .when('com.test.B')
            .thenReturn<int>(42);

        builder.apply();

        expect(registry.getServiceReference<String>('com.test.A'), isNotNull);
        expect(registry.getServiceReference<int>('com.test.B'), isNotNull);
      });
    });

    group('reset()', () {
      test('removes all stubs from the registry', () async {
        builder
            .when('com.test.A')
            .thenReturn<String>('a')
            .when('com.test.B')
            .thenReturn<int>(42);

        builder.apply();

        expect(registry.getServiceReference<String>('com.test.A'), isNotNull);

        await builder.reset();

        // After resetting tracking so lookups are clean.
        registry.resetTracking();

        final refA = registry.getServiceReference<String>('com.test.A');
        expect(refA, isNull);
        final refB = registry.getServiceReference<int>('com.test.B');
        expect(refB, isNull);
      });
    });

    group('chaining', () {
      test('multiple when() calls can be chained', () {
        builder
            .when('com.test.A')
            .thenReturn<String>('a')
            .when('com.test.B')
            .thenReturn<int>(42)
            .when('com.test.C')
            .thenReturn<double>(3.14);

        builder.apply();

        expect(registry.getServiceReference<String>('com.test.A'), isNotNull);
        expect(registry.getServiceReference<int>('com.test.B'), isNotNull);
        expect(registry.getServiceReference<double>('com.test.C'), isNotNull);
      });

      test('thenReturn returns parent builder for chaining', () {
        final returned = builder.when('com.test.A').thenReturn<String>('a');
        expect(returned, same(builder));
      });

      test('thenStream returns parent builder for chaining', () {
        final controller = StreamController<int>.broadcast();
        addTearDown(controller.close);

        final returned = builder
            .when('com.test.A')
            .thenStream<int>(controller.stream);
        expect(returned, same(builder));
      });
    });
  });
}
