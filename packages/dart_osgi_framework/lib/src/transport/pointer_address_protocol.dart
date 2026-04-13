import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

/// Cross-isolate zero-copy delivery of large native buffers.
///
/// The producer sends `Pointer<T>.address` as a plain `int` via
/// [SendPort]. The consumer reconstructs `Pointer<T>.fromAddress(addr)`.
/// The address is valid in any isolate within the same Dart VM process.
///
/// **Critical caveat** (dart-lang/sdk #55800):
/// `Pointer.asTypedList(finalizer:)` is isolate-bound, NOT
/// isolate-group-bound. Sending the resulting TypedList to another
/// isolate **copies** the buffer. Always use raw `Pointer.address`
/// for cross-isolate zero-copy.
///
/// `asTypedList()` without finalizer: Dart sees native memory but
/// does not own it — safe for ring buffer views that never move.
///
/// Usage:
/// ```dart
/// // Producer isolate
/// final ptr = allocator.allocate<Float>(count);
/// // ... fill buffer ...
/// notifyPort.send(ptr.address);
///
/// // Consumer isolate
/// port.listen((int addr) {
///   final ptr = Pointer<Float>.fromAddress(addr);
///   final view = PointerAddressProtocol.viewFloat(addr, count);
///   processData(view);
///   releasePort.send(addr); // return slot to producer
/// });
/// ```
class PointerAddressProtocol {
  PointerAddressProtocol._();

  /// Create a [Float32List] view into native memory at [address].
  ///
  /// The returned list is a direct view — no copy. It is valid as long
  /// as the native memory at [address] is alive. Do NOT attach a
  /// finalizer if this list will cross isolate boundaries.
  static Float32List viewFloat(int address, int length) {
    return Pointer<Float>.fromAddress(address).asTypedList(length);
  }

  /// Create a [Float64List] view into native memory at [address].
  static Float64List viewDouble(int address, int length) {
    return Pointer<Double>.fromAddress(address).asTypedList(length);
  }

  /// Create a [Uint8List] view into native memory at [address].
  static Uint8List viewUint8(int address, int length) {
    return Pointer<Uint8>.fromAddress(address).asTypedList(length);
  }

  /// Create a [Int32List] view into native memory at [address].
  static Int32List viewInt32(int address, int length) {
    return Pointer<Int32>.fromAddress(address).asTypedList(length);
  }

  /// Send a pointer address via [SendPort] and listen for release
  /// on the [releasePort].
  ///
  /// Returns a [PointerSlot] that tracks whether the consumer has
  /// released the buffer.
  static PointerSlot send(
    SendPort notifyPort,
    int address, {
    ReceivePort? releasePort,
  }) {
    notifyPort.send(address);
    return PointerSlot(address: address, releasePort: releasePort);
  }
}

/// Tracks an in-flight pointer address sent to a consumer.
class PointerSlot {
  PointerSlot({required this.address, this.releasePort});

  final int address;
  final ReceivePort? releasePort;

  /// Wait for the consumer to release this buffer slot.
  ///
  /// Returns when the consumer sends the address back on the release port.
  Future<void> waitForRelease() async {
    if (releasePort == null) return;
    await for (final msg in releasePort!) {
      if (msg == address) return;
    }
  }
}
