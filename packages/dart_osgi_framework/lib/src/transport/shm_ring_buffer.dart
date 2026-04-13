import 'dart:ffi';
import 'dart:typed_data';

/// SPSC (single-producer, single-consumer) mmap ring buffer.
///
/// The native side (Rust or C++) creates an mmap'd shared memory region
/// and exposes it via a base address. Both producer and consumer share
/// the same physical pages — zero copies.
///
/// Suitable for high-frequency sensor data: CAN (1kHz), IMU (200Hz).
///
/// Ring layout in shared memory:
/// ```
/// ┌──────────────────────────────────────────────────┐
/// │ Header: write_cursor (uint64) | read_cursor (uint64) │
/// ├──────────────────────────────────────────────────┤
/// │ Slot 0: [elementSize bytes]                       │
/// │ Slot 1: [elementSize bytes]                       │
/// │ ...                                               │
/// │ Slot N-1: [elementSize bytes]                     │
/// └──────────────────────────────────────────────────┘
/// ```
///
/// The header is 16 bytes (two 64-bit cursors). Slots follow immediately.
class ShmRingBuffer<T extends NativeType> {
  ShmRingBuffer({
    required this.baseAddress,
    required this.capacity,
    required this.elementSize,
  }) : _basePtr = Pointer<Uint8>.fromAddress(baseAddress);

  /// Base address of the mmap'd shared memory region.
  final int baseAddress;

  /// Number of slots in the ring.
  final int capacity;

  /// Size of each element in bytes.
  final int elementSize;

  final Pointer<Uint8> _basePtr;

  /// Header size in bytes (write_cursor + read_cursor as uint64).
  static const headerSize = 16;

  // ── Cursor access ─────────────────────────────────────────────────

  /// The write cursor (set by the producer).
  int get writeCursor => Pointer<Uint64>.fromAddress(baseAddress).value;

  /// The read cursor (set by the consumer).
  int get readCursor => Pointer<Uint64>.fromAddress(baseAddress + 8).value;

  set readCursor(int value) {
    Pointer<Uint64>.fromAddress(baseAddress + 8).value = value;
  }

  /// Number of unread elements available.
  int get available {
    final w = writeCursor;
    final r = readCursor;
    return w >= r ? w - r : capacity - r + w;
  }

  /// Whether the ring has unread data.
  bool get hasData => writeCursor != readCursor;

  // ── Read operations ───────────────────────────────────────────────

  /// Get a [Pointer<Uint8>] to the data at slot [index].
  ///
  /// The pointer is directly into shared memory — no copy.
  Pointer<Uint8> slotPointer(int index) {
    final offset = headerSize + (index % capacity) * elementSize;
    return _basePtr + offset;
  }

  /// Read one element at the current read cursor without advancing.
  ///
  /// Returns a [Uint8List] view into shared memory — no copy.
  /// Valid only until the producer overwrites this slot.
  Uint8List peek() {
    final ptr = slotPointer(readCursor);
    return ptr.asTypedList(elementSize);
  }

  /// Read one element and advance the read cursor.
  Uint8List read() {
    final data = peek();
    readCursor = (readCursor + 1) % capacity;
    return data;
  }

  /// Drain up to [maxCount] elements into [dest].
  ///
  /// Copies data into [dest] and advances the read cursor.
  /// Returns the number of elements actually read.
  int drainInto(Uint8List dest, {int? maxCount}) {
    final max = maxCount ?? (dest.length ~/ elementSize);
    var count = 0;
    while (count < max && hasData) {
      final ptr = slotPointer(readCursor);
      final src = ptr.asTypedList(elementSize);
      dest.setRange(count * elementSize, (count + 1) * elementSize, src);
      readCursor = (readCursor + 1) % capacity;
      count++;
    }
    return count;
  }

  /// Read all available elements into a pre-allocated batch buffer.
  ///
  /// Zero Dart heap allocation when [batch] is reused across calls.
  int drainBatch(Uint8List batch) {
    return drainInto(batch, maxCount: batch.length ~/ elementSize);
  }

  // ── Transport properties ──────────────────────────────────────────

  /// OSGi service properties describing this ring buffer.
  Map<String, Object> get transportProperties => {
    'transport': 'shm_ring_buffer',
    'ring_addr': baseAddress,
    'ring_capacity': capacity,
    'element_size': elementSize,
  };
}
