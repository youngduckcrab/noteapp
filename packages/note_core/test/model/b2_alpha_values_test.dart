// B2-α value types (m5-7/02-core 8.1 T22): constructors, fields, defaults, ==, hashCode, enums
// and constants. The algorithm bodies (T20a JSON, T20b geometry, T21 value-type functions) have
// their own tests since B2-β. Web-safe.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

const _frame = ElementFrame(PageRect(10, 20, 110, 70));
const _line = PolylineGeometry([
  PagePoint(0, 0),
  PagePoint(10, 10),
], closed: false);
const _style = ShapeStyle(strokeColorArgb: 0xFF112233);

ShapeObject _shape({String id = 's1', int? updatedAt}) => ShapeObject(
  id: id,
  pageId: 'p1',
  shapeKind: ShapeKind.line,
  geometry: _line,
  style: _style,
  createdAt: 5,
  updatedAt: updatedAt,
);

TextBoxObject _text() => TextBoxObject(
  id: 't1',
  pageId: 'p1',
  frame: _frame,
  text: '안녕\nhello',
  style: const TextBoxStyle(),
  createdAt: 6,
);

ImageObject _image() => ImageObject(
  id: 'i1',
  pageId: 'p1',
  frame: _frame,
  assetId: 'a' * 64,
  pixelWidth: 400,
  pixelHeight: 300,
  createdAt: 7,
);

MathObject _math() => MathObject(
  id: 'm1',
  pageId: 'p1',
  frame: _frame,
  latex: r'\frac{a}{b}',
  style: const MathStyle(),
  createdAt: 8,
);

void main() {
  group('geometry', () {
    test('PagePoint and ElementFrame: ==, hashCode over the raw values', () {
      expect(const PagePoint(1, 2), const PagePoint(1, 2));
      expect(const PagePoint(1, 2).hashCode, const PagePoint(1, 2).hashCode);
      expect(const PagePoint(1, 2), isNot(const PagePoint(2, 1)));
      expect(_frame.rotation, 0);
      expect(ElementFrame.maxSide, 14400);
      const r = PageRect(0, 0, 10, 10);
      expect(
        const ElementFrame(r, rotation: -math.pi),
        isNot(const ElementFrame(r, rotation: math.pi)),
      );
      expect(
        const ElementFrame(r, rotation: 1),
        const ElementFrame(r, rotation: 1),
      );
      expect(
        const ElementFrame(r, rotation: 1).hashCode,
        const ElementFrame(r, rotation: 1).hashCode,
      );
    });

    test('ShapeGeometry: ==, the ellipse frame is its own frame', () {
      expect(
        const PolylineGeometry([
          PagePoint(0, 0),
          PagePoint(10, 10),
        ], closed: false),
        _line,
      );
      expect(
        const PolylineGeometry([
          PagePoint(0, 0),
          PagePoint(10, 10),
        ], closed: true),
        isNot(_line),
      );
      const ellipse = EllipseGeometry(_frame);
      expect(ellipse, const EllipseGeometry(_frame));
      expect(ellipse.frame, _frame);
    });
  });

  group('page objects', () {
    test('common fields, kind, type, isDeleted, updatedAt ?? createdAt', () {
      final objects = <PageObject>[_shape(), _text(), _image(), _math()];
      expect(objects.map((o) => o.type), ['shape', 'text', 'image', 'math']);
      for (final o in objects) {
        expect(o.kind, EntityKind.pageObject);
        expect(o.pageId, 'p1');
        expect(o.updatedAt, o.createdAt);
        expect(o.deletedAt, isNull);
        expect(o.version, isNull);
        expect(o.isDeleted, isFalse);
      }
      expect(_shape(updatedAt: 9).updatedAt, 9);
      final deleted = ShapeObject(
        id: 's2',
        pageId: 'p1',
        shapeKind: ShapeKind.rectangle,
        geometry: const EllipseGeometry(_frame),
        style: _style,
        createdAt: 1,
        deletedAt: 3,
      );
      expect(deleted.isDeleted, isTrue);
      expect(deleted.frame, _frame);
    });

    test('referencedAssets: the image asset only', () {
      expect(_shape().referencedAssets, isEmpty);
      expect(_text().referencedAssets, isEmpty);
      expect(_math().referencedAssets, isEmpty);
      expect(_image().referencedAssets, {'a' * 64});
    });

    test('==, hashCode over every field', () {
      expect(_shape(), _shape());
      expect(_shape().hashCode, _shape().hashCode);
      expect(_shape(), isNot(_shape(id: 's9')));
      expect(_shape(), isNot(_shape(updatedAt: 99)));
      expect(_text(), _text());
      expect(_image(), _image());
      expect(_math(), _math());
      expect(_math().hashCode, _math().hashCode);
      expect(_text(), isNot(_math()));
    });

    test('style defaults and ==', () {
      const shapeStyle = ShapeStyle(strokeColorArgb: 1);
      expect(
        [
          shapeStyle.strokeWidth,
          shapeStyle.strokeOpacity,
          shapeStyle.dash,
          shapeStyle.fillColorArgb,
          shapeStyle.fillOpacity,
          shapeStyle.arrowHeads,
        ],
        [2.0, 1.0, LineDash.solid, null, 1.0, ArrowHeads.none],
      );
      expect(shapeStyle, const ShapeStyle(strokeColorArgb: 1));
      expect(
        shapeStyle,
        isNot(const ShapeStyle(strokeColorArgb: 1, fillColorArgb: 2)),
      );
      const textStyle = TextBoxStyle();
      expect(
        [
          textStyle.fontSizePt,
          textStyle.colorArgb,
          textStyle.bold,
          textStyle.align,
          textStyle.lineHeight,
          textStyle.backgroundArgb,
        ],
        [16, 0xFF1A1A1A, false, TextAlignKind.start, 1.4, null],
      );
      expect(textStyle, const TextBoxStyle());
      expect(textStyle, isNot(const TextBoxStyle(bold: true)));
      const mathStyle = MathStyle();
      expect([mathStyle.colorArgb, mathStyle.fontSizePt], [0xFF1A1A1A, 18]);
      expect(mathStyle, const MathStyle());
      expect(mathStyle.hashCode, const MathStyle().hashCode);
    });
  });

  group('page content, drafts, commands', () {
    final ids = SequentialIdGenerator();
    final stroke = StrokeFixtures.synthetic(pageId: 'p1', ids: ids);
    const page = Page(
      id: 'p1',
      noteId: 'n1',
      sortKey: 'a0',
      size: PageSize.a4Portrait,
      background: BlankBackground(),
      createdAt: 0,
      updatedAt: 0,
    );

    test('PageContent objects, objectById, elementById, objectCount', () {
      final shape = _shape();
      final content = PageContent(
        page: page,
        strokes: [stroke],
        objects: [shape],
        revision: 3,
      );
      expect(content.objects, [shape]);
      expect(() => content.objects.add(_text()), throwsUnsupportedError);
      expect(content.objectCount, 1);
      expect(content.objectById(shape.id), same(shape));
      expect(content.objectById(stroke.id), isNull);
      expect(content.elementById(stroke.id), same(stroke));
      expect(content.elementById(shape.id), same(shape));
      expect(content.elementById('none'), isNull);
      expect(
        PageContent(page: page, strokes: const [], revision: 0).objects,
        isEmpty,
      );
    });

    test('PageDraft.objects (default empty), copyOf, ==', () {
      expect(PageDraft.blankA4.objects, isEmpty);
      final shape = _shape();
      final content = PageContent(
        page: page,
        strokes: [stroke],
        objects: [shape],
        revision: 0,
      );
      final draft = PageDraft.copyOf(content);
      expect(draft.strokes, [stroke]);
      expect(draft.objects, [shape]);
      expect(
        draft,
        PageDraft(
          size: page.size,
          background: page.background,
          strokes: [stroke],
          objects: [shape],
        ),
      );
      expect(
        draft,
        isNot(
          PageDraft(
            size: page.size,
            background: page.background,
            strokes: [stroke],
          ),
        ),
      );
    });

    test('new commands: labels, ClearPage.includeObjects default', () {
      expect(const AddObjects(pageId: 'p', objects: []).label, 'add-objects');
      expect(
        const UpdateObjects(pageId: 'p', objects: []).label,
        'update-objects',
      );
      expect(
        const RemoveElements(pageId: 'p', elementIds: []).label,
        'remove-elements',
      );
      expect(const ClearPage(pageId: 'p').includeObjects, isFalse);
      expect(
        const ClearPage(pageId: 'p', includeObjects: true).filter,
        StrokeFilter.all,
      );
    });
  });

  group('recordings, audio ports', () {
    const recording = Recording(
      id: 'r1',
      noteId: 'n1',
      assetId: 'a',
      durationMs: 1000,
      startedAt: 0,
      createdAt: 0,
      updatedAt: 0,
    );

    test('Recording.title: copyWith, clearTitle, ==', () {
      expect(recording.title, isNull);
      final named = recording.copyWith(title: '수업');
      expect(named.title, '수업');
      expect(named, isNot(recording));
      expect(named.copyWith(durationMs: 2).title, '수업');
      expect(named.copyWith(clearTitle: true), recording);
      expect(named.copyWith(clearTitle: true).hashCode, recording.hashCode);
    });

    test('RecordingDraft, RecorderStatus, PlaybackStatus: defaults and ==', () {
      const draft = RecordingDraft(
        draftId: 'd1',
        recordingId: 'r1',
        noteId: 'n1',
        mimeType: 'audio/mp4',
        startedAt: 0,
        chunkCount: 1,
        bytes: 16,
        activeMs: 1000,
        updatedAt: 1,
      );
      expect(
        draft,
        const RecordingDraft(
          draftId: 'd1',
          recordingId: 'r1',
          noteId: 'n1',
          mimeType: 'audio/mp4',
          startedAt: 0,
          chunkCount: 1,
          bytes: 16,
          activeMs: 1000,
          updatedAt: 1,
        ),
      );
      const recorder = RecorderStatus();
      expect(
        [
          recorder.phase,
          recorder.recordingId,
          recorder.noteId,
          recorder.activeMs,
          recorder.backgroundCapable,
          recorder.interrupted,
          recorder.mimeType,
          recorder.crossPlatformPlayable,
          recorder.error,
        ],
        [RecorderPhase.idle, null, null, 0, false, false, null, true, null],
      );
      expect(
        const RecorderStatus(phase: RecorderPhase.recording),
        isNot(recorder),
      );
      expect(recorder.hashCode, const RecorderStatus().hashCode);
      const playback = PlaybackStatus();
      expect(
        [
          playback.phase,
          playback.recordingId,
          playback.durationMs,
          playback.speed,
          playback.unsupportedFormat,
          playback.error,
        ],
        [PlaybackPhase.idle, null, 0, 1.0, false, null],
      );
      expect(const PlaybackStatus(speed: 2), isNot(playback));
    });
  });

  group('handwriting, search, library, assets', () {
    test('HandwritingText: deterministic id, defaults, ==', () {
      const line = HandwritingLine(
        text: '안녕',
        rect: PageRect(0, 0, 10, 10),
        strokeIds: ['s1'],
      );
      expect(
        [line.alternatives, line.languageTag, line.userConfirmed],
        [isEmpty, 'ko', false],
      );
      expect(
        line,
        const HandwritingLine(
          text: '안녕',
          rect: PageRect(0, 0, 10, 10),
          strokeIds: ['s1'],
        ),
      );
      final pageId = UuidV7IdGenerator().newId();
      HandwritingText make() => HandwritingText(
        noteId: 'n1',
        pageId: pageId,
        engineId: 'mlkit-digital-ink/19.0.0:ko',
        sourceRev: '0123456789abcdef',
        lines: const [line],
        createdAt: 3,
      );
      final result = make();
      expect(result.id, 'hw_$pageId');
      expect(HandwritingText.idFor(pageId), 'hw_$pageId');
      expect(result.id, hasLength(39));
      expect(isValidEntityId(result.id), isTrue);
      expect(result.kind, EntityKind.handwriting);
      expect(result.updatedAt, 3);
      expect(result.isDeleted, isFalse);
      expect(result, make());
      expect(result.hashCode, make().hashCode);
    });

    test('search value types: ==, SearchText.normalizerVersion', () {
      expect(SearchText.normalizerVersion, 1);
      const hit = PageSearchHit(
        noteId: 'n1',
        pageId: 'p1',
        source: SearchSource.pdf,
        snippet: '안녕하세요',
        matchRange: (0, 2),
        rects: [PageRect(0, 0, 1, 1)],
        score: 2,
      );
      expect(
        hit,
        const PageSearchHit(
          noteId: 'n1',
          pageId: 'p1',
          source: SearchSource.pdf,
          snippet: '안녕하세요',
          matchRange: (0, 2),
          rects: [PageRect(0, 0, 1, 1)],
          score: 2,
        ),
      );
      expect(
        const SearchUnitDraft(
          body: 'ab',
          rects: [PageRect.zero, PageRect.zero],
        ),
        const SearchUnitDraft(
          body: 'ab',
          rects: [PageRect.zero, PageRect.zero],
        ),
      );
      expect(const SearchIndexStatus().pendingOwners, 0);
      expect(
        const SearchIndexStatus(),
        isNot(const SearchIndexStatus(rebuilding: true)),
      );
      final mapping = SearchTextMapping(
        text: 'ab',
        sourceStart: Int32List.fromList([0, 1]),
        sourceEnd: Int32List.fromList([1, 2]),
      );
      expect(
        mapping,
        SearchTextMapping(
          text: 'ab',
          sourceStart: Int32List.fromList([0, 1]),
          sourceEnd: Int32List.fromList([1, 2]),
        ),
      );
      const result = LibrarySearchResult(query: 'q', folders: [], notes: []);
      expect([result.pages, result.pagesTruncated], [isEmpty, false]);
      expect(
        result,
        isNot(
          const LibrarySearchResult(
            query: 'q',
            folders: [],
            notes: [],
            pages: [hit],
          ),
        ),
      );
      expect(
        result,
        const LibrarySearchResult(
          query: 'q',
          folders: [],
          notes: [],
          pages: [],
        ),
      );
    });

    test('image import, AssetStorageUsage.bytesByType, NoteStoreConfig', () {
      expect(ImageImportLimits.storedMimeTypes, {'image/jpeg', 'image/png'});
      const asset = Asset(
        id: 'a',
        ownerId: kLocalOwnerId,
        type: AssetType.image,
        mimeType: 'image/png',
        size: 1,
        createdAt: 0,
      );
      expect(
        const ImportedImage(asset: asset, pixelWidth: 2, pixelHeight: 1),
        const ImportedImage(asset: asset, pixelWidth: 2, pixelHeight: 1),
      );
      const usage = AssetStorageUsage(
        assetCount: 1,
        totalBytes: 1,
        thumbnailBytes: 0,
      );
      expect(usage.bytesByType, isEmpty);
      const typed = AssetStorageUsage(
        assetCount: 1,
        totalBytes: 1,
        thumbnailBytes: 0,
        bytesByType: {AssetType.image: 1},
      );
      expect(typed, isNot(usage));
      expect(
        typed,
        const AssetStorageUsage(
          assetCount: 1,
          totalBytes: 1,
          thumbnailBytes: 0,
          bytesByType: {AssetType.image: 1},
        ),
      );
      expect(const NoteStoreConfig().nativeAssetDirectoryPath, isNull);
    });
  });
}
