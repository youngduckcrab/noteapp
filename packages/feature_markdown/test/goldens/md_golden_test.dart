// Goldens of the rendered view (08-markdown 8.3, B-3 / MD-T12): 크래프트 · 미니멀 · 스튜디오
// × light · dark × phone 390 px and tablet 1194 px landscape = 12, plus the phone editor at
// text scale 1.3. Test font (Ahem boxes) — layout and colours only. Generated in the Linux
// container; flutter_test_config.dart here allows ≤ 0.5 %.
// Update: `flutter test --update-goldens --tags golden`, in its own commit.
@Tags(['golden'])
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

import '../support/pump.dart';
import '../support/sample_doc.dart';

void main() {
  for (final style in AppStyle.values) {
    for (final brightness in Brightness.values) {
      for (final (name, size) in const [
        ('phone', Size(390, 844)),
        ('tablet', Size(1194, 834)),
      ]) {
        testWidgets('${style.name} ${brightness.name} $name', (tester) async {
          final h = await MdHarness.create(tester);
          final id = await h.doc(tester, kSampleMarkdown, title: '회의록');
          await h.pump(
            tester,
            id,
            size: size,
            style: style,
            brightness: brightness,
          );
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('md_${style.name}_${brightness.name}_$name.png'),
          );
        });
      }
    }
  }

  testWidgets('phone editor at text scale 1.3', (tester) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, kSampleMarkdown, title: '회의록');
    await h.pump(
      tester,
      id,
      size: const Size(390, 844),
      initialEdit: true,
      textScale: 1.3,
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('md_phone_edit_scale13.png'),
    );
  });
}
