// lib/src/record/recording_output.dart — what the stop path (6.6.3) and recovery (6.10.1) do the
// same way, so a recovered recording gets the same bytes and the same asset hash: the length
// from the timeline in the file (6.6.4, R-3 v2.1), the head-only Duration patch (6.8.7, copied
// once — 6.6.5 ②), the asset file name, then AssetStore.put(audio) BEFORE createRecording (M-1).
// Also the CORE stores the recorder reads (on first use — 4.2.2) and the developer counters
// (6.14, PDF T37 draws them). Internal.
import 'dart:typed_data';

import 'package:note_core/note_core.dart' as core;

import 'buffer_ledger.dart';
import 'mp4_duration.dart';
import 'recorder_engine.dart';
import 'webm_timeline.dart';

/// The CORE stores the recorder uses (core.noteStoreProvider — read on first use, 4.2.2).
final class RecorderStores {
  const RecorderStores({
    required this.drafts,
    required this.assets,
    required this.recordings,
    required this.settings,
  });

  RecorderStores.of(core.NoteStore store)
    : drafts = store.recordingDrafts,
      assets = store.assets,
      recordings = store.recordings,
      settings = store.settings;

  final core.RecordingDraftStore drafts;
  final core.AssetStore assets;
  final core.RecordingRepository recordings;
  final core.SettingsRepository settings;
}

/// Where Recording.durationMs came from (developer overlay `src=` — 6.6.4, 6.14).
enum DurationSource { webm, mp4, probe, clock }

/// Where the bit rate of the last start came from (developer overlay `br=…(…)` — 4.6).
enum BitRateSource { config, setting, settingIgnored }

/// The developer counters of the recorder (6.14 rec / last / drafts / buf lines — PDF T37).
final class RecorderDiagnostics {
  /// Drafts recoverDraft turned into recordings.
  int recovered = 0;

  /// Drafts dropped as permanent failures (note gone, no bytes, native file unreadable).
  int dropped = 0;

  /// The last stored recording: mime, file length, its source, the clock's active ms, whether
  /// the WebM head was patched.
  ({
    String mimeType,
    int durationMs,
    DurationSource source,
    int clockMs,
    bool patched,
  })?
  lastRecording;

  /// The error of the last failed save (stop) — status.error carries saveFailed.
  Object? lastSaveFailed;

  /// The bit rate the last start asked the engine for, and why.
  int? lastBitRate;
  BitRateSource lastBitRateSource = BitRateSource.config;
}

bool isWebmMime(String mime) => mime.toLowerCase().contains('webm');

bool isMp4Mime(String mime) => mime.toLowerCase().contains('mp4');

/// The length of [bytes] from the timeline in the file (6.6.4): a native [file] → the decoder
/// probe; web WebM → [WebmTimeline.measure] endMs; web MP4 → [Mp4Duration.measure]. When that
/// fails, [clockMs] with [DurationSource.clock] ('duration from clock').
Future<({int durationMs, DurationSource source})> measureRecording(
  Uint8List bytes, {
  required String mimeType,
  required int clockMs,
  RecorderEngineFile? file,
}) async {
  if (file != null) {
    int? probed;
    try {
      probed = await file.probeDurationMs();
    } on Object {
      probed = null;
    }
    if (probed != null && probed > 0) {
      return (durationMs: probed, source: DurationSource.probe);
    }
  } else if (isWebmMime(mimeType)) {
    final m = WebmTimeline.measure(bytes);
    if (m != null) return (durationMs: m.endMs, source: DurationSource.webm);
  } else if (isMp4Mime(mimeType)) {
    final ms = Mp4Duration.measure(bytes);
    if (ms != null && ms > 0) {
      return (durationMs: ms, source: DurationSource.mp4);
    }
  }
  return (durationMs: clockMs, source: DurationSource.clock);
}

/// (WebM) [bytes] with Info > Duration = [durationMs]: the new head + bytes[restOffset..] copied
/// ONCE, the ledger swaps [hold] for the copy and the caller drops the original right away
/// ('잠깐 2 → 1' — 6.6.5 ②). Not WebM, or nothing to patch ('duration patch skipped'): the
/// same bytes, no copy.
({Uint8List bytes, BufferHold hold, bool patched}) patchRecordingHead(
  Uint8List bytes, {
  required String mimeType,
  required int durationMs,
  required BufferHold hold,
  required BufferLedger ledger,
}) {
  if (!isWebmMime(mimeType)) return (bytes: bytes, hold: hold, patched: false);
  final head = WebmTimeline.patchedHead(bytes, durationMs);
  if (head == null) return (bytes: bytes, hold: hold, patched: false);
  final headLength = head.bytes.length;
  final patched = Uint8List(headLength + bytes.length - head.restOffset)
    ..setRange(0, headLength, head.bytes)
    ..setRange(
      headLength,
      headLength + bytes.length - head.restOffset,
      bytes,
      head.restOffset,
    );
  return (
    bytes: patched,
    hold: ledger.swap(hold, patched.length),
    patched: true,
  );
}

/// [bytes] followed by the [unsaved] chunks (the rare stop path — 6.6.3 ①); the ledger swaps
/// [hold] for the joined buffer. No chunks: the same bytes, no copy.
({Uint8List bytes, BufferHold hold}) joinUnsaved(
  Uint8List bytes,
  List<Uint8List> unsaved, {
  required BufferHold hold,
  required BufferLedger ledger,
}) {
  if (unsaved.isEmpty) return (bytes: bytes, hold: hold);
  var length = bytes.length;
  for (final c in unsaved) {
    length += c.length;
  }
  final joined = Uint8List(length)..setRange(0, bytes.length, bytes);
  var at = bytes.length;
  for (final c in unsaved) {
    joined.setRange(at, at + c.length, c);
    at += c.length;
  }
  return (bytes: joined, hold: ledger.swap(hold, length));
}

/// `녹음-<startedAt local yyyyMMdd-HHmm>.m4a` (`.webm` for WebM) — Asset.fileName is for display
/// and export only (6.6.3).
String recordingFileName(core.EpochMillis startedAt, String mimeType) {
  final t = DateTime.fromMillisecondsSinceEpoch(startedAt);
  String two(int v) => v.toString().padLeft(2, '0');
  final ext = isWebmMime(mimeType) ? 'webm' : 'm4a';
  return '녹음-${t.year.toString().padLeft(4, '0')}${two(t.month)}${two(t.day)}-'
      '${two(t.hour)}${two(t.minute)}.$ext';
}

/// M-1: the asset first (CORE writes it in 4 MiB chunks, no full copy), then the recording row
/// (idempotent per id — CP-7). CORE rejects the other order (ArgumentError), and a missing or
/// purged note is EntityNotFoundException.
Future<core.Recording> storeRecording(
  RecorderStores stores,
  Uint8List bytes, {
  required core.RecordingId recordingId,
  required core.NoteId noteId,
  required String mimeType,
  required int durationMs,
  required core.EpochMillis startedAt,
  String? title,
}) async {
  final asset = await stores.assets.put(
    bytes,
    type: core.AssetType.audio,
    mimeType: mimeType,
    fileName: recordingFileName(startedAt, mimeType),
  );
  return stores.recordings.createRecording(
    id: recordingId,
    noteId: noteId,
    assetId: asset.id,
    durationMs: durationMs,
    startedAt: startedAt,
    title: title,
  );
}
