import 'dart:async';
import 'dart:isolate';

import 'package:osgi_api/osgi_api.dart';

import 'isolate/remote_bundle_context.dart';
import 'managed_bundle.dart';
import 'service_registry.dart';

/// Where a bundle's [BundleContext] comes from, and what closing it means.
///
/// A bundle that shares an isolate with the registry gets a context that calls
/// it directly; one in its own isolate gets a context that sends messages. The
/// lifecycle is identical either way, which is the point of this seam:
/// [ManagedBundle] drives the same sequence and never learns which it has.
abstract interface class BundleScope {
  /// Build the context for [bundle], ready for its activator to use.
  Future<BundleContext> open(ManagedBundle bundle);

  /// Release everything the bundle took through that context.
  ///
  /// Called on every teardown, including a start that failed partway, so it
  /// must not assume [open] finished.
  Future<void> close();
}

/// A context backed by a registry in this isolate.
class RegistryScope implements BundleScope {
  RegistryScope(this.registry);

  final ServiceRegistry registry;

  _RegistryContext? _context;

  @override
  Future<BundleContext> open(ManagedBundle bundle) async =>
      _context = _RegistryContext(bundle, registry);

  @override
  Future<void> close() async {
    await _context?.release();
    _context = null;
  }
}

/// A context built from the port the shell hands over during the handshake.
///
/// This is the shell-spawned path. The bundle cannot build its context up
/// front, because the framework port arrives *during* start: the shell posts it
/// after `init`, and the framework isolate may not even be up yet. [open] runs
/// after [ShellTransport.register] has returned, so the port is either already
/// in hand or on its way, and awaiting it here is the natural place to block.
///
/// A bundle that waits on this is a bundle that needs its peers. One with no
/// peers should not use this scope at all -- the port may arrive long after
/// registration, and a critical bundle's startup deadline is running the whole
/// time.
class ShellFrameworkScope implements BundleScope {
  ShellFrameworkScope({this.requestTimeout});

  /// Passed through to the [RemoteBundleContext] this builds.
  final Duration? requestTimeout;

  RemoteBundleContext? _context;

  @override
  Future<BundleContext> open(ManagedBundle bundle) async {
    final Future<SendPort>? delivered = bundle.frameworkPort;
    if (delivered == null) {
      throw StateError(
        'no framework port for "${bundle.symbolicName}": the shell delivers it '
        'during registration, so this scope can only open after register()',
      );
    }
    final RemoteBundleContext context = RemoteBundleContext(
      symbolicName: bundle.symbolicName,
      framework: await delivered,
      requestTimeout: requestTimeout,
    );
    _context = context;
    await context.attach();
    return context;
  }

  @override
  Future<void> close() async {
    await _context?.detach();
    _context = null;
  }
}

/// A context backed by a `FrameworkServer` in another isolate.
///
/// Attaching announces the bundle so other bundles can find and reach it;
/// detaching releases its services, its trackers, and its routing entry.
class RemoteScope implements BundleScope {
  RemoteScope(this.context);

  final RemoteBundleContext context;

  @override
  Future<BundleContext> open(ManagedBundle bundle) async {
    await context.attach();
    return context;
  }

  @override
  Future<void> close() => context.detach();
}

/// The bundle's view of a registry in the same isolate.
///
/// Everything published through it is released when the bundle stops, so an
/// activator's `stop()` does not have to be exhaustive to leave the registry
/// clean -- and a `stop()` that runs after a partial start does not need to
/// know how far the start got.
class _RegistryContext implements BundleContext {
  _RegistryContext(this._bundle, this._registry);

  final ManagedBundle _bundle;
  final ServiceRegistry _registry;

  final List<ServiceRegistration> _registrations = <ServiceRegistration>[];
  final List<ServiceTracker> _trackers = <ServiceTracker>[];

  bool _released = false;

  @override
  String get symbolicName => _bundle.symbolicName;

  @override
  BundleState get state => _bundle.state;

  @override
  Future<ServiceRegistration> registerService(
    String interfaceName,
    Object? service, [
    Map<String, Object?> properties = const <String, Object?>{},
  ]) async {
    _requireLive('register "$interfaceName"');
    final ServiceRegistration registration = _registry.register(
      interfaceName,
      service,
      properties,
    );
    _registrations.add(registration);
    return registration;
  }

  @override
  ServiceTracker trackService(String interfaceName, {String? filter}) {
    _requireLive('track "$interfaceName"');
    final ServiceTracker tracker = _registry.track(
      interfaceName,
      filter: filter,
    );
    _trackers.add(tracker);
    return tracker;
  }

  /// Drop everything this bundle published or watched.
  Future<void> release() async {
    if (_released) return;
    _released = true;
    for (final ServiceRegistration registration in _registrations) {
      // Idempotent, so an activator that already unregistered is fine.
      await registration.unregister();
    }
    _registrations.clear();
    for (final ServiceTracker tracker in _trackers) {
      await tracker.close();
    }
    _trackers.clear();
  }

  void _requireLive(String what) {
    if (_released) {
      throw StateError(
        'cannot $what: bundle "${_bundle.symbolicName}" has stopped. '
        'An asynchronous callback that outlived the activator is the usual '
        'cause, and publishing from it would leave a service nothing owns.',
      );
    }
  }
}
