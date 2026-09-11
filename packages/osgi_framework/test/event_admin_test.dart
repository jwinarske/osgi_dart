import 'dart:async';

import 'package:osgi_framework/osgi_framework.dart';
import 'package:test/test.dart';

void main() {
  late EventAdmin eventAdmin;

  setUp(() => eventAdmin = EventAdmin());
  tearDown(() => eventAdmin.dispose());

  /// Collect what [topicPattern] receives while [body] runs.
  Future<List<Event>> collect(String topicPattern, void Function() body) async {
    final List<Event> events = <Event>[];
    final StreamSubscription<Event> sub = eventAdmin
        .subscribe(topicPattern)
        .listen(events.add);
    body();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    return events;
  }

  test('delivers to a matching subscriber', () async {
    final List<Event> events = await collect('com/ivi/can/THRESHOLD', () {
      eventAdmin.post('com/ivi/can/THRESHOLD', <String, Object?>{'value': 42});
    });

    expect(events.single.topic, 'com/ivi/can/THRESHOLD');
    expect(events.single.property<int>('value'), 42);
  });

  test('does not deliver to a non-matching subscriber', () async {
    final List<Event> events = await collect('com/ivi/sensor/TEMP', () {
      eventAdmin.post('com/ivi/can/THRESHOLD');
    });

    expect(events, isEmpty);
  });

  test('postEvent delivers the same Event instance', () async {
    final Event event = Event('com/ivi/test', <String, Object?>{'k': 'v'});
    final List<Event> events = await collect(
      'com/ivi/test',
      () => eventAdmin.postEvent(event),
    );

    expect(events.single, same(event));
  });

  test('a prefix subscription sees everything below it', () async {
    final List<Event> events = await collect('com/ivi/can/*', () {
      eventAdmin.post('com/ivi/can/X');
      eventAdmin.post('com/ivi/can/deep/Y');
      eventAdmin.post('com/ivi/can');
      eventAdmin.post('com/ivi/sensor/Z');
    });

    expect(events.map((Event e) => e.topic), <String>[
      'com/ivi/can/X',
      'com/ivi/can/deep/Y',
    ]);
  });

  test('every subscriber receives the event', () async {
    final List<Event> a = <Event>[];
    final List<Event> b = <Event>[];
    eventAdmin.subscribe('com/ivi/can/*').listen(a.add);
    eventAdmin.subscribe('com/ivi/*').listen(b.add);

    eventAdmin.post('com/ivi/can/X');
    await Future<void>.delayed(Duration.zero);

    expect(a, hasLength(1));
    expect(b, hasLength(1));
  });

  test('delivery is asynchronous and in posting order', () async {
    final List<String> topics = <String>[];
    eventAdmin.subscribe('*').listen((Event e) => topics.add(e.topic));

    eventAdmin.post('a');
    eventAdmin.post('b');
    expect(topics, isEmpty, reason: 'post returns before subscribers run');

    await Future<void>.delayed(Duration.zero);
    expect(topics, <String>['a', 'b']);
  });

  test(
    'an event posted before a listener starts is not delivered to it',
    () async {
      final Stream<Event> stream = eventAdmin.subscribe('com/ivi/test');
      eventAdmin.post('com/ivi/test');
      await Future<void>.delayed(Duration.zero);

      final List<Event> events = <Event>[];
      stream.listen(events.add);
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);
    },
  );

  test('cancelling stops delivery', () async {
    final List<Event> events = <Event>[];
    final StreamSubscription<Event> sub = eventAdmin
        .subscribe('com/ivi/test')
        .listen(events.add);

    eventAdmin.post('com/ivi/test');
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    eventAdmin.post('com/ivi/test');
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(1));
  });

  test('a subscriber cannot change what another sees', () async {
    final List<Event> events = <Event>[];
    eventAdmin.subscribe('com/ivi/test').listen((Event e) {
      expect(() => e.properties['value'] = 2, throwsUnsupportedError);
    });
    eventAdmin.subscribe('com/ivi/test').listen(events.add);

    eventAdmin.post('com/ivi/test', <String, Object?>{'value': 1});
    await Future<void>.delayed(Duration.zero);

    expect(events.single.property<int>('value'), 1);
  });

  test('a malformed pattern is rejected when subscribing', () {
    expect(() => eventAdmin.subscribe('com/ivi/can*'), throwsArgumentError);
  });

  group('dispose()', () {
    test('closes every subscriber stream', () async {
      bool done = false;
      eventAdmin
          .subscribe('com/ivi/test')
          .listen(
            (_) {},
            onDone: () {
              done = true;
            },
          );

      await eventAdmin.dispose();

      expect(done, isTrue);
    });

    test('later posts are dropped, not thrown', () async {
      await eventAdmin.dispose();
      expect(() => eventAdmin.post('com/ivi/test'), returnsNormally);
    });
  });

  test('registerIn publishes it under serviceName', () async {
    final ServiceRegistry registry = ServiceRegistry();
    final ServiceRegistration reg = eventAdmin.registerIn(registry);

    expect(reg.interfaceName, EventAdmin.serviceName);
    expect(registry.getService(EventAdmin.serviceName), same(eventAdmin));
    await reg.unregister();
  });
}
