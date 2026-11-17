// (v2.17-md, 08-markdown 9 · MD-T10 — review finding) Goldens of a mixed grid — a
// handwriting note, an MD 문서 card (preview text + 'MD' mark) and a folder — in each
// home style (craft / calm / studio), light and dark: 6 images. Split-half size, test
// font (Ahem boxes) — layout and colours only. Generated in the Linux container;
// flutter_test_config.dart here allows ≤ 0.5 %. Update: `flutter test --update-goldens
// --tags golden`.
@Tags(['golden'])
@TestOn('vm')
library;

import 'package:feature_library/feature_library.dart';
import 'package:feature_library/src/ui/content/note_cover_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

import '../support/fake_library_backend.dart';
import '../support/library_test_harness.dart';
import '../support/test_sizes.dart';

void main() {
  late FakeLibraryBackend backend;

  setUp(() => backend = FakeLibraryBackend());
  tearDown(() => backend.dispose());

  for (final style in AppStyle.values) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final name = 'library_markdown_${style.wireName}_${brightness.name}.png';
      testWidgets('mixed grid, ${style.wireName} ${brightness.name}', (
        tester,
      ) async {
        await tester.runAsync(() async {
          final now = backend.clock.current;
          await backend.store.library.createFolder(name: '수업');
          await backend.seedNote('물리 2주차');
          await backend.store.markdown.create(
            title: '회의 메모',
            text:
                '# 회의 메모\n\n- [x] 발표 자료\n- [ ] 예산 정리\n\n'
                '> 다음 주 화요일까지\n\n`코드` 와 **굵게**, \$x^2\$ 수식',
          );
          backend.clock.current = now;
        });
        await LibraryTestHarness(
          backend,
          size: TestSizes.splitHalf,
        ).pump(tester, theme: buildStyleTheme(style, brightness));
        await tester.pumpAndSettle();
        expect(find.byType(MarkdownCoverCard), findsOneWidget);
        await expectLater(find.byType(LibraryScreen), matchesGoldenFile(name));
      });
    }
  }
}
