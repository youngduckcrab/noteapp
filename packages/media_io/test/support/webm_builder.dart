// Hand-made WebM samples (m5-7/06-pdf 6.8.7, 8.2 T32a; T41 builds its big synthetic draft with
// the same helpers). The bytes follow Chrome's MediaRecorder layout (6.1 E9): EBML header →
// Segment → Info (TimecodeScale, MuxingApp, WritingApp[, Duration last]) → Tracks (one Opus
// track) → Clusters of SimpleBlocks. Options add what Chrome does not write: known sizes,
// BlockGroup + BlockDuration, SeekHead, Void, Cues. The audio is not decodable (filler bytes after
// the Opus TOC) — the timeline code reads only the structure.
import 'dart:typed_data';

/// The bytes of an EBML ID (its marker bits are part of the ID).
List<int> ebmlId(int id) {
  final out = <int>[];
  var v = id;
  do {
    out.insert(0, v % 256);
    v ~/= 256;
  } while (v > 0);
  return out;
}

/// A size vint of [value] in [length] bytes (default: the shortest); [unknown] = all data bits
/// set.
List<int> ebmlSize(int value, {int? length, bool unknown = false}) {
  var n = length ?? 1;
  if (!unknown && length == null) {
    while (value >= _pow2(7 * n) - 1) {
      n++;
    }
  }
  if (unknown) {
    return [_pow2(8 - n) * 2 - 1, for (var i = 1; i < n; i++) 0xFF];
  }
  final out = List<int>.filled(n, 0);
  var v = value;
  for (var i = n - 1; i >= 0; i--) {
    out[i] = v % 256;
    v ~/= 256;
  }
  out[0] += 128 ~/ _pow2(n - 1);
  return out;
}

int _pow2(int n) {
  var v = 1;
  for (var i = 0; i < n; i++) {
    v *= 2;
  }
  return v;
}

/// One element: ID, size, body. [unknownSize] writes the 8-byte 'unknown' size (Chrome's
/// Segment and Cluster); [sizeLength] forces the vint length.
Uint8List ebml(
  int id,
  List<int> body, {
  bool unknownSize = false,
  int? sizeLength,
}) {
  final out = BytesBuilder(copy: false)
    ..add(ebmlId(id))
    ..add(
      unknownSize
          ? ebmlSize(0, length: 8, unknown: true)
          : ebmlSize(body.length, length: sizeLength),
    )
    ..add(body);
  return out.takeBytes();
}

Uint8List ebmlUint(int id, int value) {
  final bytes = <int>[];
  var v = value;
  do {
    bytes.insert(0, v % 256);
    v ~/= 256;
  } while (v > 0);
  return ebml(id, bytes);
}

Uint8List ebmlFloat64(int id, double value) =>
    ebml(id, Uint8List.sublistView(ByteData(8)..setFloat64(0, value)));

Uint8List ebmlString(int id, String value) => ebml(id, value.codeUnits);

Uint8List _concat(Iterable<List<int>> parts) {
  final out = BytesBuilder(copy: false);
  parts.forEach(out.add);
  return out.takeBytes();
}

/// An Opus packet: TOC (config, code) + the frame-count byte for code 3 + [filler] bytes.
List<int> opusPacket({
  int config = 27,
  int code = 3,
  int frames = 3,
  int filler = 8,
}) => [
  config * 8 + code,
  if (code == 3) frames,
  for (var i = 0; i < filler; i++) 0x55,
];

/// A SimpleBlock: track vint, int16 relative timecode, flags (0x80 = keyframe), packet.
Uint8List simpleBlock(
  int relative, {
  List<int>? packet,
  int track = 1,
  int flags = 0x80,
}) => ebml(0xA3, _blockBody(relative, packet ?? opusPacket(), track, flags));

/// A BlockGroup: Block (+ BlockDuration in TimecodeScale units).
Uint8List blockGroup(
  int relative, {
  List<int>? packet,
  int track = 1,
  int? duration,
}) => ebml(
  0xA0,
  _concat([
    ebml(0xA1, _blockBody(relative, packet ?? opusPacket(), track, 0)),
    if (duration != null) ebmlUint(0x9B, duration),
  ]),
);

List<int> _blockBody(int relative, List<int> packet, int track, int flags) {
  final rel = relative < 0 ? relative + 65536 : relative;
  return [...ebmlSize(track), rel ~/ 256, rel % 256, flags, ...packet];
}

/// A Cluster: Timecode then [blocks] (unknown size by default, like Chrome).
Uint8List cluster(
  int timecode,
  List<List<int>> blocks, {
  bool unknownSize = true,
}) => ebml(
  0x1F43B675,
  _concat([ebmlUint(0xE7, timecode), ...blocks]),
  unknownSize: unknownSize,
);

/// [count] SimpleBlocks [stepMs] apart from [from] (relative timecodes), each a 60 ms Opus packet.
List<Uint8List> blocks(
  int count, {
  int from = 0,
  int stepMs = 60,
  int filler = 8,
}) => [
  for (var i = 0; i < count; i++)
    simpleBlock(from + i * stepMs, packet: opusPacket(filler: filler)),
];

/// The SeekHead Chrome does not write: one Seek entry — SeekID Info, SeekPosition
/// [infoPosition] (from the Segment data start, 4 bytes).
Uint8List seekHead({required int infoPosition}) => ebml(
  0x114D9B74,
  ebml(
    0x4DBB,
    _concat([
      ebml(0x53AB, ebmlId(0x1549A966)),
      ebml(0x53AC, [
        for (var i = 3; i >= 0; i--) (infoPosition ~/ _pow2(8 * i)) % 256,
      ]),
    ]),
  ),
);

/// The length of [seekHead] (its SeekPosition is fixed at 4 bytes).
final int seekHeadLength = seekHead(infoPosition: 0).length;

/// A Void element of exactly [total] bytes (≥ 2).
Uint8List voidElement(int total) {
  for (var sizeLength = 1; sizeLength <= 8; sizeLength++) {
    final size = total - 1 - sizeLength;
    if (size >= 0 && size < _pow2(7 * sizeLength) - 1) {
      return ebml(0xEC, List<int>.filled(size, 0), sizeLength: sizeLength);
    }
  }
  throw ArgumentError.value(total, 'total');
}

/// A whole file. [duration] = Info > Duration (float64, last in Info, TimecodeScale units);
/// [segmentSizeLength] != null writes a known Segment size in that many bytes.
Uint8List webmFile({
  required List<List<int>> clusters,
  int timecodeScale = 1000000,
  double? duration,
  int? segmentSizeLength,
  bool withSeekHead = false,
  int? voidAfterInfo,
  bool withCues = false,
  String codecId = 'A_OPUS',
  int? defaultDurationNs,
  int trackNumber = 1,
  bool withTracks = true,
  String writingApp = 'Chrome',
}) {
  final header = ebml(
    0x1A45DFA3,
    _concat([
      ebmlUint(0x4286, 1),
      ebmlUint(0x42F7, 1),
      ebmlUint(0x42F2, 4),
      ebmlUint(0x42F3, 8),
      ebmlString(0x4282, 'webm'),
      ebmlUint(0x4287, 4),
      ebmlUint(0x4285, 2),
    ]),
  );
  final info = ebml(
    0x1549A966,
    _concat([
      ebmlUint(0x2AD7B1, timecodeScale),
      ebmlString(0x4D80, 'Chrome'),
      ebmlString(0x5741, writingApp),
      if (duration != null) ebmlFloat64(0x4489, duration),
    ]),
  );
  final tracks = ebml(
    0x1654AE6B,
    ebml(
      0xAE,
      _concat([
        ebmlUint(0xD7, trackNumber),
        ebmlUint(0x73C5, 1234),
        ebmlUint(0x83, 2),
        ebmlString(0x86, codecId),
        if (defaultDurationNs != null) ebmlUint(0x23E383, defaultDurationNs),
        ebml(0xE1, _concat([ebmlFloat64(0xB5, 48000), ebmlUint(0x9F, 1)])),
      ]),
    ),
  );
  final body = _concat([
    if (withSeekHead) seekHead(infoPosition: seekHeadLength),
    info,
    if (voidAfterInfo != null) voidElement(voidAfterInfo),
    if (withTracks) tracks,
    ...clusters,
    if (withCues) ebml(0x1C53BB6B, ebml(0xBB, ebmlUint(0xB3, 0))),
  ]);
  final segment = segmentSizeLength == null
      ? ebml(0x18538067, body, unknownSize: true)
      : ebml(0x18538067, body, sizeLength: segmentSizeLength);
  return _concat([header, segment]);
}

/// [file] cut [bytes] before its end (a recovered draft's half-written chunk).
Uint8List cutEnd(Uint8List file, int bytes) =>
    Uint8List.sublistView(file, 0, file.length - bytes);

/// head + original[restOffset..] — the file the stop path writes (6.6.5 ②).
Uint8List applyPatch(
  Uint8List original,
  ({Uint8List bytes, int restOffset}) patch,
) => _concat([patch.bytes, Uint8List.sublistView(original, patch.restOffset)]);
