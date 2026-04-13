import 'dart:isolate';
import 'dart:typed_data';

/// O(1) byte buffer ownership transfer using [TransferableTypedData].
///
/// Wraps Dart's [TransferableTypedData] for efficient one-time buffer
/// transfer. The buffer is moved (not copied) — the sender loses access
/// after transfer.
///
/// **Isolate-bound caveat**: The materialized [ByteBuffer] after
/// `materialize()` is bound to the receiving isolate. It cannot be
/// sent to a third isolate without copying. For cross-isolate
/// zero-copy of large buffers, use [PointerAddressProtocol] instead.
///
/// Suitable for: audio buffers, bulk data transfers, serialized
/// protocol buffers.
class TransferableBuffer {
  TransferableBuffer._(this._transferable);

  /// Create a transferable buffer from a [Uint8List].
  ///
  /// After calling this, the original list should not be used — the
  /// underlying memory may be transferred.
  factory TransferableBuffer.fromBytes(Uint8List bytes) {
    return TransferableBuffer._(TransferableTypedData.fromList([bytes]));
  }

  /// Create a transferable buffer from multiple typed data lists.
  ///
  /// All lists are concatenated into a single transferable buffer.
  factory TransferableBuffer.fromList(List<TypedData> chunks) {
    return TransferableBuffer._(TransferableTypedData.fromList(chunks));
  }

  final TransferableTypedData _transferable;

  /// The underlying [TransferableTypedData] for sending via [SendPort].
  ///
  /// Usage:
  /// ```dart
  /// // Sender
  /// final buf = TransferableBuffer.fromBytes(largeData);
  /// sendPort.send(buf.transferable);
  ///
  /// // Receiver
  /// port.listen((dynamic msg) {
  ///   final data = TransferableBuffer.materialize(
  ///       msg as TransferableTypedData);
  /// });
  /// ```
  TransferableTypedData get transferable => _transferable;

  /// Materialize a received [TransferableTypedData] into a [ByteBuffer].
  ///
  /// This is O(1) — no copy. The resulting buffer is isolate-bound.
  static ByteBuffer materialize(TransferableTypedData data) {
    return data.materialize().asByteData().buffer;
  }

  /// Materialize into a [Uint8List] view.
  static Uint8List materializeAsBytes(TransferableTypedData data) {
    return data.materialize().asUint8List();
  }
}
