// lib/src/ports/line_origin.dart — (internal) the second coordinate origin
// of a line (m5-7/05-library 6.4 v2.1, 6.20). The ML Kit adapter moves a
// line's points so the line box's top-left is (0, 0) before recognizing
// (the writing area is measured from there); the A-4 lab (L2-19) also sends
// the same strokes unmoved, in page pt, to record whether the origin changes
// the result. Not a contract port — engines without it simply get page pt.
import '../model/candidates.dart';
import '../model/handwriting_trace.dart';

/// An engine that can recognize a line without moving its points.
abstract interface class PageOriginLineRecognizer {
  /// Like HandwritingRecognizer.recognizeLine, but the points are sent in
  /// page pt as they are (no move to the line box's top-left).
  Future<List<TextCandidate>> recognizeLineInPageCoordinates(
    HandwritingLineInput line, {
    required String languageTag,
  });
}
