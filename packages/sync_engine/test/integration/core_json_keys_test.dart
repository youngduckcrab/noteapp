// T16 (integration stage, contract 7.7 step 5 v1.2 — C12-05 "JSON 키 대조"): the keys of
// table 6.3.1 (FieldUnits) = the keys of CORE's JSON golden files
// (packages/note_core/test/goldens/json, CORE 6.3), each non-meta key in exactly one merge
// unit, and every golden entity through SyncDoc and back unchanged. Reads the CORE files
// from the workspace (VM, run from packages/sync_engine).
@Tags(['integration'])
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/model/field_versions_ext.dart';
import 'package:sync_engine/sync_engine.dart';

final Directory _goldens = Directory('../note_core/test/goldens/json');

/// Golden file name → entity kind (field_versions.json is the versions golden).
EntityKind? _kindOf(String name) => switch (name) {
  'folder' => EntityKind.folder,
  'note' => EntityKind.note,
  'page_blank' || 'page_pdf' || 'page_template' => EntityKind.page,
  'stroke' => EntityKind.stroke,
  'pen_preset' => EntityKind.penPreset,
  'asset' => EntityKind.asset,
  'recording' => EntityKind.recording,
  'setting' => EntityKind.setting,
  _ => null,
};

Map<String, Map<String, Object?>> _readGoldens() {
  final files = [
    for (final f in _goldens.listSync().whereType<File>())
      if (f.path.endsWith('.json')) f,
  ]..sort((a, b) => a.path.compareTo(b.path));
  return {
    for (final f in files)
      f.uri.pathSegments.last.replaceAll('.json', ''):
          jsonDecode(f.readAsStringSync()) as Map<String, Object?>,
  };
}

void main() {
  final goldens = _readGoldens();

  test('every entity kind has a CORE golden file; only field_versions is '
      'not an entity', () {
    expect(goldens, isNotEmpty, reason: 'CORE goldens at ${_goldens.path}');
    final kinds = {for (final name in goldens.keys) ?_kindOf(name)};
    expect(kinds, EntityKind.values.toSet());
    expect(
      [
        for (final name in goldens.keys)
          if (_kindOf(name) == null) name,
      ],
      ['field_versions'],
    );
  });

  test('table 6.3.1 keys = the golden JSON keys of each kind', () {
    for (final MapEntry(key: name, value: json) in goldens.entries) {
      final kind = _kindOf(name);
      if (kind == null) continue;
      expect(json.keys.toSet(), FieldUnits.keysOf(kind), reason: name);
    }
  });

  test('every non-meta golden key is in exactly one merge unit; groups only '
      'name golden keys', () {
    for (final MapEntry(key: name, value: json) in goldens.entries) {
      final kind = _kindOf(name);
      if (kind == null) continue;
      final keys = json.keys.toSet();
      final flat = [for (final u in FieldUnits.unitsFor(kind, keys)) ...u];
      expect(flat.toSet(), keys.difference(FieldUnits.metaKeys), reason: name);
      expect(flat, hasLength(flat.toSet().length), reason: name);
      for (final group in FieldUnits.groupsOf(kind)) {
        expect(keys.containsAll(group), isTrue, reason: '$name $group');
      }
    }
  });

  test('golden entities decode, go through SyncDoc and back unchanged', () {
    for (final MapEntry(key: name, value: json) in goldens.entries) {
      final kind = _kindOf(name);
      if (kind == null) continue;
      final entity = EntityJson.decode(kind, json);
      final doc = SyncDoc.fromEntity(entity);
      expect(doc.toEntity().toJson(), entity.toJson(), reason: name);
      expect(entity.toJson(), json, reason: name);
    }
  });

  test('the field-versions golden is in the normal form SYNC writes (base = '
      'min, overrides > base)', () {
    final json = goldens['field_versions']!;
    final versions = EntityFieldVersions.fromJson(json);
    final normal = normalizedFieldVersions({
      'createdAt': versions.base,
      ...versions.overrides,
    });
    expect(normal.toJson(), json);
  });
}
