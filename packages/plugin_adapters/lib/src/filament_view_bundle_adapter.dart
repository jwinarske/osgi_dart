import 'dart:async';

import 'package:dart_osgi_framework/dart_osgi_framework.dart';
import 'package:flutter/services.dart';

import 'texture_service.dart';

/// OSGi bundle adapter for the filament_view plugin.
///
/// Registers an EGL texture ID as an OSGi service. The rendering pipeline:
/// Vulkan swapchain → VK_KHR_external_memory → EGL → Flutter external texture.
///
/// UI bundles reference the texture via `Texture(textureId: textureId)`.
class FilamentViewBundleAdapter implements BundleActivator {
  static const serviceName = 'com.ivi.3d.SceneService';

  static const _channel = MethodChannel('io.ivi-homescreen.filament_view');

  ServiceRegistration<int>? _registration;
  int? _textureId;

  /// Scene configuration passed to the native plugin.
  final Map<String, Object> sceneConfig;

  FilamentViewBundleAdapter({this.sceneConfig = const {}});

  @override
  Future<void> start(BundleContext ctx) async {
    // Create the Filament scene via platform channel.
    // The native plugin creates the Vulkan swapchain, EGL interop,
    // and returns the Flutter external texture ID.
    _textureId = await _channel.invokeMethod<int>('createScene', sceneConfig);
    if (_textureId == null) {
      throw StateError('filament_view.createScene returned null textureId');
    }

    _registration = ctx.registerService<int>(serviceName, _textureId!, {
      TextureServiceProperties.textureId: _textureId!,
      TextureServiceProperties.renderer: 'filament_vulkan',
      TextureServiceProperties.format: 'rgba8',
      ...sceneConfig,
    });
  }

  @override
  Future<void> stop(BundleContext ctx) async {
    await _registration?.unregister();
    _registration = null;
    if (_textureId != null) {
      await _channel.invokeMethod<void>('destroyScene', _textureId);
      _textureId = null;
    }
  }
}
