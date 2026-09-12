import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:osgi_flutter/osgi_flutter.dart';

const MethodChannel _bridge = MethodChannel('dev.osgi/bridge');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;

  /// Stand in for the shell's `OsgiBridgePlugin`. [rejectMethod] makes that
  /// method fail with [rejectCode], as the real one does for a duplicate `init`
  /// or for a report under a name that never called `init`.
  void installShell({String? rejectMethod, String rejectCode = 'rejected'}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_bridge, (MethodCall call) async {
          calls.add(call);
          if (call.method == rejectMethod) {
            throw PlatformException(
              code: rejectCode,
              message: 'no such bundle',
            );
          }
          return true;
        });
  }

  void removeShell() {
    // No handler at all is what a build without OSGi looks like from here.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_bridge, null);
  }

  setUp(() => calls = <MethodCall>[]);
  tearDown(removeShell);

  test('register sends the two things native code cannot obtain itself', () async {
    installShell();
    final MethodChannelShellTransport transport = MethodChannelShellTransport();

    await transport.register('com.ivi.cluster');

    expect(calls, hasLength(1));
    expect(calls.single.method, 'init');
    final Map<Object?, Object?> args =
        calls.single.arguments as Map<Object?, Object?>;
    expect(args['role'], 'bundle');
    expect(args['symbolic_name'], 'com.ivi.cluster');
    // Both must be real, non-zero addresses: the shell binds its Dart DL symbol
    // table from the first and posts to the second. A zero here would look like
    // a successful handshake and then silently deliver nothing.
    expect(
      args['dl_data'],
      isA<int>().having((int a) => a, 'dl_data', isNot(0)),
    );
    expect(args['port'], isA<int>().having((int p) => p, 'port', isNot(0)));
  });

  test('lifecycle reports name the bundle', () async {
    installShell();
    final MethodChannelShellTransport transport = MethodChannelShellTransport();

    await transport.register('com.ivi.cluster');
    await transport.reportActive('com.ivi.cluster');
    await transport.reportStopped('com.ivi.cluster');
    await transport.unregister('com.ivi.cluster');

    expect(calls.map((MethodCall c) => c.method), <String>[
      'init',
      'active',
      'stopped',
      'shutdown',
    ]);
  });

  test(
    'a rejected name raises ShellRejectedException with the shell code',
    () async {
      installShell(rejectMethod: 'active');
      final MethodChannelShellTransport transport =
          MethodChannelShellTransport();
      await transport.register('com.ivi.typo');

      await expectLater(
        transport.reportActive('com.ivi.typo'),
        throwsA(
          isA<ShellRejectedException>().having(
            (ShellRejectedException e) => e.code,
            'code',
            'rejected',
          ),
        ),
      );
    },
  );

  test('no channel surfaces as unavailable, not as a rejection', () async {
    // A shell built without OSGi is a different problem from a misconfigured
    // bundle, and a bundle that conflates them reports the wrong cause.
    removeShell();
    final MethodChannelShellTransport transport = MethodChannelShellTransport();

    await expectLater(
      transport.register('com.ivi.cluster'),
      throwsA(isA<ShellUnavailableException>()),
    );
    await expectLater(
      transport.reportActive('com.ivi.cluster'),
      throwsA(isA<ShellUnavailableException>()),
    );
  });

  test('a failed register leaves the transport reusable', () async {
    // Otherwise a retry after a transient failure hits the one-bundle guard and
    // reports a programming error instead of the real cause.
    installShell(rejectMethod: 'init');
    final MethodChannelShellTransport transport = MethodChannelShellTransport();

    await expectLater(
      transport.register('com.ivi.cluster'),
      throwsA(isA<ShellRejectedException>()),
    );

    installShell();
    await expectLater(transport.register('com.ivi.cluster'), completes);
  });

  test(
    'registering twice is a programming error naming both bundles',
    () async {
      installShell();
      final MethodChannelShellTransport transport =
          MethodChannelShellTransport();
      await transport.register('com.ivi.cluster');

      await expectLater(
        transport.register('com.ivi.navigation'),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            allOf(contains('com.ivi.cluster'), contains('com.ivi.navigation')),
          ),
        ),
      );
    },
  );

  test('unregister does not throw when the shell is already gone', () async {
    // Teardown usually runs because something else already failed; a throw here
    // masks the original cause.
    installShell();
    final MethodChannelShellTransport transport = MethodChannelShellTransport();
    await transport.register('com.ivi.cluster');

    removeShell();
    await expectLater(transport.unregister('com.ivi.cluster'), completes);
  });

  test('unregister fails a pending port wait rather than hanging it', () async {
    installShell();
    final MethodChannelShellTransport transport = MethodChannelShellTransport();
    final ShellBinding binding = await transport.register('com.ivi.cluster');

    final Future<Object?> outcome = binding.frameworkPort.then<Object?>(
      (SendPort p) => p,
      onError: (Object e) => e,
    );

    await transport.unregister('com.ivi.cluster');

    expect(await outcome, isA<ShellUnavailableException>());
  });

  test('a torn-down transport can register again', () async {
    installShell();
    final MethodChannelShellTransport transport = MethodChannelShellTransport();
    await transport.register('com.ivi.cluster');
    await transport.unregister('com.ivi.cluster');

    await expectLater(transport.register('com.ivi.cluster'), completes);
  });
}
