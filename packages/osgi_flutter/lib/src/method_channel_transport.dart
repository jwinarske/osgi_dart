import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:osgi_api/osgi_api.dart';

/// The `dev.osgi/bridge` channel, as implemented by `OsgiBridgePlugin` in the
/// shell.
const MethodChannel _bridge = MethodChannel('dev.osgi/bridge');

/// [ShellTransport] over the shell's `dev.osgi/bridge` MethodChannel.
///
/// This is the default because it is what runs today: the handshake below is
/// the one validated on hardware, against a shell that needs no changes to
/// accept it. Its costs -- a UI binding even for headless bundles, and an
/// ACTIVE report marshalled through the platform thread during the busiest part
/// of start-up -- are documented on [ShellTransport] and are the reason that
/// interface exists.
class MethodChannelShellTransport implements ShellTransport {
  /// Kept for the isolate's lifetime rather than per-call.
  ///
  /// The shell posts the framework isolate's port here, and it may do so at any
  /// point after `init` -- the framework isolate and this bundle start
  /// concurrently, so the port can arrive before `init` returns or long after.
  /// Closing this port between calls would strand that message with no error
  /// anywhere.
  ReceivePort? _fromShell;

  Completer<int>? _frameworkPort;

  StreamSubscription<dynamic>? _subscription;

  String? _registeredName;

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
    final Completer<int> frameworkPort = Completer<int>();
    _fromShell = port;
    _frameworkPort = frameworkPort;
    _registeredName = symbolicName;

    // A bundle with no interest in the framework port is normal -- plenty never
    // talk to another bundle. Without a listener here, the completeError in
    // _teardown would surface as an unhandled async error and, depending on the
    // zone, take the isolate down during what is usually already a failure
    // path. Callers that do await the future still see the error.
    unawaited(frameworkPort.future.then<void>((_) {}, onError: (Object _) {}));

    _subscription = port.listen((dynamic message) {
      // Arrives as a bare int: the shell sends it with Dart_PostCObject_DL
      // carrying an int64. Everything after this point is SendPort traffic
      // between isolates, which never touches the platform thread.
      if (message is int && !frameworkPort.isCompleted) {
        frameworkPort.complete(message);
      }
    });

    try {
      await _bridge.invokeMethod<bool>('init', <String, dynamic>{
        'role': 'bundle',
        'symbolic_name': symbolicName,
        // The two things native code cannot obtain by itself: the symbol table
        // it binds Dart_PostCObject_DL from, and a port it can post to. Every
        // isolate sends the first because any of them may be the one to arrive
        // first; the shell makes all but the first a no-op.
        'dl_data': NativeApi.initializeApiDLData.address,
        'port': port.sendPort.nativePort,
      });
    } on MissingPluginException catch (e) {
      await _teardown();
      throw ShellUnavailableException(
        'no dev.osgi/bridge channel: ${e.message ?? 'shell built without OSGi?'}',
      );
    } on PlatformException catch (e) {
      await _teardown();
      throw ShellRejectedException(e.code, e.message ?? '');
    }

    return ShellBinding(
      symbolicName: symbolicName,
      frameworkPort: frameworkPort.future,
    );
  }

  @override
  Future<void> reportActive(String symbolicName) =>
      _report('active', symbolicName);

  @override
  Future<void> reportStopped(String symbolicName) =>
      _report('stopped', symbolicName);

  @override
  Future<void> unregister(String symbolicName) async {
    try {
      await _bridge.invokeMethod<bool>('shutdown', <String, dynamic>{
        'symbolic_name': symbolicName,
      });
    } on MissingPluginException {
      // Nothing to release: the shell was never there. Not worth raising during
      // teardown, which is often already running because something else failed.
    } on PlatformException {
      // Likewise -- a shell that has forgotten this bundle is the state we were
      // asking for.
    } finally {
      await _teardown();
    }
  }

  Future<void> _report(String method, String symbolicName) async {
    try {
      await _bridge.invokeMethod<bool>(method, <String, dynamic>{
        'symbolic_name': symbolicName,
      });
    } on MissingPluginException catch (e) {
      throw ShellUnavailableException(
        'no dev.osgi/bridge channel: ${e.message ?? ''}',
      );
    } on PlatformException catch (e) {
      // `rejected` here means no `init` was made under this name. It does not
      // catch a config typo: a name matching no [[osgi.bundles]] entry is
      // accepted, and the shell ignores its reports.
      throw ShellRejectedException(e.code, e.message ?? '');
    }
  }

  Future<void> _teardown() async {
    await _subscription?.cancel();
    _subscription = null;
    _fromShell?.close();
    _fromShell = null;
    _registeredName = null;
    final Completer<int>? pending = _frameworkPort;
    _frameworkPort = null;
    if (pending != null && !pending.isCompleted) {
      // Whoever is awaiting the port needs to learn it is never coming, rather
      // than waiting on it for the life of the process.
      pending.completeError(
        ShellUnavailableException('registration torn down before port arrived'),
      );
    }
  }
}
