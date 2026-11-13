// T16 (integration stage, contract 7.7 step 5 v1.2 — C12-05 "JSON 키 대조"): the keys of
// table 6.3.1 (FieldUnits) = the keys of CORE's JSON golden files
// (packages/note_core/test/goldens/json, CORE 6.3), each non-meta key in exactly one merge
// unit, and every golden entity through SyncDoc and back unchanged. Reads the CORE files
// from the workspace (VM, run from packages/sync_engine).
//
// v2 (2nd round, R2-B7a — contract 7.2.8, 07-sync 6.4, SYNC-M4): handwriting and recording
// golden keys = keysOf(kind); each known page object type golden has the keys of
// kPageObjectTypeKeys[type] and their union is keysOf(pageObject); an unknown type
// (unknown.json) is left out of the key comparison and only goes through SyncDoc and back.
// Runs from the CORE B2-beta JSON golden commit (T20a) on (CP-S9).
@Tags(['integration'])
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/model/field_versions_ext.dart';
import 'package:sync_engine/sync_engine.dart';

import '../support/entity_fixtures.dart';

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
  'shape_rect' ||
  'shape_ellipse' ||
  'shape_arrow' ||
  'text_box' ||
  'image' ||
  'math' ||
  'math_no_engine' ||
  'math_ink' ||
  'unknown' => EntityKind.pageObject,
  'handwriting' => EntityKind.handwriting,
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

  test('table 6.3.1 keys = the golden JSON keys of each kind (pageObject: '
      'below)', () {
    for (final MapEntry(key: name, value: json) in goldens.entries) {
      final kind = _kindOf(name);
      if (kind == null || kind == EntityKind.pageObject) continue;
      expect(json.keys.toSet(), FieldUnits.keysOf(kind), reason: name);
    }
  });

  test('page object goldens: each known type has the keys of '
      'kPageObjectTypeKeys, their union is keysOf(pageObject); unknown types '
      'are left out', () {
    final types = <String>{};
    final union = <String>{};
    final unknown = <String>[];
    for (final MapEntry(key: name, value: json) in goldens.entries) {
      if (_kindOf(name) != EntityKind.pageObject) continue;
      final type = json['type'];
      final keys = kPageObjectTypeKeys[type];
      if (keys == null) {
        unknown.add(name);
        continue;
      }
      types.add(type! as String);
      union.addAll(json.keys);
      expect(json.keys.toSet(), keys, reason: name);
    }
    expect(types, kPageObjectTypeKeys.keys.toSet());
    expect(union, FieldUnits.keysOf(EntityKind.pageObject));
    expect(unknown, ['unknown']);
    // C21-11: the engine key is written when there is no engine.
    expect(goldens['math_no_engine'], containsPair('engine', isNull));
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
