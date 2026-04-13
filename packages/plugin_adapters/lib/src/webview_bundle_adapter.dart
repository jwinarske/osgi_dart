import 'dart:async';

import 'package:dart_osgi_framework/dart_osgi_framework.dart';
import 'package:flutter/services.dart';

import 'texture_service.dart';

/// OSGi bundle adapter for the WebView (CEF) plugin.
///
/// Ties CEF surface lifecycle to the OSGi bundle state:
/// - Surface created on bundle STARTING → ACTIVE
/// - Surface destroyed on bundle STOPPING
///
/// Registers a `WebViewService` with the texture ID and URL/navigation
/// control methods.
class WebViewBundleAdapter implements BundleActivator {
  static const serviceName = 'com.ivi.webview.WebViewService';

  static const _channel = MethodChannel('io.ivi-homescreen.webview_cef');

  ServiceRegistration<WebViewService>? _registration;
  int? _textureId;

  /// Initial URL to load.
  final String initialUrl;

  /// CEF browser configuration.
  final Map<String, Object> browserConfig;

  WebViewBundleAdapter({
    required this.initialUrl,
    this.browserConfig = const {},
  });

  @override
  Future<void> start(BundleContext ctx) async {
    _textureId = await _channel.invokeMethod<int>('createBrowser', {
      'url': initialUrl,
      ...browserConfig,
    });
    if (_textureId == null) {
      throw StateError('webview_cef.createBrowser returned null textureId');
    }

    final service = WebViewService(textureId: _textureId!, channel: _channel);

    _registration = ctx.registerService<WebViewService>(serviceName, service, {
      TextureServiceProperties.textureId: _textureId!,
      TextureServiceProperties.renderer: 'cef',
      'url': initialUrl,
    });
  }

  @override
  Future<void> stop(BundleContext ctx) async {
    await _registration?.unregister();
    _registration = null;
    if (_textureId != null) {
      await _channel.invokeMethod<void>('destroyBrowser', _textureId);
      _textureId = null;
    }
  }
}

/// Service interface for WebView navigation control.
///
/// Other bundles can look this up to control the web view's URL,
/// navigation, and JavaScript execution.
class WebViewService {
  WebViewService({required this.textureId, required MethodChannel channel})
    : _channel = channel;

  final int textureId;
  final MethodChannel _channel;

  /// Navigate to a URL.
  Future<void> loadUrl(String url) =>
      _channel.invokeMethod<void>('loadUrl', {'id': textureId, 'url': url});

  /// Go back in browser history.
  Future<void> goBack() =>
      _channel.invokeMethod<void>('goBack', {'id': textureId});

  /// Go forward in browser history.
  Future<void> goForward() =>
      _channel.invokeMethod<void>('goForward', {'id': textureId});

  /// Reload the current page.
  Future<void> reload() =>
      _channel.invokeMethod<void>('reload', {'id': textureId});

  /// Execute JavaScript in the browser context.
  Future<String?> executeJavaScript(String script) =>
      _channel.invokeMethod<String>('executeJavaScript', {
        'id': textureId,
        'script': script,
      });
}
