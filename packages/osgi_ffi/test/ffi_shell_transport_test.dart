import 'dart:async';
import 'dart:isolate';

import 'package:osgi_ffi/osgi_ffi.dart';
import 'package:test/test.dart';

/// Stands in for `libihs_shared`, recording what crossed and answering with
/// whatever status the test wants.
///
/// It holds the bundle's [SendPort], which is what makes the interesting case
/// reachable at all: the shell delivers the framework port by posting to it,
/// and a fake that only saw a port id could not, because Dart cannot turn one
/// back into a [SendPort].
class FakeBindings implements OsgiBindings {
  FakeBindings({
    this.registerStatus = OsgiStatus.ok,
    this.reportStatus = OsgiStatus.ok,
    this.handle = 0xB0554,
    this.available = true,
  });

  int registerStatus;
  int reportStatus;
  int handle;

  @override
  bool available;

  final List<String> calls = <String>[];
  final List<int> handles = <int>[];
  SendPort? replyTo;
  String? registeredName;

  @override
  OsgiRegistration registerBundle({
    required SendPort replyTo,
    required String symbolicName,
  }) {
    calls.add('register');
    this.replyTo = replyTo;
    registeredName = symbolicName;
    return OsgiRegistration(
      registerStatus,
      registerStatus == OsgiStatus.ok ? handle : 0,
    );
  }

  /// Deliver the framework port as the shell does, whenever the test chooses.
  void deliverFrameworkPort(SendPort port) => replyTo!.send(port);

  @override
  int reportActive(int handle) {
    calls.add('active');
    handles.add(handle);
    return reportStatus;
  }

  @override
  int reportStopped(int handle) {
    calls.add('stopped');
    handles.add(handle);
    return reportStatus;
  }

  @override
  int unregister(int handle) {
    calls.add('unregister');
    handles.add(handle);
    return OsgiStatus.ok;
  }
}

void main() {
  group('register', () {
    test(
      'announces the bundle and reports ACTIVE through the handle',
      () async {
        final FakeBindings bindings = FakeBindings();
        final FfiShellTransport transport = FfiShellTransport(
          bindings: bindings,
        );

        final ShellBinding binding = await transport.register(
          'com.ivi.cluster',
        );
        expect(binding.symbolicName, 'com.ivi.cluster');
        expect(bindings.registeredName, 'com.ivi.cluster');

        await transport.reportActive('com.ivi.cluster');
        await transport.reportStopped('com.ivi.cluster');
        expect(bindings.calls, <String>['register', 'active', 'stopped']);
        // The capability the shell minted, not the name.
        expect(bindings.handles, <int>[0xB0554, 0xB0554]);

        await transport.unregister('com.ivi.cluster');
      },
    );

    // The framework isolate and this bundle start concurrently, so the port
    // arrives whenever it arrives. Both orders are normal and neither is an
    // error -- this is the one that used to be assumed away.
    test('completes the framework port when the shell posts it later', () async {
      final FakeBindings bindings = FakeBindings();
      final FfiShellTransport transport = FfiShellTransport(bindings: bindings);

      final ShellBinding binding = await transport.register('com.ivi.cluster');

      final ReceivePort framework = ReceivePort();
      bindings.deliverFrameworkPort(framework.sendPort);

      final SendPort port = await binding.frameworkPort;
      // Prove it is usable, which is the whole reason it crosses as a SendPort.
      port.send('ping');
      expect(await framework.first, 'ping');

      framework.close();
      await transport.unregister('com.ivi.cluster');
    });

    test('one transport serves one bundle', () async {
      final FakeBindings bindings = FakeBindings();
      final FfiShellTransport transport = FfiShellTransport(bindings: bindings);
      await transport.register('com.ivi.cluster');

      expect(
        () => transport.register('com.ivi.navigation'),
        throwsA(isA<StateError>()),
      );
      await transport.unregister('com.ivi.cluster');
    });
  });

  group('status mapping', () {
    Future<void> expectRegisterThrows(int status, Matcher matcher) async {
      final FakeBindings bindings = FakeBindings(registerStatus: status);
      final FfiShellTransport transport = FfiShellTransport(bindings: bindings);
      await expectLater(
        transport.register('com.ivi.cluster'),
        throwsA(matcher),
      );
    }

    test('no OSGi host is unavailable, not a refusal', () async {
      await expectRegisterThrows(
        OsgiStatus.unavailable,
        isA<ShellUnavailableException>(),
      );
    });

    test('a declined name is rejected', () async {
      await expectRegisterThrows(
        OsgiStatus.rejected,
        isA<ShellRejectedException>().having(
          (ShellRejectedException e) => e.code,
          'code',
          'rejected',
        ),
      );
    });

    test('a DL version mismatch keeps the channel transport code', () async {
      await expectRegisterThrows(
        OsgiStatus.dartApi,
        isA<ShellRejectedException>().having(
          (ShellRejectedException e) => e.code,
          'code',
          'dart_api_unavailable',
        ),
      );
    });

    test('bad arguments keep the channel transport code', () async {
      await expectRegisterThrows(
        OsgiStatus.invalid,
        isA<ShellRejectedException>().having(
          (ShellRejectedException e) => e.code,
          'code',
          'bad_arguments',
        ),
      );
    });

    // An OK status with no handle would leave nothing to report through, and
    // every later call would fail with no explanation.
    test('an accepted registration with no handle is refused', () async {
      final FakeBindings bindings = FakeBindings()..handle = 0;
      final FfiShellTransport transport = FfiShellTransport(bindings: bindings);
      await expectLater(
        transport.register('com.ivi.cluster'),
        throwsA(isA<ShellRejectedException>()),
      );
    });
  });

  group('reporting without a registration', () {
    test('reporting before register is rejected, not a crash', () async {
      final FfiShellTransport transport = FfiShellTransport(
        bindings: FakeBindings(),
      );
      expect(
        () => transport.reportActive('com.ivi.cluster'),
        throwsA(
          isA<ShellRejectedException>().having(
            (ShellRejectedException e) => e.code,
            'code',
            'rejected',
          ),
        ),
      );
    });

    test('reporting under another name is a programming error', () async {
      final FfiShellTransport transport = FfiShellTransport(
        bindings: FakeBindings(),
      );
      await transport.register('com.ivi.cluster');
      expect(
        () => transport.reportActive('com.ivi.navigation'),
        throwsA(isA<StateError>()),
      );
      await transport.unregister('com.ivi.cluster');
    });

    test('a refused report surfaces the shell status', () async {
      final FakeBindings bindings = FakeBindings(
        reportStatus: OsgiStatus.rejected,
      );
      final FfiShellTransport transport = FfiShellTransport(bindings: bindings);
      await transport.register('com.ivi.cluster');
      expect(
        () => transport.reportActive('com.ivi.cluster'),
        throwsA(isA<ShellRejectedException>()),
      );
      await transport.unregister('com.ivi.cluster');
    });
  });

  group('teardown', () {
    test('unregister releases the handle and frees the name', () async {
      final FakeBindings bindings = FakeBindings();
      final FfiShellTransport transport = FfiShellTransport(bindings: bindings);

      await transport.register('com.ivi.cluster');
      await transport.unregister('com.ivi.cluster');
      expect(bindings.calls.last, 'unregister');

      // The name is free again, which is what a restart needs.
      await transport.register('com.ivi.cluster');
      await transport.unregister('com.ivi.cluster');
    });

    // Waiting forever on a port that is never coming is worse than an error.
    test('a pending framework port fails when the registration goes', () async {
      final FakeBindings bindings = FakeBindings();
      final FfiShellTransport transport = FfiShellTransport(bindings: bindings);

      final ShellBinding binding = await transport.register('com.ivi.cluster');
      await transport.unregister('com.ivi.cluster');

      await expectLater(
        binding.frameworkPort,
        throwsA(isA<ShellUnavailableException>()),
      );
    });

    test('unregistering without a registration is harmless', () async {
      final FakeBindings bindings = FakeBindings();
      final FfiShellTransport transport = FfiShellTransport(bindings: bindings);
      await transport.unregister('com.ivi.cluster');
      expect(bindings.calls, isEmpty);
    });
  });

  test('available reflects the host', () {
    final FakeBindings bindings = FakeBindings(available: false);
    expect(FfiShellTransport(bindings: bindings).available, isFalse);
    bindings.available = true;
    expect(FfiShellTransport(bindings: bindings).available, isTrue);
  });
}
