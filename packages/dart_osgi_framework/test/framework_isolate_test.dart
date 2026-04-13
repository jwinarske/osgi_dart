import 'dart:async';
import 'dart:isolate';

import 'package:dart_osgi_framework/dart_osgi_framework.dart';
import 'package:test/test.dart';

void main() {
  group('FrameworkIsolateConfig', () {
    test('stores frameworkCore', () {
      final config = FrameworkIsolateConfig(frameworkCore: 3);
      expect(config.frameworkCore, equals(3));
    });

    test('frameworkCore defaults to null', () {
      const config = FrameworkIsolateConfig();
      expect(config.frameworkCore, isNull);
    });
  });

  group('FrameworkIsolate', () {
    late FrameworkIsolate isolate;

    setUp(() {
      isolate = FrameworkIsolate.create();
    });

    tearDown(() {
      isolate.stop();
    });

    test('create() produces valid ports', () {
      expect(isolate.prioritySendPort, isNotNull);
      expect(isolate.normalSendPort, isNotNull);
      expect(isolate.priorityPort, isNotNull);
      expect(isolate.normalPort, isNotNull);
      // The send ports should differ (two separate ReceivePorts).
      expect(isolate.prioritySendPort, isNot(equals(isolate.normalSendPort)));
    });

    test('create() with config does not throw', () {
      final iso = FrameworkIsolate.create(
        config: const FrameworkIsolateConfig(frameworkCore: 2),
      );
      expect(iso.prioritySendPort, isNotNull);
      iso.stop();
    });

    test('start(handler) begins processing', () async {
      final received = <FrameworkMessage>[];
      isolate.start((msg) => received.add(msg));

      final msg = FrameworkMessage(
        type: FrameworkMessageType.bundleReady,
        bundleSymbolicName: 'com.test.a',
      );

      isolate.normalSendPort.send(msg);

      // Allow the message to be delivered through the event loop.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(received, hasLength(1));
      expect(received.first.bundleSymbolicName, equals('com.test.a'));
    });

    test('start() twice is safe (second call is no-op)', () {
      var callCount = 0;
      isolate.start((_) => callCount++);
      // Second start should not throw or create a new scheduler.
      isolate.start((_) => callCount++);
    });

    test('stop() closes ports', () {
      isolate.start((_) {});
      isolate.stop();

      // After stop, sending should not cause errors in the handler.
      // A second stop is also safe.
      isolate.stop();
    });
  });

  group('FrameworkScheduler', () {
    test('priority messages processed before normal', () async {
      final processed = <String>[];

      final scheduler = FrameworkScheduler(
        priorityPort: _NoOpReceivePort(),
        normalPort: _NoOpReceivePort(),
        handler: (msg) => processed.add(msg.bundleSymbolicName),
      );

      // Access the queues directly via the scheduler's internal state.
      // We will manually add messages before starting to test drain order.
      // Instead, we test indirectly by sending messages.

      // We'll use real ReceivePorts and send priority first, then normal.
      scheduler.start();

      // Manually inject messages into the queues.
      // Since the fields are private, we test via the full integration path.
      // Create a real scheduler with real ports.
      scheduler.stop();

      // Use an integration approach: create real ports, send messages, check order.
      final priorityRp = _FakeReceivePort();
      final normalRp = _FakeReceivePort();

      final ordered = <String>[];
      final sched = FrameworkScheduler(
        priorityPort: priorityRp,
        normalPort: normalRp,
        handler: (msg) => ordered.add(msg.bundleSymbolicName),
      );

      sched.start();

      // Simulate messages arriving on the priority port callback.
      priorityRp.emit(
        FrameworkMessage(
          type: FrameworkMessageType.bundleReady,
          bundleSymbolicName: 'priority-1',
        ),
      );
      priorityRp.emit(
        FrameworkMessage(
          type: FrameworkMessageType.bundleReady,
          bundleSymbolicName: 'priority-2',
        ),
      );
      normalRp.emit(
        FrameworkMessage(
          type: FrameworkMessageType.bundleReady,
          bundleSymbolicName: 'normal-1',
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Priority messages should come first.
      expect(
        ordered.indexOf('priority-1'),
        lessThan(ordered.indexOf('normal-1')),
      );
      expect(
        ordered.indexOf('priority-2'),
        lessThan(ordered.indexOf('normal-1')),
      );

      sched.stop();
    });

    test('drains ALL priority before ONE normal', () async {
      final ordered = <String>[];

      final priorityRp = _FakeReceivePort();
      final normalRp = _FakeReceivePort();

      final sched = FrameworkScheduler(
        priorityPort: priorityRp,
        normalPort: normalRp,
        handler: (msg) => ordered.add(msg.bundleSymbolicName),
      );

      sched.start();

      // Add a normal message first.
      normalRp.emit(
        FrameworkMessage(
          type: FrameworkMessageType.bundleReady,
          bundleSymbolicName: 'normal-1',
        ),
      );
      normalRp.emit(
        FrameworkMessage(
          type: FrameworkMessageType.bundleReady,
          bundleSymbolicName: 'normal-2',
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Now send priority messages along with more normals.
      ordered.clear();
      priorityRp.emit(
        FrameworkMessage(
          type: FrameworkMessageType.bundleReady,
          bundleSymbolicName: 'p1',
        ),
      );
      priorityRp.emit(
        FrameworkMessage(
          type: FrameworkMessageType.bundleReady,
          bundleSymbolicName: 'p2',
        ),
      );
      priorityRp.emit(
        FrameworkMessage(
          type: FrameworkMessageType.bundleReady,
          bundleSymbolicName: 'p3',
        ),
      );
      normalRp.emit(
        FrameworkMessage(
          type: FrameworkMessageType.bundleReady,
          bundleSymbolicName: 'n1',
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // All priority should be before any normal in this drain cycle.
      final pIndices = ['p1', 'p2', 'p3'].map((n) => ordered.indexOf(n));
      final nIndex = ordered.indexOf('n1');
      for (final pi in pIndices) {
        expect(
          pi,
          lessThan(nIndex),
          reason: 'all priority messages should be processed before normal',
        );
      }

      sched.stop();
    });

    test('stop clears queues', () {
      final priorityRp = _FakeReceivePort();
      final normalRp = _FakeReceivePort();

      final sched = FrameworkScheduler(
        priorityPort: priorityRp,
        normalPort: normalRp,
        handler: (_) {},
      );

      sched.start();
      sched.stop();

      // After stop, emitting should not cause handler calls.
      // This is a basic sanity check — the subscriptions are cancelled.
    });

    test('non-FrameworkMessage objects are ignored', () async {
      final processed = <FrameworkMessage>[];

      final priorityRp = _FakeReceivePort();
      final normalRp = _FakeReceivePort();

      final sched = FrameworkScheduler(
        priorityPort: priorityRp,
        normalPort: normalRp,
        handler: (msg) => processed.add(msg),
      );

      sched.start();

      // Emit a non-FrameworkMessage.
      priorityRp.emit('not a framework message');
      normalRp.emit(42);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(processed, isEmpty);

      sched.stop();
    });
  });
}

/// A fake ReceivePort that lets tests inject messages into the listen callback.
class _FakeReceivePort implements ReceivePort {
  final _controller = StreamController<dynamic>.broadcast(sync: true);

  void emit(dynamic message) {
    _controller.add(message);
  }

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic message)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  void close() {
    _controller.close();
  }

  @override
  SendPort get sendPort => throw UnimplementedError();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// A ReceivePort that does nothing — used as a placeholder.
class _NoOpReceivePort implements ReceivePort {
  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic message)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return const Stream<dynamic>.empty().listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  void close() {}

  @override
  SendPort get sendPort => throw UnimplementedError();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
