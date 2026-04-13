import 'dart:isolate';

import 'package:dart_osgi_framework/dart_osgi_framework.dart';
import 'package:test/test.dart';

void main() {
  late IsolateBus bus;

  setUp(() {
    bus = IsolateBus();
  });

  tearDown(() {
    bus.dispose();
  });

  group('IsolateBus', () {
    test('registerPort / getPort round-trip', () {
      final rp = ReceivePort();
      addTearDown(rp.close);

      bus.registerPort('com.test.a', rp.sendPort);
      expect(bus.getPort('com.test.a'), equals(rp.sendPort));
    });

    test('getPort returns null for unregistered bundle', () {
      expect(bus.getPort('nonexistent'), isNull);
    });

    test('unregisterPort removes the port', () {
      final rp = ReceivePort();
      addTearDown(rp.close);

      bus.registerPort('com.test.a', rp.sendPort);
      bus.unregisterPort('com.test.a');
      expect(bus.getPort('com.test.a'), isNull);
    });

    test(
      'sendTo returns true and delivers message to registered port',
      () async {
        final rp = ReceivePort();
        addTearDown(rp.close);

        bus.registerPort('com.test.a', rp.sendPort);

        final future = rp.first;
        final result = bus.sendTo('com.test.a', 'hello');

        expect(result, isTrue);
        expect(await future, equals('hello'));
      },
    );

    test('sendTo returns false for unregistered bundle', () {
      final result = bus.sendTo('nonexistent', 'hello');
      expect(result, isFalse);
    });

    test('broadcast sends to all registered ports', () async {
      final rp1 = ReceivePort();
      final rp2 = ReceivePort();
      addTearDown(rp1.close);
      addTearDown(rp2.close);

      bus.registerPort('com.test.a', rp1.sendPort);
      bus.registerPort('com.test.b', rp2.sendPort);

      final f1 = rp1.first;
      final f2 = rp2.first;
      bus.broadcast('ping');

      expect(await f1, equals('ping'));
      expect(await f2, equals('ping'));
    });

    test('broadcast with no registered ports does nothing', () {
      // Should not throw.
      bus.broadcast('ping');
    });

    test('registeredBundles returns correct names', () {
      final rp1 = ReceivePort();
      final rp2 = ReceivePort();
      addTearDown(rp1.close);
      addTearDown(rp2.close);

      bus.registerPort('com.test.a', rp1.sendPort);
      bus.registerPort('com.test.b', rp2.sendPort);

      expect(bus.registeredBundles, containsAll(['com.test.a', 'com.test.b']));
      expect(bus.registeredBundles, hasLength(2));
    });

    test('registeredBundles is empty initially', () {
      expect(bus.registeredBundles, isEmpty);
    });

    test('dispose clears all ports', () {
      final rp = ReceivePort();
      addTearDown(rp.close);

      bus.registerPort('com.test.a', rp.sendPort);
      bus.dispose();

      expect(bus.getPort('com.test.a'), isNull);
      expect(bus.registeredBundles, isEmpty);
    });

    test('registerPort overwrites existing port for same name', () {
      final rp1 = ReceivePort();
      final rp2 = ReceivePort();
      addTearDown(rp1.close);
      addTearDown(rp2.close);

      bus.registerPort('com.test.a', rp1.sendPort);
      bus.registerPort('com.test.a', rp2.sendPort);

      expect(bus.getPort('com.test.a'), equals(rp2.sendPort));
      expect(bus.registeredBundles, hasLength(1));
    });

    test('unregisterPort for non-existent name is a no-op', () {
      // Should not throw.
      bus.unregisterPort('nonexistent');
    });
  });
}
