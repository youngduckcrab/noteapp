// Sample entities shared by the JSON tests (golden files, web-format decode, round trips).
import 'package:note_core/note_core.dart';

const String kNode = '3f2a9c0d11e0b7a4';
const int kT = 1793750400000;
const Hlc kV = Hlc(kT, 0, kNode);

// Not written inline as `tags: [...]`: ws check R15 reads every literal `tags:` argument
// in test/ as a test tag.
const List<String> kSampleTags = ['math', '2학기'];

final StrokePoints kG1Points = StrokePoints.fromList(const [
  StrokePoint(10, 20, widthQ: 0.25, t: 0),
  StrokePoint(10.5, 20.25, widthQ: 0.275, t: 4.2),
  StrokePoint(11.25, 20.25, widthQ: 0.3, t: 8.3),
]);

final Map<String, SyncEntity> kSampleEntities = {
  'folder': const Folder(
    id: '0193f1d2-7c40-7000-8000-00000000f001',
    ownerId: kLocalOwnerId,
    name: '수업',
    colorArgb: 0xFF3949AB,
    icon: 'school',
    sortKey: 'a0',
    createdAt: kT,
    updatedAt: kT + 1000,
    version: kV,
  ),
  'note': const Note(
    id: '0193f1d2-7c40-7000-8000-00000000a001',
    ownerId: kLocalOwnerId,
    folderId: '0193f1d2-7c40-7000-8000-00000000f001',
    title: '강의 노트',
    cover: ColorCover(0xFFFFE600),
    tags: kSampleTags,
    isFavorite: true,
    sortKey: 'a1',
    createdAt: kT,
    updatedAt: kT + 2000,
    deletedAt: kT + 3000,
    trashRootId: '0193f1d2-7c40-7000-8000-00000000a001',
    version: kV,
    pageCount: 3,
    firstPageId: 'local-only',
    lastOpenedAt: kT + 5,
  ),
  'page_blank': const Page(
    id: '0193f1d2-7c40-7aaa-8bbb-111122223333',
    noteId: '0193f1d2-7c40-7000-8000-00000000a001',
    sortKey: 'a0',
    size: PageSize.a4Portrait,
    background: BlankBackground(paperColorArgb: PaperColors.ivory),
    createdAt: kT,
    updatedAt: kT,
    version: kV,
    contentRevision: 7,
  ),
  'page_template': const Page(
    id: '0193f1d2-7c40-7aaa-8bbb-111122224444',
    noteId: '0193f1d2-7c40-7000-8000-00000000a001',
    sortKey: 'a1',
    size: PageSize(540, 960),
    background: TemplateBackground(
      template: PageTemplate(
        kind: PageTemplateKind.cornell,
        spacing: 24,
        extras: {
          TemplateExtrasKeys.cueColumnWidth: 150,
          TemplateExtrasKeys.showMarginLine: true,
        },
      ),
      paperColorArgb: PaperColors.black,
    ),
    createdAt: kT,
    updatedAt: kT,
    version: kV,
  ),
  'page_pdf': const Page(
    id: '0193f1d2-7c40-7aaa-8bbb-111122225555',
    noteId: '0193f1d2-7c40-7000-8000-00000000a001',
    sortKey: 'a2',
    size: PageSize.letterPortrait,
    background: PdfBackground(
      assetId:
          'efd308be92a34f3aa15f289a37f213b0230fd80888a1364326ee29579d892d37',
      pdfPageIndex: 4,
    ),
    createdAt: kT,
    updatedAt: kT,
    version: kV,
  ),
  'stroke': Stroke(
    id: '0193f1d2-7c4a-7b1e-9a2f-3c4d5e6f7a8b',
    pageId: '0193f1d2-7c40-7aaa-8bbb-111122223333',
    style: StrokeStyle.defaultsFor(PenTool.fountain),
    points: kG1Points,
    createdAt: kT,
    version: kV,
  ),
  'pen_preset': PenPreset(
    id: 'preset-default-highlighter',
    ownerId: kLocalOwnerId,
    name: '형광펜',
    style: StrokeStyle.defaultsFor(PenTool.highlighter),
    sortKey: 'a2',
    createdAt: kT,
    updatedAt: kT,
    version: const Hlc(1, 0, '0000000000000000'),
  ),
  'asset': const Asset(
    id: 'efd308be92a34f3aa15f289a37f213b0230fd80888a1364326ee29579d892d37',
    ownerId: kLocalOwnerId,
    type: AssetType.pdf,
    mimeType: 'application/pdf',
    size: 758619,
    fileName: '강의자료.pdf',
    createdAt: kT,
    storagePath: 'users/local/assets/efd308be',
    version: kV,
  ),
  // (v2.0, m5-7/02-core 6.3) the golden carries a title (the 'title: null' case is in
  // test/model/recording_title_test.dart).
  'recording': kSampleRecordingV1.copyWith(title: '1교시 강의'),
  'setting': const SettingValue(
    key: 'editor.recentColors',
    valueJson: '[4279970411,4294967040]',
    updatedAt: kT,
    version: kV,
  ),
  ...kSampleObjects,
  'handwriting': kSampleHandwriting,
};

/// The recording as a v1 database row holds it (no title column until CORE T24).
const Recording kSampleRecordingV1 = Recording(
  id: '0193f1d2-7c40-7000-8000-0000000000r1',
  noteId: '0193f1d2-7c40-7000-8000-00000000a001',
  assetId: 'a54b81412d4c4ab56653bb9e4c02912b0820bb37e2bba00722ddef4d78083d4a',
  durationMs: 61000,
  startedAt: kT - 61000,
  createdAt: kT,
  updatedAt: kT,
  version: kV,
);

/// The v1.4 entity shapes as a v1 database stores them (storage row round trips): no page
/// objects / handwriting tables and no recordings.title column until CORE T24 (DB v2).
final Map<String, SyncEntity> kV1RowSamples = {
  for (final e in kSampleEntities.entries)
    if (e.value.kind != EntityKind.pageObject &&
        e.value.kind != EntityKind.handwriting)
      e.key: e.value,
  'recording': kSampleRecordingV1,
};

const String kSamplePageId = '0193f1d2-7c40-7aaa-8bbb-111122223333';
const String kSampleImageAssetId =
    '5f2b7c1d9e0a4b3c8d6e1f2a3b4c5d6e7f8091a2b3c4d5e6f708192a3b4c5d6e';

/// (v2.0) The 8 page object goldens (m5-7/02-core 6.3 table).
final Map<String, PageObject> kSampleObjects = {
  // 7.2.7 example: rotation 0 rectangle.
  'shape_rect': ShapeObject(
    id: '0193f1d2-7c4b-7000-8000-0000000000b1',
    pageId: kSamplePageId,
    shapeKind: ShapeKind.rectangle,
    geometry: const PolylineGeometry([
      PagePoint(120, 80),
      PagePoint(320, 80),
      PagePoint(320, 200),
      PagePoint(120, 200),
    ], closed: true),
    style: const ShapeStyle(strokeColorArgb: 4279900698),
    createdAt: kT,
    version: kV,
  ),
  'shape_ellipse': ShapeObject(
    id: '0193f1d2-7c4b-7000-8000-0000000000b2',
    pageId: kSamplePageId,
    shapeKind: ShapeKind.ellipse,
    geometry: const EllipseGeometry(
      ElementFrame(PageRect(100, 300, 260, 400), rotation: 0.5),
    ),
    style: const ShapeStyle(
      strokeColorArgb: 0xFF3949AB,
      strokeWidth: 3,
      fillColorArgb: 0xFFFFE600,
      fillOpacity: 0.4,
    ),
    createdAt: kT + 1,
    updatedAt: kT + 700,
    version: kV,
  ),
  'shape_arrow': ShapeObject(
    id: '0193f1d2-7c4b-7000-8000-0000000000b3',
    pageId: kSamplePageId,
    shapeKind: ShapeKind.arrow,
    geometry: const PolylineGeometry([
      PagePoint(50, 500),
      PagePoint(250.5, 560.25),
    ], closed: false),
    style: const ShapeStyle(
      strokeColorArgb: 0xFFD32F2F,
      strokeWidth: 2.5,
      strokeOpacity: 0.8,
      dash: LineDash.dashed,
      arrowHeads: ArrowHeads.both,
    ),
    createdAt: kT + 2,
    version: kV,
  ),
  'text_box': TextBoxObject(
    id: '0193f1d2-7c4b-7000-8000-0000000000b4',
    pageId: kSamplePageId,
    frame: const ElementFrame(PageRect(60, 620, 360, 690.5)),
    text: '회의록 정리\nMeeting notes — 2026',
    style: const TextBoxStyle(
      fontSizePt: 18,
      bold: true,
      align: TextAlignKind.center,
      lineHeight: 1.5,
      backgroundArgb: 0x33FFE600,
    ),
    createdAt: kT + 3,
    updatedAt: kT + 500,
    version: kV,
  ),
  'image': ImageObject(
    id: '0193f1d2-7c4b-7000-8000-0000000000b5',
    pageId: kSamplePageId,
    frame: const ElementFrame(PageRect(300, 100, 500, 250), rotation: -0.25),
    assetId: kSampleImageAssetId,
    pixelWidth: 1600,
    pixelHeight: 1200,
    createdAt: kT + 4,
    version: kV,
  ),
  'math': MathObject(
    id: '0193f1d2-7c4b-7000-8000-0000000000b6',
    pageId: kSamplePageId,
    frame: const ElementFrame(PageRect(80, 720, 240, 760)),
    latex: r'\frac{a}{b}',
    style: const MathStyle(),
    engineId: 'manual',
    createdAt: kT + 5,
    version: kV,
  ),
  // (v2.1) the engine key is written with a null value (C21-11); a deleted object.
  'math_no_engine': MathObject(
    id: '0193f1d2-7c4b-7000-8000-0000000000b7',
    pageId: kSamplePageId,
    frame: const ElementFrame(PageRect(80, 780, 260.25, 820)),
    latex: r'x^2 + y^2 = r^2',
    style: const MathStyle(colorArgb: 0xFF3949AB, fontSizePt: 24),
    createdAt: kT + 6,
    updatedAt: kT + 9000,
    deletedAt: kT + 9000,
    version: kV,
  ),
  // A type this app does not know: nested maps / arrays and unknown keys survive (C-12).
  'unknown': UnknownObject(const {
    'id': '0193f1d2-7c4b-7000-8000-0000000000b8',
    'pageId': kSamplePageId,
    'type': 'sticker',
    'frame': [400.0, 100.0, 450.0, 150.0, 0.0],
    'sticker': {
      'pack': 'animals',
      'name': 'cat',
      'tint': [255, 128, 0],
    },
    'layers': [
      {'k': 'a', 'v': 1},
      {
        'k': 'b',
        'v': [true, null, 2.5],
      },
    ],
    'futureKey': '미래',
    'createdAt': kT + 7,
    'updatedAt': kT + 7,
    'deletedAt': null,
    'version': '001793750400000-0000-3f2a9c0d11e0b7a4',
  }),
};

/// (v2.0) Handwriting golden: 2 lines, alternatives, one confirmed line.
final HandwritingText kSampleHandwriting = HandwritingText(
  noteId: '0193f1d2-7c40-7000-8000-00000000a001',
  pageId: kSamplePageId,
  engineId: 'mlkit-digital-ink/19.0.0:ko',
  sourceRev: '0123456789abcdef',
  lines: const [
    HandwritingLine(
      text: '회의록 정리',
      alternatives: ['회의륵 정리', '희의록 정리'],
      rect: PageRect(40, 60, 320.5, 96),
      strokeIds: [
        '0193f1d2-7c4a-7b1e-9a2f-000000000001',
        '0193f1d2-7c4a-7b1e-9a2f-000000000002',
      ],
    ),
    HandwritingLine(
      text: 'meeting notes',
      rect: PageRect(40, 110, 300, 140),
      strokeIds: ['0193f1d2-7c4a-7b1e-9a2f-000000000003'],
      languageTag: 'en',
      userConfirmed: true,
    ),
  ],
  createdAt: kT,
  updatedAt: kT + 60000,
  version: kV,
);

final EntityFieldVersions kSampleFieldVersions = EntityFieldVersions(kV, {
  'style': Hlc.parse('001793750460000-0002-3f2a9c0d11e0b7a4'),
  'deletedAt': Hlc.parse('001793750400000-0001-3f2a9c0d11e0b7a4'),
});
