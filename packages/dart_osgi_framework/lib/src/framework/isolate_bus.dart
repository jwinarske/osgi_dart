import 'dart:isolate';

/// Routes messages between bundle isolates by symbolic name.
///
/// Each bundle registers its [SendPort] on startup. The bus delivers
/// messages by looking up the target bundle's port. The framework
/// isolate owns this bus — it routes port integers only, never large
/// objects (control plane / data plane split).
class IsolateBus {
  final _ports = <String, SendPort>{};

  /// Register a bundle's [SendPort] for receiving messages.
  void registerPort(String symbolicName, SendPort port) {
    _ports[symbolicName] = port;
  }

  /// Remove a bundle's port (on stop/uninstall).
  void unregisterPort(String symbolicName) {
    _ports.remove(symbolicName);
  }

  /// Send a message to a specific bundle by symbolic name.
  ///
  /// Returns `true` if the bundle was found and the message sent.
  bool sendTo(String symbolicName, Object message) {
    final port = _ports[symbolicName];
    if (port == null) return false;
    port.send(message);
    return true;
  }

  /// Broadcast a message to all registered bundles.
  void broadcast(Object message) {
    for (final port in _ports.values) {
      port.send(message);
    }
  }

  /// The [SendPort] for a specific bundle, or `null` if not registered.
  SendPort? getPort(String symbolicName) => _ports[symbolicName];

  /// All currently registered bundle symbolic names.
  Iterable<String> get registeredBundles => _ports.keys;

  void dispose() {
    _ports.clear();
  }
}
