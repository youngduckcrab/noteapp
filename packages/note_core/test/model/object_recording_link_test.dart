// (v2.13-rec) The recording link of page objects: PageObject.recordingId /
// recordingOffsetMs, withRecording, JSON written only when linked, kept by
// copyWith / transformed / copyTo / copyWithMeta. Web-safe.
import 'dart:convert';

import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

const _asset =
    '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08';

List<PageObject> _objects() => [
  PageObjectFixtures.shape(pageId: 'p1', id: 'o-shape'),
  PageObjectFixtures.textBox(pageId: 'p1', id: 'o-text'),
  PageObjectFixtures.image(pageId: 'p1', assetId: _asset, id: 'o-image'),
  PageObjectFixtures.math(pageId: 'p1', id: 'o-math'),
  PageObjectFixtures.unknown(pageId: 'p1', id: 'o-unknown'),
];

void main() {
  test('an object made without a recording is not linked and writes no '
      'recording keys', () {
    for (final o in _objects()) {
      expect(o.recordingId, isNull, reason: o.type);
      expect(o.recordingOffsetMs, isNull, reason: o.type);
      expect(o.toJson().containsKey('recordingId'), isFalse, reason: o.type);
      expect(
        o.toJson().containsKey('recordingOffsetMs'),
        isFalse,
        reason: o.type,
      );
    }
  });

  test('withRecording links every type and round-trips through JSON', () {
    for (final o in _objects()) {
      final linked = o.withRecording(
        recordingId: 'rec-1',
        recordingOffsetMs: 4200,
      );
      expect(linked.runtimeType, o.runtimeType, reason: o.type);
      expect(linked.id, o.id);
      expect(linked.createdAt, o.createdAt);
      expect(linked.recordingId, 'rec-1', reason: o.type);
      expect(linked.recordingOffsetMs, 4200, reason: o.type);
      expect(linked, isNot(o), reason: o.type);
      final json = jsonDecode(jsonEncode(linked.toJson())) as Map;
      expect(json['recordingId'], 'rec-1');
      expect(json['recordingOffsetMs'], 4200);
      final back = PageObject.fromJson(json.cast<String, Object?>());
      expect(back, linked, reason: o.type);
      expect(back.recordingOffsetMs, 4200);
    }
  });

  test('copyWith, transformed, copyWithMeta and copyTo keep the link', () {
    final m = Affine2.translation(10, 20);
    for (final o in _objects()) {
      if (o is UnknownObject) continue;
      final linked = o.withRecording(
        recordingId: 'rec-1',
        recordingOffsetMs: 900,
      );
      final moved = linked.transformed(m);
      expect(moved.recordingId, 'rec-1', reason: o.type);
      expect(moved.recordingOffsetMs, 900, reason: o.type);
      final meta = linked.copyWithMeta(updatedAt: 99, deletedAt: 98);
      expect(meta.recordingOffsetMs, 900, reason: o.type);
      final copy = linked.copyTo(id: 'copy', pageId: 'p2', createdAt: 7);
      expect(copy.recordingId, 'rec-1', reason: o.type);
      expect(copy.recordingOffsetMs, 900, reason: o.type);
    }
    final shape = PageObjectFixtures.shape(
      pageId: 'p1',
    ).withRecording(recordingId: 'r', recordingOffsetMs: 5) as ShapeObject;
    expect(shape.copyWith(updatedAt: 3).recordingOffsetMs, 5);
  });

  test('an UnknownObject reads the link from its raw JSON', () {
    final u = PageObjectFixtures.unknown(pageId: 'p1', id: 'u1');
    final linked = u.withRecording(recordingId: 'rec', recordingOffsetMs: 12);
    expect(linked, isA<UnknownObject>());
    expect(linked.recordingId, 'rec');
    expect(linked.recordingOffsetMs, 12);
    final odd = UnknownObject({
      ...u.toJson(),
      'recordingId': 3,
      'recordingOffsetMs': 'x',
    });
    expect(odd.recordingId, isNull);
    expect(odd.recordingOffsetMs, isNull);
  });
}
