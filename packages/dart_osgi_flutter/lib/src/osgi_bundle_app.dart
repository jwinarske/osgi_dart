import 'package:dart_osgi_api/dart_osgi_api.dart';
import 'package:flutter/widgets.dart';

import 'flutter_bundle_context.dart';

/// Convenience widget that wraps a Flutter bundle's root widget with
/// OSGi lifecycle integration.
///
/// Usage in a bundle's main widget:
/// ```dart
/// class MyBundleApp extends StatelessWidget {
///   @override
///   Widget build(BuildContext context) {
///     return OsgiBundleApp(
///       bundleContext: myFlutterBundleContext,
///       child: MaterialApp(home: MyHomePage()),
///     );
///   }
/// }
/// ```
///
/// [OsgiBundleApp] provides the [FlutterBundleContext] to descendants
/// via [OsgiBundleApp.of(context)] and manages surface visibility
/// with the app lifecycle.
class OsgiBundleApp extends StatefulWidget {
  const OsgiBundleApp({
    super.key,
    required this.bundleContext,
    required this.child,
  });

  final FlutterBundleContext bundleContext;
  final Widget child;

  /// Retrieve the [FlutterBundleContext] from the nearest ancestor
  /// [OsgiBundleApp].
  static FlutterBundleContext of(BuildContext context) {
    final state = context.findAncestorStateOfType<_OsgiBundleAppState>();
    if (state == null) {
      throw FlutterError(
        'OsgiBundleApp.of() called with a context that does not contain '
        'an OsgiBundleApp.\nNo OsgiBundleApp ancestor could be found.',
      );
    }
    return state.widget.bundleContext;
  }

  /// Retrieve the [FlutterBundleContext] if available, or `null`.
  static FlutterBundleContext? maybeOf(BuildContext context) {
    final state = context.findAncestorStateOfType<_OsgiBundleAppState>();
    return state?.widget.bundleContext;
  }

  @override
  State<OsgiBundleApp> createState() => _OsgiBundleAppState();
}

class _OsgiBundleAppState extends State<OsgiBundleApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Surface is shown when the bundle becomes ACTIVE.
    widget.bundleContext.showSurface();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.bundleContext.hideSurface();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        widget.bundleContext.showSurface();
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        widget.bundleContext.hideSurface();
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// An [InheritedWidget] that provides convenient access to the
/// [FlutterBundleContext] for service lookup and registration
/// within the widget tree.
class OsgiBundleScope extends InheritedWidget {
  const OsgiBundleScope({
    super.key,
    required this.bundleContext,
    required super.child,
  });

  final FlutterBundleContext bundleContext;

  static FlutterBundleContext of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<OsgiBundleScope>();
    if (scope == null) {
      throw FlutterError(
        'OsgiBundleScope.of() called without an OsgiBundleScope ancestor.',
      );
    }
    return scope.bundleContext;
  }

  @override
  bool updateShouldNotify(OsgiBundleScope oldWidget) =>
      bundleContext != oldWidget.bundleContext;
}

/// Mixin for [State] classes that need to access the [FlutterBundleContext]
/// and react to service availability changes.
mixin OsgiBundleStateMixin<T extends StatefulWidget> on State<T> {
  FlutterBundleContext get bundleContext => OsgiBundleApp.of(context);

  /// Track a service and rebuild when it becomes available or is removed.
  ServiceTracker<S> trackService<S>(String className, {String? filter}) {
    return bundleContext.trackService<S>(className, filter: filter);
  }
}
