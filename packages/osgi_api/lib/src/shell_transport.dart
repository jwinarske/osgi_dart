/// How a bundle reaches the shell, and why that is a narrow seam.
///
/// There are three data paths in this system and they want different
/// mechanisms. Conflating them is the mistake worth avoiding, so they are named
/// here explicitly:
///
///  1. **Bootstrap and lifecycle** — a bundle telling the shell it exists, and
///     later that its activator finished. A handful of messages per bundle,
///     each a few integers and a string. Latency matters only in that a
///     critical bundle's startup deadline is running while it happens.
///     *This interface.*
///
///  2. **Between bundles** — service lookups, events, registry traffic. High
///     frequency, ordinary Dart objects. This never touches native code at all:
///     all engines in a process share one Dart VM, so it is `SendPort` between
///     isolates. A platform channel here would marshal every call through the
///     platform thread for no reason.
///
///  3. **Bulk payloads** — point clouds, camera frames, decoded video. Sending
///     these through any message-passing layer that copies is not viable at
///     frame rate. `Pointer.address` is passed as an `int` over a `SendPort`
///     and the receiving isolate reconstitutes the pointer; isolates share the
///     process address space, so nothing is copied.
///
/// Only (1) crosses into native code, which is why it is the only one behind an
/// interface. The other two are pure Dart and need no abstraction — they are
/// just isolates talking.
///
/// ## Why (1) is abstracted at all
///
/// The obvious implementation is a `MethodChannel`, and that is what
/// [ShellTransport] is first implemented with, because it is proven working on
/// hardware and needs nothing from the shell that is not already there.
///
/// It is not obviously the right answer forever, for two reasons:
///
///   * **It couples "I am ready" to the platform thread.** A critical bundle's
///     ACTIVE report is marshalled through the platform task runner, and that
///     thread is at its busiest during exactly the window the report needs to
///     cross — first frame, pipeline compiles. The startup deadline is running
///     the whole time.
///
///   * **A headless bundle should not need a UI binding.** A CAN decoder with
///     no views must still call `WidgetsFlutterBinding.ensureInitialized()` to
///     get a channel, which is a lot of Flutter to drag in to send three
///     integers.
///
/// An FFI transport through `libihs_shared.so` — already the documented surface
/// for out-of-tree plugins — avoids both: synchronous, no binding, no platform
/// thread.
///
/// ## Why both survive
///
/// Not as a migration, and not as a fallback. `dart:ffi` grants arbitrary read
/// and write over the whole process address space, plus `dlopen` of libc, so an
/// FFI transport can only be given to code the image already trusts. A bundle
/// loaded from outside the image gets the channel and no `dart:ffi` at all.
///
/// Which transport a bundle gets is therefore a property of how much it is
/// trusted, not of what it needs. This interface exists so that is the only
/// thing that changes: a bundle's own code is identical either way.
///
/// (DR-001 in the project plan records what was checked, and why an
/// `eglGetProcAddress`-style capability lookup does not make in-process
/// isolation work.)
library;

import 'dart:isolate';

/// The result of a bootstrap handshake.
///
/// [frameworkPort] is the framework isolate's port, which the shell delivers
/// asynchronously — it may not be known when [ShellTransport.register] returns,
/// because the framework isolate and this bundle start concurrently. Callers
/// wait on [ShellBinding.frameworkPort] rather than assuming.
class ShellBinding {
  ShellBinding({required this.symbolicName, required this.frameworkPort});

  final String symbolicName;

  /// Completes when the shell hands over the framework isolate's port. May
  /// already be complete on return, or may complete later; both orderings are
  /// normal and neither is an error.
  ///
  /// A [SendPort] rather than a port id, because a port id is useless here:
  /// Dart offers no way to turn one back into a [SendPort]. The shell posts it
  /// as a send-port object for that reason, and this is what a bundle hands to
  /// the framework client to start talking.
  final Future<SendPort> frameworkPort;
}

/// Raised when the shell refuses a bundle's handshake.
///
/// [code] is the shell's error code. `rejected` from `init` means the name is
/// empty or already registered -- typically a restart that skipped
/// [ShellTransport.unregister] -- or the port was invalid; from `active` or
/// `stopped` it means no `init` was made under that name.
/// `dart_api_unavailable` means the shell's Dart DL headers do not match the
/// running VM.
///
/// A name that matches no `[[osgi.bundles]]` entry *is* rejected, as of
/// ivi-homescreen #537: the shell is given the declared names at bring-up and
/// refuses `init` for anything else, so a typo fails at the call that made it.
/// Before that it was accepted and its reports quietly ignored, which surfaced
/// as the *correctly* named bundle's startup deadline expiring instead.
class ShellRejectedException implements Exception {
  ShellRejectedException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'ShellRejectedException($code): $message';
}

/// Raised when the shell is not reachable at all — typically a binary built
/// without OSGi support, so the channel or symbol simply is not there.
class ShellUnavailableException implements Exception {
  ShellUnavailableException(this.message);

  final String message;

  @override
  String toString() => 'ShellUnavailableException: $message';
}

/// The bundle's side of the shell contract.
///
/// Implementations are transport mechanics only: no lifecycle policy, no
/// retries, no state beyond what one call needs. The framework decides *when*
/// to call these; this decides *how* they travel.
abstract interface class ShellTransport {
  /// Announce this bundle and hand over what native code cannot obtain itself:
  /// the address of `NativeApi.initializeApiDLData`, so the shell can bind its
  /// Dart DL symbol table, and a port it can post to.
  ///
  /// Throws [ShellRejectedException] if the shell declines the name, or
  /// [ShellUnavailableException] if there is no shell to talk to.
  Future<ShellBinding> register(String symbolicName);

  /// Report that the activator's `start()` completed.
  ///
  /// This — not the engine coming up, which the shell already knows, and not
  /// the first frame, which says nothing about whether the bundle's own code is
  /// ready — is what releases a critical bundle's startup wait.
  Future<void> reportActive(String symbolicName);

  /// Report that the activator's `stop()` completed.
  Future<void> reportStopped(String symbolicName);

  /// Release the registration so the same symbolic name can be used again by a
  /// restart.
  Future<void> unregister(String symbolicName);
}
