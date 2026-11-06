// HandwritingText / HandwritingLine (2nd-round contract 7.2.5, m5-7/02-core 6.3, 6.9.1):
// deterministic id, JSON keys, id check on read, defaults for absent line keys. Web-safe.
import 'dart:convert';

import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
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

  group('value functions (CORE T21)', () {
    final ids = SequentialIdGenerator(prefix: 'hw');
    Stroke stroke(PenTool tool) =>
        StrokeFixtures.synthetic(pageId: 'p1', ids: ids, tool: tool);

    test('isRecognitionInput: every tool but highlighter, tape, laser', () {
      expect(
        {
          for (final t in PenTool.values)
            t: HandwritingText.isRecognitionInput(stroke(t)),
        },
        {
          PenTool.ballpoint: true,
          PenTool.fountain: true,
          PenTool.highlighter: false,
          PenTool.pencil: true,
          PenTool.marker: true,
          PenTool.brush: true,
          PenTool.calligraphy: true,
          PenTool.dashed: true,
          PenTool.laser: false,
          PenTool.tape: false,
        },
      );
    });

    test(
      'sourceRevOf: 16 lowercase hex, order-independent, updatedAt-dependent',
      () {
        final a = stroke(PenTool.ballpoint);
        final b = stroke(PenTool.pencil);
        final rev = HandwritingText.sourceRevOf([a, b]);
        expect(rev, matches(RegExp(r'^[0-9a-f]{16}$')));
        expect(HandwritingText.sourceRevOf([b, a]), rev);
        expect(
          HandwritingText.sourceRevOf([
            a,
            b.copyWith(updatedAt: b.updatedAt + 1),
          ]),
          isNot(rev),
        );
        expect(HandwritingText.sourceRevOf(const []), 'e3b0c44298fc1c14');
      },
    );

    test('copyWith keeps id, note, page and createdAt', () {
      final h = kSampleHandwriting;
      final c = h.copyWith(sourceRev: 'ffffffffffffffff', updatedAt: 5);
      expect(c.id, h.id);
      expect(c.noteId, h.noteId);
      expect(c.pageId, h.pageId);
      expect(c.createdAt, h.createdAt);
      expect(c.sourceRev, 'ffffffffffffffff');
      expect(c.updatedAt, 5);
      expect(c.lines, h.lines);
      expect(c.version, h.version);
      expect(h.copyWith(), h);
      final deleted = h.copyWith(deletedAt: 9);
      expect(deleted.isDeleted, isTrue);
      expect(deleted.copyWith(clearDeletedAt: true).deletedAt, isNull);
      final line = h.lines.first.copyWith(userConfirmed: true, text: '확정');
      expect(line.userConfirmed, isTrue);
      expect(line.text, '확정');
      expect(line.strokeIds, h.lines.first.strokeIds);
      expect(h.lines.first.copyWith(), h.lines.first);
    });
  });
}
