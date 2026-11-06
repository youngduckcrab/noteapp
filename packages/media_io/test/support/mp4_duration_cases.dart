// The MP4 / fragmented MP4 length cases (m5-7/06-pdf 6.6.4; 8.2 T32a — review S-7): hand-made
// boxes. The VM test (unit/mp4_duration_test) and Chrome (web/pure_logic_browser_test — dart2js
// numbers, 64-bit fields read as hi × 2^32 + lo) run the same assertions.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_io/src/record/mp4_duration.dart';

List<int> u32(int v) => [
  (v ~/ 16777216) % 256,
  (v ~/ 65536) % 256,
  (v ~/ 256) % 256,
  v % 256,
];

List<int> u64(int v) => [...u32(v ~/ 4294967296), ...u32(v % 4294967296)];

/// A box: 32-bit size, type, body.
List<int> box(String type, List<int> body) => [
  ...u32(8 + body.length),
  ...type.codeUnits,
  ...body,
];

/// A box with a 64-bit size (size field = 1).
List<int> largeBox(String type, List<int> body) => [
  ...u32(1),
  ...type.codeUnits,
  ...u64(16 + body.length),
  ...body,
];

/// A full box: version, 24-bit flags, body.
List<int> fullBox(
  String type,
  List<int> body, {
  int version = 0,
  int flags = 0,
}) => box(type, [version, ...u32(flags).sublist(1), ...body]);

List<int> mvhd({
  required int timescale,
  required int duration,
  int version = 0,
}) => fullBox('mvhd', version: version, [
  ...(version == 1 ? u64(0) : u32(0)), // creation
  ...(version == 1 ? u64(0) : u32(0)), // modification
  ...u32(timescale),
  ...(version == 1 ? u64(duration) : u32(duration)),
  ...List<int>.filled(80, 0), // rate, volume, matrix, next_track_ID
]);

List<int> mehd(int fragmentDuration, {int version = 0}) => fullBox(
  'mehd',
  version: version,
  version == 1 ? u64(fragmentDuration) : u32(fragmentDuration),
);

List<int> trex({required int track, int defaultDuration = 0}) => fullBox(
  'trex',
  [...u32(track), ...u32(1), ...u32(defaultDuration), ...u32(0), ...u32(0)],
);

/// A trak: tkhd (track id), mdia (mdhd timescale, hdlr handler).
List<int> trak({
  required int track,
  required int timescale,
  String handler = 'soun',
  int version = 0,
}) => box('trak', [
  ...fullBox('tkhd', version: version, flags: 3, [
    ...(version == 1 ? u64(0) : u32(0)),
    ...(version == 1 ? u64(0) : u32(0)),
    ...u32(track),
    ...u32(0),
    ...(version == 1 ? u64(0) : u32(0)),
    ...List<int>.filled(60, 0),
  ]),
  ...box('mdia', [
    ...fullBox('mdhd', version: version, [
      ...(version == 1 ? u64(0) : u32(0)),
      ...(version == 1 ? u64(0) : u32(0)),
      ...u32(timescale),
      ...(version == 1 ? u64(0) : u32(0)),
      ...u32(0x55C40000), // language + pre_defined
    ]),
    ...fullBox('hdlr', [...u32(0), ...handler.codeUnits, ...u32(0), 0]),
  ]),
]);

/// tfhd with the optional fields its flags name (0x01 base_data_offset, 0x02 description,
/// 0x08 default duration).
List<int> tfhd({
  required int track,
  int? defaultDuration,
  bool baseDataOffset = false,
  bool descriptionIndex = false,
}) {
  var flags = 0x020000; // default-base-is-moof
  if (baseDataOffset) flags += 0x01;
  if (descriptionIndex) flags += 0x02;
  if (defaultDuration != null) flags += 0x08;
  return fullBox('tfhd', flags: flags, [
    ...u32(track),
    if (baseDataOffset) ...u64(1234),
    if (descriptionIndex) ...u32(1),
    if (defaultDuration != null) ...u32(defaultDuration),
  ]);
}

/// trun: [durations] per sample (flag 0x100) with sizes (0x200), or [count] samples without.
List<int> trun({List<int>? durations, int count = 0}) {
  var flags = 0x01 + 0x200; // data_offset, sample sizes
  if (durations != null) flags += 0x100;
  final n = durations?.length ?? count;
  return fullBox('trun', flags: flags, [
    ...u32(n),
    ...u32(0), // data_offset
    for (var i = 0; i < n; i++) ...[
      if (durations != null) ...u32(durations[i]),
      ...u32(100), // sample size
    ],
  ]);
}

List<int> moof(List<List<int>> trafs) => box('moof', [
  ...fullBox('mfhd', u32(1)),
  for (final t in trafs) ...box('traf', t),
]);

List<int> mdat([int length = 32]) => box('mdat', List<int>.filled(length, 7));

final _ftyp = box('ftyp', [
  ...'iso5'.codeUnits,
  ...u32(512),
  ...'iso6mp41'.codeUnits,
]);

/// Safari-like fragmented MP4: mvhd duration 0, one audio trak, mvex/trex, then moof + mdat.
Uint8List fragmented(
  List<List<int>> fragments, {
  int timescale = 48000,
  int trexDefault = 1024,
  List<int> extraMvex = const [],
  List<List<int>> traks = const [],
}) => Uint8List.fromList([
  ..._ftyp,
  ...box('moov', [
    ...mvhd(timescale: 1000, duration: 0),
    if (traks.isEmpty) ...trak(track: 1, timescale: timescale),
    for (final t in traks) ...t,
    ...box('mvex', [
      ...extraMvex,
      ...trex(track: 1, defaultDuration: trexDefault),
    ]),
  ]),
  for (final f in fragments) ...f,
]);

void mp4DurationCases() {
  test('moov/mvhd duration ÷ timescale (version 0 and 1)', () {
    final v0 = Uint8List.fromList([
      ..._ftyp,
      ...box('moov', [...mvhd(timescale: 1000, duration: 2500)]),
      ...mdat(),
    ]);
    expect(Mp4Duration.measure(v0), 2500);
    final v1 = Uint8List.fromList([
      ..._ftyp,
      ...mdat(),
      ...box('moov', [
        ...mvhd(timescale: 48000, duration: 96000, version: 1),
      ]), // moov after mdat
    ]);
    expect(Mp4Duration.measure(v1), 2000);
    // 64-bit duration above 2^32 (read as hi × 2^32 + lo).
    final big = Uint8List.fromList([
      ...box('moov', [
        ...mvhd(timescale: 1000000, duration: 5000000000, version: 1),
      ]),
    ]);
    expect(Mp4Duration.measure(big), 5000000);
  });

  test('mvhd 0 → mvex/mehd fragment_duration (version 0 and 1)', () {
    final v0 = fragmented([], extraMvex: mehd(3000));
    expect(Mp4Duration.measure(v0), 3000);
    final v1 = fragmented([], extraMvex: mehd(4500, version: 1));
    expect(Mp4Duration.measure(v1), 4500);
  });

  test('no mehd → the sum of trun sample durations ÷ mdhd.timescale', () {
    final file = fragmented([
      // per-sample durations
      moof([
        [
          ...tfhd(track: 1),
          ...trun(durations: [960, 960, 1024]),
        ],
      ]),
      mdat(),
      // tfhd default duration (after base_data_offset + description index)
      moof([
        [
          ...tfhd(
            track: 1,
            defaultDuration: 960,
            baseDataOffset: true,
            descriptionIndex: true,
          ),
          ...trun(count: 10),
        ],
      ]),
      mdat(),
      // trex default duration (1024)
      moof([
        [...tfhd(track: 1), ...trun(count: 5), ...trun(count: 2)],
      ]),
      mdat(),
    ]);
    const ticks = 960 + 960 + 1024 + 10 * 960 + 7 * 1024;
    expect(Mp4Duration.measure(file), (ticks * 1000 / 48000).round());
  });

  test('a cut last moof, or a cut mdat after it, does not count', () {
    final whole = [
      moof([
        [
          ...tfhd(track: 1),
          ...trun(durations: [48000]),
        ],
      ]),
      mdat(),
    ];
    final last = moof([
      [
        ...tfhd(track: 1),
        ...trun(durations: [24000]),
      ],
    ]);
    expect(Mp4Duration.measure(fragmented([...whole, last, mdat()])), 1500);
    final cutMoof = fragmented([...whole, last]);
    expect(
      Mp4Duration.measure(
        Uint8List.sublistView(cutMoof, 0, cutMoof.length - 4),
      ),
      1000,
    );
    // The moof is complete but its mdat is cut.
    final cutMdat = fragmented([...whole, last, mdat(64)]);
    expect(
      Mp4Duration.measure(
        Uint8List.sublistView(cutMdat, 0, cutMdat.length - 10),
      ),
      1000,
    );
    // A moof with no mdat after it.
    expect(Mp4Duration.measure(fragmented([...whole, last])), 1000);
  });

  test('mvhd duration all ones (unknown) → fragments', () {
    final file = Uint8List.fromList([
      ..._ftyp,
      ...box('moov', [
        ...mvhd(timescale: 1000, duration: 0xFFFFFFFF),
        ...trak(track: 1, timescale: 1000),
        ...box('mvex', trex(track: 1, defaultDuration: 20)),
      ]),
      ...moof([
        [...tfhd(track: 1), ...trun(count: 50)],
      ]),
      ...mdat(),
    ]);
    expect(Mp4Duration.measure(file), 1000);
  });

  test('the sound trak is chosen; other tracks\' fragments are left out', () {
    final file = fragmented(
      [
        moof([
          [
            ...tfhd(track: 2),
            ...trun(durations: [3000]),
          ], // video, 90 kHz
          [
            ...tfhd(track: 1),
            ...trun(durations: [44100]),
          ],
        ]),
        mdat(),
      ],
      traks: [
        trak(track: 2, timescale: 90000, handler: 'vide'),
        trak(track: 1, timescale: 44100, version: 1),
      ],
    );
    expect(Mp4Duration.measure(file), 1000);
  });

  test('64-bit box size and size 0 (to the end)', () {
    final large = Uint8List.fromList([
      ...fragmented([]),
      ...moof([
        [
          ...tfhd(track: 1),
          ...trun(durations: [48000]),
        ],
      ]),
      ...largeBox('mdat', List<int>.filled(40, 1)),
    ]);
    expect(Mp4Duration.measure(large), 1000);
    final toEnd = Uint8List.fromList([
      ...fragmented([]),
      ...moof([
        [
          ...tfhd(track: 1),
          ...trun(durations: [96000]),
        ],
      ]),
      ...u32(0),
      ...'mdat'.codeUnits,
      ...List<int>.filled(40, 1),
    ]);
    expect(Mp4Duration.measure(toEnd), 2000);
  });

  test('nothing to read → null', () {
    expect(Mp4Duration.measure(Uint8List(0)), isNull);
    expect(Mp4Duration.measure(Uint8List.fromList(List.filled(64, 9))), isNull);
    expect(Mp4Duration.measure(Uint8List.fromList(mdat())), isNull); // no moov
    expect(
      Mp4Duration.measure(fragmented([])),
      isNull,
    ); // no fragments, no mehd
    // A trun without per-sample durations and no default anywhere.
    final noDefault = fragmented([
      moof([
        [...tfhd(track: 1), ...trun(count: 4)],
      ]),
      mdat(),
    ], trexDefault: 0);
    expect(Mp4Duration.measure(noDefault), isNull);
    // A cut moov.
    final cut = fragmented([]);
    expect(
      Mp4Duration.measure(Uint8List.sublistView(cut, 0, cut.length - 3)),
      isNull,
    );
  });
}
