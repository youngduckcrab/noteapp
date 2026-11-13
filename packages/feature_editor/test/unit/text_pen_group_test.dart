// (text pen, phase 1 — m5-7/04-editor 6.21) the 텍스트 펜's joining rule:
// the same row within 2.5 H sideways (word gaps), the next row ≤ 1.2 H below
// and overlapping sideways, nothing above or far away, the row and ink
// limits; textPenRowCount.
import 'dart:ui';

import 'package:feature_editor/src/tools/text_pen/text_pen_group.dart';
import 'package:flutter_test/flutter_test.dart';

/// A letter-sized box (12 pt high) with its left edge at [x], top at [y].
Rect _letter(double x, double y, {double w = 10, double h = 12}) =>
    Rect.fromLTWH(x, y, w, h);

void main() {
  final word = [_letter(100, 100), _letter(112, 100), _letter(124, 101)];

  group('textPenJoins', () {
    test('the same row: the next letter and a word gap up to 2.5 H join; a '
        'wider gap does not', () {
      expect(textPenJoins(members: word, stroke: _letter(136, 100)), isTrue);
      // H = 12 → 2.5 H = 30 from the last letter's right edge (134).
      expect(textPenJoins(members: word, stroke: _letter(163, 100)), isTrue);
      expect(textPenJoins(members: word, stroke: _letter(170, 100)), isFalse);
    });

    test('the next row: up to 1.2 H below and overlapping sideways joins', () {
      // The group's bottom is 113; 1.2 H = 14.4.
      expect(textPenJoins(members: word, stroke: _letter(100, 125)), isTrue);
      expect(textPenJoins(members: word, stroke: _letter(92, 126)), isTrue);
      expect(textPenJoins(members: word, stroke: _letter(100, 130)), isFalse);
    });

    test('a row below but off to the side, or a stroke above, does not '
        'join', () {
      expect(textPenJoins(members: word, stroke: _letter(300, 125)), isFalse);
      expect(textPenJoins(members: word, stroke: _letter(100, 80)), isFalse);
    });

    test('limits: strokes, points and rows', () {
      expect(
        textPenJoins(
          members: [
            for (var i = 0; i < TextPenTuning.maxGroupStrokes; i++)
              _letter(100 + i * 0.01, 100),
          ],
          stroke: _letter(100, 100),
        ),
        isFalse,
      );
      expect(
        textPenJoins(
          members: word,
          stroke: _letter(136, 100),
          groupPoints: TextPenTuning.maxGroupPoints - 10,
          strokePoints: 11,
        ),
        isFalse,
      );
      final rows = [
        for (var r = 0; r < TextPenTuning.maxRows; r++)
          _letter(100, 100 + r * 22.0),
      ];
      expect(textPenRowCount(rows), TextPenTuning.maxRows);
      final below = _letter(100, 100 + TextPenTuning.maxRows * 22.0);
      expect(textPenJoins(members: rows, stroke: below), isFalse);
      expect(
        textPenJoins(members: rows.skip(1).toList(), stroke: below),
        isTrue,
      );
    });

    test('an empty group joins nothing', () {
      expect(textPenJoins(members: const [], stroke: _letter(0, 0)), isFalse);
    });
  });

  test('textPenRowCount: overlapping letters are one row; a lower centre '
      'starts the next', () {
    expect(textPenRowCount(const []), 0);
    expect(textPenRowCount(word), 1);
    expect(textPenRowCount([...word, _letter(100, 125)]), 2);
    expect(textPenRowCount([_letter(100, 125), ...word]), 2);
  });
}
