import 'package:dart_osgi_framework/dart_osgi_framework.dart';
import 'package:test/test.dart';

void main() {
  group('DmaBufHandle', () {
    test('constructor stores all fields', () {
      final handle = DmaBufHandle(
        fd: 7,
        width: 1920,
        height: 1080,
        format: DrmFormat.argb8888,
        stride: 7680,
        offset: 0,
        modifier: 42,
      );

      expect(handle.fd, 7);
      expect(handle.width, 1920);
      expect(handle.height, 1080);
      expect(handle.format, DrmFormat.argb8888);
      expect(handle.stride, 7680);
      expect(handle.offset, 0);
      expect(handle.modifier, 42);
    });

    test('default stride, offset, modifier are zero', () {
      final handle = DmaBufHandle(
        fd: 3,
        width: 640,
        height: 480,
        format: DrmFormat.nv12,
      );

      expect(handle.stride, 0);
      expect(handle.offset, 0);
      expect(handle.modifier, 0);
    });

    group('isValid', () {
      test('returns true when fd >= 0', () {
        expect(
          DmaBufHandle(fd: 0, width: 1, height: 1, format: 0).isValid,
          isTrue,
        );
        expect(
          DmaBufHandle(fd: 42, width: 1, height: 1, format: 0).isValid,
          isTrue,
        );
      });

      test('returns false when fd < 0', () {
        expect(
          DmaBufHandle(fd: -1, width: 1, height: 1, format: 0).isValid,
          isFalse,
        );
        expect(
          DmaBufHandle(fd: -100, width: 1, height: 1, format: 0).isValid,
          isFalse,
        );
      });
    });

    test('transportProperties contains all fields', () {
      final handle = DmaBufHandle(
        fd: 5,
        width: 800,
        height: 600,
        format: DrmFormat.xrgb8888,
        stride: 3200,
        offset: 64,
        modifier: 99,
      );

      final props = handle.transportProperties;

      expect(props['transport'], 'dma_buf');
      expect(props['dma_buf_fd'], 5);
      expect(props['width'], 800);
      expect(props['height'], 600);
      expect(props['format'], DrmFormat.xrgb8888);
      expect(props['stride'], 3200);
      expect(props['offset'], 64);
      expect(props['modifier'], 99);
      expect(props.length, 8);
    });

    test('toString() includes fd, dimensions, and hex format', () {
      final handle = DmaBufHandle(
        fd: 10,
        width: 1920,
        height: 1080,
        format: DrmFormat.argb8888,
      );

      final str = handle.toString();
      expect(str, contains('fd=10'));
      expect(str, contains('1920x1080'));
      expect(str, contains('format=0x${DrmFormat.argb8888.toRadixString(16)}'));
      expect(str, startsWith('DmaBufHandle('));
      expect(str, endsWith(')'));
    });

    test('can be created as const', () {
      const handle = DmaBufHandle(fd: 1, width: 320, height: 240, format: 0);
      expect(handle.fd, 1);
    });
  });

  group('DrmFormat', () {
    test('argb8888 is correct hex value', () {
      expect(DrmFormat.argb8888, 0x34325241);
    });

    test('xrgb8888 is correct hex value', () {
      expect(DrmFormat.xrgb8888, 0x34325258);
    });

    test('nv12 is correct hex value', () {
      expect(DrmFormat.nv12, 0x3231564E);
    });

    test('yuyv is correct hex value', () {
      expect(DrmFormat.yuyv, 0x56595559);
    });

    test('r8 is correct hex value', () {
      expect(DrmFormat.r8, 0x20203852);
    });
  });
}
