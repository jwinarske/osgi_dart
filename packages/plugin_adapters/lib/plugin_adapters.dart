/// OSGi bundle adapters for ivi-homescreen-plugins.
///
/// Wraps filament_view, nav_render_view, GStreamer, camera_idl, and
/// WebView (CEF) into the OSGi bundle lifecycle. All GPU-texture plugins
/// register textureId as a service property — UI bundles reference via
/// `Texture(textureId:)`.
library;

export 'src/camera_idl_bundle_adapter.dart';
export 'src/comp_surf_lifecycle_manager.dart';
export 'src/filament_view_bundle_adapter.dart';
export 'src/gstreamer_bundle_adapter.dart';
export 'src/nav_render_view_bundle_adapter.dart';
export 'src/texture_service.dart';
export 'src/webview_bundle_adapter.dart';
