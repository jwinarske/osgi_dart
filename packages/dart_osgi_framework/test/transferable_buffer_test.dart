import 'dart:typed_data';

import 'package:dart_osgi_framework/dart_osgi_framework.dart';
import 'package:test/test.dart';

void main() {
  group('TransferableBuffer', () {
    group('fromBytes()', () {
      test('creates transferable from Uint8List', () {
        final data = Uint8List.fromList([1, 2, 3, 4, 5]);
        final buf = TransferableBuffer.fromBytes(data);
        expect(buf, isNotNull);
        expect(buf.transferable, isNotNull);
      });

      test('creates transferable from empty Uint8List', () {
        final data = Uint8List(0);
        final buf = TransferableBuffer.fromBytes(data);
        expect(buf, isNotNull);
      });
    });

    group('fromList()', () {
      test('creates transferable from multiple chunks', () {
        final chunk1 = Uint8List.fromList([1, 2, 3]);
        final chunk2 = Uint8List.fromList([4, 5, 6]);
        final buf = TransferableBuffer.fromList([chunk1, chunk2]);
        expect(buf, isNotNull);
        expect(buf.transferable, isNotNull);
      });

      test('creates transferable from single chunk list', () {
        final chunk = Uint8List.fromList([10, 20, 30]);
        final buf = TransferableBuffer.fromList([chunk]);
        expect(buf, isNotNull);
      });
    });

    group('materialize()', () {
      test('returns ByteBuffer with correct data', () {
        final data = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
        final buf = TransferableBuffer.fromBytes(data);

        final byteBuffer = TransferableBuffer.materialize(buf.transferable);
        final result = byteBuffer.asUint8List();

        expect(result, orderedEquals([0xDE, 0xAD, 0xBE, 0xEF]));
      });

      test('returns correct length', () {
        final data = Uint8List.fromList(List.generate(100, (i) => i));
        final buf = TransferableBuffer.fromBytes(data);

        final byteBuffer = TransferableBuffer.materialize(buf.transferable);

        expect(byteBuffer.lengthInBytes, 100);
      });
    });

    group('materializeAsBytes()', () {
      test('returns Uint8List with correct data', () {
        final data = Uint8List.fromList([1, 2, 3, 4]);
        final buf = TransferableBuffer.fromBytes(data);

        final result = TransferableBuffer.materializeAsBytes(buf.transferable);

        expect(result, isA<Uint8List>());
        expect(result, orderedEquals([1, 2, 3, 4]));
      });

      test('works with concatenated chunks', () {
        final chunk1 = Uint8List.fromList([10, 20]);
        final chunk2 = Uint8List.fromList([30, 40]);
        final buf = TransferableBuffer.fromList([chunk1, chunk2]);

        final result = TransferableBuffer.materializeAsBytes(buf.transferable);

        expect(result, orderedEquals([10, 20, 30, 40]));
      });
    });

    test(
      'transferable getter returns the underlying TransferableTypedData',
      () {
        final data = Uint8List.fromList([7, 8, 9]);
        final buf = TransferableBuffer.fromBytes(data);
        final transferable = buf.transferable;

        // Verify it is usable by materializing it.
        final bytes = TransferableBuffer.materializeAsBytes(transferable);
        expect(bytes, orderedEquals([7, 8, 9]));
      },
    );
  });
}
