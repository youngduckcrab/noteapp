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
  'recording': const Recording(
    id: '0193f1d2-7c40-7000-8000-0000000000r1',
    noteId: '0193f1d2-7c40-7000-8000-00000000a001',
    assetId: 'a54b81412d4c4ab56653bb9e4c02912b0820bb37e2bba00722ddef4d78083d4a',
    durationMs: 61000,
    startedAt: kT - 61000,
    createdAt: kT,
    updatedAt: kT,
    version: kV,
  ),
  'setting': const SettingValue(
    key: 'editor.recentColors',
    valueJson: '[4279970411,4294967040]',
    updatedAt: kT,
    version: kV,
  ),
};

final EntityFieldVersions kSampleFieldVersions = EntityFieldVersions(kV, {
  'style': Hlc.parse('001793750460000-0002-3f2a9c0d11e0b7a4'),
  'deletedAt': Hlc.parse('001793750400000-0001-3f2a9c0d11e0b7a4'),
});
