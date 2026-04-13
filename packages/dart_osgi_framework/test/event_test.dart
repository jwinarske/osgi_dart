import 'package:dart_osgi_framework/dart_osgi_framework.dart';
import 'package:test/test.dart';

void main() {
  group('Event', () {
    test('constructor stores topic and properties', () {
      final event = Event('com/ivi/can/THRESHOLD', {'signal': 'EngineTemp'});
      expect(event.topic, 'com/ivi/can/THRESHOLD');
      expect(event.properties, {'signal': 'EngineTemp'});
    });

    test('constructor defaults to empty properties', () {
      final event = Event('com/ivi/test');
      expect(event.topic, 'com/ivi/test');
      expect(event.properties, isEmpty);
    });

    test('property<T>() returns typed value when type matches', () {
      final event = Event('t', {
        'name': 'hello',
        'count': 42,
        'ratio': 3.14,
        'flag': true,
      });
      expect(event.property<String>('name'), 'hello');
      expect(event.property<int>('count'), 42);
      expect(event.property<double>('ratio'), 3.14);
      expect(event.property<bool>('flag'), true);
    });

    test('property<T>() returns null when type does not match', () {
      final event = Event('t', {'name': 'hello'});
      expect(event.property<int>('name'), isNull);
      expect(event.property<bool>('name'), isNull);
    });

    test('property<T>() returns null for missing key', () {
      final event = Event('t', {'name': 'hello'});
      expect(event.property<String>('missing'), isNull);
    });

    test('toString() includes topic and properties', () {
      final event = Event('com/ivi/test', {'k': 'v'});
      expect(event.toString(), 'Event(com/ivi/test, {k: v})');
    });

    test('toString() with empty properties', () {
      final event = Event('com/ivi/test');
      expect(event.toString(), 'Event(com/ivi/test, {})');
    });

    test('can be created as const', () {
      const event = Event('com/ivi/const', {'key': 'value'});
      expect(event.topic, 'com/ivi/const');
      expect(event.properties, {'key': 'value'});
    });
  });

  group('Topics', () {
    test('bundle constant', () {
      expect(Topics.bundle, 'com/ivi/bundle');
    });

    test('navigation constant', () {
      expect(Topics.navigation, 'com/ivi/navigation');
    });

    test('can constant', () {
      expect(Topics.can, 'com/ivi/can');
    });

    test('sensor constant', () {
      expect(Topics.sensor, 'com/ivi/sensor');
    });

    test('media constant', () {
      expect(Topics.media, 'com/ivi/media');
    });

    test('bundleStarted constant', () {
      expect(Topics.bundleStarted, 'com/ivi/bundle/STARTED');
    });

    test('bundleStopped constant', () {
      expect(Topics.bundleStopped, 'com/ivi/bundle/STOPPED');
    });

    test('bundleUpdated constant', () {
      expect(Topics.bundleUpdated, 'com/ivi/bundle/UPDATED');
    });

    test('routeChanged constant', () {
      expect(Topics.routeChanged, 'com/ivi/navigation/ROUTE_CHANGED');
    });
  });
}
