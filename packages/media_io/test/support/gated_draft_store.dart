// A RecordingDraftStore double for the draft writer (m5-7/06-pdf 6.8.5): records every append
// (draft id, bytes, activeMs, when), can hold appends open (a CORE commit retry never
// completes), make them throw (a blob write failure) or throw StateError (the draft was
// recovered elsewhere). The other members are not used by the writer.
import 'dart:async';
import 'dart:typed_data';

import 'package:note_core/note_core.dart' as core;

final class GatedDraftStore implements core.RecordingDraftStore {
  GatedDraftStore({this.now});

  /// For the [appends] timestamps (fake time); null → 0.
  final Duration Function()? now;

  /// Every append that started, in order.
  final List<({String draftId, Uint8List chunk, int activeMs, Duration at})>
  appends = [];

  /// Appends that completed.
  final List<Uint8List> written = [];

  /// While set, each append waits for it.
  Completer<void>? gate;

  /// The next appends throw these, in order (StateError → unknown draft).
  final List<Object> failures = [];

  /// Appends in flight now / the most at the same time.
  int inFlight = 0, maxInFlight = 0;

  @override
  Future<void> append(
    String draftId,
    Uint8List chunk, {
    required int activeMs,
  }) async {
    appends.add((
      draftId: draftId,
      chunk: chunk,
      activeMs: activeMs,
      at: now?.call() ?? Duration.zero,
    ));
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      final g = gate;
      if (g != null) await g.future;
      if (failures.isNotEmpty) {
        Error.throwWithStackTrace(failures.removeAt(0), StackTrace.current);
      }
      written.add(chunk);
    } finally {
      inFlight--;
    }
  }

  /// Lets the held appends go on.
  void open() {
    final g = gate;
    gate = null;
    g?.complete();
  }

  @override
  Future<core.RecordingDraft> begin({
    required core.RecordingId recordingId,
    required core.NoteId noteId,
    required String mimeType,
    required core.EpochMillis startedAt,
  }) => throw UnsupportedError('GatedDraftStore.begin');

  @override
  Future<void> discard(String draftId) =>
      throw UnsupportedError('GatedDraftStore.discard');

  @override
  Future<List<core.RecordingDraft>> listDrafts() =>
      throw UnsupportedError('GatedDraftStore.listDrafts');

  @override
  Future<Uint8List> readAll(String draftId) =>
      throw UnsupportedError('GatedDraftStore.readAll');
}
