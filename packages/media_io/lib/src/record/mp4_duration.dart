// lib/src/record/mp4_duration.dart — m5-7/06-pdf 6.6.4 (v2.1, review S-7). Internal, pure Dart.
//
// The timeline length of an MP4 / fragmented MP4 recording (web Safari's MediaRecorder): the web
// side does not measure with a decoder (6.6.4). In order:
//   1. moov/mvhd.duration ÷ timescale when it is neither 0 nor 'unknown' (all ones);
//   2. moov/mvex/mehd.fragment_duration ÷ mvhd.timescale;
//   3. the sum of every moof/traf/trun sample duration (default from tfhd, then trex) ÷ the audio
//      track's mdhd.timescale. A fragment counts when its moof is complete and the mdat right
//      after it is not cut by the end of the file (a recovered draft's half-written chunk).
//
// Web-safe numbers (contract 7.4): no 64-bit reads (hi × 2^32 + lo), flags read by arithmetic.
import 'dart:typed_data';

abstract final class Mp4Duration {
  /// The length in ms, or `null` when no box gives one (the caller then uses the clock).
  static int? measure(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final top = _boxes(data, 0, bytes.length).toList();
    final moov = top.where((b) => b.type == _moov && !b.cut).firstOrNull;
    if (moov == null) return null;

    final children = _boxes(data, moov.dataStart, moov.end).toList();
    final mvhd = children.where((b) => b.type == _mvhd && !b.cut).firstOrNull;
    int? movieScale;
    if (mvhd != null) {
      final header = _readMvhd(data, mvhd);
      if (header != null) {
        movieScale = header.timescale;
        final duration = header.duration;
        if (duration != null && duration > 0) {
          return _ms(duration, header.timescale);
        }
      }
    }

    final mvex = children.where((b) => b.type == _mvex && !b.cut).firstOrNull;
    final trexDefaults = <int, int>{};
    if (mvex != null) {
      for (final box in _boxes(data, mvex.dataStart, mvex.end)) {
        if (box.cut) break;
        if (box.type == _mehd && movieScale != null) {
          final fragment = _fullBoxValue(data, box);
          if (fragment != null && fragment > 0) {
            return _ms(fragment, movieScale);
          }
        } else if (box.type == _trex && box.end - box.dataStart >= 24) {
          final track = data.getUint32(box.dataStart + 4);
          trexDefaults[track] = data.getUint32(box.dataStart + 12);
        }
      }
    }

    final audio = _audioTrack(data, children);
    if (audio == null) return null;

    var total = 0;
    int? pending;
    for (final box in top) {
      if (pending != null) {
        if (!(box.type == _mdat && box.cut)) total += pending;
        pending = null;
      }
      if (box.type != _moof || box.cut) continue;
      final ticks = _fragmentTicks(data, box, audio.track, trexDefaults);
      if (ticks == null) return null;
      pending = ticks;
    }
    // A moof as the last box has no media data in the file.
    if (total <= 0) return null;
    return _ms(total, audio.timescale);
  }
}

const _moov = 0x6D6F6F76; // 'moov'
const _mvhd = 0x6D766864;
const _mvex = 0x6D766578;
const _mehd = 0x6D656864;
const _trex = 0x74726578;
const _trak = 0x7472616B;
const _tkhd = 0x746B6864;
const _mdia = 0x6D646961;
const _mdhd = 0x6D646864;
const _hdlr = 0x68646C72;
const _soun = 0x736F756E;
const _moof = 0x6D6F6F66;
const _traf = 0x74726166;
const _tfhd = 0x74666864;
const _trun = 0x7472756E;
const _mdat = 0x6D646174;

/// One box: [cut] = it runs past its parent (or the file).
typedef _Box = ({int type, int offset, int dataStart, int end, bool cut});

Iterable<_Box> _boxes(ByteData d, int start, int end) sync* {
  var p = start;
  while (p + 8 <= end) {
    var size = d.getUint32(p);
    final type = d.getUint32(p + 4);
    var header = 8;
    if (size == 1) {
      if (p + 16 > end) {
        yield (type: type, offset: p, dataStart: end, end: end, cut: true);
        return;
      }
      size = _u64(d, p + 8);
      header = 16;
    } else if (size == 0) {
      size = end - p; // to the end of the parent
    }
    if (size < header) return; // broken — nothing after it can be trusted
    final boxEnd = p + size;
    if (boxEnd > end) {
      yield (type: type, offset: p, dataStart: p + header, end: end, cut: true);
      return;
    }
    yield (
      type: type,
      offset: p,
      dataStart: p + header,
      end: boxEnd,
      cut: false,
    );
    p = boxEnd;
  }
}

int _u64(ByteData d, int at) =>
    d.getUint32(at) * 4294967296 + d.getUint32(at + 4);

int _ms(int ticks, int timescale) => (ticks * 1000 / timescale).round();

bool _flag(int flags, int bit) => (flags ~/ bit) % 2 == 1;

/// mvhd: timescale and duration (`null` = 'unknown', all ones).
({int timescale, int? duration})? _readMvhd(ByteData d, _Box box) {
  final at = box.dataStart;
  final version = d.getUint8(at);
  final need = version == 1 ? 4 + 28 : 4 + 16;
  if (box.end - at < need) return null;
  final int timescale;
  int? duration;
  if (version == 1) {
    timescale = d.getUint32(at + 20);
    final hi = d.getUint32(at + 24);
    final lo = d.getUint32(at + 28);
    duration = hi == 0xFFFFFFFF && lo == 0xFFFFFFFF
        ? null
        : hi * 4294967296 + lo;
  } else {
    timescale = d.getUint32(at + 12);
    final value = d.getUint32(at + 16);
    duration = value == 0xFFFFFFFF ? null : value;
  }
  if (timescale == 0) return null;
  return (timescale: timescale, duration: duration);
}

/// A full box whose first field is a 32-bit (version 0) or 64-bit (version 1) value (mehd).
int? _fullBoxValue(ByteData d, _Box box) {
  final at = box.dataStart;
  if (box.end - at < 8) return null;
  if (d.getUint8(at) == 1) {
    if (box.end - at < 12) return null;
    return _u64(d, at + 4);
  }
  return d.getUint32(at + 4);
}

/// The audio track (hdlr 'soun', else the first trak): its id and mdhd.timescale.
({int? track, int timescale})? _audioTrack(ByteData d, List<_Box> moov) {
  ({int? track, int timescale})? first;
  for (final trak in moov.where((b) => b.type == _trak && !b.cut)) {
    int? track, timescale;
    var sound = false;
    for (final box in _boxes(d, trak.dataStart, trak.end)) {
      if (box.cut) break;
      if (box.type == _tkhd && box.end - box.dataStart >= 24) {
        final v1 = d.getUint8(box.dataStart) == 1;
        track = d.getUint32(box.dataStart + (v1 ? 20 : 12));
      } else if (box.type == _mdia) {
        for (final m in _boxes(d, box.dataStart, box.end)) {
          if (m.cut) break;
          if (m.type == _mdhd && m.end - m.dataStart >= 24) {
            final v1 = d.getUint8(m.dataStart) == 1;
            if (!v1 || m.end - m.dataStart >= 32) {
              timescale = d.getUint32(m.dataStart + (v1 ? 20 : 12));
            }
          } else if (m.type == _hdlr && m.end - m.dataStart >= 12) {
            sound = d.getUint32(m.dataStart + 8) == _soun;
          }
        }
      }
    }
    if (timescale == null || timescale == 0) continue;
    final found = (track: track, timescale: timescale);
    if (sound) return found;
    first ??= found;
  }
  return first;
}

/// The sample durations of one moof for [track]; `null` = a trun whose durations are unknown.
int? _fragmentTicks(
  ByteData d,
  _Box moof,
  int? track,
  Map<int, int> trexDefaults,
) {
  var ticks = 0;
  for (final traf in _boxes(d, moof.dataStart, moof.end)) {
    if (traf.cut) break;
    if (traf.type != _traf) continue;
    int? trafTrack, defaultDuration;
    for (final box in _boxes(d, traf.dataStart, traf.end)) {
      if (box.cut) break;
      if (box.type == _tfhd) {
        final at = box.dataStart;
        if (box.end - at < 8) return null;
        final flags = _flags(d, at);
        trafTrack = d.getUint32(at + 4);
        var q = at + 8;
        if (_flag(flags, 0x01)) q += 8; // base_data_offset
        if (_flag(flags, 0x02)) q += 4; // sample_description_index
        if (_flag(flags, 0x08)) {
          if (q + 4 > box.end) return null;
          defaultDuration = d.getUint32(q);
        }
        if (track != null && trafTrack != track) break;
        defaultDuration ??= trexDefaults[trafTrack];
      } else if (box.type == _trun) {
        if (track != null && trafTrack != null && trafTrack != track) break;
        final sum = _trunTicks(d, box, defaultDuration);
        if (sum == null) return null;
        ticks += sum;
      }
    }
  }
  return ticks;
}

int _flags(ByteData d, int at) =>
    d.getUint8(at + 1) * 65536 + d.getUint8(at + 2) * 256 + d.getUint8(at + 3);

int? _trunTicks(ByteData d, _Box box, int? defaultDuration) {
  final at = box.dataStart;
  if (box.end - at < 8) return null;
  final flags = _flags(d, at);
  final count = d.getUint32(at + 4);
  var q = at + 8;
  if (_flag(flags, 0x01)) q += 4; // data_offset
  if (_flag(flags, 0x04)) q += 4; // first_sample_flags
  final hasDuration = _flag(flags, 0x100);
  if (!hasDuration) {
    if (defaultDuration == null) return null;
    return count * defaultDuration;
  }
  var stride = 4;
  if (_flag(flags, 0x200)) stride += 4;
  if (_flag(flags, 0x400)) stride += 4;
  if (_flag(flags, 0x800)) stride += 4;
  if (q + count * stride > box.end) return null;
  var sum = 0;
  for (var i = 0; i < count; i++) {
    sum += d.getUint32(q + i * stride);
  }
  return sum;
}
