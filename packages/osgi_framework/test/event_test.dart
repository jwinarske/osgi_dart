import 'package:osgi_framework/osgi_framework.dart';
import 'package:test/test.dart';

void main() {
  test('stores topic and properties', () {
    final Event event = Event('com/ivi/can/THRESHOLD', <String, Object?>{
      'signal': 'Temp',
    });
    expect(event.topic, 'com/ivi/can/THRESHOLD');
    expect(event.properties, <String, Object?>{'signal': 'Temp'});
  });

  test('defaults to no properties', () {
    expect(Event('com/ivi/test').properties, isEmpty);
  });

  test('property<T>() returns the value only when it is a T', () {
    final Event event = Event('t', <String, Object?>{
      'name': 'hello',
      'count': 42,
      'ratio': 3.14,
      'flag': true,
    });
    expect(event.property<String>('name'), 'hello');
    expect(event.property<int>('count'), 42);
    expect(event.property<double>('ratio'), 3.14);
    expect(event.property<bool>('flag'), isTrue);
    expect(event.property<int>('name'), isNull);
    expect(event.property<String>('missing'), isNull);
  });

  test('copies its properties, so the publisher cannot change them later', () {
    final Map<String, Object?> props = <String, Object?>{'value': 1};
    final Event event = Event('t', props);

    props['value'] = 2;

    expect(event.property<int>('value'), 1);
  });

  test('its properties are unmodifiable, so one subscriber cannot change '
      'what the next sees', () {
    final Event event = Event('t', <String, Object?>{'value': 1});
    expect(() => event.properties['value'] = 2, throwsUnsupportedError);
  });

  test('rejects an empty topic or one containing a wildcard', () {
    expect(() => Event(''), throwsArgumentError);
    expect(() => Event('com/ivi/*'), throwsArgumentError);
  });

  test('toString() shows topic and properties', () {
    expect(
      Event('com/ivi/test', <String, Object?>{'k': 'v'}).toString(),
      'Event(com/ivi/test, {k: v})',
    );
  });
}
