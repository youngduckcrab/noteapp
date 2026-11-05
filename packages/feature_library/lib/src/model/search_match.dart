// lib/src/model/search_match.dart — 05-library 6.14: the highlighted part of
// a search result title.

/// `[start, end)` of [query] in [title], case-insensitive:
/// `title.toLowerCase().indexOf(query.toLowerCase())`. null when [query] is
/// empty or not found (CORE matches after normalizing Hangul jamo and spaces,
/// so a hit can have no visible match), and when lower-casing changes the
/// length of either string (the index would not point into [title]).
({int start, int end})? searchMatchRange(String title, String query) {
  if (query.isEmpty) return null;
  final lowerTitle = title.toLowerCase();
  final lowerQuery = query.toLowerCase();
  if (lowerTitle.length != title.length || lowerQuery.length != query.length) {
    return null;
  }
  final start = lowerTitle.indexOf(lowerQuery);
  if (start < 0) return null;
  return (start: start, end: start + query.length);
}
