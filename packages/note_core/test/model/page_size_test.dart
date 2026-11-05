import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

void main() {
  test('presets (portrait form)', () {
    // ignore: use_named_constants
    expect(PageSizePreset.a4.portrait, const PageSize(595.2756, 841.8898));
    // ignore: use_named_constants
    expect(PageSizePreset.letter.portrait, const PageSize(612, 792));
    expect(PageSizePreset.widescreen16x9.portrait, const PageSize(540, 960));
    expect(
      PageSizePreset.widescreen16x9.portrait.landscape,
      PageSize.widescreen16x9,
    );
  });

  test('match: either orientation within ±0.5 pt, else null', () {
    expect(PageSizePreset.match(const PageSize(595, 842)), PageSizePreset.a4);
    expect(
      PageSizePreset.match(const PageSize(842.3, 595.6)),
      PageSizePreset.a4,
    );
    expect(
      PageSizePreset.match(const PageSize(792, 612)),
      PageSizePreset.letter,
    );
    expect(
      // ignore: use_named_constants
      PageSizePreset.match(const PageSize(960, 540)),
      PageSizePreset.widescreen16x9,
    );
    expect(
      PageSizePreset.match(const PageSize(540.5, 959.5)),
      PageSizePreset.widescreen16x9,
    );
    expect(PageSizePreset.match(const PageSize(594.7, 841.8898)), isNull);
    expect(PageSizePreset.match(const PageSize(500, 500)), isNull);
  });

  test('orientation helpers and clamping', () {
    const a4 = PageSize.a4Portrait;
    expect(a4.isLandscape, isFalse);
    expect(a4.landscape, const PageSize(841.8898, 595.2756));
    expect(a4.landscape.isLandscape, isTrue);
    expect(a4.landscape.portrait, a4);
    expect(const PageSize(10, 99999).clamped(), const PageSize(72, 14400));
    expect(PageSize.minSide, 72);
    expect(PageSize.maxSide, 14400);
    expect(PageSizeLimits.userMinSidePt, 100);
    expect(PageSizeLimits.userMaxSidePt, 3000);
  });
}
