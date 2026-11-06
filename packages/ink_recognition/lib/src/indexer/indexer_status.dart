// lib/src/indexer/indexer_status.dart — contract m5-7/00-overview 7.2.11
// (v2.1, CP-L1; m5-7/05-library 4.4.1, 6.19). Final since the 2차
// foundation step R2-B6.
//
// The value the indexer publishes. INFRA's developer overlay and the settings
// section read it; toString() is the one-line overlay form of 6.19.
import 'package:meta/meta.dart';

// (v2.1, CP-L1) status fields (05-library 4.4.1 — toString() is the one-line overlay form):
enum HandwritingIndexerPhase {
  off, // not started, disposed, web, or recognizer unavailable
  disabled, // started; recog.autoIndex is false
  waitingModel, // enabled; the model for languageTag is not ready
  idle, // enabled; nothing queued
  waitingInput, // pages queued, waiting for their quiet time (3 s local / 30 s remote)
  recognizing, // one line in flight
  paused, // app lifecycle is not resumed
}

@immutable
final class HandwritingIndexerStatus {
  const HandwritingIndexerStatus({
    this.phase = HandwritingIndexerPhase.off,
    this.languageTag,
    this.queuedPages = 0,
    this.indexedPages = 0,
    this.failedPages = 0,
    this.currentPageId,
    this.lastError,
  });

  final HandwritingIndexerPhase phase;

  /// recog.language in use
  final String? languageTag;

  /// dirty pages + catch-up queue
  final int queuedPages;

  /// pages written since start(): update that stored a value, or removeForPage
  final int indexedPages;

  /// pages skipped after an engine error (until their ink changes)
  final int failedPages;
  final String? currentPageId;

  /// Short English, developer overlay only. In waitingModel it is the reason (v2.1, review S-9):
  /// 'model ko: waiting for Wi-Fi' (Android, wifiOnly) / 'model ko: not downloaded' (iOS).
  final String? lastError;

  /// One line, e.g. 'recognizing · ko · queue 3 · done 12 · failed 0' (INFRA overlay until CP4).
  /// 6.19: `off`; `disabled · ko` and `waitingModel · ko` (+ ` · lastError`);
  /// the other phases add `page <id>` while one is current, then the counts.
  @override
  String toString() {
    final parts = <String>[phase.name];
    if (phase == HandwritingIndexerPhase.off) return parts.single;
    final lang = languageTag;
    if (lang != null) parts.add(lang);
    switch (phase) {
      case HandwritingIndexerPhase.disabled:
        break;
      case HandwritingIndexerPhase.waitingModel:
        final reason = lastError;
        if (reason != null) parts.add(reason);
      case HandwritingIndexerPhase.off:
      case HandwritingIndexerPhase.idle:
      case HandwritingIndexerPhase.waitingInput:
      case HandwritingIndexerPhase.recognizing:
      case HandwritingIndexerPhase.paused:
        final page = currentPageId;
        if (page != null) parts.add('page $page');
        parts
          ..add('queue $queuedPages')
          ..add('done $indexedPages')
          ..add('failed $failedPages');
    }
    return parts.join(' · ');
  }

  @override
  bool operator ==(Object other) =>
      other is HandwritingIndexerStatus &&
      other.phase == phase &&
      other.languageTag == languageTag &&
      other.queuedPages == queuedPages &&
      other.indexedPages == indexedPages &&
      other.failedPages == failedPages &&
      other.currentPageId == currentPageId &&
      other.lastError == lastError;

  @override
  int get hashCode => Object.hash(
    phase,
    languageTag,
    queuedPages,
    indexedPages,
    failedPages,
    currentPageId,
    lastError,
  );
}
