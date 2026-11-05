// CORE T25a — guards the V7 fixture (docs/plans/m5-7/02-core.md 6.12.3; contract
// 00-overview 7.7.2 V7): test/fixtures/db_v1/ holds exactly what
// tool/make_v1_fixture.dart wrote from the 1st-round code, manifest.json is
// current for those files, and the fixture has the contract's shape. The V7
// migration tests themselves (v1 → v2, VM and Chrome) are CORE T25b.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../../tool/v1_fixture_manifest.dart'
    show
        computeManifestText,
        kManifestFile,
        kPdfFile,
        kSourceFile,
        kVmFile,
        kWebFile;

final Directory _dir = Directory('test/fixtures/db_v1');

Map<String, Object?> _json(String name) =>
    jsonDecode(File('${_dir.path}/$name').readAsStringSync())
        as Map<String, Object?>;

String _sha256Of(String path) =>
    sha256.convert(File(path).readAsBytesSync()).toString();

void main() {
  test('manifest.json is current for the fixture files', () async {
    final current = File('${_dir.path}/$kManifestFile').readAsStringSync();
    expect(
      await computeManifestText(_dir),
      current,
      reason: 'run dart run tool/v1_fixture_manifest.dart',
    );
  });

  test('the fixture files are the ones the generator wrote', () {
    final source = _json(kSourceFile);
    expect(source['format'], 'noteapp-v1-fixture-source 1');
    expect(source['sourceCommit'], matches(RegExp(r'^[0-9a-f]{40}$')));
    expect(source['noteCoreTree'], matches(RegExp(r'^[0-9a-f]{40}$')));
    final files = source['files']! as Map<String, Object?>;
    for (final name in [kVmFile, kWebFile, kPdfFile]) {
      expect(_sha256Of('${_dir.path}/$name'), files[name], reason: name);
    }
    // The committed generator is the one that ran (regenerate after a change).
    final generator = source['generator']! as Map<String, Object?>;
    expect(
      _sha256Of('tool/make_v1_fixture.dart'),
      generator['tool/make_v1_fixture.dart'],
    );
    expect(_json(kManifestFile)['fullDumpSha256'], source['fullDumpSha256']);
  });

  test('the fixture has the V7 shape (contract 7.7.2)', () {
    final manifest = _json(kManifestFile);
    final counts = manifest['counts']! as Map<String, Object?>;
    expect(counts['notes'], 3);
    expect(counts['notesInTrash'], 1);
    expect(counts['pages'], 20);
    expect(counts['strokes'], 2000);
    expect(counts['pdfAssets'], 1);
    expect(counts['pagesWithPdfBackground'], greaterThan(0));
    expect(counts['strokesWithRecording'], greaterThan(0));
    expect(counts['recordings'], 1);
    expect(counts['syncedSettings'], greaterThanOrEqualTo(1));
    expect(counts['deviceSettings'], greaterThanOrEqualTo(1));
    expect(counts['outbox'], greaterThan(0));
    expect(counts['fieldVersionOverrides'], greaterThan(0));
    final sqlite = manifest['sqlite']! as Map<String, Object?>;
    expect(sqlite['userVersion'], 1);
    final files = manifest['files']! as Map<String, Object?>;
    expect((files[kVmFile]! as Map<String, Object?>)['journalHeader'], 'wal');
    expect(
      (files[kWebFile]! as Map<String, Object?>)['journalHeader'],
      'delete',
    );
    // Header bytes 18-19: 2 = WAL, 1 = rollback journal (SQLite file format).
    final vm = File('${_dir.path}/$kVmFile').readAsBytesSync();
    final web = File('${_dir.path}/$kWebFile').readAsBytesSync();
    expect([vm[18], vm[19]], [2, 2]);
    expect([web[18], web[19]], [1, 1]);
  });
}
