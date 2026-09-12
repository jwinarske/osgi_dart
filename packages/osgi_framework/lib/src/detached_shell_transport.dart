import 'dart:async';
import 'dart:isolate';

import 'package:osgi_api/osgi_api.dart';

/// A [ShellTransport] for a bundle the shell does not know about.
///
/// The shell tracks engines it spawned from `[[osgi.bundles]]`. A pure-Dart
/// bundle that the framework spawned with `Isolate.spawn` has no engine, so
/// there is nothing for it to register with and nothing waiting on its ACTIVE
/// report. Its lifecycle is real, but it is the framework's business alone.
///
/// Every call succeeds and does nothing, so [ManagedBundle] needs no special
/// case. The one exception is [ShellBinding.frameworkPort]: a bundle that
/// awaits it is asking for something that does not exist on this path, so the
/// future completes with an error saying so rather than hanging forever.
class DetachedShellTransport implements ShellTransport {
  const DetachedShellTransport();

  @override
  Future<ShellBinding> register(String symbolicName) async {
    final Completer<SendPort> port = Completer<SendPort>();
    port.completeError(
      ShellUnavailableException(
        'bundle "$symbolicName" runs in a framework-spawned isolate, which the '
        'shell does not know about: there is no framework port to hand over. '
        'Bundles on this path reach the framework through the SendPort they '
        'were spawned with.',
      ),
    );
    // A bundle that never awaits the port is the normal case here, and an
    // unawaited error would otherwise escape into the enclosing zone.
    unawaited(port.future.then<void>((_) {}, onError: (Object _) {}));
    return ShellBinding(symbolicName: symbolicName, frameworkPort: port.future);
  }

  @override
  Future<void> reportActive(String symbolicName) async {}

  @override
  Future<void> reportStopped(String symbolicName) async {}

  @override
  Future<void> unregister(String symbolicName) async {}
}
