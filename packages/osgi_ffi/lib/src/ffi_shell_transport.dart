import 'dart:async';
import 'dart:isolate';

import 'package:osgi_api/osgi_api.dart';

import 'osgi_bindings.dart';

/// [ShellTransport] over the shell's `ihs_osgi_*` surface in `libihs_shared`.
///
/// Same handshake as the MethodChannel transport and the same lifecycle
/// contract -- what differs is that these calls are synchronous, need no UI
/// binding, and never touch the platform task runner.
///
/// One difference is visible in the code rather than the interface.
/// [ShellTransport] names a bundle on every call, but the C surface reports
/// through an opaque handle the shell mints at registration, because a name is
/// no barrier: every `ihs_*` symbol is reachable by anything in the process
/// that opens this library, and reporting ACTIVE releases a critical bundle's
/// startup wait. So this holds the handle and checks the name it is given
/// against the one it registered.
class FfiShellTransport implements ShellTransport {
  /// Talk to [bindings], or to the real library when none is given.
  ///
  /// Opening the library here rather than lazily means a shell without OSGi is
  /// reported at construction, where a bundle can still choose the other
  /// transport, instead of at the first report.
  FfiShellTransport({OsgiBindings? bindings})
    : _bindings = bindings ?? NativeOsgiBindings.open();

  final OsgiBindings _bindings;

  /// Kept for the isolate's lifetime rather than per-call: the shell posts the
  /// framework port at any point after registration, and closing this between
  /// calls would strand that message with no error anywhere.
  ReceivePort? _fromShell;

  Completer<SendPort>? _frameworkPort;
  StreamSubscription<dynamic>? _subscription;
  String? _registeredName;
  int _handle = 0;

  /// Whether the shell has an OSGi host installed. Advisory only.
  bool get available => _bindings.available;

  @override
  Future<ShellBinding> register(String symbolicName) async {
    final String? existing = _registeredName;
    if (existing != null) {
      throw StateError(
        'already registered as "$existing", cannot register "$symbolicName": '
        'one transport serves one bundle',
      );
    }

    final ReceivePort port = ReceivePort();
    final Completer<SendPort> frameworkPort = Completer<SendPort>();
    _fromShell = port;
    _frameworkPort = frameworkPort;

    // A bundle with no interest in the framework port is normal -- plenty never
    // talk to another bundle. Without a listener the completeError in
    // _teardown would surface as an unhandled async error. Callers that do
    // await the future still see it.
    unawaited(frameworkPort.future.then<void>((_) {}, onError: (Object _) {}));

    _subscription = port.listen((dynamic message) {
      // Arrives as a SendPort because the shell posts a Dart_CObject_kSendPort:
      // a port id would be useless here, since Dart cannot turn one back into a
      // SendPort. Anything else is ignored rather than fatal -- it leaves the
      // bundle without peers rather than crashing it.
      if (message is SendPort && !frameworkPort.isCompleted) {
        frameworkPort.complete(message);
      }
    });

    final OsgiRegistration registration = _bindings.registerBundle(
      replyTo: port.sendPort,
      symbolicName: symbolicName,
    );
    if (!registration.ok) {
      await _teardown();
      throw _asException(
        registration.status,
        'register "$symbolicName"',
        // A zero handle with an OK status would mean the shell accepted the
        // bundle and minted nothing to report through, which no later call
        // could recover from.
        handleMissing: registration.status == OsgiStatus.ok,
      );
    }

    _registeredName = symbolicName;
    _handle = registration.handle;

    return ShellBinding(
      symbolicName: symbolicName,
      frameworkPort: frameworkPort.future,
    );
  }

  @override
  Future<void> reportActive(String symbolicName) async =>
      _report(_bindings.reportActive, symbolicName, 'active');

  @override
  Future<void> reportStopped(String symbolicName) async =>
      _report(_bindings.reportStopped, symbolicName, 'stopped');

  @override
  Future<void> unregister(String symbolicName) async {
    final int handle = _handle;
    try {
      // Errors are swallowed on purpose: a shell that has already forgotten
      // this bundle is the state we were asking for, and teardown is usually
      // running because something else failed -- a second failure here would
      // bury the first.
      if (handle != 0) _bindings.unregister(handle);
    } finally {
      await _teardown();
    }
  }

  void _report(int Function(int) call, String symbolicName, String what) {
    final String? registered = _registeredName;
    if (registered == null || _handle == 0) {
      throw ShellRejectedException(
        'rejected',
        'no registration to report $what for "$symbolicName"',
      );
    }
    if (registered != symbolicName) {
      // A programming error rather than a shell refusal: this transport holds
      // one bundle's capability, and reporting under another name would be
      // asking it to speak for a bundle it is not.
      throw StateError(
        'registered as "$registered", cannot report $what for "$symbolicName"',
      );
    }
    final int status = call(_handle);
    if (status != OsgiStatus.ok) {
      throw _asException(status, 'report $what for "$symbolicName"');
    }
  }

  /// Map a status onto the exceptions [ShellTransport] documents, using the
  /// same codes the MethodChannel transport surfaces so a bundle's error
  /// handling does not have to know which transport it got.
  Object _asException(int status, String what, {bool handleMissing = false}) {
    if (handleMissing) {
      return ShellRejectedException(
        'rejected',
        'the shell accepted $what but minted no handle',
      );
    }
    switch (status) {
      case OsgiStatus.unavailable:
        return ShellUnavailableException(
          'no OSGi host in this process (shell built without ENABLE_OSGI?): '
          'could not $what',
        );
      case OsgiStatus.dartApi:
        return ShellRejectedException(
          'dart_api_unavailable',
          "the shell's vendored Dart DL headers do not match the running VM",
        );
      case OsgiStatus.invalid:
        return ShellRejectedException(
          'bad_arguments',
          'the shell refused the arguments to $what',
        );
      case OsgiStatus.rejected:
      default:
        return ShellRejectedException(
          'rejected',
          'the shell declined to $what',
        );
    }
  }

  Future<void> _teardown() async {
    await _subscription?.cancel();
    _subscription = null;
    _fromShell?.close();
    _fromShell = null;
    _registeredName = null;
    _handle = 0;
    final Completer<SendPort>? pending = _frameworkPort;
    _frameworkPort = null;
    if (pending != null && !pending.isCompleted) {
      // Whoever awaits the port needs to learn it is never coming, rather than
      // waiting on it for the life of the process.
      pending.completeError(
        ShellUnavailableException('registration torn down before port arrived'),
      );
    }
  }
}
