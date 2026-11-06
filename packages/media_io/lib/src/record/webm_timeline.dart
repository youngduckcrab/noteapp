// lib/src/record/webm_timeline.dart — m5-7/06-pdf 6.8.7 (v2.1, PDF-M6 — R-3). Internal, pure Dart.
//
// The length of a WebM recording from the audio timeline IN THE FILE: the last complete block's
// absolute timecode + that packet's length (Opus TOC). Chrome's MediaRecorder writes a live WebM —
// Segment and Cluster sizes unknown, no Info > Duration (6.1 E9) — so <audio> reads Infinity.
// patchedHead builds a new head (file start … Info end) that carries Info > Duration; the stop and
// recovery paths copy head + bytes[restOffset..] once (6.6.5 ②). The recording clock is never
// written into the file (review M-6): durationMs = measure(bytes).endMs (6.1 E11 — the length the
// decoder reads).
//
// Web-safe numbers (contract 7.4, 1차 7.4.3): arithmetic instead of bit operations, no 64-bit
// reads; positions and sizes stay far below 2^53.
import 'dart:math' as math;
import 'dart:typed_data';

import '../tuning.dart';

/// What [WebmTimeline.measure] reads: the last complete audio block's start, its end
/// (= durationMs) and its packet length, in ms.
typedef WebmMeasure = ({int lastBlockStartMs, int endMs, int packetMs});

/// [WebmTimeline.patchedHead]: the new file is `bytes` + `original[restOffset..]`.
typedef WebmPatchedHead = ({Uint8List bytes, int restOffset});

abstract final class WebmTimeline {
  /// The audio timeline of [bytes], or `null` when the structure is not found (the caller then
  /// uses the clock and the developer overlay says 'duration from clock').
  ///
  /// 1. EBML header → Segment (unknown size allowed) → Info (TimecodeScale, default 1 ms) and
  ///    Tracks (audio track number, CodecID, DefaultDuration).
  /// 2. The last Cluster: every Cluster ID in the last [tailScanBytes] (from the end) is parsed
  ///    forward to the end of the file and must hold up (Timecode before SimpleBlock /
  ///    BlockGroup); when none does, the walk starts at the first Cluster.
  /// 3. Its last COMPLETE block — an element cut by the end of the file (the half-written chunk of a
  ///    recovered draft) is dropped.
  /// 4. The packet length: BlockDuration → (A_OPUS) TOC (RFC 6716 3.1) → DefaultDuration →
  ///    [MediaTuning.opusDefaultPacketMs].
  /// 5. endMs = round((block time + packet length) / 1 ms).
  static WebmMeasure? measure(
    Uint8List bytes, {
    int tailScanBytes = MediaTuning.webmTailScanBytes,
  }) {
    final head = _Head.parse(bytes);
    final first = head?.firstCluster;
    if (head == null || first == null) return null;
    final from = math.max(first, bytes.length - tailScanBytes);
    for (var p = bytes.length - 4; p >= from; p--) {
      if (bytes[p] != 0x1F ||
          bytes[p + 1] != 0x43 ||
          bytes[p + 2] != 0xB6 ||
          bytes[p + 3] != 0x75) {
        continue;
      }
      final walk = _walkSegment(bytes, p, head);
      if (walk == null) continue; // not a Cluster after all
      final block = walk.last;
      if (block != null) return block.measure;
      // A real Cluster without a complete block (cut at the end): an earlier one has it.
    }
    if (from > first) return _walkSegment(bytes, first, head)?.last?.measure;
    return null;
  }

  /// A new head with Info > Duration = [durationMs] (float64, TimecodeScale units), or `null`
  /// when it cannot be patched (no Info before the first Cluster; SeekHead or Cues without a
  /// Void of ≥ 11 bytes right after Info) — the developer overlay says 'duration patch skipped'.
  ///
  /// An existing Duration only gets its value rewritten. Otherwise 11 bytes go at the end of Info
  /// and the Info size vint is rewritten; a known Segment size grows by the same amount in a vint
  /// of the same length (unknown stays unknown). With SeekHead or Cues the positions after Info
  /// must not move, so the Void right after Info shrinks by what Info grew.
  static WebmPatchedHead? patchedHead(Uint8List bytes, int durationMs) {
    final head = _Head.parse(bytes);
    final info = head?.info;
    if (head == null || info == null || durationMs < 0) return null;
    final value = durationMs * 1e6 / head.timecodeScale;

    final content = BytesBuilder(copy: false);
    final old = Uint8List.sublistView(bytes, info.dataStart, info.end);
    final durationAt = head.durationDataStart;
    if (durationAt != null) {
      final copy = Uint8List.fromList(old);
      final view = ByteData.sublistView(copy);
      final at = durationAt - info.dataStart;
      switch (head.durationSize) {
        case 8:
          view.setFloat64(at, value);
        case 4:
          view.setFloat32(at, value);
        default:
          return null;
      }
      content.add(copy);
    } else {
      content
        ..add(old)
        ..add(const [0x44, 0x89, 0x88]);
      final float = ByteData(8)..setFloat64(0, value);
      content.add(Uint8List.sublistView(float));
    }
    final infoBody = content.takeBytes();
    final infoSize = _sizeVint(infoBody.length, minLength: info.sizeLength);
    if (infoSize == null) return null;
    final newInfo = BytesBuilder(copy: false)
      ..add(
        Uint8List.sublistView(
          bytes,
          info.offset,
          info.dataStart - info.sizeLength,
        ),
      )
      ..add(infoSize)
      ..add(infoBody);
    final newInfoBytes = newInfo.takeBytes();
    final grow = newInfoBytes.length - (info.end - info.offset);

    final out = BytesBuilder(copy: false);
    if (grow == 0) {
      out
        ..add(Uint8List.sublistView(bytes, 0, info.offset))
        ..add(newInfoBytes);
      return (bytes: out.takeBytes(), restOffset: info.end);
    }
    if (!head.hasSeekHead && !head.hasCues) {
      final prefix = Uint8List.fromList(
        Uint8List.sublistView(bytes, 0, info.offset),
      );
      if (head.segmentSize >= 0) {
        final size = _sizeVint(
          head.segmentSize + grow,
          minLength: head.segmentSizeLength,
        );
        if (size == null || size.length != head.segmentSizeLength) return null;
        prefix.setRange(
          head.segmentSizeAt,
          head.segmentSizeAt + size.length,
          size,
        );
      }
      out
        ..add(prefix)
        ..add(newInfoBytes);
      return (bytes: out.takeBytes(), restOffset: info.end);
    }
    // SeekHead / Cues: keep every later position — the Void right after Info gives the room.
    final voidAfter = head.afterInfo;
    if (voidAfter == null || voidAfter.id != _Id.voidElement) return null;
    final left = (voidAfter.end - voidAfter.offset) - grow;
    if (left < 0 || left == 1) return null;
    out
      ..add(Uint8List.sublistView(bytes, 0, info.offset))
      ..add(newInfoBytes);
    if (left > 0) {
      final filler = _voidElement(left);
      if (filler == null) return null;
      out.add(filler);
    }
    return (bytes: out.takeBytes(), restOffset: voidAfter.end);
  }
}

// ---------------------------------------------------------------------------------------------
// EBML reading

abstract final class _Id {
  static const ebml = 0x1A45DFA3;
  static const segment = 0x18538067;
  static const seekHead = 0x114D9B74;
  static const info = 0x1549A966;
  static const timecodeScale = 0x2AD7B1;
  static const duration = 0x4489;
  static const tracks = 0x1654AE6B;
  static const trackEntry = 0xAE;
  static const trackNumber = 0xD7;
  static const trackType = 0x83;
  static const codecId = 0x86;
  static const defaultDuration = 0x23E383;
  static const cluster = 0x1F43B675;
  static const timecode = 0xE7;
  static const position = 0xA7;
  static const prevSize = 0xAB;
  static const silentTracks = 0x5854;
  static const simpleBlock = 0xA3;
  static const blockGroup = 0xA0;
  static const block = 0xA1;
  static const blockDuration = 0x9B;
  static const encryptedBlock = 0xAF;
  static const cues = 0x1C53BB6B;
  static const tags = 0x1254C367;
  static const chapters = 0x1043A770;
  static const attachments = 0x1941A469;
  static const voidElement = 0xEC;
  static const crc32 = 0xBF;

  /// Children of Segment only — they end an unknown-size Cluster.
  static const segmentLevel = {
    cluster,
    seekHead,
    info,
    tracks,
    cues,
    tags,
    chapters,
    attachments,
  };

  /// Children of a Cluster that are not blocks (the global Void and CRC-32 included).
  static const clusterOther = {
    position,
    prevSize,
    silentTracks,
    encryptedBlock,
    voidElement,
    crc32,
  };
}

/// One element header. [size] is −1 when unknown; [cut] = the header itself runs past the limit.
final class _Header {
  const _Header(
    this.id,
    this.offset,
    this.dataStart,
    this.sizeLength,
    this.size,
  ) : cut = false;
  const _Header.cut()
    : id = 0,
      offset = 0,
      dataStart = 0,
      sizeLength = 0,
      size = 0,
      cut = true;

  final int id, offset, dataStart, sizeLength, size;
  final bool cut;

  bool get unknown => size < 0;
  int get end => dataStart + size;
}

/// The header at [p] (before [limit]); `null` = not an EBML element.
_Header? _header(Uint8List b, int p, int limit) {
  if (p >= limit) return const _Header.cut();
  final first = b[p];
  final idLength = first >= 0x80
      ? 1
      : first >= 0x40
      ? 2
      : first >= 0x20
      ? 3
      : first >= 0x10
      ? 4
      : 0;
  if (idLength == 0) return null;
  if (p + idLength >= limit) return const _Header.cut();
  var id = 0;
  for (var i = 0; i < idLength; i++) {
    id = id * 256 + b[p + i];
  }
  final q = p + idLength;
  final vint = _vint(b, q, limit);
  if (vint == null) return null;
  if (vint.cut) return const _Header.cut();
  return _Header(id, p, q + vint.length, vint.length, vint.value);
}

/// A size-style vint (marker removed) at [p]: value −1 = all data bits set (unknown).
({int value, int length, bool cut})? _vint(Uint8List b, int p, int limit) {
  if (p >= limit) return (value: 0, length: 0, cut: true);
  final first = b[p];
  if (first == 0) return null; // longer than 8 bytes
  var length = 1;
  var marker = 0x80;
  while (first < marker) {
    length++;
    marker ~/= 2;
  }
  if (p + length > limit) return (value: 0, length: 0, cut: true);
  var value = first - marker;
  var allOnes = value == marker - 1;
  for (var i = 1; i < length; i++) {
    final x = b[p + i];
    value = value * 256 + x;
    if (x != 0xFF) allOnes = false;
  }
  return (value: allOnes ? -1 : value, length: length, cut: false);
}

int _uint(Uint8List b, int start, int end) {
  var v = 0;
  for (var i = start; i < end; i++) {
    v = v * 256 + b[i];
  }
  return v;
}

/// The size vint of [value] in at least [minLength] bytes (all-ones is reserved for 'unknown').
Uint8List? _sizeVint(int value, {int minLength = 1}) {
  for (var length = math.max(1, minLength); length <= 8; length++) {
    final room = math.pow(2, 7 * length).toInt() - 1;
    if (value >= room) continue;
    final out = Uint8List(length);
    var v = value;
    for (var i = length - 1; i >= 0; i--) {
      out[i] = v % 256;
      v ~/= 256;
    }
    out[0] += 128 ~/ math.pow(2, length - 1).toInt();
    return out;
  }
  return null;
}

/// A Void element of exactly [total] bytes (≥ 2).
Uint8List? _voidElement(int total) {
  for (var sizeLength = 1; sizeLength <= 8; sizeLength++) {
    final size = total - 1 - sizeLength;
    if (size < 0) return null;
    final vint = _sizeVint(size, minLength: sizeLength);
    if (vint == null || vint.length != sizeLength) continue;
    return Uint8List(total)
      ..[0] = _Id.voidElement
      ..setRange(1, 1 + sizeLength, vint);
  }
  return null;
}

/// EBML header, Segment and the Segment children before the first Cluster.
final class _Head {
  _Head._(this.segmentDataStart, this.segmentEnd);

  final int segmentDataStart, segmentEnd;
  int segmentSize = -1, segmentSizeAt = 0, segmentSizeLength = 0;
  int timecodeScale = 1000000;
  int? durationDataStart;
  int durationSize = 0;
  _Header? info;

  /// The Segment child right after Info.
  _Header? afterInfo;
  bool hasSeekHead = false, hasCues = false;
  int? firstCluster;
  int? audioTrack;
  String? codecId;
  int? defaultDurationNs;

  static _Head? parse(Uint8List b) {
    final length = b.length;
    final ebml = _header(b, 0, length);
    if (ebml == null || ebml.cut || ebml.id != _Id.ebml || ebml.unknown) {
      return null;
    }
    final segment = _header(b, ebml.end, length);
    if (segment == null || segment.cut || segment.id != _Id.segment) {
      return null;
    }
    final end = segment.unknown ? length : math.min(segment.end, length);
    final head = _Head._(segment.dataStart, end)
      ..segmentSize = segment.size
      ..segmentSizeAt = segment.dataStart - segment.sizeLength
      ..segmentSizeLength = segment.sizeLength;
    final tracks = <({int? number, int? type, String? codec, int? dd})>[];
    var p = segment.dataStart;
    _Header? previous;
    while (p < end) {
      final h = _header(b, p, end);
      if (h == null || h.cut) break;
      if (previous != null && previous.id == _Id.info) head.afterInfo = h;
      previous = h;
      if (h.id == _Id.cluster) {
        head.firstCluster = p;
        break;
      }
      if (h.unknown || h.end > end) break;
      switch (h.id) {
        case _Id.info:
          head.info = h;
          head._readInfo(b, h);
        case _Id.tracks:
          _readTracks(b, h, tracks);
        case _Id.seekHead:
          head.hasSeekHead = true;
        case _Id.cues:
          head.hasCues = true;
      }
      p = h.end;
    }
    final audio =
        tracks.where((t) => t.type == 2).firstOrNull ??
        tracks.where((t) => t.codec?.startsWith('A_') ?? false).firstOrNull ??
        (tracks.length == 1 ? tracks.single : null);
    if (audio != null) {
      head
        ..audioTrack = audio.number
        ..codecId = audio.codec
        ..defaultDurationNs = audio.dd;
    }
    return head;
  }

  void _readInfo(Uint8List b, _Header info) {
    var p = info.dataStart;
    while (p < info.end) {
      final h = _header(b, p, info.end);
      if (h == null || h.cut || h.unknown || h.end > info.end) return;
      if (h.id == _Id.timecodeScale) {
        final scale = _uint(b, h.dataStart, h.end);
        if (scale > 0) timecodeScale = scale;
      } else if (h.id == _Id.duration) {
        durationDataStart = h.dataStart;
        durationSize = h.size;
      }
      p = h.end;
    }
  }

  static void _readTracks(
    Uint8List b,
    _Header tracks,
    List<({int? number, int? type, String? codec, int? dd})> out,
  ) {
    var p = tracks.dataStart;
    while (p < tracks.end) {
      final entry = _header(b, p, tracks.end);
      if (entry == null || entry.cut || entry.unknown) return;
      if (entry.end > tracks.end) return;
      if (entry.id == _Id.trackEntry) {
        int? number, type, dd;
        String? codec;
        var q = entry.dataStart;
        while (q < entry.end) {
          final h = _header(b, q, entry.end);
          if (h == null || h.cut || h.unknown || h.end > entry.end) break;
          switch (h.id) {
            case _Id.trackNumber:
              number = _uint(b, h.dataStart, h.end);
            case _Id.trackType:
              type = _uint(b, h.dataStart, h.end);
            case _Id.codecId:
              codec = String.fromCharCodes(
                b.sublist(h.dataStart, h.end).where((c) => c != 0),
              );
            case _Id.defaultDuration:
              dd = _uint(b, h.dataStart, h.end);
          }
          q = h.end;
        }
        out.add((number: number, type: type, codec: codec, dd: dd));
      }
      p = entry.end;
    }
  }
}

/// A complete audio block: start and packet length in ns.
final class _Block {
  const _Block(this.startNs, this.packetNs);

  final double startNs, packetNs;

  WebmMeasure get measure => (
    lastBlockStartMs: (startNs / 1e6).round(),
    endMs: ((startNs + packetNs) / 1e6).round(),
    packetMs: (packetNs / 1e6).round(),
  );
}

/// Parses Segment children from the Cluster at [p] to the end; `null` = the structure does not
/// hold (a false Cluster ID inside block data).
({_Block? last})? _walkSegment(Uint8List b, int p, _Head head) {
  final end = head.segmentEnd;
  _Block? last;
  var first = true;
  while (p < end) {
    final h = _header(b, p, end);
    if (h == null) return null;
    if (h.cut) break; // a header cut by the end of the file
    if (first && h.id != _Id.cluster) return null;
    first = false;
    if (h.id == _Id.cluster) {
      final cluster = _walkCluster(b, h, end, head);
      if (cluster == null) return null;
      if (cluster.last != null) last = cluster.last;
      if (cluster.next < 0) break; // cut by the end of the file
      p = cluster.next;
    } else if (_Id.segmentLevel.contains(h.id) ||
        h.id == _Id.voidElement ||
        h.id == _Id.crc32) {
      if (h.unknown || h.end >= end) break;
      p = h.end;
    } else {
      return null;
    }
  }
  return (last: last);
}

/// One Cluster: its last complete audio block and where the next element starts (−1 = the
/// Cluster runs to the end of the file); `null` = not a Cluster. A Cluster cut by the end of the
/// file holds up whatever it has so far (it gives no block when its Timecode is missing) — an
/// earlier candidate's walk must get through it.
({_Block? last, int next})? _walkCluster(
  Uint8List b,
  _Header cluster,
  int end,
  _Head head,
) {
  final toEnd = cluster.unknown || cluster.end >= end;
  final limit = toEnd ? end : cluster.end;
  int? timecode;
  _Block? last;
  var p = cluster.dataStart;
  while (p < limit) {
    final h = _header(b, p, limit);
    if (h == null) return null;
    if (h.cut) {
      // A header cut by the end of the file; inside a known-size Cluster it is broken.
      return toEnd ? (last: last, next: -1) : null;
    }
    if (cluster.unknown && _Id.segmentLevel.contains(h.id)) {
      if (timecode == null) return null;
      return (last: last, next: p);
    }
    if (h.unknown) return null;
    if (h.end > limit) {
      // Cut by the end of the file (dropped), or bigger than its known-size Cluster (broken).
      return toEnd ? (last: last, next: -1) : null;
    }
    switch (h.id) {
      case _Id.timecode:
        timecode = _uint(b, h.dataStart, h.end);
      case _Id.simpleBlock:
        if (timecode == null) return null;
        final block = _block(b, h.dataStart, h.end, timecode, head, null);
        if (block == null) return null;
        if (block.audio) last = block.block;
      case _Id.blockGroup:
        if (timecode == null) return null;
        final block = _blockGroup(b, h, timecode, head);
        if (block == null) return null;
        if (block.audio) last = block.block;
      default:
        if (!_Id.clusterOther.contains(h.id)) return null;
    }
    p = h.end;
  }
  if (toEnd) return (last: last, next: -1);
  if (timecode == null) return null;
  return (last: last, next: cluster.end);
}

({_Block? block, bool audio})? _blockGroup(
  Uint8List b,
  _Header group,
  int timecode,
  _Head head,
) {
  int? start, end, duration;
  var p = group.dataStart;
  while (p < group.end) {
    final h = _header(b, p, group.end);
    if (h == null || h.cut || h.unknown || h.end > group.end) return null;
    if (h.id == _Id.block) {
      start = h.dataStart;
      end = h.end;
    } else if (h.id == _Id.blockDuration) {
      duration = _uint(b, h.dataStart, h.end);
    }
    p = h.end;
  }
  if (start == null || end == null) return null;
  return _block(b, start, end, timecode, head, duration);
}

/// A Block / SimpleBlock body: track number vint, int16 relative timecode, flags, frame data.
({_Block? block, bool audio})? _block(
  Uint8List b,
  int start,
  int end,
  int clusterTimecode,
  _Head head,
  int? blockDurationTicks,
) {
  final track = _vint(b, start, end);
  if (track == null || track.cut) return null;
  final at = start + track.length;
  if (at + 3 > end) return null;
  final audioTrack = head.audioTrack;
  if (audioTrack != null && track.value != audioTrack) {
    return (block: null, audio: false);
  }
  var relative = b[at] * 256 + b[at + 1];
  if (relative >= 32768) relative -= 65536;
  final flags = b[at + 2];
  final data = at + 3;
  final scale = head.timecodeScale;
  final startNs = math.max(0, clusterTimecode + relative) * scale.toDouble();
  final laced = (flags ~/ 2) % 4 != 0;
  final frames = laced ? (data < end ? b[data] + 1 : 1) : 1;
  double? packetNs;
  if (blockDurationTicks != null) {
    packetNs = blockDurationTicks * scale.toDouble();
  } else if (!laced && head.codecId == 'A_OPUS') {
    packetNs = _opusPacketNs(b, data, end);
  }
  packetNs ??=
      frames *
      (head.defaultDurationNs ?? MediaTuning.opusDefaultPacketMs * 1e6)
          .toDouble();
  return (block: _Block(startNs, packetNs), audio: true);
}

/// RFC 6716 3.1: the TOC config gives the frame length, the code the frame count.
double? _opusPacketNs(Uint8List b, int data, int end) {
  if (data >= end) return null;
  final toc = b[data];
  final config = toc ~/ 8;
  final code = toc % 4;
  final double frameMs;
  if (config < 12) {
    frameMs = const [10.0, 20.0, 40.0, 60.0][config % 4];
  } else if (config < 16) {
    frameMs = const [10.0, 20.0][config % 2];
  } else {
    frameMs = const [2.5, 5.0, 10.0, 20.0][config % 4];
  }
  final int count;
  switch (code) {
    case 0:
      count = 1;
    case 1 || 2:
      count = 2;
    default:
      if (data + 1 >= end) return null;
      count = b[data + 1] % 64;
      if (count == 0) return null;
  }
  return frameMs * count * 1e6;
}
