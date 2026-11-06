// Internal (exported by testing.dart): PageObjectFixtures — 2nd-round contract 7.6 '기반 단계
// 시험 도우미' / 02-core 4.9. Valid objects with the contract defaults; an omitted id is
// 'fx-<type>-<n>' (n counts up per isolate, so two fixtures never share an id).
import '../common/geometry.dart';
import '../common/ids.dart';
import '../model/object_styles.dart';
import '../model/shape_geometry.dart';
import '../model/stroke.dart';

var _serial = 0;
String _id(String type, String? id) =>
    id ?? 'fx-$type-${(++_serial).toString().padLeft(6, '0')}';

abstract final class PageObjectFixtures {
  /// [kind]'s template on [rect] (line / arrow: top-left → bottom-right, an arrow with a head
  /// at the end; polygon: a pentagon; star: 5 points), 2 pt near-black stroke.
  static ShapeObject shape({
    required String pageId,
    ShapeKind kind = ShapeKind.rectangle,
    PageRect rect = const PageRect(100, 100, 300, 220),
    int createdAt = 1,
    String? id,
  }) => ShapeObject(
    id: _id('shape', id),
    pageId: pageId,
    shapeKind: kind,
    geometry: switch (kind) {
      ShapeKind.line || ShapeKind.arrow => ShapeGeometry.line(
        PagePoint(rect.left, rect.top),
        PagePoint(rect.right, rect.bottom),
      ),
      ShapeKind.rectangle => ShapeGeometry.rectangle(rect),
      ShapeKind.ellipse => ShapeGeometry.ellipse(rect),
      ShapeKind.triangle => ShapeGeometry.triangle(rect),
      ShapeKind.polygon => ShapeGeometry.regularPolygon(rect, 5),
      ShapeKind.star => ShapeGeometry.star(rect),
    },
    style: ShapeStyle(
      strokeColorArgb: 0xFF1A1A1A,
      arrowHeads: kind == ShapeKind.arrow ? ArrowHeads.end : ArrowHeads.none,
    ),
    createdAt: createdAt,
  );

  static TextBoxObject textBox({
    required String pageId,
    String text = '안녕 hello',
    PageRect rect = const PageRect(100, 300, 400, 340),
    int createdAt = 1,
    String? id,
  }) => TextBoxObject(
    id: _id('text', id),
    pageId: pageId,
    frame: ElementFrame(rect),
    text: text,
    style: const TextBoxStyle(),
    createdAt: createdAt,
  );

  static ImageObject image({
    required String pageId,
    required AssetId assetId,
    PageRect rect = const PageRect(100, 400, 300, 550),
    int pixelWidth = 400,
    int pixelHeight = 300,
    int createdAt = 1,
    String? id,
  }) => ImageObject(
    id: _id('image', id),
    pageId: pageId,
    frame: ElementFrame(rect),
    assetId: assetId,
    pixelWidth: pixelWidth,
    pixelHeight: pixelHeight,
    createdAt: createdAt,
  );

  static MathObject math({
    required String pageId,
    String latex = r'\frac{a}{b}',
    PageRect rect = const PageRect(100, 600, 200, 650),
    int createdAt = 1,
    String? id,
  }) => MathObject(
    id: _id('math', id),
    pageId: pageId,
    frame: ElementFrame(rect),
    latex: latex,
    style: const MathStyle(),
    createdAt: createdAt,
  );

  /// An object of a type this app does not know: the common keys, the frame and a nested
  /// payload (createdAt = updatedAt = 1).
  static UnknownObject unknown({
    required String pageId,
    String type = 'sticker',
    PageRect rect = const PageRect(400, 100, 450, 150),
    String? id,
  }) => UnknownObject({
    'id': _id('unknown', id),
    'pageId': pageId,
    'type': type,
    'frame': ElementFrame(rect).toJson(),
    'payload': {
      'fixture': true,
      'items': [1, 2, 3],
    },
    'createdAt': 1,
    'updatedAt': 1,
    'deletedAt': null,
    'version': null,
  });
}
