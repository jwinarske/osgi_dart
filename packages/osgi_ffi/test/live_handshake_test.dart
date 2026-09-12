// The handshake against a real libihs_shared, with a real Dart VM.
//
// WHAT THIS PROVES THAT NOTHING ELSE DOES
//
// Every other test of this path fakes one side. The fake bindings in
// ffi_shell_transport_test hand the transport a Dart SendPort directly, never
// through C. ivi-homescreen's suites fake the Dart DL calls, because the real
// ones need a VM. So the step that actually crosses the boundary --
// Dart_PostCObject_DL putting a Dart_CObject_kSendPort into a live isolate's
// message queue, and Dart materialising a usable SendPort from it -- has never
// been executed by any test.
//
// That step is the framework's load-bearing assumption. Dart cannot turn a port
// id back into a SendPort, which is why the shell posts a send-port object
// rather than an integer (ivi-homescreen #531). If that did not work, a bundle
// would complete its handshake and silently never reach the framework isolate
// -- which is exactly the bug that sat in ivi-homescreen's own activator for a
// month, unnoticed, because nothing exercised it.
//
// HOW TO RUN IT
//
// Skipped unless both paths are in the environment, so `dart test` stays green
// on a machine with no native build:
//
//   IHS_SHARED_PATH=<prefix>/lib64/libihs_shared.so.1 \
//   IHS_OSGI_SHIM_PATH=<build>/libosgi_test_host.so \
//       dart test test/live_handshake_test.dart
//
// The shim stands in for the shell: see test/native/osgi_test_host.c.

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

// Everything used here is exported from the package's own library; unlike
// abi_conformance_test.dart, this file needs nothing from src/.
import 'package:osgi_ffi/osgi_ffi.dart';
import 'package:test/test.dart';

typedef _VoidNative = Void Function();
typedef _VoidDart = void Function();

void main() {
  // Environment, not String.fromEnvironment: these are paths a CI step exports,
  // not compile-time -D defines.
  final String? libPath = Platform.environment['IHS_SHARED_PATH'];
  final String? shimPath = Platform.environment['IHS_OSGI_SHIM_PATH'];

  // A skip rather than a failure: this needs a native build, and the ordinary
  // suite must stay runnable without one. The CI job that sets these is the
  // one that makes the claim above actually tested.
  final bool runnable = libPath != null && shimPath != null;

  group(
    'live handshake',
    () {
      late DynamicLibrary shim;
      late OsgiBindings bindings;

      setUpAll(() {
        if (!runnable) return;
        // The shim first: it installs the host, and until it has, every call on
        // the surface below answers IHS_OSGI_ERR_UNAVAILABLE.
        shim = DynamicLibrary.open(shimPath);
        shim.lookupFunction<_VoidNative, _VoidDart>('osgi_test_host_install')();
        bindings = NativeOsgiBindings.open(libPath);
      });

      tearDownAll(() {
        if (!runnable) return;
        shim.lookupFunction<_VoidNative, _VoidDart>(
          'osgi_test_host_uninstall',
        )();
      });

      test('the surface reports a host once one is installed', () {
        expect(
          bindings.available,
          isTrue,
          reason: 'ihs_osgi_set_host should have taken effect',
        );
      });

      // The whole point of the file.
      test('a posted kSendPort arrives in Dart as a usable SendPort', () async {
        final ReceivePort inbox = ReceivePort();
        final Completer<SendPort> gotPort = Completer<SendPort>();
        final Completer<Object?> gotEcho = Completer<Object?>();

        inbox.listen((Object? message) {
          if (message is SendPort && !gotPort.isCompleted) {
            gotPort.complete(message);
          } else if (!gotEcho.isCompleted) {
            gotEcho.complete(message);
          }
        });

        final OsgiRegistration registration = bindings.registerBundle(
          replyTo: inbox.sendPort,
          symbolicName: 'com.ivi.live',
        );
        expect(
          registration.ok,
          isTrue,
          reason:
              'status ${registration.status}, handle ${registration.handle}',
        );

        // It arrived as a SendPort, not as an int. A port id would have been
        // useless here, and this is the assertion that says so from Dart's side.
        final SendPort framework = await gotPort.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw StateError(
            'no SendPort arrived: Dart_PostCObject_DL did not deliver a '
            'kSendPort into this isolate',
          ),
        );

        // Usable, not merely present: send through it and see the message land.
        framework.send('ping');
        expect(
          await gotEcho.future.timeout(const Duration(seconds: 5)),
          'ping',
        );

        inbox.close();
      });

      test('reporting through the minted handle is accepted', () {
        final ReceivePort inbox = ReceivePort();
        final OsgiRegistration registration = bindings.registerBundle(
          replyTo: inbox.sendPort,
          symbolicName: 'com.ivi.reporter',
        );
        expect(registration.ok, isTrue);

        expect(bindings.reportActive(registration.handle), OsgiStatus.ok);
        expect(bindings.reportStopped(registration.handle), OsgiStatus.ok);
        expect(bindings.unregister(registration.handle), OsgiStatus.ok);
        inbox.close();
      });

      // A forged handle is refused across the real C boundary, not just against
      // the fake. The handle is the capability, so this is the property that
      // matters most about it.
      test('a handle the host never minted is refused', () {
        expect(bindings.reportActive(0xDEAD), OsgiStatus.rejected);
      });

      // The status mapping, exercised against real C rather than a fake that
      // returns whatever the test asked for.
      test('a refused name maps to a rejection through the transport', () {
        final FfiShellTransport transport = FfiShellTransport(
          bindings: bindings,
        );
        expect(
          () => transport.register('com.ivi.refused'),
          throwsA(
            isA<ShellRejectedException>().having(
              (ShellRejectedException e) => e.code,
              'code',
              'rejected',
            ),
          ),
        );
      });
    },
    skip: runnable
        ? null
        : 'needs IHS_SHARED_PATH and IHS_OSGI_SHIM_PATH (a native build of '
              'ivi-homescreen shared/ with ENABLE_OSGI=ON, plus '
              'test/native/osgi_test_host.c)',
  );
}
