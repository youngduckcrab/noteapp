// HandwritingText / HandwritingLine (2nd-round contract 7.2.5, m5-7/02-core 6.3, 6.9.1):
// deterministic id, JSON keys, id check on read, defaults for absent line keys. Web-safe.
import 'dart:convert';

import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

import '../shared/entity_samples.dart';

void main() {
  group('JSON (CORE T20a)', () {
    test("id = 'hw_' + pageId, set by the constructor", () {
      expect(HandwritingText.idFor('p1'), 'hw_p1');
      expect(kSampleHandwriting.id, 'hw_$kSamplePageId');
      expect(isValidEntityId(kSampleHandwriting.id), isTrue);
      expect(kSampleHandwriting.kind, EntityKind.handwriting);
    });

    test('keys of the entity and of a line (6.3)', () {
      final json = kSampleHandwriting.toJson();
      expect(json.keys.toList(), [
        'id',
        'noteId',
        'pageId',
        'engineId',
        'sourceRev',
        'lines',
        'createdAt',
        'updatedAt',
        'deletedAt',
        'version',
      ]);
      final line = (json['lines']! as List).first as Map<String, Object?>;
      expect(line.keys.toList(), [
        'text',
        'alternatives',
        'rect',
        'strokeIds',
        'languageTag',
        'userConfirmed',
      ]);
      expect(line['rect'], [40.0, 60.0, 320.5, 96.0]);
    });

    test('round trip, also through jsonEncode and EntityJson', () {
      final back = HandwritingText.fromJson(kSampleHandwriting.toJson());
      expect(back, kSampleHandwriting);
      expect(back.hashCode, kSampleHandwriting.hashCode);
      final decoded = EntityJson.decode(
        EntityKind.handwriting,
        jsonDecode(jsonEncode(kSampleHandwriting.toJson()))
            as Map<String, Object?>,
      );
      expect(decoded, kSampleHandwriting);
    });

    test('fromJson: an id other than idFor(pageId) is a FormatException', () {
      final json = kSampleHandwriting.toJson();
      expect(
        () => HandwritingText.fromJson({...json, 'id': 'hw_other'}),
        throwsFormatException,
      );
      expect(
        () => HandwritingText.fromJson({...json, 'pageId': 'other'}),
        throwsFormatException,
      );
    });

    test(
      'line: absent alternatives / languageTag / userConfirmed → defaults',
      () {
        final line = HandwritingLine.fromJson(const {
          'text': '안녕',
          'rect': [0, 0, 10, 10],
          'strokeIds': ['s1'],
        });
        expect(
          line,
          const HandwritingLine(
            text: '안녕',
            rect: PageRect(0, 0, 10, 10),
            strokeIds: ['s1'],
          ),
        );
        expect(line.languageTag, 'ko');
        expect(line.userConfirmed, isFalse);
        expect(line.alternatives, isEmpty);
      },
    );

    test('line: bad input is a FormatException', () {
      const good = {
        'text': 'x',
        'rect': [0, 0, 1, 1],
        'strokeIds': <String>[],
      };
      final bad = <Map<String, Object?>>[
        {...good}..remove('text'),
        {...good}..remove('rect'),
        {...good}..remove('strokeIds'),
        {
          ...good,
          'rect': [0, 0, 1],
        },
        {...good, 'rect': '0,0,1,1'},
        {
          ...good,
          'strokeIds': [1],
        },
        {
          ...good,
          'alternatives': ['a', 2],
        },
        {...good, 'userConfirmed': 'yes'},
      ];
      for (final json in bad) {
        expect(
          () => HandwritingLine.fromJson(json),
          throwsFormatException,
          reason: '$json',
        );
      }
    });
  });
}
