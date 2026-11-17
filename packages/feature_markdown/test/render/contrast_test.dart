// MD-T12 (08-markdown 8.3): link, inline code, emphasis and the other text colours of the
// rendered view reach 4.5:1 on the backgrounds they are drawn on, in all six themes
// (크래프트 · 미니멀 · 스튜디오 × 밝게 · 어둡게).
import 'package:feature_markdown/src/render/md_style.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

void main() {
  for (final style in AppStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets('${style.name} ${brightness.name}: text ≥ 4.5:1', (
        tester,
      ) async {
        late MdStyle s;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildStyleTheme(style, brightness),
            home: Builder(
              builder: (context) {
                s = MdStyle.of(context);
                return const SizedBox();
              },
            ),
          ),
        );
        final t = s.tokens;
        // 보기 draws on `toolbar`, 나란히's preview on `panel`; code blocks, tables'
        // header and the front matter box on `card`.
        final pages = {'toolbar': t.toolbar, 'panel': t.panel};
        final checks = <String, (Color, Color)>{
          for (final p in pages.entries) ...{
            'body on ${p.key}': (s.body.color!, p.value),
            'link on ${p.key}': (s.link(s.body).color!, p.value),
            'strong / em on ${p.key}': (s.body.color!, p.value),
            'quote / h6 on ${p.key}': (s.quoted(s.body).color!, p.value),
            'small on ${p.key}': (s.small.color!, p.value),
          },
          'inline code': (s.inlineCode.color!, s.inlineCode.backgroundColor!),
          'code block on card': (t.textPrimary, t.card),
          'table header on card': (s.body.color!, t.card),
          'secondary on card': (t.textSecondary, t.card),
        };
        for (final c in checks.entries) {
          final (fg, bg) = c.value;
          expect(
            contrastRatio(fg, bg),
            greaterThanOrEqualTo(4.5),
            reason: '${style.name} ${brightness.name}: ${c.key}',
          );
        }
      });
    }
  }
}
