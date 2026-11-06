// lib/src/indexer/handwriting_indexer.dart — contract m5-7/00-overview 7.2.11
// (m5-7/05-library 4.4.7, 6.9).
//
// 2차 foundation step R2-B6 (contract 7.6.2): the contract constructor and
// members only — start() does nothing (status stays `off`), dispose() is
// idempotent and status is a fixed `off` value. The constructor arguments are
// not kept yet. LIBRARY L2-10a (schedule, page jobs, status) and L2-10b (line
// reuse, merge, catch-up, lifecycle) fill in the behaviour documented on
// start() below.
import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart' as core;

import '../ports/handwriting_recognizer.dart';
import 'indexer_status.dart';

final class HandwritingIndexer {
  HandwritingIndexer({
    required core.NoteStore store,
    required HandwritingRecognizer recognizer,
    required ValueListenable<bool> enabled,
    ValueListenable<bool>?
    foreground, // (v2.1, CP-L10) default: AppLifecycleListener
  });

  final ValueNotifier<HandwritingIndexerStatus> _status =
      ValueNotifier<HandwritingIndexerStatus>(const HandwritingIndexerStatus());
  bool _disposed = false;

  /// Watches NoteStore.changes (stroke → pageId; (v2.1) handwriting → abandon that page's job and
  /// requeue it), waits for idle (≥ 3 s no local input on that page, 30 s after a remote change),
  /// asks stalePages first (no point decode), recognizes line by line yielding between lines, writes
  /// with HandwritingRepository.update (merged with what is stored — G-4). (v2.1) Fresh = same
  /// sourceRev and language; another engine id / version / device is fresh. Start-up catch-up:
  /// notesWithStalePages(). Never runs on web. dispose() is idempotent.
  // R2-B6: does nothing (idempotent; phase stays off).
  void start() {
    if (_disposed) return;
  }

  /// Idempotent (INFRA R-3: the provider's onDispose and INFRA's idle task
  /// shutdown may both call it). Never disposes the recognizer (the provider
  /// owns it).
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _status.value = const HandwritingIndexerStatus();
  }

  ValueListenable<HandwritingIndexerStatus> get status => _status;
}
