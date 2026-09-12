import 'dart:async';
import 'dart:isolate';

import 'package:osgi_api/osgi_api.dart';
import 'package:osgi_test/osgi_test.dart';
import 'package:test/test.dart';

/// A bundle activator written the way one actually would be, used here to show
/// what the fake buys: every case below is a real failure mode, and none of
/// them needs a shell, an engine, or a display to reach.
class _SampleActivator {
  _SampleActivator(this.transport, this.symbolicName, {this.needsPeers = true});

  final ShellTransport transport;
  final String symbolicName;

  /// A bundle that talks to other bundles needs the framework port; one that
  /// does not should never wait on it.
  final bool needsPeers;

  SendPort? frameworkPort;
  Object? failure;

  Future<void> start() async {
    try {
      final ShellBinding binding = await transport.register(symbolicName);
      if (needsPeers) frameworkPort = await binding.frameworkPort;
      await transport.reportActive(symbolicName);
    } on ShellRejectedException catch (e) {
      failure = e;
    } on ShellUnavailableException catch (e) {
      failure = e;
    }
  }
}

void main() {
  late ReceivePort framework;

  setUp(() => framework = ReceivePort('fake.framework'));
  tearDown(() => framework.close());

  test('the happy path reports ACTIVE', () async {
    final FakeShellTransport shell = FakeShellTransport(
      autoFrameworkPort: framework.sendPort,
    );
    final _SampleActivator activator = _SampleActivator(
      shell,
      'com.ivi.cluster',
    );

    await activator.start();

    expect(shell.methods, <String>['init', 'active']);
    expect(shell.reportedActive('com.ivi.cluster'), isTrue);
    expect(activator.frameworkPort, framework.sendPort);
    expect(activator.failure, isNull);
  });

  test(
    'the framework port arriving late does not stall ACTIVE forever',
    () async {
      // The ordering that works on a fast machine and hangs on a loaded one: the
      // framework isolate and the bundle start concurrently, so the port can
      // arrive well after register() returns. A critical bundle's startup
      // deadline is running the whole time.
      final FakeShellTransport shell = FakeShellTransport();
      final _SampleActivator activator = _SampleActivator(
        shell,
        'com.ivi.cluster',
      );

      final Future<void> started = activator.start();
      await shell.registered;

      expect(
        shell.methods,
        <String>['init'],
        reason: 'ACTIVE must not be sent before the bundle is really ready',
      );

      shell.completeFrameworkPort(framework.sendPort);
      await started;

      expect(shell.methods, <String>['init', 'active']);
      expect(activator.frameworkPort, framework.sendPort);
    },
  );

  test('a bundle with no peers never waits on the port', () async {
    // A headless service bundle that awaited a port it does not need would
    // burn its startup deadline waiting for a message nobody is going to care
    // about.
    final FakeShellTransport shell = FakeShellTransport();
    final _SampleActivator activator = _SampleActivator(
      shell,
      'com.ivi.candecoder',
      needsPeers: false,
    );

    await activator.start().timeout(const Duration(seconds: 2));

    expect(shell.methods, <String>['init', 'active']);
  });

  test('a rejected name never reports ACTIVE', () async {
    // The realistic cause is a name that is already registered -- a restart
    // that skipped unregister. Assert on what the shell was told, not on
    // start() throwing -- this activator swallows the exception, as many do.
    final FakeShellTransport shell = FakeShellTransport(
      rejectRegister: 'rejected',
    );
    final _SampleActivator activator = _SampleActivator(shell, 'com.ivi.typo');

    await activator.start();

    expect(shell.methods, <String>['init']);
    expect(shell.reportedActive('com.ivi.typo'), isFalse);
    expect(activator.failure, isA<ShellRejectedException>());
  });

  test('a shell built without OSGi surfaces as unavailable', () async {
    final FakeShellTransport shell = FakeShellTransport(unavailable: true);
    final _SampleActivator activator = _SampleActivator(
      shell,
      'com.ivi.cluster',
    );

    await activator.start();

    expect(activator.failure, isA<ShellUnavailableException>());
    expect(shell.reportedActive('com.ivi.cluster'), isFalse);
  });

  test('unregister fails a pending port wait rather than hanging it', () async {
    final FakeShellTransport shell = FakeShellTransport();
    final ShellBinding binding = await shell.register('com.ivi.cluster');

    final Future<Object?> outcome = binding.frameworkPort.then<Object?>(
      (SendPort p) => p,
      onError: (Object e) => e,
    );

    await shell.unregister('com.ivi.cluster');

    expect(await outcome, isA<ShellUnavailableException>());
  });

  test(
    'an unawaited port that never arrives is not an unhandled error',
    () async {
      // A bundle with no interest in the port is normal. If tearing down
      // completed an error onto a future nobody listened to, it would escape
      // into the enclosing zone and fail whatever test happened to be running.
      Object? escaped;
      await runZonedGuarded(() async {
        final FakeShellTransport shell = FakeShellTransport();
        await shell.register('com.ivi.candecoder');
        await shell.unregister('com.ivi.candecoder');
        await Future<void>.delayed(Duration.zero);
      }, (Object error, StackTrace _) => escaped = error);

      expect(escaped, isNull);
    },
  );

  test('completing a port before registering is a programming error', () {
    final FakeShellTransport shell = FakeShellTransport();
    expect(
      () => shell.completeFrameworkPort(framework.sendPort),
      throwsStateError,
    );
  });

  test(
    'registering twice is refused, as the real transport refuses it',
    () async {
      final FakeShellTransport shell = FakeShellTransport(
        autoFrameworkPort: framework.sendPort,
      );
      await shell.register('com.ivi.cluster');

      await expectLater(
        shell.register('com.ivi.navigation'),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            allOf(contains('com.ivi.cluster'), contains('com.ivi.navigation')),
          ),
        ),
      );
      expect(shell.methods, <String>[
        'init',
      ], reason: 'the refused call never reaches the shell');
    },
  );

  test('a torn-down fake can register again', () async {
    final FakeShellTransport shell = FakeShellTransport(
      autoFrameworkPort: framework.sendPort,
    );
    await shell.register('com.ivi.cluster');
    await shell.unregister('com.ivi.cluster');

    await expectLater(shell.register('com.ivi.cluster'), completes);
  });
}
