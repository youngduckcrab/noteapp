// Recording.title (2nd-round contract 7.2.4, m5-7/02-core 6.3, CP-7): the 'title' key is
// always written (null when unset) and an absent key reads as null. Web-safe.
import 'dart:convert';

import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

import '../shared/entity_samples.dart';

void main() {
  test("'title' is always written — null when unset", () {
    final json = kSampleRecordingV1.toJson();
    expect(json.containsKey('title'), isTrue);
    expect(json['title'], isNull);
    expect(json.keys.toSet(), {
      'id',
      'noteId',
      'assetId',
      'durationMs',
      'startedAt',
      'title',
      'createdAt',
      'updatedAt',
      'deletedAt',
      'version',
    });
  });

  test('a title round-trips (also through jsonEncode)', () {
    final named = kSampleRecordingV1.copyWith(title: '1교시 강의');
    expect(named.toJson()['title'], '1교시 강의');
    expect(Recording.fromJson(named.toJson()), named);
    expect(
      EntityJson.decode(
        EntityKind.recording,
        jsonDecode(jsonEncode(named.toJson())) as Map<String, Object?>,
      ),
      named,
    );
  });

  test('an absent title key (a v1.4 writer) reads as null', () {
    final v14 = Map.of(kSampleRecordingV1.toJson())..remove('title');
    final r = Recording.fromJson(v14);
    expect(r.title, isNull);
    expect(r, kSampleRecordingV1);
  });

  test('a non-string title is a FormatException', () {
    expect(
      () => Recording.fromJson({...kSampleRecordingV1.toJson(), 'title': 3}),
      throwsFormatException,
    );
  });

  test('copyWith(title:, clearTitle:)', () {
    final named = kSampleRecordingV1.copyWith(title: '수업');
    expect(named.copyWith(durationMs: 5).title, '수업');
    expect(named.copyWith(clearTitle: true), kSampleRecordingV1);
    expect(named.copyWith(clearTitle: true).toJson()['title'], isNull);
  });
}
