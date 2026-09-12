import 'dart:isolate';

import 'package:osgi_framework/osgi_framework.dart';
import 'package:osgi_test/osgi_test.dart';
import 'package:test/test.dart';

/// Publishes one service through whatever context it is given -- here, one
/// built from the port the shell delivered during registration.
class _PublishingActivator implements BundleActivator {
  _PublishingActivator(this.service);

  final SendPort service;

  @override
  Future<void> start(BundleContext context) async {
    await context.registerService('CanBus', service, const <String, Object?>{
      'interface': 'can0',
    });
  }

  @override
  Future<void> stop(BundleContext context) async {}
}

void main() {
  late FrameworkServer server;
  late ReceivePort service;
  late RemoteBundleContext observer;

  setUp(() async {
    server = FrameworkServer()..start();
    service = ReceivePort('can.service');
    observer = RemoteBundleContext(
      symbolicName: 'com.ivi.observer',
      framework: server.port,
      requestTimeout: const Duration(seconds: 10),
    );
    await observer.attach();
  });

  tearDown(() async {
    await observer.detach();
    service.close();
    await server.stop();
  });

  ManagedBundle bundleOn(FakeShellTransport shell) => ManagedBundle(
    symbolicName: 'com.ivi.can',
    activator: _PublishingActivator(service.sendPort),
    transport: shell,
    scope: ShellFrameworkScope(requestTimeout: const Duration(seconds: 10)),
  );

  test('a shell-spawned bundle reaches the framework through the delivered '
      'port', () async {
    // The whole loop, which is what the SendPort change exists for: the shell
    // hands over a port during registration, ShellFrameworkScope builds the
    // framework client from it, and what the activator publishes is then
    // visible to every other bundle. A port id could not do any of this.
    final FakeShellTransport shell = FakeShellTransport(
      autoFrameworkPort: server.port,
    );
    final ManagedBundle bundle = bundleOn(shell);

    await bundle.start();

    expect(shell.methods, <String>['init', 'active']);
    expect(bundle.state, BundleState.active);

    final ServiceEndpoint? found = await observer.lookup(
      'CanBus',
      filter: '(interface=can0)',
    );
    expect(found, isNotNull);
    expect(found!.port, service.sendPort, reason: 'the owner is reachable');

    await bundle.stop();

    expect(
      await observer.lookup('CanBus'),
      isNull,
      reason: 'stopping detached the bundle, releasing what it published',
    );
    await bundle.dispose();
  });

  test('start waits for a port the shell has not delivered yet', () async {
    // The hazard this scope carries, stated as a test: a bundle that needs its
    // peers blocks until the framework port arrives, and a critical bundle's
    // startup deadline is running the whole time. A bundle with no peers
    // should not use this scope.
    final FakeShellTransport shell = FakeShellTransport();
    final ManagedBundle bundle = bundleOn(shell);

    final Future<void> starting = bundle.start();
    await shell.registered;
    await pumpEventQueue();

    expect(
      shell.methods,
      <String>['init'],
      reason: 'nothing is ACTIVE while the port is still outstanding',
    );
    expect(bundle.state, BundleState.starting);

    shell.completeFrameworkPort(server.port);
    await starting;

    expect(bundle.state, BundleState.active);
    expect(await observer.lookup('CanBus'), isNotNull);

    await bundle.stop();
    await bundle.dispose();
  });
}
