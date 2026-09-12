/// A Dart-native OSGi framework.
///
/// Runs in the framework isolate. Pure Dart by design -- the framework
/// arbitrates between bundles and never draws, so nothing here depends on
/// Flutter.
library;

// The registry hands back osgi_api types, so a caller that has this package
// has everything it needs to use what this package returns.
export 'package:osgi_api/osgi_api.dart';

export 'src/event.dart';
export 'src/event_admin.dart';
export 'src/isolate/framework_server.dart';
export 'src/isolate/protocol.dart';
export 'src/isolate/remote_bundle_context.dart';
export 'src/ldap_filter.dart';
export 'src/managed_bundle.dart';
export 'src/service_registry.dart';
export 'src/topic_filter.dart';
