import 'bundle_context.dart';

/// Entry point for bundle lifecycle.
///
/// Each bundle declares an activator in its bundle.yaml manifest.
/// The framework calls [start] when the bundle transitions to STARTING
/// and [stop] when it transitions to STOPPING.
abstract class BundleActivator {
  Future<void> start(BundleContext context);
  Future<void> stop(BundleContext context);
}
