// ABI conformance for the OSGi handshake structs.
//
// dart:ffi cannot read a C header, so the declarations in
// lib/src/osgi_bindings.dart are a hand-written mirror of IhsOsgiPeerInfo and
// IhsOsgiBundleInfo in ivi-homescreen's shared/include/ihs/ihs_osgi.h. Nothing
// connects the two.
//
// `struct_size` does not close the gap. The C forwarder refuses a struct
// smaller than it expects, so a mirror that lost a field is caught -- but a
// field that *moved* keeps the same size, passes that check, and then writes a
// port id over a pointer. That is memory corruption at the boundary, surfacing
// later as an unrelated crash, which is exactly the kind of failure a test has
// to catch before it happens rather than explain afterwards.
//
// The same numbers are asserted from the C side in
// ivi-homescreen's shared/tests/osgi_abi/osgi_abi.c, where they are
// _Static_assert and fail the build. Changing either struct means changing
// both; whichever side is touched first fails.
//
// Offsets are pinned by writing sentinels and reading the memory back, because
// dart:ffi exposes no public offsetOf -- and sizes alone would miss a
// reordering, which is the case that matters.

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:osgi_ffi/src/osgi_bindings.dart';
import 'package:test/test.dart';

/// LP64, which is what ivi-homescreen targets on every supported board. A
/// 32-bit port would fail here rather than silently disagreeing with the C
/// side, which is the correct outcome: the mirrors would need review first.
const int _peerInfoSize = 24;
const int _bundleInfoSize = 40;

void main() {
  group('struct sizes match the C header', () {
    test('IhsOsgiPeerInfo is 24 bytes', () {
      expect(sizeOf<PeerInfo>(), _peerInfoSize);
    });

    test('IhsOsgiBundleInfo is 40 bytes', () {
      expect(sizeOf<BundleInfo>(), _bundleInfoSize);
    });

    // BundleInfo embeds PeerInfo by value, so its size is not independent:
    // 8 (struct_size) + 24 (peer) + 8 (symbolic_name).
    test(
      'BundleInfo accounts for an embedded PeerInfo, not a pointer to one',
      () {
        expect(sizeOf<BundleInfo>(), 8 + _peerInfoSize + 8);
      },
    );
  });

  group('field offsets match the C header', () {
    test('PeerInfo lays out struct_size@0, dart_api_dl_data@8, port@16', () {
      final Pointer<PeerInfo> p = calloc<PeerInfo>();
      try {
        p.ref.structSize = 0x1111111111111111;
        p.ref.dartApiDlData = Pointer<Void>.fromAddress(0x2222222222222222);
        p.ref.port = 0x3333333333333333;

        // Read the same memory as raw 8-byte slots: slot n is offset n * 8.
        final Pointer<Int64> raw = p.cast<Int64>();
        expect(raw[0], 0x1111111111111111, reason: 'struct_size is not at 0');
        expect(
          raw[1],
          0x2222222222222222,
          reason: 'dart_api_dl_data is not at 8',
        );
        expect(raw[2], 0x3333333333333333, reason: 'port is not at 16');
      } finally {
        calloc.free(p);
      }
    });

    test('BundleInfo lays out struct_size@0, peer@8, symbolic_name@32', () {
      final Pointer<BundleInfo> p = calloc<BundleInfo>();
      try {
        p.ref.structSize = 0x4444444444444444;
        // Writing through the embedded peer proves it starts at 8: its own
        // port field sits 16 bytes further in, i.e. slot 3.
        p.ref.peer.structSize = 0x5555555555555555;
        p.ref.peer.port = 0x6666666666666666;
        p.ref.symbolicName = Pointer<Utf8>.fromAddress(0x7777777777777777);

        final Pointer<Int64> raw = p.cast<Int64>();
        expect(raw[0], 0x4444444444444444, reason: 'struct_size is not at 0');
        expect(raw[1], 0x5555555555555555, reason: 'peer does not start at 8');
        expect(
          raw[3],
          0x6666666666666666,
          reason: 'peer.port is not at 8 + 16',
        );
        expect(
          raw[4],
          0x7777777777777777,
          reason: 'symbolic_name is not at 32',
        );
      } finally {
        calloc.free(p);
      }
    });
  });

  // The status values are hardcoded here and in ivi-homescreen's activator
  // fixture, so they are part of the same contract as the layout. The C side
  // asserts them against the enum in the same file that asserts the offsets.
  group('status values match IhsOsgiStatus', () {
    test('the five documented codes are what the C enum defines', () {
      expect(OsgiStatus.ok, 0);
      expect(OsgiStatus.invalid, -1);
      expect(OsgiStatus.dartApi, -2);
      expect(OsgiStatus.rejected, -3);
      expect(OsgiStatus.unavailable, -4);
    });
  });
}
