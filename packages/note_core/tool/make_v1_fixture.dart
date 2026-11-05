// tool/make_v1_fixture.dart — CORE T25a (docs/plans/m5-7/02-core.md 6.12.3, 8.1;
// contract 00-overview 7.7.2 V7, 00-review '최종 승인' CORE-F2): builds the V7
// fixture, a v1 database written by the 1st-round CORE code.
//
// It uses ONLY the v1.4 public API of note_core (note_core.dart, dev_tools.dart)
// plus package:sqlite3 for the file checks, so it compiles against the 1st-round
// code and against every later version. It is meant to run in a temporary tree
// exported from the commit whose 1st-round CORE code the fixture records (the
// generator file is the only thing copied into that tree — no 2nd-round code):
//
//   git archive <commit> | tar -x -C /tmp/claude-0/core-v1-fixture
//   cp tool/make_v1_fixture.dart tool/src/v1_dump.dart → same paths there
//   (cd /tmp/claude-0/core-v1-fixture && flutter pub get --enforce-lockfile)
//   (cd …/packages/note_core && dart run tool/make_v1_fixture.dart \
//       --out <dir> --source-commit <sha> --core-tree <tree sha>)
//
// Then copy <dir>/* to test/fixtures/db_v1/ and run
// `dart run tool/v1_fixture_manifest.dart` (manifest.json — dump hashes).
//
// Output (<dir>, refused when it already holds fixture files unless --force):
//   noteapp_v1.sqlite      the file database exactly as openNoteStore left it
//                          (VM / native: WAL journal header, fully checkpointed)
//   noteapp_v1_web.sqlite  the same database with the rollback journal header
//                          (PRAGMA journal_mode = DELETE) — the form of a web
//                          worker database: drift's WasmDatabase sets no journal
//                          mode, and the WAL file fails there as initial bytes
//                          (SQLITE_NOTADB, sqlite3.wasm 3.54.1 in Chrome)
//   pdf_asset.pdf          the bytes of the PDF asset (the 1st-round native blob
//                          store is in memory, so the database has no bytes)
//   fixture_source.json    commit, tree, time, generator hash, entity ids
//
// Contents (contract V7: 3 notes, 20 pages, 2,000 strokes, 1 PDF asset,
// settings, unsent outbox): the default pen presets; folders '2026 가을 학기' and
// a child whose name has full-width Latin and decomposed Hangul (the derived
// name_norm differs between v1 and the v2 SearchText.normalize); note A (10
// pages, 950 synthetic strokes of 30 points + 50 strokes linked to a
// recording, 4 erased, 3 moved), note B (8 pages, 800 strokes, 4 PDF page
// backgrounds and 1 template, 5 restyled, renamed, favorite), note C (2 pages,
// 200 strokes, in the trash); one synced and one device setting; a recording
// and its audio asset (metadata only, no bytes on this device) taken through
// sync.applyRemote — the 1st round has no local recording API. Nothing is
// synced, so every local write is still in the outbox.
//
// The clock and the ids are fixed (UUIDv7-shaped ids from the fixture clock);
// the device node id is random (openNoteStore makes it), so two runs differ in
// HLC node ids — the committed files are the fixture, manifest.json hashes them.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:note_core/dev_tools.dart';
import 'package:note_core/note_core.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

import 'src/v1_dump.dart';

/// 2026-10-26T00:00:00Z (09:00 KST): the fixture clock starts here.
const int kStartMillis = 1792972800000;

/// HLC node of the "other device" whose recording applyRemote takes.
const String kRemoteNodeId = '7e57de71ce000002';

const String kVmFile = 'noteapp_v1.sqlite';
const String kWebFile = 'noteapp_v1_web.sqlite';
const String kPdfFile = 'pdf_asset.pdf';
const String kSourceFile = 'fixture_source.json';
const List<String> kOutputFiles = [kVmFile, kWebFile, kPdfFile, kSourceFile];

/// Full-width 'Physics', two spaces, '물리' as conjoining jamo (NFD).
const String kChildFolderName = 'Ｐｈｙｓｉｃｓ  물리';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  final out = Directory(options.out);
  if (!options.force) {
    for (final name in kOutputFiles) {
      if (File('${out.path}/$name').existsSync()) {
        _fail(
          '${out.path}/$name exists (the committed fixture?) — use --force',
        );
      }
    }
  }
  final work = await Directory.systemTemp.createTemp('make_v1_fixture_');
  try {
    await _run(options, out, work);
  } finally {
    await work.delete(recursive: true);
  }
}

Future<void> _run(_Options options, Directory out, Directory work) async {
  final dbPath = '${work.path}/$kVmFile';
  final fx = _FixtureClock(kStartMillis);
  final ids = _FixtureIds(fx);
  final pdfBytes = fixturePdf();

  final store = await openNoteStore(
    NoteStoreConfig(
      nativeDatabasePath: dbPath,
      idGenerator: ids,
      clock: fx.clock,
    ),
  );
  final _Built built;
  final String deviceNodeId;
  try {
    deviceNodeId = store.sync.deviceNodeId;
    built = await _build(store, fx, pdfBytes);
    await store.flush();
  } finally {
    await store.close();
  }
  final endMillis = fx.millis;

  // The VM form: openNoteStore's WAL file, checkpointed by the last close.
  for (final suffix in ['-wal', '-shm']) {
    final f = File('$dbPath$suffix');
    if (f.existsSync() && f.lengthSync() > 0) {
      _fail('$dbPath$suffix is left after close (not checkpointed)');
    }
  }
  final vmBytes = await File(dbPath).readAsBytes();
  if (vmBytes[18] != 2 || vmBytes[19] != 2) {
    _fail('$kVmFile: expected the WAL header (bytes 18-19 = 2)');
  }

  // The web form: same rows, rollback journal header.
  final webPath = '${work.path}/$kWebFile';
  await File(dbPath).copy(webPath);
  final webDb = sql.sqlite3.open(webPath);
  try {
    final mode = webDb
        .select('PRAGMA journal_mode = DELETE')
        .single
        .columnAt(0);
    if (mode != 'delete') _fail('journal_mode = DELETE returned $mode');
  } finally {
    webDb.close();
  }
  final webBytes = await File(webPath).readAsBytes();
  if (webBytes[18] != 1 || webBytes[19] != 1) {
    _fail('$kWebFile: expected the rollback journal header (bytes 18-19 = 1)');
  }

  final vmDump = await dumpOfCopy(vmBytes, work);
  final webDump = await dumpOfCopy(webBytes, work);
  if (sha256.convert(vmDump) != sha256.convert(webDump)) {
    _fail('the VM and web forms have different canonical dumps');
  }
  if (sha256.convert(pdfBytes).toString() != built.pdfAssetId) {
    _fail('pdf_asset.pdf does not hash to the PDF asset id');
  }

  await out.create(recursive: true);
  await File('${out.path}/$kVmFile').writeAsBytes(vmBytes, flush: true);
  await File('${out.path}/$kWebFile').writeAsBytes(webBytes, flush: true);
  await File('${out.path}/$kPdfFile').writeAsBytes(pdfBytes, flush: true);

  final source = <String, Object?>{
    'format': 'noteapp-v1-fixture-source 1',
    'task':
        'CORE T25a — docs/plans/m5-7/02-core.md 6.12.3, 8.1; '
        'contract 00-overview 7.7.2 V7',
    'sourceCommit': options.sourceCommit,
    'noteCoreTree': options.coreTree,
    if (options.note != null) 'sourceNote': options.note,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'generator': {
      'tool/make_v1_fixture.dart': _sha256OfFile(Platform.script),
      'tool/src/v1_dump.dart': _sha256OfFile(
        Platform.script.resolve('src/v1_dump.dart'),
      ),
      'dart': Platform.version,
      'sqlite': sql.sqlite3.version.libVersion,
    },
    'api':
        'openNoteStore(NoteStoreConfig(nativeDatabasePath, idGenerator, '
        'clock)), library, assets.put, session commands, settings.set, '
        'sync.applyRemote, dev_tools seedSyntheticNote — v1.4 public API only',
    'clock': {
      'startMillis': kStartMillis,
      'endMillis': endMillis,
      'trashedAtMillis': built.trashedAt,
      'note':
          'NoteStoreConfig.trashRetention is 30 days: a store opened with '
          'a clock later than trashedAtMillis + 30 days purges note C '
          '10 s after openNoteStore (auto purge)',
    },
    'deviceNodeId': deviceNodeId,
    'remoteNodeId': kRemoteNodeId,
    'entities': built.toJson(),
    'files': {
      kVmFile: _sha256Hex(vmBytes),
      kWebFile: _sha256Hex(webBytes),
      kPdfFile: _sha256Hex(pdfBytes),
    },
    'fullDumpSha256': sha256.convert(vmDump).toString(),
  };
  await File('${out.path}/$kSourceFile').writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(source)}\n',
    flush: true,
  );
  stdout.writeln(
    'make_v1_fixture: wrote ${kOutputFiles.join(', ')} to ${out.path} '
    '(${vmBytes.length} B database)',
  );
}

final class _Built {
  late final String folderTermId, folderPhysicsId;
  late final String noteA, noteB, noteC;
  late final String pdfAssetId, audioAssetId, recordingId;
  late final List<String> pdfPageIds;
  late final String templatePageId;
  late final String recordingPageId;
  late final List<String> recordingStrokeIds;
  late final List<String> erasedStrokeIds, movedStrokeIds, restyledStrokeIds;
  late final int trashedAt;

  Map<String, Object?> toJson() => {
    'folders': {'term': folderTermId, 'physics': folderPhysicsId},
    'notes': {'A': noteA, 'B': noteB, 'C (trashed)': noteC},
    'pdfAsset': pdfAssetId,
    'audioAsset (remote, metadata only)': audioAssetId,
    'recording (remote)': recordingId,
    'noteB pdfBackgroundPages (pdfPageIndex 0..3)': pdfPageIds,
    'noteB templatePage': templatePageId,
    'noteA recordingPage': recordingPageId,
    'noteA recordingStrokes': recordingStrokeIds.length,
    'noteA erasedStrokes': erasedStrokeIds,
    'noteA movedStrokes': movedStrokeIds,
    'noteB restyledStrokes': restyledStrokeIds,
  };
}

Future<_Built> _build(NoteStore store, _FixtureClock fx, Uint8List pdf) async {
  final b = _Built();
  final lib = store.library;

  // Folders.
  fx.advance(const Duration(minutes: 1));
  final term = await lib.createFolder(
    name: '2026 가을 학기',
    colorArgb: 0xFF3F7FBF,
  );
  b.folderTermId = term.id;
  fx.advance(const Duration(minutes: 1));
  final physics = await lib.createFolder(
    parentId: term.id,
    name: kChildFolderName,
  );
  b.folderPhysicsId = physics.id;

  // Note A: 10 pages × 95 synthetic strokes (30 points).
  fx.advance(const Duration(minutes: 1));
  b.noteA = await seedSyntheticNote(
    store,
    title: '역학 1주차 필기',
    pages: 10,
    strokesPerPage: 95,
    pointsPerStroke: 30,
    seed: 1,
  );
  fx.advance(const Duration(minutes: 1));
  await lib.moveItems([NoteRef(b.noteA)], targetFolderId: physics.id);
  await lib.setTags(b.noteA, const ['물리', 'week 1']);
  await lib.setCover(b.noteA, const ColorCover(0xFF8E24AA));

  // The PDF asset and note B: 8 pages × 100 strokes.
  fx.advance(const Duration(minutes: 5));
  final asset = await store.assets.put(
    pdf,
    type: AssetType.pdf,
    mimeType: 'application/pdf',
    fileName: '강의자료 3장.pdf',
  );
  b.pdfAssetId = asset.id;
  fx.advance(const Duration(minutes: 1));
  b.noteB = await seedSyntheticNote(
    store,
    title: 'PDF 강의 자료',
    pages: 8,
    strokesPerPage: 100,
    pointsPerStroke: 30,
    seed: 2,
  );
  fx.advance(const Duration(minutes: 1));
  final sessionB = await store.openSession(b.noteB);
  try {
    final pages = sessionB.pages;
    b.pdfPageIds = [for (var i = 0; i < 4; i++) pages[i].id];
    for (var i = 0; i < 4; i++) {
      sessionB.execute(
        SetPageBackground(
          pageIds: [pages[i].id],
          background: PdfBackground(assetId: asset.id, pdfPageIndex: i),
        ),
      );
    }
    b.templatePageId = pages[4].id;
    sessionB.execute(
      SetPageBackground(
        pageIds: [pages[4].id],
        background: TemplateBackground(
          template: PageTemplate.defaults(PageTemplateKind.lined),
        ),
      ),
    );
    fx.advance(const Duration(minutes: 1));
    final first = await sessionB.openPage(pages[0].id);
    try {
      b.restyledStrokeIds = [for (final s in first.strokes.take(5)) s.id];
      sessionB.execute(
        RestyleStrokes(
          pageId: pages[0].id,
          strokeIds: b.restyledStrokeIds,
          patch: const StrokeStylePatch(colorArgb: 0xFFD32F2F),
        ),
      );
    } finally {
      sessionB.closePage(pages[0].id);
    }
    await sessionB.flush();
  } finally {
    await sessionB.close();
  }
  fx.advance(const Duration(minutes: 1));
  await lib.moveItems([NoteRef(b.noteB)], targetFolderId: term.id);
  await lib.setFavorite([b.noteB], true);
  await lib.renameNote(b.noteB, 'PDF 강의 자료 — 3장');

  // A recording of note A from "another device" (no local API in the 1st round):
  // its audio asset (metadata only — the bytes are 2,048 zero bytes, nowhere on
  // this device) and the Recording, through applyRemote.
  fx.advance(const Duration(minutes: 10));
  final startedAt = fx.millis - const Duration(minutes: 20).inMilliseconds;
  const durationMs = 900000; // 15 min
  final stoppedAt = startedAt + durationMs;
  final remoteAt = stoppedAt + 1000;
  final audioBytes = Uint8List(2048);
  b.audioAssetId = _sha256Hex(audioBytes);
  b.recordingId = store.ids.newId();
  final assetVersion = Hlc(remoteAt, 0, kRemoteNodeId);
  final recordingVersion = Hlc(remoteAt, 1, kRemoteNodeId);
  await store.sync.applyRemote([
    RemoteUpsert(
      Asset(
        id: b.audioAssetId,
        ownerId: store.ownerId,
        type: AssetType.audio,
        mimeType: 'audio/mp4',
        size: audioBytes.length,
        fileName: 'recording.m4a',
        createdAt: stoppedAt,
        storagePath: 'users/${store.ownerId}/assets/${b.audioAssetId}',
        version: assetVersion,
        hasLocalBytes: false,
      ),
      EntityFieldVersions(assetVersion),
    ),
    RemoteUpsert(
      Recording(
        id: b.recordingId,
        noteId: b.noteA,
        assetId: b.audioAssetId,
        durationMs: durationMs,
        startedAt: startedAt,
        createdAt: stoppedAt,
        updatedAt: stoppedAt,
        version: recordingVersion,
      ),
      EntityFieldVersions(recordingVersion),
    ),
  ], policy: (local, remote, pendingLocalFields) => const TakeRemote());

  // Note A: 50 strokes written during the recording (page 2), then an erase and
  // a lasso move on page 1.
  fx.advance(const Duration(minutes: 1));
  final sessionA = await store.openSession(b.noteA);
  try {
    final pages = sessionA.pages;
    final recPage = pages[1];
    b.recordingPageId = recPage.id;
    await sessionA.openPage(recPage.id);
    try {
      final strokes = [
        for (var i = 0; i < 50; i++)
          _recordingStroke(
            id: store.ids.newId(),
            pageId: recPage.id,
            index: i,
            recordingId: b.recordingId,
            createdAt: startedAt + 10000 + i * 16000,
            recordingOffsetMs: 10000 + i * 16000,
          ),
      ];
      b.recordingStrokeIds = [for (final s in strokes) s.id];
      sessionA.execute(AddStrokes(pageId: recPage.id, strokes: strokes));
    } finally {
      sessionA.closePage(recPage.id);
    }
    fx.advance(const Duration(minutes: 1));
    final first = await sessionA.openPage(pages[0].id);
    try {
      final ids = [for (final s in first.strokes) s.id];
      b.erasedStrokeIds = ids.sublist(10, 14);
      b.movedStrokeIds = ids.sublist(20, 23);
      sessionA.execute(
        RemoveStrokes(pageId: pages[0].id, strokeIds: b.erasedStrokeIds),
      );
      fx.advance(const Duration(seconds: 5));
      sessionA.execute(
        TransformElements(
          pageId: pages[0].id,
          elementIds: b.movedStrokeIds,
          transform: Affine2.translation(12, -8),
        ),
      );
    } finally {
      sessionA.closePage(pages[0].id);
    }
    await sessionA.flush();
  } finally {
    await sessionA.close();
  }

  // Note C: 2 pages × 100 strokes, then the trash.
  fx.advance(const Duration(minutes: 5));
  b.noteC = await seedSyntheticNote(
    store,
    title: '지난 메모',
    pages: 2,
    strokesPerPage: 100,
    pointsPerStroke: 30,
    seed: 3,
  );
  fx.advance(const Duration(minutes: 1));
  b.trashedAt = fx.millis;
  await lib.trashItems([NoteRef(b.noteC)]);

  // Settings: one synced (LIBRARY's new note defaults), one device (view mode).
  fx.advance(const Duration(minutes: 1));
  await store.settings.set(
    SettingKey.jsonMap('library.newNote.defaults'),
    const {
      'size': 'a4',
      'orientation': 'portrait',
      'customW': 210.0,
      'customH': 297.0,
      'template': 'lined',
      'paper': 0xFFFFFFFF,
    },
  );
  await store.settings.set(
    SettingKey.string('library.viewMode', 'grid', scope: SettingScope.device),
    'list',
  );
  return b;
}

/// A handwriting-like stroke (30 points, 120 Hz); every 10th is a highlighter,
/// every 10th + 5 a calligraphy pen (style extras), the rest a fountain pen.
Stroke _recordingStroke({
  required String id,
  required String pageId,
  required int index,
  required String recordingId,
  required int createdAt,
  required int recordingOffsetMs,
}) {
  final random = math.Random(9000 + index);
  final tool = index % 10 == 0
      ? PenTool.highlighter
      : index % 10 == 5
      ? PenTool.calligraphy
      : PenTool.fountain;
  final row = index ~/ 5;
  final builder = StrokePointsBuilder(initialCapacity: 30);
  var x = 80.0 + (index % 5) * 95 + random.nextDouble() * 10;
  var y = 120.0 + row * 60 + random.nextDouble() * 6;
  var heading = random.nextDouble() * 0.6 - 0.3;
  for (var p = 0; p < 30; p++) {
    builder.add(x, y, widthQ: 0.22 + random.nextDouble() * 0.06, t: p * 8.3);
    heading += random.nextDouble() * 0.5 - 0.25;
    x += math.cos(heading) * 2.4;
    y += math.sin(heading) * 2.4 + math.sin(p / 3) * 0.8;
  }
  return Stroke(
    id: id,
    pageId: pageId,
    style: StrokeStyle.defaultsFor(tool).normalized(),
    points: builder.build(),
    recordingId: recordingId,
    recordingOffsetMs: recordingOffsetMs,
    createdAt: createdAt,
  );
}

/// The fixture PDF: 4 A4 pages with a title line (Helvetica), deterministic.
Uint8List fixturePdf() {
  const pageCount = 4;
  final kids = [for (var k = 0; k < pageCount; k++) '${3 + 2 * k} 0 R'];
  final bodies = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [${kids.join(' ')}] /Count $pageCount >>',
  ];
  const fontObject = 3 + 2 * pageCount;
  for (var k = 0; k < pageCount; k++) {
    bodies.add(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595.2756 841.8898] '
      '/Resources << /Font << /F1 $fontObject 0 R >> >> /Contents ${4 + 2 * k} 0 R >>',
    );
    final line = 'Page ${k + 1} of $pageCount - noteapp v1 database fixture';
    final content = [
      '0.93 0.95 0.98 rg 56 56 483.2756 729.8898 re f',
      '0.1 0.1 0.1 rg',
      'BT /F1 28 Tf 72 740 Td (V7 fixture PDF) Tj ET',
      'BT /F1 14 Tf 72 708 Td ($line) Tj ET',
    ].join('\n');
    bodies.add('<< /Length ${content.length} >>\nstream\n$content\nendstream');
  }
  bodies.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');

  final out = BytesBuilder(copy: false)
    ..add(ascii.encode('%PDF-1.4\n%'))
    ..add(const [0xE2, 0xE3, 0xCF, 0xD3])
    ..add(ascii.encode('\n'));
  final offsets = <int>[];
  for (var i = 0; i < bodies.length; i++) {
    offsets.add(out.length);
    out.add(ascii.encode('${i + 1} 0 obj\n${bodies[i]}\nendobj\n'));
  }
  final xref = out.length;
  final table = StringBuffer()
    ..write('xref\n0 ${bodies.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final o in offsets) {
    table.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  table
    ..write('trailer\n<< /Size ${bodies.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xref\n%%EOF\n');
  out.add(ascii.encode(table.toString()));
  final bytes = out.toBytes();
  for (var i = 0; i < offsets.length; i++) {
    final head = ascii.decode(bytes.sublist(offsets[i], offsets[i] + 8));
    if (!head.startsWith('${i + 1} 0 obj')) {
      throw StateError('PDF xref offset of object ${i + 1} is wrong');
    }
  }
  return bytes;
}

/// The canonical dump of database [bytes], read from a copy in [work] (never
/// the output file: opening a WAL database writes -wal / -shm files).
Future<Uint8List> dumpOfCopy(Uint8List bytes, Directory work) async {
  final dir = await work.createTemp('dump_');
  final path = '${dir.path}/copy.sqlite';
  await File(path).writeAsBytes(bytes, flush: true);
  final db = sql.sqlite3.open(path);
  try {
    return await canonicalDump(
      (q) async => [for (final r in db.select(q)) r.columnAt(0) as String],
    );
  } finally {
    db.close();
    await dir.delete(recursive: true);
  }
}

/// The fixture clock: moves only when [advance] is called.
final class _FixtureClock {
  _FixtureClock(this.millis);
  int millis;
  late final Clock clock = Clock(
    () => DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
  );
  void advance(Duration d) => millis += d.inMilliseconds;
}

/// RFC 9562 UUIDv7-shaped ids, deterministic: the fixture clock's ms, then the
/// sequence number (so ids sort in creation order, as UuidV7IdGenerator's do at
/// ms precision), then 54 bits of math.Random(sequence).
final class _FixtureIds implements IdGenerator {
  _FixtureIds(this._clock);
  final _FixtureClock _clock;
  int _seq = 0;

  @override
  String newId() {
    _seq++;
    if (_seq >= 1 << 20) throw StateError('fixture id sequence exhausted');
    final ts = _clock.millis.toRadixString(16).padLeft(12, '0');
    final randA = (_seq >> 8) & 0xfff;
    final r = math.Random(_seq);
    final noise = (r.nextInt(1 << 32) << 22) | r.nextInt(1 << 22); // 54 bits
    final randB = ((_seq & 0xff) << 54) | noise; // 62 bits
    final variant = 0x8 | (randB >>> 60);
    final low = (randB & ((1 << 60) - 1)).toRadixString(16).padLeft(15, '0');
    return '${ts.substring(0, 8)}-${ts.substring(8)}-'
        '7${randA.toRadixString(16).padLeft(3, '0')}-'
        '${variant.toRadixString(16)}${low.substring(0, 3)}-${low.substring(3)}';
  }
}

final class _Options {
  _Options(this.out, this.sourceCommit, this.coreTree, this.note, this.force);

  final String out;
  final String sourceCommit;
  final String coreTree;
  final String? note;
  final bool force;

  static _Options parse(List<String> args) {
    String? out, commit, tree, note;
    var force = false;
    for (var i = 0; i < args.length; i++) {
      String value() {
        if (i + 1 >= args.length) _usage('${args[i]} needs a value');
        return args[++i];
      }

      switch (args[i]) {
        case '--out':
          out = value();
        case '--source-commit':
          commit = value();
        case '--core-tree':
          tree = value();
        case '--note':
          note = value();
        case '--force':
          force = true;
        default:
          _usage('unknown argument ${args[i]}');
      }
    }
    final hex = RegExp(r'^[0-9a-f]{40}$');
    if (out == null || commit == null || tree == null) {
      _usage('--out, --source-commit and --core-tree are required');
    }
    if (!hex.hasMatch(commit) || !hex.hasMatch(tree)) {
      _usage('--source-commit / --core-tree take full 40-char git hashes');
    }
    return _Options(out, commit, tree, note, force);
  }
}

String _sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

String _sha256OfFile(Uri uri) =>
    _sha256Hex(File.fromUri(uri).readAsBytesSync());

Never _usage(String message) {
  stderr.writeln(
    'make_v1_fixture: $message\n'
    'usage: dart run tool/make_v1_fixture.dart --out <dir> '
    '--source-commit <sha> --core-tree <tree sha> [--note <text>] [--force]',
  );
  exit(64);
}

Never _fail(String message) {
  stderr.writeln('make_v1_fixture: $message');
  exit(1);
}
