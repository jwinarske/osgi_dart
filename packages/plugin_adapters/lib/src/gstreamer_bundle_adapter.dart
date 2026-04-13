import 'dart:async';

import 'package:dart_osgi_framework/dart_osgi_framework.dart';
import 'package:flutter/services.dart';

import 'texture_service.dart';

/// OSGi bundle adapter for the GStreamer EGL plugin.
///
/// Requires BUILD_PLUGIN_GSTREAMER_EGL=ON in the ivi-homescreen build.
///
/// Pipeline: VA-API decode → DMA-BUF fd → EGLImage → GL external texture
/// → 0 CPU copies.
///
/// Registers a `VideoTextureService` with the texture ID so UI bundles
/// can display video via `Texture(textureId:)`.
class GStreamerBundleAdapter implements BundleActivator {
  static const serviceName = 'com.ivi.media.VideoTextureService';

  static const _channel = MethodChannel('io.ivi-homescreen.gstreamer_egl');

  ServiceRegistration<int>? _registration;
  int? _textureId;

  /// GStreamer pipeline description or media URI.
  final String pipelineUri;

  GStreamerBundleAdapter({required this.pipelineUri});

  @override
  Future<void> start(BundleContext ctx) async {
    _textureId = await _channel.invokeMethod<int>('createPipeline', {
      'uri': pipelineUri,
    });
    if (_textureId == null) {
      throw StateError('gstreamer_egl.createPipeline returned null textureId');
    }

    _registration = ctx.registerService<int>(serviceName, _textureId!, {
      TextureServiceProperties.textureId: _textureId!,
      TextureServiceProperties.renderer: 'gstreamer_egl',
      TextureServiceProperties.format: 'nv12',
      'pipeline.uri': pipelineUri,
      'decode': 'vaapi',
      'transport': 'dma_buf_eglimage',
    });
  }

  @override
  Future<void> stop(BundleContext ctx) async {
    await _registration?.unregister();
    _registration = null;
    if (_textureId != null) {
      await _channel.invokeMethod<void>('destroyPipeline', _textureId);
      _textureId = null;
    }
  }
}
