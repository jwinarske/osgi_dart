import 'bundle_context.dart';
import 'bundle_state.dart';

/// Represents an installed OSGi bundle within the framework.
abstract class Bundle {
  /// The unique symbolic name of this bundle (e.g. "com.ivi.instrument-cluster").
  String get symbolicName;

  /// The semantic version string of this bundle.
  String get version;

  /// The current lifecycle state of this bundle.
  BundleState get state;

  /// The manifest headers from bundle.yaml.
  Map<String, Object> get headers;

  /// The [BundleContext] for this bundle, or `null` if not yet started.
  BundleContext? get bundleContext;

  /// The startup priority declared in the bundle manifest.
  BundlePriority get priority;
}

/// Startup priority levels for bundle ordering.
enum BundlePriority { critical, normal, background }
