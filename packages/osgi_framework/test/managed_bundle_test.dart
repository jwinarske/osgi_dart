import 'dart:async';

import 'package:osgi_framework/osgi_framework.dart';
import 'package:osgi_test/osgi_test.dart';
import 'package:test/test.dart';

/// An activator whose every step a test can drive.
class _Activator implements BundleActivator {
  _Activator({this.onStart, this.startError, this.stopError});

  final Future<void> Function(BundleContext context)? onStart;
  final Object? startError;
  final Object? stopError;

  BundleContext? startedWith;
  bool stopCalled = false;

  @override
  Future<void> start(BundleContext context) async {
    startedWith = context;
    await onStart?.call(context);
    if (startError != null) throw startError!;
  }

  @override
  Future<void> stop(BundleContext context) async {
    stopCalled = true;
    if (stopError != null) throw stopError!;
  }
}

void main() {
  late FakeShellTransport shell;
  late ServiceRegistry registry;

  setUp(() {
    shell = FakeShellTransport(autoFrameworkPort: 7);
    registry = ServiceRegistry();
  });

  ManagedBundle bundleOf(
    BundleActivator activator, {
    String name = 'com.ivi.cluster',
  }) => ManagedBundle(
    symbolicName: name,
    activator: activator,
    transport: shell,
    registry: registry,
  );

  group('start', () {
    test('registers, runs the activator, then reports ACTIVE', () async {
      final _Activator activator = _Activator();
      final ManagedBundle bundle = bundleOf(activator);
      final Future<List<BundleState>> states = bundle.states.take(2).toList();

      await bundle.start();

      expect(shell.methods, <String>['init', 'active']);
      expect(bundle.state, BundleState.active);
      expect(await states, <BundleState>[
        BundleState.starting,
        BundleState.active,
      ]);
      expect(activator.startedWith?.symbolicName, 'com.ivi.cluster');
      await bundle.dispose();
    });

    test('reports ACTIVE only after the activator returns', () async {
      // The whole contract: ACTIVE releases a critical bundle's startup wait,
      // so reporting it early would release the wait on a bundle that is not
      // ready.
      final Completer<void> finishStart = Completer<void>();
      final ManagedBundle bundle = bundleOf(
        _Activator(onStart: (_) => finishStart.future),
      );

      final Future<void> starting = bundle.start();
      await shell.registered;
      await pumpEventQueue();

      expect(shell.methods, <String>['init']);
      expect(bundle.state, BundleState.starting);

      finishStart.complete();
      await starting;

      expect(shell.methods, <String>['init', 'active']);
      await bundle.dispose();
    });

    test(
      'the framework port is there once registered, and not before',
      () async {
        final ManagedBundle bundle = bundleOf(_Activator());
        expect(bundle.frameworkPort, isNull);

        await bundle.start();

        expect(await bundle.frameworkPort, 7);
        await bundle.dispose();
      },
    );

    test('starting twice is a programming error', () async {
      final ManagedBundle bundle = bundleOf(_Activator());
      await bundle.start();

      await expectLater(bundle.start(), throwsStateError);
      await bundle.dispose();
    });
  });

  group('a failed start', () {
    test('never reports ACTIVE and unwinds to resolved', () async {
      final _Activator activator = _Activator(
        startError: StateError('no display'),
      );
      final ManagedBundle bundle = bundleOf(activator);
      final Future<List<BundleState>> states = bundle.states.take(3).toList();

      await expectLater(bundle.start(), throwsStateError);

      expect(shell.reportedActive('com.ivi.cluster'), isFalse);
      expect(bundle.state, BundleState.resolved);
      // A failed start unwinds the way a healthy stop does.
      expect(await states, <BundleState>[
        BundleState.starting,
        BundleState.stopping,
        BundleState.resolved,
      ]);
      expect(
        activator.stopCalled,
        isTrue,
        reason: 'stop() runs so a partial start can release what it took',
      );
      await bundle.dispose();
    });

    test(
      'releases services the activator published before it failed',
      () async {
        final ManagedBundle bundle = bundleOf(
          _Activator(
            onStart: (BundleContext ctx) async {
              await ctx.registerService('Nav', 'half-built');
            },
            startError: StateError('failed after registering'),
          ),
        );

        await expectLater(bundle.start(), throwsStateError);

        expect(
          registry.getService('Nav'),
          isNull,
          reason: 'a failed start must not leave a service nothing owns',
        );
        await bundle.dispose();
      },
    );

    test('leaves the bundle able to start again', () async {
      // Restart is a normal operation, which is why STOPPING returns to
      // RESOLVED rather than going on to UNINSTALLED.
      bool fail = true;
      final ManagedBundle bundle = bundleOf(
        _Activator(
          onStart: (_) async {
            if (fail) throw StateError('first attempt fails');
          },
        ),
      );

      await expectLater(bundle.start(), throwsStateError);
      fail = false;
      await bundle.start();

      expect(bundle.state, BundleState.active);
      expect(shell.methods, <String>['init', 'shutdown', 'init', 'active']);
      await bundle.dispose();
    });

    test('surfaces the start error even when stop() also fails', () async {
      // Otherwise the teardown's own failure buries the reason the bundle
      // never came up, which is the one thing worth reporting.
      final ManagedBundle bundle = bundleOf(
        _Activator(
          startError: ArgumentError('the real cause'),
          stopError: StateError('teardown also failed'),
        ),
      );

      await expectLater(bundle.start(), throwsArgumentError);

      expect(bundle.state, BundleState.resolved);
      await bundle.dispose();
    });

    test('a rejected registration surfaces and reports nothing', () async {
      shell = FakeShellTransport(rejectRegister: 'rejected');
      final ManagedBundle bundle = bundleOf(_Activator());

      await expectLater(bundle.start(), throwsA(isA<ShellRejectedException>()));

      expect(shell.methods, <String>['init', 'shutdown']);
      expect(bundle.state, BundleState.resolved);
      await bundle.dispose();
    });

    test('a shell built without OSGi surfaces as unavailable', () async {
      shell = FakeShellTransport(unavailable: true);
      final ManagedBundle bundle = bundleOf(_Activator());

      await expectLater(
        bundle.start(),
        throwsA(isA<ShellUnavailableException>()),
      );
      expect(bundle.state, BundleState.resolved);
      await bundle.dispose();
    });
  });

  group('stop', () {
    test(
      'runs the activator, reports STOPPED, and releases the name',
      () async {
        final _Activator activator = _Activator();
        final ManagedBundle bundle = bundleOf(activator);
        await bundle.start();

        await bundle.stop();

        expect(activator.stopCalled, isTrue);
        expect(shell.methods, <String>[
          'init',
          'active',
          'stopped',
          'shutdown',
        ]);
        expect(bundle.state, BundleState.resolved);
        await bundle.dispose();
      },
    );

    test('unregisters services the activator left behind', () async {
      final ManagedBundle bundle = bundleOf(
        _Activator(
          onStart: (BundleContext ctx) async {
            await ctx.registerService('Nav', 'nav-impl');
          },
        ),
      );
      await bundle.start();
      expect(registry.getService('Nav'), 'nav-impl');

      await bundle.stop();

      expect(registry.getService('Nav'), isNull);
      await bundle.dispose();
    });

    test('closes trackers the activator opened', () async {
      late ServiceTracker tracker;
      final ManagedBundle bundle = bundleOf(
        _Activator(
          onStart: (BundleContext ctx) async {
            tracker = ctx.trackService('Nav');
            await tracker.open();
          },
        ),
      );
      await bundle.start();

      await bundle.stop();

      // A closed tracker's stream is done; a still-open one would keep
      // delivering into a bundle that has stopped.
      expect(await tracker.addingService.isEmpty, isTrue);
      await bundle.dispose();
    });

    test('the context is unusable afterwards', () async {
      final _Activator activator = _Activator();
      final ManagedBundle bundle = bundleOf(activator);
      await bundle.start();
      final BundleContext context = activator.startedWith!;

      await bundle.stop();

      await expectLater(
        context.registerService('Nav', 'late'),
        throwsStateError,
      );
      expect(() => context.trackService('Nav'), throwsStateError);
      await bundle.dispose();
    });

    test('an activator that throws still leaves a clean bundle', () async {
      final ManagedBundle bundle = bundleOf(
        _Activator(
          onStart: (BundleContext ctx) async {
            await ctx.registerService('Nav', 'nav-impl');
          },
          stopError: StateError('stop failed'),
        ),
      );
      await bundle.start();

      // The error surfaces...
      await expectLater(bundle.stop(), throwsStateError);

      // ...but the teardown still finished.
      expect(registry.getService('Nav'), isNull);
      expect(bundle.state, BundleState.resolved);
      expect(shell.methods, <String>['init', 'active', 'stopped', 'shutdown']);
      await bundle.dispose();
    });

    test(
      'stopping a bundle that is not active is a programming error',
      () async {
        final ManagedBundle bundle = bundleOf(_Activator());

        await expectLater(bundle.stop(), throwsStateError);
        await bundle.dispose();
      },
    );
  });
}
