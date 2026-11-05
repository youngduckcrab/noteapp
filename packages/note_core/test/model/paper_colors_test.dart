import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

void main() {
  test('palette', () {
    expect(PaperColors.all, [
      PaperColors.white,
      PaperColors.ivory,
      PaperColors.gray,
      PaperColors.black,
    ]);
    expect(PaperColors.ivory, 0xFFFBF7EC);
    expect(PaperColors.black, 0xFF202124);
  });

  test('luminance reference values (CORE 6.2.6)', () {
    expect(PaperColors.luminance(PaperColors.white), closeTo(1.0, 1e-4));
    expect(PaperColors.luminance(PaperColors.ivory), closeTo(0.9309, 1e-4));
    expect(PaperColors.luminance(PaperColors.gray), closeTo(0.8933, 1e-4));
    expect(PaperColors.luminance(PaperColors.black), closeTo(0.0152, 1e-4));
  });

  test('isDark boundary', () {
    expect(PaperColors.luminance(0xFFBCBCBC), closeTo(0.5029, 1e-4));
    expect(PaperColors.isDark(0xFFBCBCBC), isFalse);
    expect(PaperColors.luminance(0xFFBBBBBB), closeTo(0.4969, 1e-4));
    expect(PaperColors.isDark(0xFFBBBBBB), isTrue);
    expect(PaperColors.isDark(PaperColors.black), isTrue);
    expect(PaperColors.isDark(PaperColors.white), isFalse);
    expect(
      PaperColors.luminance(0x00FFFFFF),
      PaperColors.luminance(0xFFFFFFFF),
      reason: 'alpha ignored',
    );
  });

  test('template extras keys', () {
    expect(TemplateExtrasKeys.plannerLayout, 'layout');
    expect(TemplateExtrasKeys.staffGap, 'staffGap');
    expect(PageTemplateKind.values.length, 6);
  });
}
