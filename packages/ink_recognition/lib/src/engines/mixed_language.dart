// lib/src/engines/mixed_language.dart — (internal, pure) m5-7/05-library 6.8:
// strategy B of 03-recognition 3.4 — one line recognized with both the `ko`
// and the `en` model, merged WITHOUT comparing scores across models (the
// engines' scores are not on one scale — contract TextCandidate.score).
// Used by the A-4 lab (6.20) next to A (`ko`) and `en`; not shown in the
// conversion sheet until A-4 says so (12.2 Q3).
import '../model/candidates.dart';

/// Strategy B (03-recognition 3.4): never compares scores across models.
/// ko top has a Hangul syllable → ko list, then en top (if new).
/// Neither top has Hangul → en list, then ko top (if new).
/// ko top without Hangul but en top with Hangul (rare) → ko list.
// 'new' = no candidate of the list has the same text. An empty list has no
// top: ko empty → the en rule (en list, nothing to add); en empty with a
// non-Hangul ko top → [] + ko top. The input order of each list is kept.
List<TextCandidate> pickMixedCandidates(
  List<TextCandidate> ko,
  List<TextCandidate> en,
) {
  final koTop = ko.isEmpty ? null : ko.first;
  final enTop = en.isEmpty ? null : en.first;
  final koHangul = koTop != null && hasHangulSyllable(koTop.text);
  final enHangul = enTop != null && hasHangulSyllable(enTop.text);

  List<TextCandidate> withTop(List<TextCandidate> list, TextCandidate? top) => [
    ...list,
    if (top != null && !list.any((c) => c.text == top.text)) top,
  ];

  if (koHangul) return List.unmodifiable(withTop(ko, enTop));
  if (!enHangul) return List.unmodifiable(withTop(en, koTop));
  return List.unmodifiable(ko.isEmpty ? en : ko);
}

/// A precomposed Hangul syllable (U+AC00–U+D7A3) in [text].
bool hasHangulSyllable(String text) =>
    text.runes.any((r) => r >= 0xAC00 && r <= 0xD7A3);
