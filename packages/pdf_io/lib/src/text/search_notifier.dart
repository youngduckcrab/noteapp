// lib/src/text/search_notifier.dart — single active search for the open editor
// (06-pdf 4.8, 6.10.2, 6.13).
//
// Foundation step B4 (T0): build() is real (pdfActiveSearchProvider reads as idle); the
// search actions come with PDF T11.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_core/note_core.dart' as core;

import 'search_types.dart';

class PdfSearchNotifier extends Notifier<PdfSearchState> {
  /// PdfSearchState.idle
  @override
  PdfSearchState build() => PdfSearchState.idle;

  /// Cancels the previous search; empty query → idle.
  void start(core.NoteId noteId, String query) =>
      throw UnimplementedError('PdfSearchNotifier.start (PDF T11)');

  void select(int index) =>
      throw UnimplementedError('PdfSearchNotifier.select (PDF T11)');

  /// wraps around
  void selectNext() =>
      throw UnimplementedError('PdfSearchNotifier.selectNext (PDF T11)');

  void selectPrevious() =>
      throw UnimplementedError('PdfSearchNotifier.selectPrevious (PDF T11)');

  void clear() => throw UnimplementedError('PdfSearchNotifier.clear (PDF T11)');
}
