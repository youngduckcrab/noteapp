// lib/src/model/names.dart — 05-library 6.12. Mirrors CORE C-6 (trimmed,
// String.length 1..200) so dialogs can refuse a name before calling CORE.

/// Longest folder name / note title (CORE C-6, String.length after trim).
const int kMaxItemNameLength = 200;

/// Largest number [uniqueName] appends ('새 폴더 999').
const int kMaxUniqueNameNumber = 999;

enum NameIssue { empty, tooLong }

/// Trims; empty → NameIssue.empty; length > 200 → NameIssue.tooLong; else null.
NameIssue? validateItemName(String raw) {
  final name = raw.trim();
  if (name.isEmpty) return NameIssue.empty;
  if (name.length > kMaxItemNameLength) return NameIssue.tooLong;
  return null;
}

final RegExp _whitespaceRun = RegExp(r'\s+');

/// trim → collapse internal whitespace runs to one space → toLowerCase.
String normalizeItemName(String name) =>
    name.trim().replaceAll(_whitespaceRun, ' ').toLowerCase();

/// [base] if no normalized match in [existing]; else '$base 2', '$base 3', …
/// (first free, up to 999; then [base]).
String uniqueName(String base, Iterable<String> existing) {
  final taken = {for (final name in existing) normalizeItemName(name)};
  if (!taken.contains(normalizeItemName(base))) return base;
  for (var n = 2; n <= kMaxUniqueNameNumber; n++) {
    final candidate = '$base $n';
    if (!taken.contains(normalizeItemName(candidate))) return candidate;
  }
  return base;
}
