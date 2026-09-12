/// The `ihs_osgi_*` C surface of `libihs_shared`, behind a seam.
///
/// Two layers, deliberately. [OsgiBindings] is plain Dart -- no `dart:ffi` in
/// any of its signatures -- so the transport above it can be tested without a
/// shell, a library to `dlopen`, or a real handshake. [NativeOsgiBindings] is
/// the only thing here that touches `dart:ffi`.
///
/// The seam takes a [SendPort] rather than the port id the C surface wants, and
/// that is the point rather than an oversight: Dart cannot turn a port id back
/// into a [SendPort], so a seam dealing in integers could never let a test
/// deliver the framework port the way the shell does. Extracting `nativePort`
/// is the native implementation's job.
library;

import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:osgi_api/osgi_api.dart';

/// `IhsOsgiStatus`. Negative values are errors.
abstract final class OsgiStatus {
  /// The call succeeded.
  static const int ok = 0;

  /// A required argument was null, a `struct_size` was not recognized, or a
  /// port was zero.
  static const int invalid = -1;

  /// `Dart_InitializeApiDL` failed: the shell's vendored Dart DL headers do not
  /// match the running VM. Nothing on this surface will work.
  static const int dartApi = -2;

  /// The shell declined -- usually a `symbolic_name` matching no
  /// `[[osgi.bundles]]` entry, or one already registered.
  static const int rejected = -3;

  /// No OSGi host: built without `ENABLE_OSGI`, not an ivi-homescreen process,
  /// or the shell is shutting down.
  static const int unavailable = -4;
}

/// What `ihs_osgi_register_bundle` answered.
///
/// [handle] is the shell-minted capability, as an address. Zero when the call
/// failed. It is opaque: nothing here dereferences it, and it is never derived
/// from the name or the port -- reporting ACTIVE releases a critical bundle's
/// startup wait, so the handle is the only thing standing between that and a
/// forged report.
class OsgiRegistration {
  const OsgiRegistration(this.status, this.handle);

  final int status;
  final int handle;

  bool get ok => status == OsgiStatus.ok && handle != 0;
}

/// The handshake, in terms a test can satisfy.
abstract interface class OsgiBindings {
  /// Whether an OSGi host is installed. Advisory: the host can go away between
  /// this call and the next, and every other call reports for itself.
  bool get available;

  /// Register this bundle. The shell posts the framework isolate's port to
  /// [replyTo] when it knows it, which may be before or after this returns.
  OsgiRegistration registerBundle({
    required SendPort replyTo,
    required String symbolicName,
  });

  /// The activator's `start()` finished. This is what releases a critical
  /// bundle's startup wait.
  int reportActive(int handle);

  /// The activator's `stop()` finished. The bundle stays registered:
  /// STOPPING returns to RESOLVED, from which it can start again.
  int reportStopped(int handle);

  /// Release the registration so a restart can reuse the symbolic name.
  int unregister(int handle);
}

/// `IhsOsgiPeerInfo`.
final class _PeerInfo extends Struct {
  @Size()
  external int structSize;

  external Pointer<Void> dartApiDlData;

  @Int64()
  external int port;
}

/// `IhsOsgiBundleInfo`.
final class _BundleInfo extends Struct {
  @Size()
  external int structSize;

  external _PeerInfo peer;

  external Pointer<Utf8> symbolicName;
}

typedef _AvailableNative = Bool Function();
typedef _AvailableDart = bool Function();

typedef _RegisterBundleNative =
    Int32 Function(Pointer<_BundleInfo>, Pointer<Pointer<Void>>);
typedef _RegisterBundleDart =
    int Function(Pointer<_BundleInfo>, Pointer<Pointer<Void>>);

typedef _ReportNative = Int32 Function(Pointer<Void>);
typedef _ReportDart = int Function(Pointer<Void>);

/// [OsgiBindings] over the real `libihs_shared`.
class NativeOsgiBindings implements OsgiBindings {
  NativeOsgiBindings._(DynamicLibrary library)
    : _available = library.lookupFunction<_AvailableNative, _AvailableDart>(
        'ihs_osgi_available',
      ),
      _registerBundle = library
          .lookupFunction<_RegisterBundleNative, _RegisterBundleDart>(
            'ihs_osgi_register_bundle',
          ),
      _reportActive = library.lookupFunction<_ReportNative, _ReportDart>(
        'ihs_osgi_report_active',
      ),
      _reportStopped = library.lookupFunction<_ReportNative, _ReportDart>(
        'ihs_osgi_report_stopped',
      ),
      _unregister = library.lookupFunction<_ReportNative, _ReportDart>(
        'ihs_osgi_unregister',
      );

  /// The documented open string: the versioned SONAME, not the link name.
  static const String defaultLibrary = 'libihs_shared.so.1';

  /// Open [path] and bind the handshake.
  ///
  /// Throws [ShellUnavailableException] when the library is not there or
  /// carries no `ihs_osgi_*` symbols -- a shell built without `ENABLE_OSGI`
  /// exports none, so this is the ordinary "no OSGi here" answer rather than a
  /// broken installation.
  factory NativeOsgiBindings.open([String path = defaultLibrary]) {
    final DynamicLibrary library;
    try {
      library = DynamicLibrary.open(path);
    } on ArgumentError catch (e) {
      throw ShellUnavailableException('cannot open $path: $e');
    }
    try {
      return NativeOsgiBindings._(library);
    } on ArgumentError catch (e) {
      throw ShellUnavailableException(
        '$path exports no ihs_osgi_* symbols '
        '(shell built without ENABLE_OSGI?): $e',
      );
    }
  }

  final _AvailableDart _available;
  final _RegisterBundleDart _registerBundle;
  final _ReportDart _reportActive;
  final _ReportDart _reportStopped;
  final _ReportDart _unregister;

  @override
  bool get available => _available();

  @override
  OsgiRegistration registerBundle({
    required SendPort replyTo,
    required String symbolicName,
  }) {
    final Pointer<_BundleInfo> info = calloc<_BundleInfo>();
    final Pointer<Pointer<Void>> outBundle = calloc<Pointer<Void>>();
    final Pointer<Utf8> name = symbolicName.toNativeUtf8();
    try {
      info.ref.structSize = sizeOf<_BundleInfo>();
      info.ref.peer.structSize = sizeOf<_PeerInfo>();
      // The two things native code cannot obtain for itself: the symbol table
      // it binds Dart_PostCObject_DL from, and a port it can post to. Every
      // caller sends the first because any isolate may arrive first; the shell
      // makes all but the first a no-op.
      info.ref.peer.dartApiDlData = NativeApi.initializeApiDLData;
      info.ref.peer.port = replyTo.nativePort;
      info.ref.symbolicName = name;
      final int status = _registerBundle(info, outBundle);
      return OsgiRegistration(status, outBundle.value.address);
    } finally {
      calloc.free(name);
      calloc.free(outBundle);
      calloc.free(info);
    }
  }

  @override
  int reportActive(int handle) =>
      _reportActive(Pointer<Void>.fromAddress(handle));

  @override
  int reportStopped(int handle) =>
      _reportStopped(Pointer<Void>.fromAddress(handle));

  @override
  int unregister(int handle) => _unregister(Pointer<Void>.fromAddress(handle));
}
