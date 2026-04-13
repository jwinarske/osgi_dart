/// Flutter-specific OSGi helpers.
///
/// Provides [FlutterBundleContext] and [OsgiBundleApp] for Flutter
/// bundles running as engine instances on ivi-homescreen.
///
/// Key design point: all Flutter engines share a single Dart VM,
/// so SendPort works cross-engine without platform channels.
library;

export 'package:dart_osgi_api/dart_osgi_api.dart';

export 'src/flutter_bundle_context.dart';
export 'src/osgi_bundle_app.dart';
