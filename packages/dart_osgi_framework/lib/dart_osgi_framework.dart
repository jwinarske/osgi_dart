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
