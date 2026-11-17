// (v2.17-md, m5-7/08-markdown 4.3–4.5, MD-T02 · MD-T03 · MD-T05 real half) The SQLite store
// passes the shared MarkdownRepository contract, plus what only it has: the outbox entries of
// a body write, md_docs.text_bytes, base_text_version on remote apply and acknowledge, the
// format guard of remote note writes, the preview through SQL substr, and the store reopened
// from a file.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/testing.dart';
import 'package:note_core/testing_vm.dart';
import 'package:test/test.dart';

import '../shared/markdown_contract.dart';

const String kOtherNode = 'ffffffffffffffff';

/// The body of [noteId] gone (the note arrived by sync before its body).
Future<void> removeBodyReal(NoteStore store, NoteId noteId) async {
  final s = store as DriftNoteStore;
  await s.queue.run((tx) async {
    await s.db.customStatement('DELETE FROM md_docs WHERE note_id = ?', [
      noteId,
    ]);
    tx.touch(EntityKind.markdown);
  });
}

/// [text] arriving from another device (a newer version of [kOtherNode]), after this
/// device's text was uploaded (its pending body entry acknowledged) — otherwise the apply
/// keeps the unsent local text as a conflict copy (08-markdown 5.3 L2).
Future<Hlc> remoteTextReal(NoteStore store, NoteId noteId, String text) async {
  final s = store as DriftNoteStore;
  final current = (await store.markdown.get(noteId))!;
  await store.sync.acknowledge([
    for (final e in await store.sync.pendingChanges())
      if (e.kind == EntityKind.markdown &&
          e.entityId == MarkdownText.idFor(noteId))
        OutboxAck(e.seq, e.rev, uploadedTextVersion: current.textVersion),
  ]);
  final last = s.queue.hlc.last;
  final v = Hlc(last.millis, last.counter + 1, kOtherNode);
  final body = MarkdownText(
    noteId: noteId,
    text: text,
    createdAt: current.note.createdAt,
    updatedAt: s.clock.now().millisecondsSinceEpoch,
    version: v,
  );
  await store.sync.applyRemote([
    RemoteUpsert(body, EntityFieldVersions(v)),
  ], policy: newerVersionWinsPolicy);
  return v;
}

void main() {
  defineMarkdownContract((clock) => openTestNoteStore(clock: clock), (
    removeBody: removeBodyReal,
    remoteText: remoteTextReal,
  ));

  group('SQLite store only', () {
    late DriftNoteStore store;
    setUp(() async {
      store = await openTestNoteStore(
        clock: Clock.fixed(DateTime.utc(2026, 11, 17, 9)),
        seedDefaultPenPresets: false,
      ) as DriftNoteStore;
    });
    tearDown(() => store.close());

    Future<List<OutboxEntry>> outbox() => store.sync.pendingChanges();

    Future<Map<String, Object?>> row(NoteId noteId) async =>
        (await store.db
                .customSelect(
                  'SELECT * FROM md_docs WHERE note_id = ?',
                  variables: [Variable<String>(noteId)],
                )
                .getSingle())
            .data;

    test(
      'create: note + body in the outbox (*), saveText: body [text] with the '
      'noteId hint, the note updated_at without an outbox field',
      () async {
        final note = await store.markdown.create(title: '문서', text: '하나');
        var entries = await outbox();
        expect(
          {for (final e in entries) (e.kind, e.entityId): e.changedFields},
          {
            (EntityKind.note, note.id): {kAllFields},
            (EntityKind.markdown, MarkdownText.idFor(note.id)): {kAllFields},
          },
        );
        await store.sync.acknowledge([for (final e in entries) e.ack]);
        final doc = (await store.markdown.get(note.id))!;
        await store.markdown.saveText(
          note.id,
          '둘',
          baseVersion: doc.textVersion,
        );
        entries = await outbox();
        expect(entries, hasLength(1));
        expect(entries.single.kind, EntityKind.markdown);
        expect(entries.single.changedFields, {'text'});
        expect(entries.single.noteId, note.id);
        final r = await row(note.id);
        expect(r['text_bytes'], utf8.encode('둘').length);
      },
    );

    test('preview reads a SQL prefix of a long body', () async {
      final note = await store.markdown.create(
        title: 'p',
        text: '# 첫 줄\n${'본문 ' * 50000}',
      );
      final p = await store.markdown.preview(note.id, maxChars: 20);
      expect(p, startsWith('첫 줄\n본문'));
      expect(p.length, lessThanOrEqualTo(20));
    });

    test('base_text_version: received text (remote apply) and the '
        'acknowledged upload (OutboxAck.uploadedTextVersion)', () async {
      final note = await store.markdown.create(title: 'b', text: 'x');
      expect((await row(note.id))['base_text_version'], isNull);
      final remote = await remoteTextReal(store, note.id, 'y');
      expect((await row(note.id))['base_text_version'], '$remote');
      // A local edit, then its upload is acknowledged with the uploaded version.
      final doc = (await store.markdown.get(note.id))!;
      final saved = await store.markdown.saveText(
        note.id,
        'z',
        baseVersion: doc.textVersion,
      );
      final entry = (await outbox()).singleWhere(
        (e) => e.kind == EntityKind.markdown,
      );
      // The user types again during the upload: the entry's rev moves on.
      await store.markdown.saveText(
        note.id,
        'zz',
        baseVersion: saved.textVersion,
      );
      await store.sync.acknowledge([
        OutboxAck(entry.seq, entry.rev, uploadedTextVersion: saved.textVersion),
      ]);
      expect((await row(note.id))['base_text_version'], '${saved.textVersion}');
      // The newer edit stays pending.
      expect(
        (await outbox()).where((e) => e.kind == EntityKind.markdown),
        hasLength(1),
      );
    });

    test('a remote note write that changes the format is rejected', () async {
      final note = await store.markdown.create(title: 'f', text: 'x');
      final last = store.queue.hlc.last;
      final v = Hlc(last.millis + 1, 0, kOtherNode);
      final ink = Note(
        id: note.id,
        ownerId: note.ownerId,
        title: note.title,
        sortKey: note.sortKey,
        createdAt: note.createdAt,
        updatedAt: note.updatedAt,
        version: v,
      );
      await expectLater(
        store.sync.applyRemote([
          RemoteUpsert(ink, EntityFieldVersions(v)),
        ], policy: newerVersionWinsPolicy),
        throwsArgumentError,
      );
      expect((await store.markdown.get(note.id))!.note.isMarkdown, isTrue);
      // A remote MD note (new id) is stored as an MD 문서; its body may come later.
      final other = Note(
        id: 'remote-md',
        ownerId: note.ownerId,
        title: '받은 문서',
        sortKey: 'b0',
        schemaVersion: kMarkdownNoteSchemaVersion,
        createdAt: 1,
        updatedAt: 1,
        version: v,
      );
      await store.sync.applyRemote([
        RemoteUpsert(other, EntityFieldVersions(v)),
      ], policy: newerVersionWinsPolicy);
      final received = (await store.markdown.get('remote-md'))!;
      expect(received.bodyPresent, isFalse);
      expect(received.readOnlyReason, MarkdownReadOnlyReason.bodyMissing);
    });

    test('a received body moves its note up in recent order', () async {
      final note = await store.markdown.create(title: 'r', text: 'x');
      final before = (await store.markdown.get(note.id))!.note.updatedAt;
      final s = store;
      final last = s.queue.hlc.last;
      final v = Hlc(last.millis, last.counter + 1, kOtherNode);
      await store.sync.applyRemote([
        RemoteUpsert(
          MarkdownText(
            noteId: note.id,
            text: 'later',
            createdAt: 1,
            updatedAt: before + 60000,
            version: v,
          ),
          EntityFieldVersions(v),
        ),
      ], policy: newerVersionWinsPolicy);
      expect(
        (await store.markdown.get(note.id))!.note.updatedAt,
        before + 60000,
      );
    });

    test('purge deletes the body row, its search units and the outbox entry', () async {
      final note = await store.markdown.create(title: 'g', text: '지울 글');
      await store.library.trashItems([NoteRef(note.id)]);
      await store.trash.purge([NoteRef(note.id)]);
      final left = await store.db
          .customSelect(
            'SELECT (SELECT count(*) FROM md_docs) AS d, '
            "(SELECT count(*) FROM search_owners WHERE source = 'markdown') AS o, "
            "(SELECT count(*) FROM search_units WHERE source = 'markdown') AS u, "
            "(SELECT count(*) FROM outbox WHERE entity_kind = 'markdown') AS q",
          )
          .getSingle();
      expect(left.data, {'d': 0, 'o': 0, 'u': 0, 'q': 0});
    });

    test('duplicateNoteForRecovery copies the body', () async {
      final note = await store.markdown.create(title: '원본', text: '살릴 글');
      final copy = await store.sync.duplicateNoteForRecovery(
        note.id,
        titleSuffix: ' (복구)',
      );
      final doc = (await store.markdown.get(copy!))!;
      expect(doc.text, '살릴 글');
      expect(doc.note.title, '원본 (복구)');
      expect(doc.note.isMarkdown, isTrue);
    });
  });

  test('a file store reopened keeps the text byte for byte', () async {
    final dir = Directory.systemTemp.createTempSync('md_reopen_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/notes.db';
    const text = '﻿# 제목\r\n본문 🙂\r\n';
    var store = await openTestNoteStore(filePath: path);
    final note = await store.markdown.create(title: 'f', text: text);
    await store.close();
    store = await openTestNoteStore(filePath: path);
    addTearDown(store.close);
    final doc = (await store.markdown.get(note.id))!;
    expect(utf8.encode(doc.text), utf8.encode(text));
    expect(await store.search.searchPages('본문'), hasLength(1));
  });

  test('NoteMigrator leaves MD documents alone (schemaVersion ≥ 1)', () async {
    final store = await openTestNoteStore();
    addTearDown(store.close);
    final note = await store.markdown.create(title: 'm', text: 'x');
    final migrated = await (store as DriftNoteStore).noteMigrator
        .migrateIfNeeded(note.id);
    expect(migrated.schemaVersion, kMarkdownNoteSchemaVersion);
    expect((await store.markdown.get(note.id))!.text, 'x');
  });

  test('a lone surrogate is stored as U+FFFD and saving the same editor text '
      'again is a no-op (review finding)', () async {
    final store = await openTestNoteStore();
    addTearDown(store.close);
    final note = await store.markdown.create(title: 's', text: 'a\uD800b');
    var doc = (await store.markdown.get(note.id))!;
    expect(doc.text.codeUnits, [0x61, 0xFFFD, 0x62]);
    final again = await store.markdown.saveText(
      note.id,
      'a\uD800b',
      baseVersion: doc.textVersion,
    );
    expect(again.outcome, MarkdownSaveOutcome.unchanged);
    await store.markdown.saveText(
      note.id,
      'x\uDC00\uD83D\uDE42',
      baseVersion: doc.textVersion,
    );
    doc = (await store.markdown.get(note.id))!;
    expect(doc.text, 'x\uFFFD\uD83D\uDE42');
  });

  test('a received body tombstone makes the document read-only, like a '
      'missing body (review finding)', () async {
    final store = await openTestNoteStore() as DriftNoteStore;
    addTearDown(store.close);
    final note = await store.markdown.create(title: 't', text: '찾을 글');
    final current = (await store.markdown.get(note.id))!;
    final last = store.queue.hlc.last;
    final v = Hlc(last.millis + 1000, 0, kOtherNode);
    await store.sync.applyRemote([
      RemoteUpsert(
        MarkdownText(
          noteId: note.id,
          text: '찾을 글',
          createdAt: current.note.createdAt,
          updatedAt: last.millis + 1000,
          deletedAt: last.millis + 1000,
          version: v,
        ),
        EntityFieldVersions(v),
      ),
    ], policy: newerVersionWinsPolicy);
    final doc = (await store.markdown.get(note.id))!;
    expect(doc.bodyPresent, isFalse);
    expect(doc.isReadOnly, isTrue);
    expect(await store.search.searchPages('찾을'), isEmpty);
  });
}
