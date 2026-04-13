import 'dart:async';

import 'package:dart_osgi_framework/dart_osgi_framework.dart';
import 'package:flutter/services.dart';

import 'texture_service.dart';

/// OSGi bundle adapter for the nav_render_view plugin.
///
/// Registers an EGL texture ID + viewport as OSGi service properties.
/// The navigation renderer draws map tiles into an EGL surface that
/// is exposed as a Flutter external texture.
class NavRenderViewBundleAdapter implements BundleActivator {
  static const serviceName = 'com.ivi.navigation.RenderService';

  static const _channel = MethodChannel('io.ivi-homescreen.nav_render_view');

  ServiceRegistration<int>? _registration;
  int? _textureId;

  /// Initial viewport configuration.
  final Map<String, Object> viewportConfig;

  NavRenderViewBundleAdapter({this.viewportConfig = const {}});

  @override
  Future<void> start(BundleContext ctx) async {
    _textureId = await _channel.invokeMethod<int>('createView', viewportConfig);
    if (_textureId == null) {
      throw StateError('nav_render_view.createView returned null textureId');
    }

    _registration = ctx.registerService<int>(serviceName, _textureId!, {
      TextureServiceProperties.textureId: _textureId!,
      TextureServiceProperties.renderer: 'nav_render_egl',
      TextureServiceProperties.format: 'rgba8',
      ...viewportConfig,
    });
  }

  @override
  Future<void> stop(BundleContext ctx) async {
    await _registration?.unregister();
    _registration = null;
    if (_textureId != null) {
      await _channel.invokeMethod<void>('destroyView', _textureId);
      _textureId = null;
    }
  }
}
