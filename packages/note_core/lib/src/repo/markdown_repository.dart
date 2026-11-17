// lib/src/repo/markdown_repository.dart — (v2.17-md) contract 00-overview 7.9 C217M-04,
// m5-7/08-markdown.md 4 and 12.1: MD 문서 (markdown documents). An MD 문서 is a Note whose
// format is markdown (schemaVersion 100..199, see kMarkdownNoteSchemaVersion) plus ONE body
// entity holding the original text. Library, trash, recent, favourites, rename, move and copy
// are the Note rules unchanged; this repository reads and writes the body.
import 'dart:convert';

import 'package:meta/meta.dart';

import '../common/errors.dart';
import '../common/hlc.dart';
import '../common/ids.dart';
import '../model/note.dart';

/// Size limits of an MD 문서 (C217M-04, 08-markdown 4.4).
abstract final class MarkdownLimits {
  /// UTF-8 bytes of the original text (BOM and CRLF included).
  static const int maxTextBytes = 400000;

  /// UTF-8 bytes of the text written as a JSON string — what one sync record carries
  /// (control characters cost 6 bytes as `\u00XX`). Leaves 100,000 of the 1,000,000-byte
  /// record cap for the other keys and the field versions (08-markdown 4.4, review D4).
  static const int maxEncodedBytes = 900000;

  /// Files in one 'MD 가져오기'.
  static const int maxImportFiles = 20;

  /// Characters of a library card preview.
  static const int previewChars = 400;

  /// UTF-8 length of [text] without encoding it (a lone surrogate counts 3, as U+FFFD).
  static int utf8BytesOf(String text) {
    var n = 0;
    final length = text.length;
    for (var i = 0; i < length; i++) {
      final c = text.codeUnitAt(i);
      if (c < 0x80) {
        n += 1;
      } else if (c < 0x800) {
        n += 2;
      } else if (c >= 0xD800 &&
          c <= 0xDBFF &&
          i + 1 < length &&
          (text.codeUnitAt(i + 1) & 0xFC00) == 0xDC00) {
        n += 4;
        i++;
      } else {
        n += 3;
      }
    }
    return n;
  }

  /// UTF-8 length of `jsonEncode(text)` (the quotes included).
  static int encodedBytesOf(String text) => utf8BytesOf(jsonEncode(text));

  /// Throws [MarkdownTooLargeException] when [text] is over [maxTextBytes] or
  /// [maxEncodedBytes]. Every write of a body (create, save, import, conflict copy) calls it
  /// before it changes anything.
  static void check(String text) {
    final bytes = utf8BytesOf(text);
    if (bytes > maxTextBytes) {
      throw MarkdownTooLargeException(
        'MD text is $bytes bytes (at most $maxTextBytes)',
        bytes: bytes,
        encodedBytes: bytes,
      );
    }
    final encoded = encodedBytesOf(text);
    if (encoded > maxEncodedBytes) {
      throw MarkdownTooLargeException(
        'MD text takes $encoded bytes in a sync record (at most $maxEncodedBytes)',
        bytes: bytes,
        encodedBytes: encoded,
      );
    }
  }
}

/// Why an MD 문서 cannot be edited now (the screen shows one banner per reason).
enum MarkdownReadOnlyReason {
  /// In the trash.
  trashed,

  /// Written by a newer app (`Note.requiresNewerApp`).
  newerApp,

  /// The note arrived by sync before its body: editing would overwrite the real body with
  /// an edit of the empty text (08-markdown 5.3).
  bodyMissing,
}

/// One MD 문서: the note and its body.
@immutable
final class MarkdownDoc {
  const MarkdownDoc({
    required this.note,
    required this.text,
    required this.bodyPresent,
    this.textVersion,
  });

  /// `note.isMarkdown` is always true.
  final Note note;

  /// The original text, byte for byte (BOM and CRLF kept); '' while [bodyPresent] is false.
  final String text;

  /// False while the body has not arrived yet (sync) — read-only.
  final bool bodyPresent;

  /// The field version of the last write of [text] (null in the fake store's first write
  /// and while [bodyPresent] is false). The editor passes the version it loaded as
  /// `baseVersion` to [MarkdownRepository.saveText].
  final Hlc? textVersion;

  MarkdownReadOnlyReason? get readOnlyReason => note.isDeleted
      ? MarkdownReadOnlyReason.trashed
      : note.requiresNewerApp
      ? MarkdownReadOnlyReason.newerApp
      : !bodyPresent
      ? MarkdownReadOnlyReason.bodyMissing
      : null;

  bool get isReadOnly => readOnlyReason != null;

  @override
  bool operator ==(Object other) =>
      other is MarkdownDoc &&
      other.note == note &&
      other.text == text &&
      other.bodyPresent == bodyPresent &&
      other.textVersion == textVersion;

  @override
  int get hashCode => Object.hash(note, text, bodyPresent, textVersion);

  @override
  String toString() =>
      'MarkdownDoc(${note.id}, ${text.length} chars'
      '${bodyPresent ? '' : ', no body'}, v: $textVersion)';
}

/// What [MarkdownRepository.saveText] did.
enum MarkdownSaveOutcome {
  /// The text was written.
  saved,

  /// The stored text already equals the given text: nothing was written.
  unchanged,

  /// The stored text had changed since `baseVersion` (another device's text arrived, or
  /// another writer saved): that stored text was first kept as a new MD 문서
  /// (`MarkdownConflictCopy.titleFor`, same folder), then the given text was written. Both
  /// texts exist — nothing is lost silently (08-markdown 5.3 L1).
  savedWithConflictCopy,
}

@immutable
final class MarkdownSaveResult {
  const MarkdownSaveResult({
    required this.outcome,
    required this.textVersion,
    this.conflictCopyId,
  });

  final MarkdownSaveOutcome outcome;

  /// The field version of the stored text afterwards — the editor's next `baseVersion`.
  final Hlc? textVersion;

  /// The new MD 문서 of [MarkdownSaveOutcome.savedWithConflictCopy].
  final NoteId? conflictCopyId;

  @override
  bool operator ==(Object other) =>
      other is MarkdownSaveResult &&
      other.outcome == outcome &&
      other.textVersion == textVersion &&
      other.conflictCopyId == conflictCopyId;

  @override
  int get hashCode => Object.hash(outcome, textVersion, conflictCopyId);

  @override
  String toString() =>
      'MarkdownSaveResult(${outcome.name}, v: $textVersion'
      '${conflictCopyId == null ? '' : ', copy: $conflictCopyId'})';
}

/// The name of a conflict copy (C217M-07): '<제목> (충돌 사본 yyyy-MM-dd HH:mm)', cut so the
/// whole name fits 200 characters (the title is cut, never the suffix, never inside a
/// surrogate pair).
abstract final class MarkdownConflictCopy {
  static String titleFor(String title, DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    final suffix =
        ' (충돌 사본 ${at.year.toString().padLeft(4, '0')}-${two(at.month)}-'
        '${two(at.day)} ${two(at.hour)}:${two(at.minute)})';
    final base = title.trim();
    if (base.length + suffix.length <= 200) return base + suffix;
    var cut = 200 - suffix.length;
    final unit = base.codeUnitAt(cut - 1);
    if (unit >= 0xD800 && unit <= 0xDBFF) cut--;
    return base.substring(0, cut).trimRight() + suffix;
  }
}

/// Plain-text preview of an MD 문서 for library cards (C217M-04, 08-markdown 9): a light,
/// parser-free clean-up — no `package:markdown` in note_core.
abstract final class MarkdownPreviewText {
  static final RegExp _fence = RegExp(r'^\s{0,3}(```|~~~)');
  static final RegExp _heading = RegExp(r'^\s{0,3}#{1,6}(\s+|$)');
  static final RegExp _quote = RegExp(r'^\s{0,3}>\s?');
  static final RegExp _list = RegExp(r'^\s*(?:[-*+]|\d{1,9}[.)])\s+');
  static final RegExp _task = RegExp(r'^\[[ xX]\]\s+');
  static final RegExp _rule = RegExp(r'^\s{0,3}([-*_])(\s*\1){2,}\s*$');
  static final RegExp _tableRule = RegExp(
    r'^\s*\|?\s*:?-{1,}:?\s*(\|\s*:?-{1,}:?\s*)*\|?\s*$',
  );
  static final RegExp _image = RegExp(r'!\[([^\]]*)\]\([^)]*\)');
  static final RegExp _link = RegExp(r'\[([^\]]*)\]\([^)]*\)');
  static final RegExp _tag = RegExp(r'<\/?[A-Za-z][^<>]*>');
  static final RegExp _marks = RegExp(r'(\*{1,3}|_{2,3}|~~|`+)');
  static final RegExp _spaces = RegExp(r'[ \t]+');

  /// Lines of [text] (front matter skipped, block markers and inline marks removed, empty
  /// lines dropped) joined with '\n', at most [maxChars] characters.
  static String of(String text, {int maxChars = MarkdownLimits.previewChars}) {
    if (maxChars <= 0) return '';
    var lines = text
        .replaceFirst('﻿', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    // YAML front matter ('---' first line … '---' or '...').
    if (lines.isNotEmpty && lines.first.trim() == '---') {
      final end = lines.indexWhere(
        (l) => l.trim() == '---' || l.trim() == '...',
        1,
      );
      if (end > 0) lines = lines.sublist(end + 1);
    }
    final out = StringBuffer();
    var length = 0;
    for (var line in lines) {
      if (_fence.hasMatch(line) || _rule.hasMatch(line)) continue;
      if (_tableRule.hasMatch(line) && line.contains('-')) continue;
      line = line.replaceFirst(_heading, '');
      while (_quote.hasMatch(line)) {
        line = line.replaceFirst(_quote, '');
      }
      line = line.replaceFirst(_list, '');
      line = line.replaceFirst(_task, '');
      line = line
          .replaceAllMapped(_image, (m) => m.group(1)!)
          .replaceAllMapped(_link, (m) => m.group(1)!)
          .replaceAll(_tag, '')
          .replaceAll(_marks, '')
          .replaceAll('|', ' ')
          .replaceAll(_spaces, ' ')
          .trim();
      if (line.isEmpty) continue;
      if (length > 0) {
        out.write('\n');
        length++;
      }
      out.write(line);
      length += line.length;
      if (length >= maxChars) break;
    }
    final s = out.toString();
    if (s.length <= maxChars) return s;
    var cut = maxChars;
    final unit = s.codeUnitAt(cut - 1);
    if (unit >= 0xD800 && unit <= 0xDBFF) cut--;
    return s.substring(0, cut);
  }
}

/// Key of `markdownPreviewProvider`: the note's `updatedAt` is part of the key, so a card
/// never shows a stale preview after an edit.
typedef MarkdownPreviewKey = ({NoteId noteId, EpochMillis updatedAt});

/// (v2.17-md) `NoteStore.markdown` (C217M-04). Real store: Track A (DriftMarkdownRepository);
/// fake store: complete in-memory implementation.
abstract interface class MarkdownRepository {
  /// The MD 문서 [id]; null when the note does not exist (or was purged) or is not an MD
  /// 문서. Trashed documents ARE returned (read-only). Current value right after listen, then
  /// on every change (C-1).
  Stream<MarkdownDoc?> watch(NoteId id);

  /// Same value as the first [watch] event.
  Future<MarkdownDoc?> get(NoteId id);

  /// A new MD 문서: the Note (schemaVersion kMarkdownNoteSchemaVersion, no pages) and its
  /// body in ONE transaction, at the end of [folderId]. Title rules = createNote (trimmed,
  /// 1..200 characters, else ArgumentError). EntityNotFoundException (folder),
  /// MarkdownTooLargeException ([text], `MarkdownLimits.check`).
  Future<Note> create({
    FolderId? folderId,
    required String title,
    String text = '',
  });

  /// Writes [text] as the document's text: one local write (outbox 'text'), the note's
  /// updatedAt bumped. [baseVersion] = the `MarkdownDoc.textVersion` the caller's text was
  /// based on (null if it loaded none):
  ///
  /// * stored text == [text] → [MarkdownSaveOutcome.unchanged], nothing written;
  /// * stored version == [baseVersion] → [MarkdownSaveOutcome.saved];
  /// * otherwise the stored text is first kept as a conflict copy (a new MD 문서 in the same
  ///   folder, `MarkdownConflictCopy.titleFor(title, now)`), then [text] is written →
  ///   [MarkdownSaveOutcome.savedWithConflictCopy]. One transaction.
  ///
  /// Throws before any change: EntityNotFoundException (no such note), WrongNoteFormatException
  /// (not an MD 문서), ReadOnlyNoteException (`MarkdownDoc.isReadOnly`),
  /// MarkdownTooLargeException (`MarkdownLimits.check`).
  Future<MarkdownSaveResult> saveText(
    NoteId id,
    String text, {
    required Hlc? baseVersion,
  });

  /// Card preview: `MarkdownPreviewText.of` of the text ('' without a body or note).
  Future<String> preview(
    NoteId id, {
    int maxChars = MarkdownLimits.previewChars,
  });
}
