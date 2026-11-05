// lib/src/ink_adapter/ink_vectorizer.dart — 06-pdf 4.9, 6.11.8.
//
// Foundation step B4 (T0): signature only; the INK vector export adapter comes with
// PDF T12 (it will import package:ink_engine `as ink`, 3).
import 'package:note_core/note_core.dart' as core;

import '../export/vectors.dart';

/// ink.InkVectorExport.exportPage + ink.TemplateVectors.build (6.11.8).
final class InkEngineVectorizer implements PdfInkVectorizer {
  const InkEngineVectorizer();

  @override
  PdfPageVectors vectorize(
    core.Page page,
    List<core.Stroke> strokes, {
    required bool includeInk,
    required bool includeTemplate,
  }) => throw UnimplementedError('InkEngineVectorizer.vectorize (PDF T12)');
}
