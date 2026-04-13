import 'package:dart_osgi_api/dart_osgi_api.dart';

import '../manifest/bundle_manifest.dart';
import 'bundle_state_manager.dart';

/// Concrete [Bundle] implementation backed by a [BundleManifest] and
/// [BundleStateManager]. Created and owned by [BundleManager].
class ManagedBundle implements Bundle {
  ManagedBundle(this.manifest);

  final BundleManifest manifest;

  late final BundleStateManager stateManager = BundleStateManager(this);

  BundleContext? _bundleContext;

  @override
  String get symbolicName => manifest.symbolicName;

  @override
  String get version => manifest.version.toString();

  @override
  BundleState get state => stateManager.state;

  @override
  Map<String, Object> get headers => {
    'symbolicName': manifest.symbolicName,
    'version': manifest.version.toString(),
    'type': manifest.type.name,
    'activator': manifest.activator,
    if (manifest.flutterAsset != null) 'flutterAsset': manifest.flutterAsset!,
  };

  @override
  BundleContext? get bundleContext => _bundleContext;

  set bundleContext(BundleContext? ctx) => _bundleContext = ctx;

  @override
  BundlePriority get priority => manifest.startup.priority;
}
