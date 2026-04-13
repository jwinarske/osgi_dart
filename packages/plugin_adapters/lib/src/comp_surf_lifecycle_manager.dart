import 'dart:async';

import 'package:dart_osgi_framework/dart_osgi_framework.dart';
import 'package:dart_osgi_flutter/dart_osgi_flutter.dart';

/// Automatically maps bundle lifecycle transitions to comp_surf
/// surface show/hide operations.
///
/// Listens to the framework's bundle event stream and calls
/// [FlutterBundleContext.showSurface] on STARTED and
/// [FlutterBundleContext.hideSurface] on STOPPING for any
/// Flutter bundle that has a [FlutterBundleContext].
class CompSurfLifecycleManager {
  CompSurfLifecycleManager(this._framework);

  final DartOSGiFramework _framework;
  StreamSubscription<BundleEvent>? _subscription;

  /// Start listening for bundle lifecycle events.
  void start() {
    _subscription = _framework.bundleEvents.listen(_onBundleEvent);
  }

  /// Stop listening.
  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  void _onBundleEvent(BundleEvent event) {
    final ctx = event.bundle.bundleContext;
    if (ctx is! FlutterBundleContext) return;

    switch (event.type) {
      case BundleEventType.started:
        ctx.showSurface();
      case BundleEventType.stopping:
        ctx.hideSurface();
      default:
        break;
    }
  }
}
