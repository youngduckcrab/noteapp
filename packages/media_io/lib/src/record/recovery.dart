// lib/src/record/recovery.dart — pendingDrafts / recoverDraft (m5-7/06-pdf 6.10; M-2, M-4, D13,
// D19, contract 7.2.4 v2.1 and 7.2.12 '묻지 않고'). Internal; MediaRecorderService delegates.
//
// pendingDrafts() = listDrafts() minus
//   ① this recorder's session in progress (starting … finishing),
//   ② the draft being recovered now,
//   ③ drafts updated within max(10 s, 5 × webDraftChunkMs) (another tab may be recording),
//   ④ (web) drafts whose Web Lock 'noteapp-rec-<draftId>' is held,
//   ⑤ drafts with media.recoverAttempts ≥ recoverMaxAttempts (2) — '복구하지 못한 녹음'.
// recoverDraft() runs one at a time, writes the attempt BEFORE trying (an attempt that kills the
// tab still counts — 6.10.3), measures and patches like the stop path (recording_output.dart),
// stores Asset then Recording(title '복구된 녹음', the draft's recordingId and startedAt), and
// classifies EntityNotFoundException (note missing or purged), no bytes and an unreadable
// native file as permanent failures (draft and attempts cleaned, null). Anything else keeps the
// draft and the attempt and rethrows (INFRA logs it and goes on — 01-infra 6.5.2).
import 'dart:typed_data';

import 'package:note_core/note_core.dart' as core;

import '../config.dart';
import '../platform/web_locks.dart';
import '../tuning.dart';
import 'buffer_ledger.dart';
import 'recorder_engine.dart';
import 'recording_output.dart';
import 'recover_attempts.dart';

/// Why pendingDrafts() leaves a draft out (①–⑤).
enum DraftExclusion { activeSession, recovering, recent, locked, stuck }

final class DraftRecovery {
  DraftRecovery({
    required this.stores,
    required this.now,
    required this.config,
    required this.engine,
    required this.locks,
    required this.ledger,
    required this.diagnostics,
    required this.activeDraftId,
  });

  final RecorderStores Function() stores;
  final DateTime Function() now;
  final MediaIoConfig config;
  final RecorderEngine engine;
  final WebLocks locks;
  final BufferLedger ledger;
  final RecorderDiagnostics diagnostics;

  /// ① The draft of this recorder's session (starting … finishing), or null.
  final String? Function() activeDraftId;

  final Set<String> _recovering = {};
  Future<void> _chain = Future<void>.value();
  bool _orphanFilesChecked = false;

  /// The drafts recovery may take now (①–⑤ left out). Also drops the attempt entries of drafts
  /// that no longer exist and, once (native), the recording files without a draft (6.9.5).
  Future<List<core.RecordingDraft>> pending() async {
    final s = stores();
    final all = await s.drafts.listDrafts();
    if (!_orphanFilesChecked) {
      _orphanFilesChecked = true;
      try {
        await engine.deleteOrphanFiles({for (final d in all) d.recordingId});
      } on Object {
        // best effort — tried again on the next start-up
      }
    }
    final attempts = await _attempts(
      s,
      prune: [for (final d in all) d.draftId],
    );
    final held = await _held();
    return [
      for (final d in all)
        if (exclusionOf(d, attempts: attempts, held: held) == null) d,
    ];
  }

  /// The drafts out of automatic recovery because of their attempts (⑤ — the panel's
  /// '복구하지 못한 녹음이 있어요' line, 6.13.2; PDF T36b).
  Future<List<core.RecordingDraft>> stuck() async {
    final s = stores();
    final all = await s.drafts.listDrafts();
    final attempts = await _attempts(s);
    return [
      for (final d in all)
        if (RecoverAttempts.isStuck(attempts[d.draftId] ?? 0)) d,
    ];
  }

  /// The first of ①–⑤ that leaves [d] out, or null.
  DraftExclusion? exclusionOf(
    core.RecordingDraft d, {
    required Map<String, int> attempts,
    required Set<String>? held,
  }) {
    if (d.draftId == activeDraftId()) return DraftExclusion.activeSession;
    if (_recovering.contains(d.draftId)) return DraftExclusion.recovering;
    final window = MediaTuning.recentDraftWindowMs(config.webDraftChunkMs);
    if (now().millisecondsSinceEpoch - d.updatedAt < window) {
      return DraftExclusion.recent;
    }
    if (held != null && held.contains(recordingLockName(d.draftId))) {
      return DraftExclusion.locked;
    }
    if (RecoverAttempts.isStuck(attempts[d.draftId] ?? 0)) {
      return DraftExclusion.stuck;
    }
    return null;
  }

  /// recoverDraft (one at a time). `null` when the draft is not there (anymore), its bytes are
  /// empty or it was a permanent failure; StateError when pendingDrafts() leaves it out.
  Future<core.Recording?> recover(String draftId) {
    final run = _chain.then((_) => _recover(draftId));
    _chain = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<core.Recording?> _recover(String draftId) async {
    final s = stores();
    final all = await s.drafts.listDrafts();
    core.RecordingDraft? d;
    for (final x in all) {
      if (x.draftId == draftId) d = x;
    }
    if (d == null) return null;
    final why = exclusionOf(
      d,
      attempts: await _attempts(s),
      held: await _held(),
    );
    if (why != null) {
      throw StateError(
        'Recording draft $draftId cannot be recovered now (${why.name})',
      );
    }
    _recovering.add(draftId);
    try {
      final attempts = RecoverAttempts(s.settings);
      await attempts.increment(draftId); // before the attempt (6.10.3)

      RecorderEngineFile? file;
      Uint8List bytes;
      if (d.chunkCount > 0) {
        bytes = await s.drafts.readAll(draftId);
      } else {
        // native: the draft is a row only; the bytes are the file (6.9.5)
        file = await engine.leftoverFile(d.recordingId);
        try {
          bytes = file == null ? Uint8List(0) : await file.read();
        } on Object {
          bytes = Uint8List(0);
        }
      }
      if (bytes.isEmpty) {
        await _drop(s, d, file);
        return null;
      }

      var hold = ledger.hold(bytes.length);
      try {
        final length = await measureRecording(
          bytes,
          mimeType: d.mimeType,
          clockMs: d.activeMs,
          file: file,
        );
        if (file != null && length.source != DurationSource.probe) {
          // a native file the decoder cannot open (killed before moov — 6.9.5)
          await _drop(s, d, file);
          return null;
        }
        final patched = patchRecordingHead(
          bytes,
          mimeType: d.mimeType,
          durationMs: length.durationMs,
          hold: hold,
          ledger: ledger,
        );
        bytes = patched.bytes;
        hold = patched.hold;
        final core.Recording recording;
        try {
          recording = await storeRecording(
            s,
            bytes,
            recordingId: d.recordingId,
            noteId: d.noteId,
            mimeType: d.mimeType,
            durationMs: length.durationMs,
            startedAt: d.startedAt,
            title: MediaTuning.recoveredTitle,
          );
        } on core.EntityNotFoundException {
          await _drop(s, d, file);
          return null;
        }
        await _discard(s, draftId);
        await attempts.clear(draftId);
        await _deleteFile(file);
        diagnostics.recovered++;
        return recording;
      } finally {
        ledger.release(hold);
      }
    } finally {
      _recovering.remove(draftId);
    }
  }

  /// Permanent failure: the draft, its attempts and its file go.
  Future<void> _drop(
    RecorderStores s,
    core.RecordingDraft d,
    RecorderEngineFile? file,
  ) async {
    await _discard(s, d.draftId);
    await RecoverAttempts(s.settings).clear(d.draftId);
    await _deleteFile(file);
    diagnostics.dropped++;
  }

  Future<void> _discard(RecorderStores s, String draftId) async {
    try {
      await s.drafts.discard(draftId);
    } on StateError {
      // already gone (discarded elsewhere)
    }
  }

  Future<void> _deleteFile(RecorderEngineFile? file) async {
    if (file == null) return;
    try {
      await file.delete();
    } on Object {
      // an orphan file is removed by the next start-up's deleteOrphanFiles
    }
  }

  Future<Map<String, int>> _attempts(
    RecorderStores s, {
    List<String>? prune,
  }) async {
    final a = RecoverAttempts(s.settings);
    return prune == null ? a.read() : a.prune(prune);
  }

  Future<Set<String>?> _held() async {
    if (!locks.available) return null;
    try {
      return await locks.heldNames();
    } on Object {
      return null;
    }
  }
}
