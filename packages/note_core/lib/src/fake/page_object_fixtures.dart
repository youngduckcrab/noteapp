// Internal (exported by testing.dart): PageObjectFixtures — 2nd-round contract 7.6 '기반 단계
// 시험 도우미' / 02-core 4.9. B2-α declares the factories; they build objects from CORE
// T23b on (02-core 8.1 'B2 상태').
import '../common/geometry.dart';
import '../common/ids.dart';
import '../common/pending.dart';
import '../model/shape_geometry.dart';
import '../model/stroke.dart';

abstract final class PageObjectFixtures {
  static ShapeObject shape({
    required String pageId,
    ShapeKind kind = ShapeKind.rectangle,
    PageRect rect = const PageRect(100, 100, 300, 220),
    int createdAt = 1,
    String? id,
  }) => notYet('T23b', 'PageObjectFixtures.shape');
  static TextBoxObject textBox({
    required String pageId,
    String text = '안녕 hello',
    PageRect rect = const PageRect(100, 300, 400, 340),
    int createdAt = 1,
    String? id,
  }) => notYet('T23b', 'PageObjectFixtures.textBox');
  static ImageObject image({
    required String pageId,
    required AssetId assetId,
    PageRect rect = const PageRect(100, 400, 300, 550),
    int pixelWidth = 400,
    int pixelHeight = 300,
    int createdAt = 1,
    String? id,
  }) => notYet('T23b', 'PageObjectFixtures.image');
  static MathObject math({
    required String pageId,
    String latex = r'\frac{a}{b}',
    PageRect rect = const PageRect(100, 600, 200, 650),
    int createdAt = 1,
    String? id,
  }) => notYet('T23b', 'PageObjectFixtures.math');
  static UnknownObject unknown({
    required String pageId,
    String type = 'sticker',
    PageRect rect = const PageRect(400, 100, 450, 150),
    String? id,
  }) => notYet('T23b', 'PageObjectFixtures.unknown');
}
