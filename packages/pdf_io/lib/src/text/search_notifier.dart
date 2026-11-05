// lib/src/text/search_notifier.dart — single active search for the open editor
// (06-pdf 4.8, 6.10.2, 6.13; PDF T11).
//
// The search runs on pdfTextServiceProvider (read when a search starts, so reading this
// provider or pdfSearchHighlightsProvider never builds the render chain). Only ref.read is
// used here: pdfSearchHighlightsProvider and pdfBackgroundLayerBuilderProvider must never be
// rebuilt by a search (PDF-3-4).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_core/note_core.dart' as core;

import '../common/cancel_signal.dart';
import '../common/error_report.dart';
import '../errors.dart';
import '../providers.dart';
import 'search_types.dart';
import 'text_normalizer.dart';

class PdfSearchNotifier extends Notifier<PdfSearchState> {
  PdfCancelSignal? _cancel;
  StreamSubscription<PdfSearchProgress>? _subscription;

  /// PdfSearchState.idle
  @override
  PdfSearchState build() {
    ref.onDispose(_stop);
    return PdfSearchState.idle;
  }

  /// Cancels the previous search; empty query → idle.
  void start(core.NoteId noteId, String query) {
    _stop();
    if (PdfTextNormalizer.normalizeQuery(query).isEmpty) {
      state = PdfSearchState.idle;
      return;
    }
    final cancel = _cancel = PdfCancelSignal();
    state = PdfSearchState(
      noteId: noteId,
      query: query,
      status: PdfSearchStatus.searching,
    );
    final stream = ref
        .read(pdfTextServiceProvider)
        .searchNote(noteId, query, cancel: cancel);
    _subscription = stream.listen(
      (progress) {
        if (cancel.isCancelled) return;
        final hits = progress.newHits.isEmpty
            ? state.hits
            : List<PdfSearchHit>.unmodifiable([
                ...state.hits,
                ...progress.newHits,
              ]);
        state = PdfSearchState(
          noteId: noteId,
          query: query,
          status: progress.isDone
              ? PdfSearchStatus.done
              : PdfSearchStatus.searching,
          scannedPages: progress.scannedPages,
          totalPages: progress.totalPages,
          hits: hits,
          // The first result is selected as soon as it arrives (6.10.2 step 7).
          currentIndex: state.currentIndex < 0 && hits.isNotEmpty
              ? 0
              : state.currentIndex,
          truncated: progress.truncated,
        );
      },
      onError: (Object error, StackTrace stack) {
        if (cancel.isCancelled) return;
        final PdfIoException failure;
        if (error is PdfIoException) {
          failure = error;
        } else {
          reportPdfError(error, stack, 'pdf search');
          failure = PdfIoException(
            PdfErrorCode.corrupt,
            detail: 'search',
            cause: error,
          );
        }
        state = PdfSearchState(
          noteId: noteId,
          query: query,
          status: PdfSearchStatus.failed,
          scannedPages: state.scannedPages,
          totalPages: state.totalPages,
          hits: state.hits,
          currentIndex: state.currentIndex,
          truncated: state.truncated,
          error: failure,
        );
      },
      onDone: () {
        if (identical(_cancel, cancel)) {
          _cancel = null;
          _subscription = null;
        }
      },
    );
  }

  void select(int index) {
    final s = state;
    if (index < 0 || index >= s.hits.length) return;
    // A new but equal state when [index] is already current: Riverpod (previous != next)
    // and the highlights ValueNotifier skip it (PdfSearchState ==, PDF-3-2).
    state = _withCurrent(s, index);
  }

  /// wraps around
  void selectNext() {
    final s = state;
    if (s.hits.isEmpty) return;
    select((s.currentIndex + 1) % s.hits.length);
  }

  void selectPrevious() {
    final s = state;
    if (s.hits.isEmpty) return;
    final i = s.currentIndex <= 0 ? s.hits.length - 1 : s.currentIndex - 1;
    select(i);
  }

  void clear() {
    _stop();
    state = PdfSearchState.idle;
  }

  /// stopPdfSearch: cancels a running search and keeps the hits found so far (status idle,
  /// so the panel starts it again when it reopens for the same note).
  void _stopRunning() {
    if (state.status != PdfSearchStatus.searching) return;
    _stop();
    final s = state;
    state = PdfSearchState(
      noteId: s.noteId,
      query: s.query,
      scannedPages: s.scannedPages,
      totalPages: s.totalPages,
      hits: s.hits,
      currentIndex: s.currentIndex,
      truncated: s.truncated,
    );
  }

  /// Cancels the running search (its stream ends without an error, 6.10.2 step 0).
  void _stop() {
    _cancel?.cancel();
    _cancel = null;
    // Not awaited: under fake_async the cancel Future may complete in the root zone.
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  static PdfSearchState _withCurrent(PdfSearchState s, int index) =>
      PdfSearchState(
        noteId: s.noteId,
        query: s.query,
        status: s.status,
        scannedPages: s.scannedPages,
        totalPages: s.totalPages,
        hits: s.hits,
        currentIndex: index,
        truncated: s.truncated,
        error: s.error,
      );
}

/// Internal (not exported): the search panel was closed (6.10.2 step 0 — closing the panel
/// cancels its search). A running search stops; its hits so far stay highlighted with status
/// idle. A finished search is left as it is (its highlights stay until a new query or
/// clear()).
void stopPdfSearch(PdfSearchNotifier notifier) => notifier._stopRunning();
