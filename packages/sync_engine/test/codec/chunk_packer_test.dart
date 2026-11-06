import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/codec/chunk_codec.dart';
import 'package:sync_engine/src/codec/chunk_id.dart';
import 'package:sync_engine/src/codec/chunk_packer.dart';
import 'package:sync_engine/sync_engine.dart';

import '../support/entity_fixtures.dart';

final Hlc v0 = Hlc.parse(hlcText(kT0));

/// A setting record whose encoded length is exactly [length] bytes.
UpsertRecord sizedSetting(String id, int length) {
  UpsertRecord make(int pad) => UpsertRecord(
    SyncDoc(
      kind: EntityKind.setting,
      id: id,
      json: {
        'key': id,
        'valueJson': '"${'x' * pad}"',
        'updatedAt': kT0,
        'deletedAt': null,
        'version': v0.toString(),
      },
    ),
    EntityFieldVersions(v0),
  );
  var pad = 0;
  for (var i = 0; i < 4; i++) {
    final len = ChunkCodec.encodeRecord(make(pad)).length;
    if (len == length) return make(pad);
    pad += length - len;
    if (pad < 0) throw ArgumentError('length $length is too small');
  }
  final r = make(pad);
  expect(ChunkCodec.encodeRecord(r).length, length);
  return r;
}

PurgeRecord purge(String id, [int dt = 0]) =>
    PurgeRecord(EntityRef(EntityKind.note, id), Hlc.parse(hlcText(kT0 + dt)));

UpsertRecord upsert(EntityKind kind, String id) {
  final json = fixtureJson(kind, id: id);
  return UpsertRecord(
    SyncDoc(kind: kind, id: id, json: json),
    EntityFieldVersions(v0),
  );
}

PackItem<String> item(SyncRecord r, [String scope = 'lib']) =>
    PackItem(r, scope: scope, tag: r.ref.id);

ChunkPacker packer([SyncConfig config = const SyncConfig()]) =>
    ChunkPacker(config: config, authorNodeId: kNodeA);

List<PackedChunk<String>> chunksOf(PackResult<String> r) => [
  for (final c in r.commits) ...c.chunks,
];

void main() {
  group('chunks', () {
    test('one chunk per scope, scopes in sorted order', () {
      final result = packer().pack([
        item(upsert(EntityKind.stroke, 's1'), 'n2'),
        item(upsert(EntityKind.note, 'n1')),
        item(upsert(EntityKind.page, 'p1'), 'n1'),
        item(upsert(EntityKind.stroke, 's2'), 'n1'),
      ]);
      final chunks = chunksOf(result);
      expect([for (final c in chunks) c.write.scope], ['lib', 'n1', 'n2']);
      expect(
        [for (final c in chunks) c.items.map((i) => i.tag).toList()],
        [
          ['n1'],
          ['p1', 's2'],
          ['s1'],
        ],
      );
      expect(result.commits, hasLength(1));
      expect(result.tooLarge, isEmpty);
    });

    test('records sort by kind order, then id — payload is deterministic', () {
      final records = <SyncRecord>[
        upsert(EntityKind.stroke, 's1'),
        upsert(EntityKind.recording, 'r1'),
        upsert(EntityKind.asset, 'a1'),
        upsert(EntityKind.setting, 'k.1'),
        upsert(EntityKind.penPreset, 'pp1'),
        upsert(EntityKind.page, 'p1'),
        upsert(EntityKind.note, 'n1'),
        purge('n0'),
        upsert(EntityKind.folder, 'f2'),
        upsert(EntityKind.folder, 'f1'),
      ];
      final expected = [
        'f1', 'f2', 'n0', 'n1', 'p1', 'pp1', 'k.1', 'a1', 'r1', 's1', //
      ];
      final first = chunksOf(packer().pack([for (final r in records) item(r)]));
      expect(first, hasLength(1));
      expect([for (final i in first.single.items) i.tag], expected);
      expect([
        for (final r in ChunkCodec.decode(first.single.write.payload)) r.ref.id,
      ], expected);
      final random = Random(7);
      for (var round = 0; round < 5; round++) {
        final shuffled = [...records]..shuffle(random);
        final again = chunksOf(
          packer().pack([for (final r in shuffled) item(r)]),
        );
        expect(again.single.write.id, first.single.write.id);
        expect(again.single.write.payload, first.single.write.payload);
      }
    });

    // (2nd round, S2-2, contract 7.2.8) … stroke, pageObject, handwriting.
    test('kind order is the contract 7.2.8 list', () {
      // folder, note, page, penPreset, setting, asset, recording, stroke, pageObject,
      // handwriting.
      expect(ChunkPacker.kindOrder, const [
        EntityKind.folder,
        EntityKind.note,
        EntityKind.page,
        EntityKind.penPreset,
        EntityKind.setting,
        EntityKind.asset,
        EntityKind.recording,
        EntityKind.stroke,
        EntityKind.pageObject,
        EntityKind.handwriting,
      ]);
      expect(ChunkPacker.kindOrder.toSet(), EntityKind.values.toSet());
    });

    test('a note scope with the new kinds: page, recording, strokes, objects, '
        'handwriting — deterministic payload', () {
      final records = <SyncRecord>[
        upsert(EntityKind.handwriting, 'hw_p1'),
        upsert(EntityKind.pageObject, 'o2'),
        upsert(EntityKind.stroke, 's1'),
        upsert(EntityKind.pageObject, 'o1'),
        upsert(EntityKind.recording, 'r1'),
        upsert(EntityKind.page, 'p1'),
        upsert(EntityKind.handwriting, 'hw_p0'),
      ];
      final expected = ['p1', 'r1', 's1', 'o1', 'o2', 'hw_p0', 'hw_p1'];
      final first = chunksOf(
        packer().pack([for (final r in records) item(r, 'n1')]),
      );
      expect(first, hasLength(1));
      expect(first.single.write.scope, 'n1');
      expect([for (final i in first.single.items) i.tag], expected);
      final decoded = ChunkCodec.decode(first.single.write.payload);
      expect([for (final r in decoded) r.ref.id], expected);
      expect(decoded, [
        for (final id in expected) records.firstWhere((r) => r.ref.id == id),
      ]);
      final random = Random(11);
      for (var round = 0; round < 5; round++) {
        final shuffled = [...records]..shuffle(random);
        final again = chunksOf(
          packer().pack([for (final r in shuffled) item(r, 'n1')]),
        );
        expect(again.single.write.id, first.single.write.id);
        expect(again.single.write.payload, first.single.write.payload);
      }
    });

    test('new kinds carry no blobs: header JSON only', () {
      for (final kind in [EntityKind.pageObject, EntityKind.handwriting]) {
        expect(ChunkCodec.blobKeys, isNot(contains(kind)));
        final r = upsert(kind, kind == EntityKind.handwriting ? 'hw_p1' : 'o1');
        final bytes = ChunkCodec.encodeRecord(r);
        // op, varuint header length, header, blobCount 0.
        expect(bytes.last, 0, reason: kind.name);
      }
    });

    test('ChunkWrite fields', () {
      final records = [purge('n1', 5), purge('n2', 9), purge('n3', 1)];
      final c = chunksOf(
        packer().pack([
          for (final r in records) item(r),
        ], kind: ChunkKind.snapshot),
      ).single.write;
      expect(c.id, chunkIdOf(kNodeA, c.payload));
      expect(c.authorNodeId, kNodeA);
      expect(c.recordCount, 3);
      expect(c.format, ChunkCodec.formatVersion);
      expect(c.kind, ChunkKind.snapshot);
      expect(c.maxHlc, hlcText(kT0 + 9));
      expect(ChunkCodec.decode(c.payload), records);
    });

    test('soft limit: a payload of exactly the limit stays one chunk', () {
      const config = SyncConfig(chunkSoftLimitBytes: 1000);
      // payload = 3 + varuint(2) + a + b
      final fits = packer(
        config,
      ).pack([item(sizedSetting('a.1', 500)), item(sizedSetting('a.2', 496))]);
      expect(chunksOf(fits), hasLength(1));
      expect(chunksOf(fits).single.write.payload, hasLength(1000));
      final over = packer(
        config,
      ).pack([item(sizedSetting('a.1', 500)), item(sizedSetting('a.2', 497))]);
      expect([for (final c in chunksOf(over)) c.write.recordCount], [1, 1]);
    });

    test('soft limit: records fill chunks in order', () {
      const config = SyncConfig(chunkSoftLimitBytes: 1000);
      final result = packer(config)
          .pack([for (var i = 0; i < 7; i++) item(sizedSetting('b.$i', 300))]);
      expect(
        [for (final c in chunksOf(result)) c.write.recordCount],
        [3, 3, 1],
      );
      for (final c in chunksOf(result)) {
        expect(c.write.payload.length, lessThanOrEqualTo(1000));
      }
    });

    test('default soft limit is 256 KiB', () {
      final result = packer().pack([
        item(sizedSetting('c.1', 200000)),
        item(sizedSetting('c.2', 62140)),
        item(sizedSetting('c.3', 250)),
      ]);
      final chunks = chunksOf(result);
      expect([for (final c in chunks) c.write.recordCount], [2, 1]);
      expect(chunks.first.write.payload, hasLength(262144));
    });

    test('a record larger than the soft limit gets a chunk of its own', () {
      const config = SyncConfig(chunkSoftLimitBytes: 1000);
      final result = packer(config).pack([
        item(sizedSetting('d.1', 250)),
        item(sizedSetting('d.2', 1500)),
        item(sizedSetting('d.3', 250)),
      ]);
      expect(
        [for (final c in chunksOf(result)) c.items.map((i) => i.tag)],
        [
          ['d.1'],
          ['d.2'],
          ['d.3'],
        ],
      );
    });

    test('2,000 records per chunk', () {
      final exactly = packer().pack([
        for (var i = 0; i < 2000; i++) item(purge('n${i + 10000}')),
      ]);
      expect([for (final c in chunksOf(exactly)) c.write.recordCount], [2000]);
      final more = packer().pack([
        for (var i = 0; i < 2001; i++) item(purge('n${i + 10000}')),
      ]);
      expect([for (final c in chunksOf(more)) c.write.recordCount], [2000, 1]);
    });
  });

  group('hard limit', () {
    test('a single-record chunk over the hard limit is quarantined', () {
      const config = SyncConfig(chunkHardLimitBytes: 2000);
      // payload of one record = 4 + length
      final result = packer(config).pack([
        item(sizedSetting('e.ok', 1996)),
        item(sizedSetting('e.big', 1997)),
        item(sizedSetting('e.small', 250)),
      ]);
      expect([for (final i in result.tooLarge) i.tag], ['e.big']);
      final sent = [
        for (final c in chunksOf(result)) ...c.items.map((i) => i.tag),
      ];
      expect(sent, unorderedEquals(['e.ok', 'e.small']));
    });

    test('default hard limit is 1,000,000 bytes', () {
      final result = packer().pack([
        item(sizedSetting('f.ok', 999996)),
        item(sizedSetting('f.big', 999997)),
      ]);
      expect([for (final i in result.tooLarge) i.tag], ['f.big']);
      expect(chunksOf(result).single.write.payload, hasLength(1000000));
    });
  });

  group('commits', () {
    test('at most 16 chunks per commit', () {
      final result = packer().pack([
        for (var i = 0; i < 17; i++)
          item(
            upsert(EntityKind.page, 'p$i'),
            'n${i.toString().padLeft(2, '0')}',
          ),
      ]);
      expect([for (final c in result.commits) c.chunks.length], [16, 1]);
      final exactly = packer().pack([
        for (var i = 0; i < 16; i++)
          item(
            upsert(EntityKind.page, 'p$i'),
            'n${i.toString().padLeft(2, '0')}',
          ),
      ]);
      expect([for (final c in exactly.commits) c.chunks.length], [16]);
    });

    test('at most maxBytesPerCommit bytes per commit', () {
      const config = SyncConfig(
        chunkSoftLimitBytes: 1000,
        maxBytesPerCommit: 3000,
      );
      // four chunks of exactly 1000 bytes (one 996-byte record each)
      final result = packer(config).pack([
        for (var i = 0; i < 4; i++) item(sizedSetting('g.$i', 996), 's$i'),
      ]);
      expect([for (final c in result.commits) c.chunks.length], [3, 1]);
      expect(result.commits.first.bytes, 3000);
    });

    test('default 8 MiB per commit', () {
      final result = packer().pack([
        for (var i = 0; i < 9; i++) item(sizedSetting('h.$i', 950000), 's$i'),
      ]);
      expect([for (final c in result.commits) c.chunks.length], [8, 1]);
      expect(result.commits.first.bytes, lessThanOrEqualTo(8 * 1024 * 1024));
    });
  });
}
