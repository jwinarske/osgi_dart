/// DMA-BUF file descriptor handle for GPU buffer sharing.
///
/// Wraps a Linux DMA-BUF fd for sharing GPU buffers between the
/// Wayland compositor and Flutter engines via `zwp_linux_dmabuf_v1`.
///
/// The compositor can scan out the buffer directly — the data never
/// touches the CPU. Requires ivi-homescreen DRM backend:
/// BUILD_BACKEND_WAYLAND_DRM=ON.
///
/// Typical pipeline:
/// ```
/// GStreamer VA-API decode → DMA-BUF fd → EGLImage → GL external texture
/// Camera → DMA-BUF fd → Vulkan import → compute inference
/// ```
class DmaBufHandle {
  const DmaBufHandle({
    required this.fd,
    required this.width,
    required this.height,
    required this.format,
    this.stride = 0,
    this.offset = 0,
    this.modifier = 0,
  });

  /// The DMA-BUF file descriptor.
  final int fd;

  /// Buffer width in pixels.
  final int width;

  /// Buffer height in pixels.
  final int height;

  /// Pixel format (DRM fourcc code, e.g. DRM_FORMAT_ARGB8888).
  final int format;

  /// Row stride in bytes. 0 means tightly packed.
  final int stride;

  /// Offset into the buffer in bytes.
  final int offset;

  /// DRM format modifier (e.g. for tiled layouts). 0 means linear.
  final int modifier;

  /// Whether this handle has a valid file descriptor.
  bool get isValid => fd >= 0;

  /// OSGi service properties describing this DMA-BUF.
  Map<String, Object> get transportProperties => {
    'transport': 'dma_buf',
    'dma_buf_fd': fd,
    'width': width,
    'height': height,
    'format': format,
    'stride': stride,
    'offset': offset,
    'modifier': modifier,
  };

  @override
  String toString() =>
      'DmaBufHandle(fd=$fd, ${width}x$height, format=0x${format.toRadixString(16)})';
}

/// Well-known DRM fourcc format codes.
///
/// Subset of drm_fourcc.h constants used in ivi-homescreen pipelines.
abstract final class DrmFormat {
  static const argb8888 = 0x34325241;
  static const xrgb8888 = 0x34325258;
  static const nv12 = 0x3231564E;
  static const yuyv = 0x56595559;
  static const r8 = 0x20203852;
}
