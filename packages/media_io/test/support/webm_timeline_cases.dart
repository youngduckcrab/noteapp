// The hand-sample cases of the WebM timeline (m5-7/06-pdf 6.8.7 last paragraph; 8.2 T32a):
// the VM test (unit/webm_timeline_test) and Chrome (web/pure_logic_browser_test — dart2js
// numbers) run the same assertions.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_io/src/record/webm_timeline.dart';
import 'package:media_io/src/tuning.dart';

import 'webm_builder.dart';

/// [count] 60 ms blocks in clusters of 17 (≈ 1 s, like Chrome: cluster timecodes 0, 1020, …).
List<Uint8List> chromeLikeClusters(int count, {bool unknownSize = true}) {
  final out = <Uint8List>[];
  for (var start = 0; start < count; start += 17) {
    final n = start + 17 > count ? count - start : 17;
    out.add(cluster(start * 60, blocks(n), unknownSize: unknownSize));
  }
  return out;
}

/// Every hand-sample group.
void webmTimelineCases() {
  group('measure — hand samples', () {
    test(
      'unknown-size Segment and Clusters, Opus code 3 × 3 frames of 20 ms',
      () {
        final file = webmFile(clusters: chromeLikeClusters(34));
        expect(WebmTimeline.measure(file), (
          lastBlockStartMs: 1980,
          endMs: 2040,
          packetMs: 60,
        ));
      },
    );

    test('known-size Segment and Clusters', () {
      final file = webmFile(
        clusters: chromeLikeClusters(34, unknownSize: false),
        segmentSizeLength: 8,
      );
      expect(WebmTimeline.measure(file)?.endMs, 2040);
      final short = webmFile(
        clusters: chromeLikeClusters(5, unknownSize: false),
        segmentSizeLength: 4,
      );
      expect(WebmTimeline.measure(short)?.endMs, 300);
    });

    test('TimecodeScale 1 ms and 1 µs', () {
      final ms = webmFile(
        clusters: [
          cluster(5000, [simpleBlock(0), simpleBlock(500)]),
        ],
      );
      expect(WebmTimeline.measure(ms), (
        lastBlockStartMs: 5500,
        endMs: 5560,
        packetMs: 60,
      ));
      // 1 µs ticks: Cluster timecodes and int16 block offsets in µs.
      final us = webmFile(
        timecodeScale: 1000,
        clusters: [
          for (var i = 0; i < 10; i++)
            cluster(i * 60000, [simpleBlock(0), simpleBlock(30000)]),
        ],
      );
      expect(WebmTimeline.measure(us), (
        lastBlockStartMs: 570,
        endMs: 630,
        packetMs: 60,
      ));
    });

    test('BlockGroup + BlockDuration wins over the TOC', () {
      final file = webmFile(
        clusters: [
          cluster(0, [simpleBlock(0), blockGroup(60, duration: 100)]),
        ],
      );
      expect(WebmTimeline.measure(file), (
        lastBlockStartMs: 60,
        endMs: 160,
        packetMs: 100,
      ));
      // A BlockGroup without BlockDuration reads the TOC like a SimpleBlock.
      final noDuration = webmFile(
        clusters: [
          cluster(0, [blockGroup(60)]),
        ],
      );
      expect(WebmTimeline.measure(noDuration)?.endMs, 120);
    });

    test('Opus TOC: code 0 = 1 frame, code 1 / 2 = 2 frames, code 3 = the count byte', () {
      int? end(List<int> packet) => WebmTimeline.measure(
        webmFile(
          clusters: [
            cluster(1000, [simpleBlock(0, packet: packet)]),
          ],
        ),
      )?.endMs;
      expect(end(opusPacket(config: 31, code: 0)), 1020); // CELT 20 ms
      expect(end(opusPacket(config: 3, code: 0)), 1060); // SILK 60 ms
      expect(end(opusPacket(config: 1, code: 1)), 1040); // SILK 20 ms × 2
      expect(end(opusPacket(config: 13, code: 2)), 1040); // Hybrid 20 ms × 2
      expect(
        end(opusPacket(config: 16, code: 3, frames: 4)),
        1010,
      ); // 2.5 ms × 4
      expect(end(opusPacket(config: 27, code: 3, frames: 3)), 1060);
      expect(
        end(opusPacket(config: 22, code: 3, frames: 6)),
        1060,
      ); // 10 ms × 6
    });

    test('no readable TOC → DefaultDuration → opusDefaultPacketMs', () {
      // An empty packet has no TOC.
      final withDefault = webmFile(
        defaultDurationNs: 40000000,
        clusters: [
          cluster(0, [simpleBlock(100, packet: const [])]),
        ],
      );
      expect(WebmTimeline.measure(withDefault)?.packetMs, 40);
      final bare = webmFile(
        clusters: [
          cluster(0, [simpleBlock(100, packet: const [])]),
        ],
      );
      expect(
        WebmTimeline.measure(bare)?.packetMs,
        MediaTuning.opusDefaultPacketMs,
      );
      // Not Opus: DefaultDuration without looking at the first byte.
      final vorbis = webmFile(
        codecId: 'A_VORBIS',
        defaultDurationNs: 23000000,
        clusters: [
          cluster(0, [simpleBlock(100)]),
        ],
      );
      expect(WebmTimeline.measure(vorbis)?.endMs, 123);
    });

    test('a cut last block is dropped — the one before it counts', () {
      final file = webmFile(clusters: chromeLikeClusters(34));
      for (final cut in [1, 5, 9]) {
        expect(WebmTimeline.measure(cutEnd(file, cut)), (
          lastBlockStartMs: 1920,
          endMs: 1980,
          packetMs: 60,
        ), reason: 'cut $cut');
      }
    });

    test('the last Cluster holds only a cut block → the previous Cluster', () {
      final file = webmFile(
        clusters: [cluster(0, blocks(17)), cluster(1020, blocks(1))],
      );
      expect(WebmTimeline.measure(file)?.endMs, 1080);
      final cut = cutEnd(file, 3);
      expect(WebmTimeline.measure(cut), (
        lastBlockStartMs: 960,
        endMs: 1020,
        packetMs: 60,
      ));
      // Cut inside the last Cluster's Timecode / its header.
      final header = cluster(1020, const []).length;
      expect(
        WebmTimeline.measure(cutEnd(file, blocks(1).single.length + 2))?.endMs,
        1020,
      );
      expect(
        WebmTimeline.measure(cutEnd(file, blocks(1).single.length + header - 2))
            ?.endMs,
        1020,
      );
    });

    test(
      'a Cluster longer than the tail window → walks from the first Cluster',
      () {
        // 600 blocks of ~520 B in one Cluster (> 256 KiB); no Cluster ID in the last 256 KiB.
        // 50 ms apart so the int16 block offsets stay below 32,768.
        final big = cluster(0, blocks(600, filler: 500, stepMs: 50));
        expect(big.length, greaterThan(MediaTuning.webmTailScanBytes));
        final file = webmFile(clusters: [big]);
        expect(WebmTimeline.measure(file), (
          lastBlockStartMs: 29950,
          endMs: 30010,
          packetMs: 60,
        ));
        // The same walk when the window is smaller than one Chrome cluster.
        final chrome = webmFile(clusters: chromeLikeClusters(34));
        expect(WebmTimeline.measure(chrome, tailScanBytes: 64)?.endMs, 2040);
      },
    );

    test('a Cluster ID inside block data is not taken for a Cluster', () {
      final fake = [0x1F, 0x43, 0xB6, 0x75, 0x81, 0xE7, 0x81, 0x00];
      final packet = [...opusPacket(), ...fake, 0, 0, 0];
      final file = webmFile(
        clusters: [
          cluster(0, [...blocks(5), simpleBlock(300, packet: packet)]),
        ],
      );
      expect(WebmTimeline.measure(file), (
        lastBlockStartMs: 300,
        endMs: 360,
        packetMs: 60,
      ));
    });

    test('blocks of another track and Cues after the last Cluster', () {
      final file = webmFile(
        withCues: true,
        clusters: [
          cluster(0, [
            ...blocks(3),
            simpleBlock(500, track: 2),
          ], unknownSize: false),
        ],
      );
      expect(WebmTimeline.measure(file)?.endMs, 180);
    });

    test('Duration present or absent does not change the timeline', () {
      final without = webmFile(clusters: chromeLikeClusters(34));
      final withDuration = webmFile(
        clusters: chromeLikeClusters(34),
        duration: 99,
      );
      expect(WebmTimeline.measure(withDuration), WebmTimeline.measure(without));
    });

    test('SeekHead + Void before the Clusters', () {
      final file = webmFile(
        withSeekHead: true,
        voidAfterInfo: 20,
        clusters: chromeLikeClusters(34),
      );
      expect(WebmTimeline.measure(file)?.endMs, 2040);
    });

    test('not a WebM, or no complete block → null', () {
      expect(WebmTimeline.measure(Uint8List(0)), isNull);
      expect(WebmTimeline.measure(Uint8List.fromList([1, 2, 3, 4, 5])), isNull);
      expect(WebmTimeline.measure(webmFile(clusters: const [])), isNull);
      expect(
        WebmTimeline.measure(webmFile(clusters: [cluster(0, const [])])),
        isNull,
      );
      final one = webmFile(clusters: [cluster(0, blocks(1))]);
      expect(WebmTimeline.measure(cutEnd(one, 2)), isNull);
    });
  });

  group('patchedHead', () {
    test(
      'Chrome layout: Duration appended to Info, unknown Segment size kept',
      () {
        final original = webmFile(clusters: chromeLikeClusters(34));
        final patch = WebmTimeline.patchedHead(original, 2040)!;
        final expected = webmFile(
          clusters: chromeLikeClusters(34),
          duration: 2040,
        );
        expect(applyPatch(original, patch), expected);
        // head = file start … Info end, 11 bytes longer.
        expect(patch.bytes.length, patch.restOffset + 11);
        expect(WebmTimeline.measure(applyPatch(original, patch)), (
          lastBlockStartMs: 1980,
          endMs: 2040,
          packetMs: 60,
        ));
      },
    );

    test('a known Segment size grows by 11 in a vint of the same length', () {
      for (final length in [4, 8]) {
        final original = webmFile(
          clusters: chromeLikeClusters(5, unknownSize: false),
          segmentSizeLength: length,
        );
        final patch = WebmTimeline.patchedHead(original, 300)!;
        expect(
          applyPatch(original, patch),
          webmFile(
            clusters: chromeLikeClusters(5, unknownSize: false),
            segmentSizeLength: length,
            duration: 300,
          ),
          reason: 'segment size vint $length bytes',
        );
      }
    });

    test('an existing Duration only gets its value', () {
      final original = webmFile(
        clusters: chromeLikeClusters(34),
        duration: 1234,
      );
      final patch = WebmTimeline.patchedHead(original, 2040)!;
      expect(patch.bytes.length, patch.restOffset);
      expect(
        applyPatch(original, patch),
        webmFile(clusters: chromeLikeClusters(34), duration: 2040),
      );
    });

    test('TimecodeScale 1 µs: Duration in ticks', () {
      List<Uint8List> clusters() => [
        cluster(0, [simpleBlock(0), simpleBlock(30000)]),
      ];
      final original = webmFile(timecodeScale: 1000, clusters: clusters());
      final patch = WebmTimeline.patchedHead(original, 90)!;
      expect(
        applyPatch(original, patch),
        webmFile(timecodeScale: 1000, clusters: clusters(), duration: 90000),
      );
    });

    test('Info size vint that needs another byte', () {
      final long =
          'W' * 100; // Info body 119 B → 130 B: the 1-byte size vint becomes 2
      final original = webmFile(
        clusters: chromeLikeClusters(3),
        writingApp: long,
      );
      final patch = WebmTimeline.patchedHead(original, 180)!;
      expect(patch.bytes.length, patch.restOffset + 12);
      expect(
        applyPatch(original, patch),
        webmFile(
          clusters: chromeLikeClusters(3),
          writingApp: long,
          duration: 180,
        ),
      );
    });

    test('SeekHead + Void: the Void shrinks so no position moves', () {
      final original = webmFile(
        withSeekHead: true,
        voidAfterInfo: 20,
        clusters: chromeLikeClusters(34),
      );
      final patch = WebmTimeline.patchedHead(original, 2040)!;
      expect(patch.bytes.length, patch.restOffset); // same length
      final patched = applyPatch(original, patch);
      expect(patched.length, original.length);
      expect(
        patched,
        webmFile(
          withSeekHead: true,
          voidAfterInfo: 9,
          clusters: chromeLikeClusters(34),
          duration: 2040,
        ),
      );
      expect(WebmTimeline.measure(patched)?.endMs, 2040);
      // A Void of exactly 11 bytes goes away.
      final exact = webmFile(
        withSeekHead: true,
        voidAfterInfo: 11,
        clusters: chromeLikeClusters(3),
      );
      expect(
        applyPatch(exact, WebmTimeline.patchedHead(exact, 180)!),
        webmFile(
          withSeekHead: true,
          clusters: chromeLikeClusters(3),
          duration: 180,
        ),
      );
      // 12 bytes would leave 1 — no element is 1 byte long.
      final twelve = webmFile(
        withSeekHead: true,
        voidAfterInfo: 12,
        clusters: chromeLikeClusters(3),
      );
      expect(WebmTimeline.patchedHead(twelve, 180), isNull);
      final small = webmFile(
        withSeekHead: true,
        voidAfterInfo: 10,
        clusters: chromeLikeClusters(3),
      );
      expect(WebmTimeline.patchedHead(small, 180), isNull);
    });

    test('SeekHead without a Void → not patched', () {
      final file = webmFile(
        withSeekHead: true,
        clusters: chromeLikeClusters(34),
      );
      expect(WebmTimeline.patchedHead(file, 2040), isNull);
      expect(WebmTimeline.measure(file)?.endMs, 2040);
    });

    test('not a WebM → null', () {
      expect(WebmTimeline.patchedHead(Uint8List(16), 1000), isNull);
    });
  });
}
