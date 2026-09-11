/// Test doubles for OSGi bundles.
///
/// A bundle's activator is ordinary Dart, and most of what can go wrong in one
/// -- never reporting ACTIVE, assuming the framework port is already in hand,
/// mishandling a rejected handshake -- needs no shell, no engine and no display
/// to reproduce. This package exists so those cases are reachable from
/// `dart test` rather than only from a rig with two monitors attached.
library;

export 'src/fake_shell_transport.dart';
