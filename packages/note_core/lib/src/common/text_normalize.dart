// lib/src/common/text_normalize.dart — internal, shared by the DB store and the fake store
// (CORE 4.1, 6.8). (v2, m5-7/02-core 6.10.1 — review S-16, CORE T24) The title / name
// search form is the one normalization of the search index: SearchText.normalize.
import '../search/search_text.dart';

/// name_norm / title_norm / title search query form (6.8): SearchText.normalize (line-end
/// hyphen joining, zero-width characters removed, whitespace runs → one space, Hangul
/// conjoining jamo composed, per-code-point lowercase, trimmed — 6.10.1). The v1 → v2
/// upgrade recomputes the stored columns with the same function (6.12.1 step 5).
String normalizeForSearch(String text) => SearchText.normalize(text);
