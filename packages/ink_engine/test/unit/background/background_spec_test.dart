// T13 (03-ink 8, 4.10): InkBackgroundSpec.fromCore for the four CORE
// backgrounds and isDarkPaper.
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:note_core/note_core.dart' as core;

void main() {
  test('fromCore: blank / template / pdf / image', () {
    final blank = InkBackgroundSpec.fromCore(
      const core.BlankBackground(paperColorArgb: core.PaperColors.ivory),
    );
    expect(blank.kind, InkBackgroundKind.blank);
    expect(blank.paperColorArgb, core.PaperColors.ivory);
    expect(blank.template, isNull);

    final template = core.PageTemplate.defaults(core.PageTemplateKind.cornell);
    final t = InkBackgroundSpec.fromCore(
      core.TemplateBackground(
        template: template,
        paperColorArgb: core.PaperColors.black,
      ),
    );
    expect(t.kind, InkBackgroundKind.template);
    expect(t.template, template);
    expect(t.paperColorArgb, core.PaperColors.black);

    final pdf = InkBackgroundSpec.fromCore(
      const core.PdfBackground(assetId: 'asset1', pdfPageIndex: 3),
    );
    expect(pdf.kind, InkBackgroundKind.pdf);
    expect((pdf.assetId, pdf.pdfPageIndex), ('asset1', 3));
    expect(pdf.paperColorArgb, core.PaperColors.white);

    final image = InkBackgroundSpec.fromCore(
      const core.ImageBackground(assetId: 'img'),
    );
    expect(image.kind, InkBackgroundKind.image);
    expect(image.assetId, 'img');
    expect(image.pdfPageIndex, isNull);
  });

  test('isDarkPaper = core.PaperColors.isDark', () {
    for (final paper in [...core.PaperColors.all, 0xFF000000, 0xFF7F7F7F]) {
      final spec = InkBackgroundSpec(
        kind: InkBackgroundKind.blank,
        paperColorArgb: paper,
      );
      expect(spec.isDarkPaper, core.PaperColors.isDark(paper));
    }
    expect(
      InkBackgroundSpec.fromCore(
        const core.BlankBackground(paperColorArgb: core.PaperColors.black),
      ).isDarkPaper,
      isTrue,
    );
    expect(
      const InkBackgroundSpec(kind: InkBackgroundKind.unknown).isDarkPaper,
      isFalse,
    );
  });

  test('value equality', () {
    final a = InkBackgroundSpec.fromCore(
      core.TemplateBackground(
        template: core.PageTemplate.defaults(core.PageTemplateKind.grid),
      ),
    );
    final b = InkBackgroundSpec.fromCore(
      core.TemplateBackground(
        template: core.PageTemplate.defaults(core.PageTemplateKind.grid),
      ),
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
