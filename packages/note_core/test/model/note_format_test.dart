// (v2.17-md, m5-7/08-markdown 4.1, MD-T01) NoteFormat is derived from Note.schemaVersion:
// no new field, so the note JSON (and every golden) stays byte-identical.
import 'dart:convert';

import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

Note _note({int schemaVersion = kNoteSchemaVersion, EpochMillis? deletedAt}) =>
    Note(
      id: 'n1',
      ownerId: kLocalOwnerId,
      title: 'Doc',
      sortKey: 'a0',
      schemaVersion: schemaVersion,
      createdAt: 1,
      updatedAt: 2,
      deletedAt: deletedAt,
    );

void main() {
  test(
    'ofSchemaVersion ranges: <100 ink, 100..199 markdown, >=200 unknown',
    () {
      expect(NoteFormat.ofSchemaVersion(0), NoteFormat.ink);
      expect(NoteFormat.ofSchemaVersion(1), NoteFormat.ink);
      expect(NoteFormat.ofSchemaVersion(99), NoteFormat.ink);
      expect(NoteFormat.ofSchemaVersion(100), NoteFormat.markdown);
      expect(NoteFormat.ofSchemaVersion(199), NoteFormat.markdown);
      expect(NoteFormat.ofSchemaVersion(200), NoteFormat.unknown);
      expect(NoteFormat.ofSchemaVersion(1 << 30), NoteFormat.unknown);
    },
  );

  test('requiresNewerApp compares with the version of the note format', () {
    expect(_note().requiresNewerApp, isFalse);
    expect(_note(schemaVersion: 2).requiresNewerApp, isTrue);
    expect(_note(schemaVersion: 99).requiresNewerApp, isTrue);
    final md = _note(schemaVersion: kMarkdownNoteSchemaVersion);
    expect(md.format, NoteFormat.markdown);
    expect(md.isMarkdown, isTrue);
    expect(md.requiresNewerApp, isFalse);
    expect(_note(schemaVersion: 101).requiresNewerApp, isTrue);
    expect(_note(schemaVersion: 101).isMarkdown, isTrue);
    expect(_note(schemaVersion: 250).requiresNewerApp, isTrue);
    expect(_note(schemaVersion: 250).isMarkdown, isFalse);
    expect(_note().format, NoteFormat.ink);
    expect(_note().isMarkdown, isFalse);
  });

  test('JSON: no format key, an MD note round-trips through schemaVersion', () {
    final ink = _note();
    expect(ink.toJson().containsKey('format'), isFalse);
    final md = _note(schemaVersion: kMarkdownNoteSchemaVersion);
    final json = jsonDecode(jsonEncode(md.toJson())) as Map<String, Object?>;
    expect(json.keys, ink.toJson().keys);
    final back = Note.fromJson(json);
    expect(back, md);
    expect(back.isMarkdown, isTrue);
  });

  test('copyWith keeps the format (copy paths pass schemaVersion)', () {
    final md = _note(schemaVersion: kMarkdownNoteSchemaVersion);
    expect(md.copyWith(title: 'x', updatedAt: 9).isMarkdown, isTrue);
    expect(md.toString(), contains('markdown'));
    expect(_note().toString(), isNot(contains('markdown')));
  });
}
