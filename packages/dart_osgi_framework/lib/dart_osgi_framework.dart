/// OSGi framework implementation.
///
/// Provides the concrete registry, event admin, isolate bus,
/// and bundle lifecycle management.
library;

export 'package:dart_osgi_api/dart_osgi_api.dart';

// Phase 1: Manifest & Lifecycle
export 'src/lifecycle/bundle_manager.dart';
export 'src/lifecycle/bundle_state_manager.dart'
    show BundleStateManager, InvalidTransitionException;
export 'src/lifecycle/managed_bundle.dart';
export 'src/manifest/bundle_manifest.dart';
export 'src/manifest/dependency_graph.dart';

// Phase 2: Service Registry
export 'src/registry/ldap_filter.dart';
export 'src/registry/service_registry.dart';
export 'src/registry/service_tracker_impl.dart';

// Phase 3: Framework Isolate & Bundle Context
export 'src/framework/dart_osgi_framework.dart';
export 'src/framework/framework_isolate.dart';
export 'src/framework/framework_message.dart';
export 'src/framework/isolate_bundle_context.dart';
export 'src/framework/isolate_bus.dart';

// Phase 4: Dart Bundle Loader
export 'src/loader/bundle_main.dart';
export 'src/loader/bundle_spawn_args.dart';
export 'src/loader/isolate_bundle_loader.dart';
