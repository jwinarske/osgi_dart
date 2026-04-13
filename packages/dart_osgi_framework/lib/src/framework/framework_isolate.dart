import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'framework_message.dart';

/// Configuration passed to the framework isolate on spawn.
class FrameworkIsolateConfig {
  const FrameworkIsolateConfig({this.frameworkCore});

  /// CPU core for affinity (set by C++ host via pthread_setaffinity before
  /// spawning). Stored here for diagnostics — actual pinning is done in C++.
  final int? frameworkCore;
}

/// The central framework isolate with priority-separated message ports.
///
/// Provides dual [ReceivePort]s:
/// - **priorityPort**: for critical bundles (instrument cluster, safety)
/// - **normalPort**: for normal and background bundles
///
/// The [FrameworkScheduler] ensures the priority queue is fully drained
/// before any normal message is processed on each event loop turn.
class FrameworkIsolate {
  FrameworkIsolate._({
    required this.priorityPort,
    required this.normalPort,
    required this.prioritySendPort,
    required this.normalSendPort,
  });

  final ReceivePort priorityPort;
  final ReceivePort normalPort;

  /// SendPort that critical bundles use to reach the framework.
  final SendPort prioritySendPort;

  /// SendPort that normal/background bundles use to reach the framework.
  final SendPort normalSendPort;

  late final FrameworkScheduler _scheduler;

  bool _running = false;

  /// Create the framework isolate with its dual ports.
  ///
  /// Call [start] to begin processing messages.
  static FrameworkIsolate create({FrameworkIsolateConfig? config}) {
    final priorityPort = ReceivePort('framework.priority');
    final normalPort = ReceivePort('framework.normal');

    return FrameworkIsolate._(
      priorityPort: priorityPort,
      normalPort: normalPort,
      prioritySendPort: priorityPort.sendPort,
      normalSendPort: normalPort.sendPort,
    );
  }

  /// Start the framework event loop with the given message [handler].
  ///
  /// The handler is called for each [FrameworkMessage] in priority order.
  void start(void Function(FrameworkMessage message) handler) {
    if (_running) return;
    _running = true;
    _scheduler = FrameworkScheduler(
      priorityPort: priorityPort,
      normalPort: normalPort,
      handler: handler,
    );
    _scheduler.start();
  }

  /// Stop the framework event loop and close ports.
  void stop() {
    if (!_running) return;
    _running = false;
    _scheduler.stop();
    priorityPort.close();
    normalPort.close();
  }
}

/// Drains the priority port to empty before processing any normal message.
///
/// On each event loop turn:
/// 1. Drain ALL queued priority messages.
/// 2. Process ONE normal message.
/// 3. Repeat.
///
/// This ensures critical bundles (instrument cluster) never wait behind
/// normal traffic.
class FrameworkScheduler {
  FrameworkScheduler({
    required this.priorityPort,
    required this.normalPort,
    required this.handler,
  });

  final ReceivePort priorityPort;
  final ReceivePort normalPort;
  final void Function(FrameworkMessage message) handler;

  final _priorityQueue = Queue<FrameworkMessage>();
  final _normalQueue = Queue<FrameworkMessage>();

  StreamSubscription<dynamic>? _prioritySub;
  StreamSubscription<dynamic>? _normalSub;
  bool _running = false;
  bool _draining = false;

  void start() {
    _running = true;

    _prioritySub = priorityPort.listen((dynamic msg) {
      if (msg is FrameworkMessage) {
        _priorityQueue.add(msg);
        _drain();
      }
    });

    _normalSub = normalPort.listen((dynamic msg) {
      if (msg is FrameworkMessage) {
        _normalQueue.add(msg);
        _drain();
      }
    });
  }

  void stop() {
    _running = false;
    _prioritySub?.cancel();
    _normalSub?.cancel();
    _priorityQueue.clear();
    _normalQueue.clear();
  }

  /// Process queued messages: drain all priority, then one normal.
  void _drain() {
    if (!_running || _draining) return;
    _draining = true;

    try {
      // Drain ALL priority messages first.
      while (_priorityQueue.isNotEmpty) {
        handler(_priorityQueue.removeFirst());
      }

      // Process ONE normal message per drain cycle.
      if (_normalQueue.isNotEmpty) {
        handler(_normalQueue.removeFirst());
      }
    } finally {
      _draining = false;
    }

    // If more messages arrived during processing, schedule another drain.
    if (_priorityQueue.isNotEmpty || _normalQueue.isNotEmpty) {
      scheduleMicrotask(_drain);
    }
  }
}
