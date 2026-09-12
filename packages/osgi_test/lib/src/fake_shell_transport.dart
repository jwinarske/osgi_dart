import 'dart:async';
import 'dart:isolate';

import 'package:osgi_api/osgi_api.dart';

/// One thing a bundle told the shell.
class ShellCall {
  const ShellCall(this.method, this.symbolicName);

  final String method;
  final String symbolicName;

  @override
  String toString() => '$method($symbolicName)';

  @override
  bool operator ==(Object other) =>
      other is ShellCall &&
      other.method == method &&
      other.symbolicName == symbolicName;

  @override
  int get hashCode => Object.hash(method, symbolicName);
}

/// An in-memory [ShellTransport] that records what a bundle said.
///
/// The point is to make the orderings that actually break things reachable in a
/// unit test. Two of them are not hypothetical -- both were real bugs on the
/// shell side:
///
///   * **The framework port arriving after `register` returns.** The framework
///     isolate and the bundle start concurrently, so either order happens. Code
///     that assumes the port is in hand when registration completes works on a
///     fast machine and fails on a loaded one. [completeFrameworkPort] is
///     manual by default so a test picks the order deliberately.
///
///   * **ACTIVE never being sent.** A bundle whose activator throws, hangs, or
///     returns early leaves a critical startup wait to expire. Assert on
///     [calls] rather than on the activator not throwing -- an activator can
///     fail without throwing anywhere the test can see.
class FakeShellTransport implements ShellTransport {
  FakeShellTransport({
    this.autoFrameworkPort,
    this.rejectRegister,
    this.rejectActive,
    this.unavailable = false,
  });

  /// If set, [register] completes the framework port with this immediately.
  /// Leave null to control the timing with [completeFrameworkPort].
  ///
  /// A [SendPort] because that is what the shell delivers: a port id would be
  /// useless to the bundle, which cannot turn one back into a [SendPort]. Pass
  /// a `FrameworkServer`'s port here to wire a bundle to a real framework.
  final SendPort? autoFrameworkPort;

  /// If set, [register] throws [ShellRejectedException] with this code. The
  /// realistic value is `rejected`, which the shell returns for a symbolic name
  /// that is already registered.
  final String? rejectRegister;

  /// If set, [reportActive] throws [ShellRejectedException] with this code.
  final String? rejectActive;

  /// Stand in for a shell built without OSGi support: every call throws
  /// [ShellUnavailableException].
  final bool unavailable;

  /// Every call, in order. This is the assertion surface.
  final List<ShellCall> calls = <ShellCall>[];

  Completer<SendPort>? _frameworkPort;

  String? _registeredName;

  /// Completes after [register] has been called and the bundle is waiting.
  Future<void> get registered => _registered.future;
  final Completer<void> _registered = Completer<void>();

  bool get isRegistered => _frameworkPort != null;

  /// Deliver the framework isolate's port, as the shell would, at whatever
  /// moment the test wants.
  void completeFrameworkPort(SendPort port) {
    final Completer<SendPort>? pending = _frameworkPort;
    if (pending == null) {
      throw StateError('not registered; no one is waiting for a port');
    }
    if (pending.isCompleted) return;
    pending.complete(port);
  }

  @override
  Future<ShellBinding> register(String symbolicName) async {
    // The same guard as the real transport, so a test against the fake
    // catches a double registration the real one would refuse.
    final String? existing = _registeredName;
    if (existing != null) {
      throw StateError(
        'already registered as "$existing", cannot register "$symbolicName": '
        'one transport serves one bundle',
      );
    }
    calls.add(ShellCall('init', symbolicName));
    if (unavailable) {
      throw ShellUnavailableException('no dev.osgi/bridge (fake)');
    }
    final String? reject = rejectRegister;
    if (reject != null) {
      throw ShellRejectedException(reject, 'rejected by fake');
    }

    final Completer<SendPort> port = Completer<SendPort>();
    _frameworkPort = port;
    _registeredName = symbolicName;
    // Same reason as the real transport: a bundle that never awaits the port is
    // normal, and an unawaited error would escape into the test's zone and fail
    // an unrelated expectation.
    unawaited(port.future.then<void>((_) {}, onError: (Object _) {}));

    final SendPort? auto = autoFrameworkPort;
    if (auto != null) port.complete(auto);
    if (!_registered.isCompleted) _registered.complete();

    return ShellBinding(symbolicName: symbolicName, frameworkPort: port.future);
  }

  @override
  Future<void> reportActive(String symbolicName) async {
    calls.add(ShellCall('active', symbolicName));
    if (unavailable) {
      throw ShellUnavailableException('no dev.osgi/bridge (fake)');
    }
    final String? reject = rejectActive;
    if (reject != null) {
      throw ShellRejectedException(reject, 'rejected by fake');
    }
  }

  @override
  Future<void> reportStopped(String symbolicName) async {
    calls.add(ShellCall('stopped', symbolicName));
    if (unavailable) {
      throw ShellUnavailableException('no dev.osgi/bridge (fake)');
    }
  }

  @override
  Future<void> unregister(String symbolicName) async {
    calls.add(ShellCall('shutdown', symbolicName));
    _registeredName = null;
    final Completer<SendPort>? pending = _frameworkPort;
    _frameworkPort = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(
        ShellUnavailableException('torn down before port arrived'),
      );
    }
  }

  /// The method names in order, which is usually what an assertion wants.
  List<String> get methods =>
      calls.map((ShellCall c) => c.method).toList(growable: false);

  /// Whether this bundle ever declared itself ACTIVE. A critical bundle that
  /// never does is one that would have burned its startup deadline.
  bool reportedActive(String symbolicName) =>
      calls.contains(ShellCall('active', symbolicName));
}
