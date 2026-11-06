#!/usr/bin/env python3
# Writes test/goldens/chunk_v1_kinds_golden.bin and the Dart copy
# test/shared/chunk_v1_kinds_golden_bytes.dart (07-sync 6.2.3, S2-2), separately from
# the Dart encoder: change chunk codec v1 (6.4.4) with the 2nd-round kinds and one
# record of a kind this app does not know ('bookmark', as a newer app would write it).
#
# Run once from packages/sync_engine with `python3 -I test/goldens/make_chunk_kinds_golden.py`.
# Tests never run it; goldens/chunk_v1_kinds_golden_test.dart checks that the Dart
# encoder writes the same bytes. Doubles are non-integral only, so the bytes are the
# same on the VM and in Chrome (web jsonEncode writes 100.0 as 100).
import json
import os
import sys

T0 = 1793750400000
NODE = '3f2a9c0d11e0b7a4'


def hlc(millis, counter=0, node=NODE):
    return '%015d-%04x-%s' % (millis, counter, node)


V0 = hlc(T0)
V1 = hlc(T0 + 5000, 1)


def canonical(value):
    # Keys sorted at every level, no whitespace, UTF-8 as is (Dart jsonEncode).
    return json.dumps(value, sort_keys=True, separators=(',', ':'),
                      ensure_ascii=False, allow_nan=False)


def varuint(n):
    # Unsigned LEB128, at most 5 bytes (CORE 6.2.4).
    assert 0 <= n <= 128 ** 5 - 1
    out = bytearray()
    while n >= 128:
        out.append(n % 128 + 128)
        n //= 128
    out.append(n)
    return bytes(out)


def upsert(kind, entity, fv):
    # op 0x01, varuint header length, header, varuint blobCount (no blob keys here).
    header = canonical({'e': entity, 'fv': fv, 'id': entity['id'], 'k': kind})
    data = header.encode('utf-8')
    assert len(data) <= 1000000
    return b'\x01' + varuint(len(data)) + data + varuint(0)


def records():
    # Payload order = ChunkPacker.kindOrder inside scope n1 (contract 7.2.8): page,
    # recording, pageObject (by id), handwriting; the unknown kind last.
    page = {
        'id': 'p1', 'noteId': 'n1', 'sortKey': 'a1', 'size': [540.5, 960.5],
        'background': {'type': 'blank', 'paperColor': 4294967295},
        'createdAt': T0, 'updatedAt': T0, 'deletedAt': None, 'version': V0,
    }
    recording = {
        'id': 'r1', 'noteId': 'n1',
        'assetId': 'a54b81412d4c4ab56653bb9e4c02912b0820bb37e2bba00722ddef4d78083d4a',
        'durationMs': 61000, 'startedAt': T0 - 61000, 'title': '1교시 녹음',
        'createdAt': T0, 'updatedAt': T0 + 5000, 'deletedAt': None, 'version': V1,
    }
    shape = {
        'id': 'o-shape', 'pageId': 'p1', 'type': 'shape',
        'frame': [100.5, 100.5, 300.5, 220.5, 0.25], 'shape': 'rectangle',
        'geometry': {'closed': True,
                     'poly': [100.5, 100.5, 300.5, 100.5, 300.5, 220.5, 100.5, 220.5]},
        'style': {'strokeColorArgb': 4279900698, 'strokeWidth': 2.5, 'strokeOpacity': 0.75,
                  'fillColorArgb': None, 'fillOpacity': 0.5, 'dash': 'solid',
                  'arrowHeads': 'none'},
        'createdAt': T0, 'updatedAt': T0, 'deletedAt': None, 'version': V0,
    }
    text = {
        'id': 'o-text', 'pageId': 'p1', 'type': 'text',
        'frame': [100.5, 300.5, 400.5, 340.5, 0.25], 'text': '안녕 hello',
        'style': {'fontSizePt': 16.5, 'colorArgb': 4279900698, 'bold': False,
                  'align': 'start', 'lineHeight': 1.4, 'backgroundArgb': None},
        'createdAt': T0, 'updatedAt': T0 + 5000, 'deletedAt': None, 'version': V1,
    }
    handwriting = {
        'id': 'hw_p1', 'noteId': 'n1', 'pageId': 'p1',
        'engineId': 'mlkit-digital-ink/19.0.0:ko', 'sourceRev': '0123456789abcdef',
        'lines': [
            {'text': '미분 방정식', 'alternatives': ['미분 방정석', '미분방정식'],
             'languageTag': 'ko', 'rect': [40.5, 80.5, 320.5, 120.5],
             'strokeIds': ['s1', 's2'], 'userConfirmed': False},
        ],
        'createdAt': T0, 'updatedAt': T0, 'deletedAt': None, 'version': V0,
    }
    bookmark = {
        'id': 'b1', 'noteId': 'n1', 'pageId': 'p1', 'label': '1장', 'y': 120.5,
        'createdAt': T0, 'updatedAt': T0, 'deletedAt': None, 'version': V0,
    }
    return [
        upsert('page', page, {'b': V0}),
        upsert('recording', recording, {'b': V0, 'o': {'title': V1}}),
        upsert('pageObject', shape, {'b': V0}),
        upsert('pageObject', text, {'b': V0, 'o': {'frame': V1, 'text': V1}}),
        upsert('handwriting', handwriting, {'b': V0}),
        upsert('bookmark', bookmark, {'b': V0}),
    ]


def main():
    recs = records()
    payload = b'NC\x01' + varuint(len(recs)) + b''.join(recs)
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, 'chunk_v1_kinds_golden.bin'), 'wb') as f:
        f.write(payload)
    lines = [
        '// Dart constant copy of test/goldens/chunk_v1_kinds_golden.bin (07-sync 6.2.3)',
        '// for Chrome, which cannot read files. Written by',
        '// test/goldens/make_chunk_kinds_golden.py; goldens/chunk_v1_kinds_golden_test.dart',
        '// (VM) checks that this list equals the file byte for byte.',
        '// dart format off',
        'const List<int> kChunkV1KindsGolden = [',
    ]
    for i in range(0, len(payload), 12):
        row = payload[i:i + 12]
        lines.append('  ' + ', '.join('0x%02X' % b for b in row) + ',')
    lines += ['];', '// dart format on', '']
    with open(os.path.join(here, '..', 'shared', 'chunk_v1_kinds_golden_bytes.dart'),
              'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines))
    print('%d bytes, %d records, record lengths %s'
          % (len(payload), len(recs), [len(r) for r in recs]))


if __name__ == '__main__':
    sys.exit(main())
