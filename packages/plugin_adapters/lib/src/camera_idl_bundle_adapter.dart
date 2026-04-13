import 'dart:async';

import 'package:dart_osgi_framework/dart_osgi_framework.dart';
import 'package:flutter/services.dart';

import 'texture_service.dart';

/// OSGi bundle adapter for the camera_idl plugin with DMA-BUF pipeline
/// and cam_infer_models inference integration.
///
/// Pipeline: camera → DMA-BUF → GPU memory → Vulkan compute inference →
/// inference results as const OSGi events.
///
/// Registers:
/// - `CameraService` with textureId for live camera preview
/// - Inference results posted via EventAdmin as const events
class CameraIdlBundleAdapter implements BundleActivator {
  static const serviceName = 'com.ivi.camera.CameraService';
  static const inferenceTopic = 'com/ivi/camera/INFERENCE_RESULT';

  static const _channel = MethodChannel('io.ivi-homescreen.camera_idl');

  ServiceRegistration<int>? _registration;
  int? _textureId;
  StreamSubscription<dynamic>? _inferenceEventSub;

  /// Camera device configuration.
  final Map<String, Object> cameraConfig;

  /// Inference model configuration for cam_infer_models.
  final Map<String, Object> inferenceConfig;

  CameraIdlBundleAdapter({
    this.cameraConfig = const {},
    this.inferenceConfig = const {},
  });

  @override
  Future<void> start(BundleContext ctx) async {
    _textureId = await _channel.invokeMethod<int>('openCamera', {
      ...cameraConfig,
      'inference': inferenceConfig,
    });
    if (_textureId == null) {
      throw StateError('camera_idl.openCamera returned null textureId');
    }

    _registration = ctx.registerService<int>(serviceName, _textureId!, {
      TextureServiceProperties.textureId: _textureId!,
      TextureServiceProperties.renderer: 'camera_dma_buf',
      TextureServiceProperties.format: 'nv12',
      'transport': 'dma_buf_gpu',
    });

    // Listen for inference results from the native plugin and post
    // as OSGi events via EventAdmin.
    final eventAdminRef = ctx.getServiceReference<EventAdmin>(
      EventAdmin.serviceName,
    );
    if (eventAdminRef != null) {
      final eventAdmin = ctx.getService(eventAdminRef);
      if (eventAdmin != null) {
        _inferenceEventSub =
            const EventChannel(
              'io.ivi-homescreen.camera_idl/inference',
            ).receiveBroadcastStream().listen((dynamic result) {
              if (result is Map) {
                eventAdmin.postEvent(
                  Event(inferenceTopic, Map<String, Object>.from(result)),
                );
              }
            });
      }
    }
  }

  @override
  Future<void> stop(BundleContext ctx) async {
    await _inferenceEventSub?.cancel();
    _inferenceEventSub = null;
    await _registration?.unregister();
    _registration = null;
    if (_textureId != null) {
      await _channel.invokeMethod<void>('closeCamera', _textureId);
      _textureId = null;
    }
  }
}
