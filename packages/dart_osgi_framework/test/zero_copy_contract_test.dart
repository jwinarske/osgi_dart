import 'package:dart_osgi_framework/dart_osgi_framework.dart';
import 'package:test/test.dart';

void main() {
  group('TransportType', () {
    test('has all expected values', () {
      expect(
        TransportType.values,
        containsAll([
          TransportType.transferableTypedData,
          TransportType.pointerAddress,
          TransportType.shmRingBuffer,
          TransportType.dmaBuf,
          TransportType.constReference,
        ]),
      );
    });

    test('has exactly 5 values', () {
      expect(TransportType.values, hasLength(5));
    });

    test('enum names are correct', () {
      expect(TransportType.transferableTypedData.name, 'transferableTypedData');
      expect(TransportType.pointerAddress.name, 'pointerAddress');
      expect(TransportType.shmRingBuffer.name, 'shmRingBuffer');
      expect(TransportType.dmaBuf.name, 'dmaBuf');
      expect(TransportType.constReference.name, 'constReference');
    });
  });

  group('TransportProperties', () {
    test('transport constant', () {
      expect(TransportProperties.transport, 'transport');
    });

    test('ringAddr constant', () {
      expect(TransportProperties.ringAddr, 'ring_addr');
    });

    test('ringCapacity constant', () {
      expect(TransportProperties.ringCapacity, 'ring_capacity');
    });

    test('elementSize constant', () {
      expect(TransportProperties.elementSize, 'element_size');
    });

    test('notifyPort constant', () {
      expect(TransportProperties.notifyPort, 'notify_port');
    });

    test('releasePort constant', () {
      expect(TransportProperties.releasePort, 'release_port');
    });

    test('dmaBufFd constant', () {
      expect(TransportProperties.dmaBufFd, 'dma_buf_fd');
    });

    test('schema constant', () {
      expect(TransportProperties.schema, 'schema');
    });
  });
}
