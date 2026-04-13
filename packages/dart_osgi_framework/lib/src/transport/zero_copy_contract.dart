/// The transport mechanism used by a zero-copy service.
///
/// Each data flow in the system must be categorised by transport
/// mechanism. This enum is the authoritative reference — see the
/// implementation plan's Zero-copy Transport Reference table.
enum TransportType {
  /// O(1) byte buffer ownership transfer via [TransferableTypedData].
  /// Within-isolate finalizer; isolate-bound (not group-bound).
  transferableTypedData,

  /// Cross-isolate delivery of large buffers as raw `int` addresses.
  /// Consumer reconstructs `Pointer<T>.fromAddress(addr)`.
  /// Zero bytes cross the isolate boundary.
  pointerAddress,

  /// SPSC mmap ring buffer (Rust FFI).
  /// Producer and consumer share physical pages.
  /// Suitable for CAN (1kHz), IMU (200Hz).
  shmRingBuffer,

  /// GPU buffer handles via `zwp_linux_dmabuf_v1`.
  /// Wayland compositor scans out directly — never touches CPU.
  /// Requires BUILD_BACKEND_WAYLAND_DRM=ON.
  dmaBuf,

  /// Immutable `const Map<String, Object>` sent by VM reference.
  /// O(1), zero bytes moved — the VM shares the pointer.
  constReference,
}

/// Documents which transport mechanism a service uses.
///
/// Services implementing this interface expose their transport type
/// and buffer metadata as OSGi service properties, enabling consumers
/// to select the correct zero-copy receive pattern.
abstract class ZeroCopyContract {
  /// The transport mechanism this service uses.
  TransportType get transportType;

  /// Service properties describing the transport.
  ///
  /// Standard keys:
  /// - `transport`: [TransportType] name string
  /// - `ring_addr`: int (for [TransportType.shmRingBuffer])
  /// - `ring_capacity`: int (for [TransportType.shmRingBuffer])
  /// - `element_size`: int (bytes per element)
  /// - `notify_port`: SendPort hashCode (for notification)
  /// - `release_port`: SendPort hashCode (for slot return)
  /// - `dma_buf_fd`: int (for [TransportType.dmaBuf])
  /// - `schema`: String (data layout description)
  Map<String, Object> get transportProperties;
}

/// Standard service property keys for zero-copy transport metadata.
abstract final class TransportProperties {
  static const transport = 'transport';
  static const ringAddr = 'ring_addr';
  static const ringCapacity = 'ring_capacity';
  static const elementSize = 'element_size';
  static const notifyPort = 'notify_port';
  static const releasePort = 'release_port';
  static const dmaBufFd = 'dma_buf_fd';
  static const schema = 'schema';
}
