import 'dart:isolate';

import 'package:dart_osgi_framework/dart_osgi_framework.dart';

/// Flutter-specific [BundleContext] for UI bundles running as separate
/// Flutter engine instances on ivi-homescreen.
///
/// Key design point: all Flutter engines share a single Dart VM, so
/// [SendPort] works cross-engine without platform channels. Platform
/// channels are only needed for C++ plugin calls (GStreamer, Filament,
/// Wayland surface ops).
///
/// This context extends [IsolateBundleContext] with Flutter-specific
/// surface and texture management.
class FlutterBundleContext implements BundleContext {
  FlutterBundleContext({required this.inner, int? textureId, int? surfaceId})
    : _textureId = textureId,
      _surfaceId = surfaceId;

  /// The underlying framework bundle context.
  final IsolateBundleContext inner;

  int? _textureId;
  int? _surfaceId;
  bool _surfaceVisible = false;

  /// The Flutter external texture ID for this bundle's surface, if assigned.
  int? get textureId => _textureId;

  /// The comp_surf surface ID managed by ivi-homescreen.
  int? get surfaceId => _surfaceId;

  /// Whether this bundle's surface is currently visible.
  bool get isSurfaceVisible => _surfaceVisible;

  /// The [SendPort] to the framework isolate.
  SendPort get frameworkPort => inner.frameworkPort;

  // ── Surface lifecycle ─────────────────────────────────────────────

  /// Called by the framework when the bundle transitions to ACTIVE.
  /// Maps to comp_surf.show() in the C++ host.
  void showSurface() {
    _surfaceVisible = true;
  }

  /// Called by the framework when the bundle transitions to STOPPING.
  /// Maps to comp_surf.hide() in the C++ host.
  void hideSurface() {
    _surfaceVisible = false;
  }

  /// Set the texture ID assigned by the C++ engine loader.
  void setTextureId(int id) => _textureId = id;

  /// Set the surface ID assigned by the C++ compositor.
  void setSurfaceId(int id) => _surfaceId = id;

  // ── Service convenience for texture sharing ───────────────────────

  /// Register a texture service so other bundles can reference this
  /// bundle's rendered output via [Texture] widget.
  ServiceRegistration<int> registerTextureService(
    String serviceName,
    int textureId, {
    Map<String, Object>? extraProperties,
  }) {
    return inner.registerService<int>(serviceName, textureId, {
      ...?extraProperties,
      'textureId': textureId,
      'renderer': 'flutter_engine',
    });
  }

  // ── Delegated BundleContext methods ────────────────────────────────

  @override
  ServiceRegistration<T> registerService<T>(
    String className,
    T service,
    Map<String, Object>? properties,
  ) => inner.registerService<T>(className, service, properties);

  @override
  ServiceReference<T>? getServiceReference<T>(String className) =>
      inner.getServiceReference<T>(className);

  @override
  List<ServiceReference<T>> getServiceReferences<T>(
    String className,
    String? filter,
  ) => inner.getServiceReferences<T>(className, filter);

  @override
  T? getService<T>(ServiceReference<T> reference) =>
      inner.getService<T>(reference);

  @override
  bool ungetService<T>(ServiceReference<T> reference) =>
      inner.ungetService<T>(reference);

  @override
  ServiceTracker<T> trackService<T>(String className, {String? filter}) =>
      inner.trackService<T>(className, filter: filter);

  @override
  Bundle get bundle => inner.bundle;

  @override
  void addBundleListener(void Function(BundleEvent event) listener) =>
      inner.addBundleListener(listener);

  @override
  void removeBundleListener(void Function(BundleEvent event) listener) =>
      inner.removeBundleListener(listener);

  @override
  void addServiceListener(
    void Function(ServiceEvent event) listener, {
    String? filter,
  }) => inner.addServiceListener(listener, filter: filter);

  @override
  void removeServiceListener(void Function(ServiceEvent event) listener) =>
      inner.removeServiceListener(listener);

  /// Dispose this context and hide the surface.
  Future<void> dispose() async {
    hideSurface();
    await inner.dispose();
  }
}
