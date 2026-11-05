// API surface of note_core's four entry points (contract 00-overview 7.2.2 ~ 7.2.14 and
// 7.6 'B2 테스트·개발 도우미', CORE 4.1 ~ 4.10, 8.1 T4 / T5).
// v2 (2nd-round contract docs/plans/m5-7/00-overview.md 7.2.2 ~ 7.2.7 and 7.6 '기반 단계
// 시험 도우미', m5-7/02-core 4.1 ~ 4.11, 8.1 T22 = B2-α): the 'v2' tests below reference
// every 2nd-round name with its contract type. testing_web.dart is a browser-only entry
// point: test/web/testing_web_browser_test.dart references its names (4.11).
//
// The checks are mostly compile-time:
// - every contract name is referenced from its entry point with the contract types;
// - every interface is implemented below member by member, so an added / changed member
//   breaks the build and a removed one is reported by the analyzer (@override);
// - names removed by the contract (and test-only / internal names) are declared again in
//   support/absent_names.dart, imported next to the barrel without a prefix — if the barrel
//   still exported one of them, the reference would be ambiguous (compile error);
// - removed members are checked with extensions returning [Absent]: if the class still had
//   the member, the class member would win and the assignment to [Absent] would not compile.
// openTestNoteStore is referenced, never called (it is UnimplementedError until CORE T6).
@TestOn('vm')
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:note_core/dev_tools.dart' as dev;
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart' as testing;
import 'package:note_core/testing_vm.dart' as testing_vm;
import 'package:riverpod/misc.dart' show ProviderListenable, ProviderOrFamily;
import 'package:riverpod/riverpod.dart' show AsyncValue, Provider;
import 'package:test/test.dart';

import 'support/absent_names.dart';

extension on StrokePoint {
  Absent get pressure => const Absent();
}

extension on StrokePoints {
  Absent get hasPressure => const Absent();
  Absent pressure(int i) => const Absent();
}

extension on Stroke {
  Absent get boundsInflationPerWidth => const Absent();
}

extension on SyncStore {
  Absent readEntities() => const Absent();
  Absent readCursor() => const Absent();
}

Never _no() => throw UnimplementedError();

// ---- interfaces, implemented member by member ------------------------------------------

final class _Ids implements IdGenerator {
  @override
  String newId() => 'x';
}

final class _Session implements NoteSession {
  @override
  NoteId get noteId => _no();
  @override
  Note get note => _no();
  @override
  Stream<Note> get noteStream => _no();
  @override
  bool get isReadOnly => _no();
  @override
  List<Page> get pages => _no();
  @override
  Stream<List<Page>> get pagesStream => _no();
  @override
  Future<PageContent> openPage(PageId pageId) => _no();
  @override
  void closePage(PageId pageId) => _no();
  @override
  PageContent? pageIfLoaded(PageId pageId) => _no();
  @override
  Stream<PageContentChange> pageChanges(PageId pageId) => _no();
  @override
  CommandReceipt execute(EditCommand command) => _no();
  @override
  Future<CommandReceipt> executeAsync(EditCommand command) => _no();
  @override
  HistoryState get history => _no();
  @override
  Stream<HistoryState> get historyStream => _no();
  @override
  Future<UndoRedoResult> undo() => _no();
  @override
  Future<UndoRedoResult> redo() => _no();
  @override
  void clearHistory() => _no();
  @override
  Future<void> flush() => _no();
  @override
  Future<void> close() => _no();
  @override
  bool get isClosed => _no();
}

final class _Library implements LibraryRepository {
  @override
  Stream<FolderTree> watchFolderTree() => _no();
  @override
  Stream<LibraryListing> watchListing(LibraryQuery query) => _no();
  @override
  Stream<Note?> watchNote(NoteId id) => _no();
  @override
  Future<Note?> getNote(NoteId id) => _no();
  @override
  Future<Folder?> getFolder(FolderId id) => _no();
  @override
  Stream<List<Note>> watchRecentNotes({int limit = 20}) => _no();
  @override
  Stream<List<Note>> watchFavoriteNotes() => _no();
  @override
  Future<LibrarySearchResult> searchLibrary(String query, {int limit = 50}) =>
      _no();
  @override
  Future<Folder> createFolder({
    FolderId? parentId,
    required String name,
    int? colorArgb,
    String? icon,
  }) => _no();
  @override
  Future<void> renameFolder(FolderId id, String name) => _no();
  @override
  Future<void> setFolderAppearance(
    FolderId id, {
    int? colorArgb,
    String? icon,
    bool clearColor = false,
    bool clearIcon = false,
  }) => _no();
  @override
  Future<Note> createNote({
    FolderId? folderId,
    required String title,
    List<PageDraft> pages = const [PageDraft.blankA4],
    NoteCover cover = const FirstPageCover(),
  }) => _no();
  @override
  Future<void> renameNote(NoteId id, String title) => _no();
  @override
  Future<void> setFavorite(List<NoteId> ids, bool favorite) => _no();
  @override
  Future<void> setCover(NoteId id, NoteCover cover) => _no();
  @override
  Future<void> setTags(NoteId id, List<String> tags) => _no();
  @override
  Future<void> markOpened(NoteId id) => _no();
  @override
  Future<void> moveItems(
    List<LibraryItemRef> items, {
    required FolderId? targetFolderId,
  }) => _no();
  @override
  Future<void> reorderItem(
    LibraryItemRef item, {
    LibraryItemRef? after,
    LibraryItemRef? before,
  }) => _no();
  @override
  Future<void> reorderItems(
    List<LibraryItemRef> items, {
    LibraryItemRef? after,
    LibraryItemRef? before,
  }) => _no();
  @override
  Future<List<LibraryItemRef>> copyItems(
    List<LibraryItemRef> items, {
    required FolderId? targetFolderId,
    String nameSuffix = '',
  }) => _no();
  @override
  Future<void> trashItems(List<LibraryItemRef> items) => _no();
}

final class _Trash implements TrashRepository {
  @override
  Stream<List<TrashItem>> watchTrash() => _no();
  @override
  Future<void> restore(List<LibraryItemRef> items) => _no();
  @override
  Future<void> purge(List<LibraryItemRef> items) => _no();
  @override
  Future<void> emptyTrash() => _no();
  @override
  Future<int> purgeExpired() => _no();
}

final class _Presets implements PenPresetRepository {
  @override
  Stream<List<PenPreset>> watchPresets() => _no();
  @override
  Future<List<PenPreset>> getPresets() => _no();
  @override
  Future<PenPreset> createPreset({
    required String name,
    required StrokeStyle style,
    String? group,
    bool pinned = true,
    PresetId? after,
  }) => _no();
  @override
  Future<void> updatePreset(PenPreset preset) => _no();
  @override
  Future<void> reorderPreset(
    PresetId id, {
    PresetId? after,
    PresetId? before,
  }) => _no();
  @override
  Future<void> reorderPresets(List<PresetId> orderedIds) => _no();
  @override
  Future<void> deletePreset(PresetId id) => _no();
  @override
  Future<void> ensureDefaults() => _no();
}

final class _Settings implements SettingsRepository {
  @override
  Future<T> get<T>(SettingKey<T> key) => _no();
  @override
  Stream<T> watch<T>(SettingKey<T> key) => _no();
  @override
  Future<void> set<T>(SettingKey<T> key, T value) => _no();
  @override
  Future<void> reset<T>(SettingKey<T> key) => _no();
  @override
  Stream<SettingsSnapshot> watchAll() => _no();
}

final class _Reader implements NoteContentReader {
  @override
  Future<List<Page>> pagesOf(NoteId noteId) => _no();
  @override
  Future<PageContent> loadPage(PageId pageId) => _no();
  @override
  Future<Page?> getPage(PageId pageId) => _no();
}

final class _Sync implements SyncStore {
  @override
  String get deviceNodeId => _no();
  @override
  OwnerId get ownerId => _no();
  @override
  Future<List<OutboxEntry>> pendingChanges({int limit = 500, int? afterSeq}) =>
      _no();
  @override
  Stream<int> watchPendingCount() => _no();
  @override
  Future<void> acknowledge(List<OutboxAck> acks) => _no();
  @override
  Future<List<VersionedEntity?>> readVersioned(List<EntityRef> refs) => _no();
  @override
  Future<RemoteApplyReport> applyRemote(
    List<RemoteChange> changes, {
    required RemoteMergePolicy policy,
    Map<String, String> metaUpdates = const {},
  }) => _no();
  @override
  Future<void> commitRepairs(List<RepairWrite> repairs) => _no();
  @override
  Future<String?> readMeta(String key) => _no();
  @override
  Future<void> writeMeta(Map<String, String> updates) => _no();
  @override
  Future<void> reassignOwner({required OwnerId from, required OwnerId to}) =>
      _no();
  @override
  Future<NoteId?> duplicateNoteForRecovery(
    NoteId noteId, {
    required String titleSuffix,
  }) => _no();
}

final class _Assets implements AssetStore {
  @override
  Future<Asset> put(
    Uint8List bytes, {
    required AssetType type,
    required String mimeType,
    String? fileName,
  }) => _no();
  @override
  Future<Asset?> getAsset(AssetId id) => _no();
  @override
  Future<Uint8List?> readBytes(AssetId id) => _no();
  @override
  Future<bool> hasBytes(AssetId id) => _no();
  @override
  Future<void> putDownloadedBytes(AssetId id, Uint8List bytes) => _no();
  @override
  Future<List<Asset>> listAssets({bool? hasLocalBytes, bool? uploaded}) =>
      _no();
  @override
  Future<void> markUploaded(AssetId id, String storagePath) => _no();
  @override
  Future<AssetStorageUsage> usage() => _no();
  @override
  Stream<AssetId> get bytesArrived => _no();
}

final class _Thumbs implements ThumbnailCache {
  @override
  Future<PageThumbnail?> read(PageId pageId) => _no();
  @override
  Future<void> write(PageThumbnail thumbnail) => _no();
  @override
  Future<void> delete(PageId pageId) => _no();
  @override
  Stream<PageId> get updates => _no();
}

final class _Renderer implements PageThumbnailRenderer {
  @override
  Future<PageThumbnail?> render(PageContent content, {int maxSidePx = 512}) =>
      _no();
}

final class _Fetcher implements RemoteAssetFetcher {
  @override
  Future<bool> ensureLocal(AssetId id) => _no();
  @override
  Stream<RemoteAssetProgress> watch(AssetId id) => _no();
}

final class _Store implements NoteStore {
  @override
  OwnerId get ownerId => _no();
  @override
  LibraryRepository get library => _no();
  @override
  TrashRepository get trash => _no();
  @override
  PenPresetRepository get penPresets => _no();
  @override
  SettingsRepository get settings => _no();
  @override
  NoteContentReader get content => _no();
  @override
  AssetStore get assets => _no();
  @override
  ThumbnailCache get thumbnails => _no();
  @override
  SyncStore get sync => _no();
  @override
  Stream<ChangeBatch> get changes => _no();
  @override
  PersistenceStatus get persistenceStatus => _no();
  @override
  Stream<PersistenceStatus> get persistenceStatusStream => _no();
  @override
  StorageInfo get storageInfo => _no();
  @override
  IdGenerator get ids => _no();
  @override
  Clock get clock => _no();
  @override
  Future<StorageInfo> refreshStorageInfo() => _no();
  @override
  Future<NoteSession> openSession(
    NoteId noteId, {
    NoteSessionOptions options = const NoteSessionOptions(),
  }) => _no();
  @override
  Future<void> flush() => _no();
  @override
  Future<void> close() => _no();
  @override
  Future<Uint8List> exportBackupJson() => _no();
  // v2 (7.2.6, C2-15)
  @override
  RecordingRepository get recordings => _Recordings();
  @override
  RecordingDraftStore get recordingDrafts => _Drafts();
  @override
  HandwritingRepository get handwriting => _Handwriting();
  @override
  SearchIndex get search => _Search();
}

// ---- v2 interfaces (7.2.4, 7.2.5) -------------------------------------------------------

final class _Recordings implements RecordingRepository {
  @override
  Stream<List<Recording>> watchRecordings(NoteId noteId) => _no();
  @override
  Future<List<Recording>> recordingsOf(NoteId noteId) => _no();
  @override
  Future<Recording?> getRecording(RecordingId id) => _no();
  @override
  Future<Recording> createRecording({
    required RecordingId id,
    required NoteId noteId,
    required AssetId assetId,
    required int durationMs,
    required EpochMillis startedAt,
    String? title,
  }) => _no();
  @override
  Future<void> renameRecording(RecordingId id, String? title) => _no();
  @override
  Future<void> deleteRecording(RecordingId id) => _no();
  @override
  Future<int> audioBytesOf(NoteId noteId) => _no();
}

final class _Drafts implements RecordingDraftStore {
  @override
  Future<RecordingDraft> begin({
    required RecordingId recordingId,
    required NoteId noteId,
    required String mimeType,
    required EpochMillis startedAt,
  }) => _no();
  @override
  Future<void> append(
    String draftId,
    Uint8List chunk, {
    required int activeMs,
  }) => _no();
  @override
  Future<List<RecordingDraft>> listDrafts() => _no();
  @override
  Future<Uint8List> readAll(String draftId) => _no();
  @override
  Future<void> discard(String draftId) => _no();
}

final class _Recorder implements AudioRecorderService {
  @override
  RecorderStatus get status => _no();
  @override
  Stream<RecorderStatus> get statusStream => _no();
  @override
  Future<AudioSupport> checkSupport({bool requestPermission = false}) => _no();
  @override
  Future<void> start({
    required RecordingId recordingId,
    required NoteId noteId,
  }) => _no();
  @override
  Future<void> pause() => _no();
  @override
  Future<void> resume() => _no();
  @override
  Future<Recording?> stop() => _no();
  @override
  Future<void> cancel() => _no();
  @override
  int? offsetNowMs() => _no();
  @override
  Future<List<RecordingDraft>> pendingDrafts() => _no();
  @override
  Future<Recording?> recoverDraft(String draftId) => _no();
}

final class _Player implements AudioPlaybackService {
  @override
  PlaybackStatus get status => _no();
  @override
  Stream<PlaybackStatus> get statusStream => _no();
  @override
  Future<void> open(Recording recording) => _no();
  @override
  Future<void> play() => _no();
  @override
  Future<void> pause() => _no();
  @override
  Future<void> seekMs(int positionMs) => _no();
  @override
  Future<void> setSpeed(double speed) => _no();
  @override
  int positionMs() => _no();
  @override
  Future<void> close() => _no();
}

final class _Handwriting implements HandwritingRepository {
  @override
  Future<HandwritingText?> forPage(PageId pageId) => _no();
  @override
  Stream<HandwritingText?> watchPage(PageId pageId) => _no();
  @override
  Future<void> put(HandwritingText value) => _no();
  @override
  Future<HandwritingText?> update(
    PageId pageId,
    HandwritingText? Function(HandwritingText? current) transform,
  ) => _no();
  @override
  Future<void> removeForPage(PageId pageId) => _no();
  @override
  Future<List<PageId>> stalePages(NoteId noteId) => _no();
  @override
  Future<List<NoteId>> notesWithStalePages() => _no();
}

final class _Writer implements SearchIndexWriter {
  @override
  Future<String?> sourceRevOf(SearchSource source, String ownerKey) => _no();
  @override
  Future<Map<String, String>> sourceRevs(SearchSource source) => _no();
  @override
  Future<void> replaceUnits(
    SearchSource source,
    String ownerKey,
    List<SearchUnitDraft> units, {
    required String sourceRev,
  }) => _no();
  @override
  Future<void> removeOwner(SearchSource source, String ownerKey) => _no();
}

final class _Search extends _Writer implements SearchIndex {
  @override
  Future<List<PageSearchHit>> searchPages(
    String query, {
    int limit = 100,
    NoteId? withinNote,
  }) => _no();
  @override
  Stream<SearchIndexStatus> get status => _no();
  @override
  Future<void> rebuild({Set<SearchSource>? sources}) => _no();
}

final class _Entity implements SyncEntity {
  @override
  EntityKind get kind => EntityKind.folder;
  @override
  String get id => 'x';
  @override
  Hlc? get version => null;
  @override
  EpochMillis? get deletedAt => null;
  @override
  bool get isDeleted => false;
  @override
  Map<String, Object?> toJson() => const {};
}

// ---- name references -------------------------------------------------------------------

String _exhaustiveElement(PageElement e) => switch (e) {
  Stroke() => 'stroke',
  ShapeObject() => 'shape',
  TextBoxObject() => 'text',
  ImageObject() => 'image',
  MathObject() => 'math',
  UnknownObject() => 'unknown',
};

String _exhaustiveObject(PageObject o, ShapeGeometry g) =>
    switch (o) {
      ShapeObject() || TextBoxObject() || ImageObject() || MathObject() => 'k',
      UnknownObject() => 'u',
    } +
    switch (g) {
      PolylineGeometry() => 'p',
      EllipseGeometry() => 'e',
    };

String _exhaustiveCommand(EditCommand c) => switch (c) {
  AddStrokes() => c.label,
  RemoveStrokes() => c.label,
  SplitStrokes() => c.label,
  TransformElements() => c.label,
  RestyleStrokes() => c.label,
  ClearPage() => c.label,
  InsertPages() => c.label,
  DeletePages() => c.label,
  DuplicatePages() => c.label,
  MovePages() => c.label,
  SetPageBackground() => c.label,
  ResizePages() => c.label,
  CompositeCommand() => c.label,
  AddObjects() => c.label,
  UpdateObjects() => c.label,
  RemoveElements() => c.label,
};

String _exhaustiveException(NoteCoreException e) => switch (e) {
  EntityNotFoundException() => 'a',
  FolderCycleException() => 'b',
  ReadOnlyNoteException() => 'c',
  PageNotOpenException() => 'd',
  LastPageDeletionException() => 'e',
  SessionClosedException() => 'f',
  AssetHashMismatchException() => 'g',
  NoteStoreOpenException() => 'h',
};

String _exhaustiveSealed(
  PageBackground b,
  NoteCover c,
  PagePosition p,
  LibraryItemRef r,
  TrashItem t,
  RemoteChange rc,
  MergeDecision m,
) => [
  switch (b) {
    BlankBackground() => 'blank',
    TemplateBackground() => 'template',
    PdfBackground() => 'pdf',
    ImageBackground() => 'image',
  },
  switch (c) {
    FirstPageCover() => 'first',
    ColorCover() => 'color',
    AssetCover() => 'asset',
  },
  switch (p) {
    PageAtStart() => 's',
    PageAtEnd() => 'e',
    PageBefore() => 'b',
    PageAfter() => 'a',
  },
  switch (r) {
    FolderRef() => 'f',
    NoteRef() => 'n',
  },
  switch (t) {
    TrashedFolder() => 'tf',
    TrashedNote() => 'tn',
  },
  switch (rc) {
    RemoteUpsert() => 'u',
    RemotePurge() => 'p',
  },
  switch (m) {
    KeepLocal() => 'k',
    TakeRemote() => 't',
    WriteMerged() => 'w',
  },
].join();

void main() {
  test('7.2.2 base types', () {
    const FolderId f = 'f';
    const NoteId n = 'n';
    const PageId p = 'p';
    const ElementId e = 'e';
    const PresetId pr = 'pr';
    const RecordingId r = 'r';
    const AssetId a = 'a';
    const OwnerId o = kLocalOwnerId;
    const EpochMillis t = 0;
    expect([f, n, p, e, pr, r, a, o, '$t'], hasLength(9));
    final IdGenerator g1 = UuidV7IdGenerator(clock: const Clock());
    final IdGenerator g2 = SequentialIdGenerator(prefix: 'id');
    expect(g1.newId(), isNotEmpty);
    expect(g2.newId(), 'id-000001');
    expect(_Ids().newId(), 'x');
    final bool Function(String) valid = isValidEntityId;
    expect(valid('a'), isTrue);
    const rect = PageRect(0, 0, 1, 1);
    expect([
      PageRect.fromLTWH(0, 0, 1, 1),
      PageRect.fromPoints(0, 0, 1, 1),
    ], everyElement(rect));
    expect(PageRect.zero.isEmpty, isTrue);
    // ignore: use_named_constants
    const m = Affine2(1, 0, 0, 1, 0, 0);
    expect(m, Affine2.identity);
    final Affine2? inv = m.inverse();
    final (double, double) applied = m.apply(1, 2);
    expect([inv, applied], hasLength(2));
    const h = Hlc(1, 0, '0000000000000000');
    final Hlc Function(String) parse = Hlc.parse;
    final Hlc? Function(String?) tryParse = Hlc.tryParse;
    expect(parse(h.toString()), h);
    expect(tryParse(null), isNull);
    expect([Hlc.zero, Hlc.maxCounter], hasLength(2));
    final clock = HlcClock(
      nodeId: '0000000000000001',
      clock: const Clock(),
      last: h,
      maxForwardDrift: const Duration(hours: 24),
    );
    expect(clock.maxForwardDrift, const Duration(hours: 24));
    final Hlc Function() now = clock.now;
    final Hlc Function(Hlc) receive = clock.receive;
    expect([now, receive, clock.last, clock.nodeId], hasLength(4));
    final String Function([Random?]) node = generateNodeId;
    expect(node().length, 16);
    final String Function(String?, String?) between = SortKeys.between;
    final List<String> Function(String?, String?, int) nBetween =
        SortKeys.nBetween;
    final bool Function(String) isValid = SortKeys.isValid;
    expect([
      between,
      nBetween,
      isValid,
      SortKeys.digits,
      SortKeys.first,
    ], hasLength(5));
    final int Function(String, String, String, String) cmp =
        compareSortKeyThenId;
    expect(cmp('a0', 'a', 'a0', 'a'), 0);
    const exceptions = <NoteCoreException>[
      EntityNotFoundException('m'),
      FolderCycleException('m'),
      ReadOnlyNoteException('m'),
      PageNotOpenException('m'),
      LastPageDeletionException('m'),
      SessionClosedException('m'),
      AssetHashMismatchException('m'),
      NoteStoreOpenException(NoteStoreOpenFailure.corrupted, 'm', cause: 'c'),
    ];
    expect(exceptions.map(_exhaustiveException).join(), 'abcdefgh');
    expect(exceptions.every((x) => x.message == 'm'), isTrue);
    expect(NoteStoreOpenFailure.values, hasLength(5));
    final NoteStoreOpenException open =
        exceptions.last as NoteStoreOpenException;
    final (NoteStoreOpenFailure, Object?) reason = (open.reason, open.cause);
    expect(reason.$1, NoteStoreOpenFailure.corrupted);
  });

  test('7.2.3 ~ 7.2.6 data entities', () {
    expect([kMaxWidthFactor, kNominalWidthQ], [4.0, 0.25]);
    const sp = StrokePoint(
      0,
      0,
      widthQ: kNominalWidthQ,
      tilt: 0,
      azimuth: 0,
      t: 0,
    );
    final pts = StrokePoints.fromList([sp], hasTilt: false, hasAzimuth: false);
    final StrokePoints Function(Float32List, {bool hasTilt, bool hasAzimuth})
    interleaved = StrokePoints.fromInterleaved;
    expect(interleaved(pts.rawData).contentEquals(pts), isTrue);
    expect([StrokePoints.stride, StrokePoints.maxLength], [6, 100000]);
    final builder =
        StrokePointsBuilder(
            hasTilt: false,
            hasAzimuth: false,
            initialCapacity: 4,
          )
          ..add(0, 0, widthQ: 0.25, tilt: 0, azimuth: 0, t: 0)
          ..addPoint(sp);
    expect([
      builder.length,
      builder.isFull,
      builder.hasTilt,
      builder.hasAzimuth,
    ], hasLength(4));
    final Uint8List Function(StrokePoints) enc = StrokePointsCodec.encode;
    final StrokePoints Function(Uint8List) dec = StrokePointsCodec.decode;
    final String Function(StrokePoints) enc64 = StrokePointsCodec.encodeBase64;
    final StrokePoints Function(String) dec64 = StrokePointsCodec.decodeBase64;
    expect(dec(enc(pts)).contentEquals(dec64(enc64(pts))), isTrue);
    // Removed members (contract 7.2.3 'Removed').
    final Absent a1 = sp.pressure;
    final Absent a2 = pts.hasPressure;
    final Absent a3 = pts.pressure(0);
    final stroke = Stroke(
      id: 's',
      pageId: 'p',
      style: StrokeStyle.defaultsFor(PenTool.ballpoint),
      points: pts,
      recordingId: null,
      recordingOffsetMs: null,
      createdAt: 0,
      updatedAt: null,
      deletedAt: null,
      version: null,
    );
    final Absent a4 = stroke.boundsInflationPerWidth;
    expect([a1, a2, a3, a4, kDefaultPressure], everyElement(const Absent()));
    final PageElement element = stroke;
    expect(_exhaustiveElement(element), 'stroke');
    final int Function(PageElement, PageElement) order = Stroke.compareOrder;
    expect(order(stroke, stroke), 0);
    final Stroke frag = stroke.fragment(id: 's2', points: pts);
    final Stroke moved = stroke.transformed(Affine2.identity, scaleWidth: true);
    final Stroke copy = stroke.copyWith(
      id: 'c',
      pageId: 'p',
      style: stroke.style,
      points: pts,
      recordingId: 'r',
      recordingOffsetMs: 1,
      createdAt: 1,
      updatedAt: 1,
      deletedAt: 1,
      clearDeletedAt: true,
      version: Hlc.zero,
    );
    expect([
      frag,
      moved,
      copy,
      stroke.bounds,
      stroke.estimatedBytes,
    ], hasLength(5));
    expect(Stroke.fromJson(stroke.toJson()), stroke);

    expect(PenTool.values, hasLength(10));
    final PenTool Function(String) wire = PenTool.fromWireName;
    expect(wire('pencil'), PenTool.pencil);
    expect([
      PressureCurve.linear,
      PressureCurve.soft,
      PressureCurve.firm,
    ], hasLength(3));
    // ignore: use_named_constants
    const curve = PressureCurve(x1: 0.25, y1: 0.25, x2: 0.75, y2: 0.75);
    expect(PressureCurve.fromJson(curve.toJson()), curve);
    const style = StrokeStyle(
      tool: PenTool.ballpoint,
      colorArgb: 0xFF000000,
      width: 1,
      opacity: 1.0,
      pressureSensitivity: 1.0,
      pressureCurve: PressureCurve.linear,
      smoothing: 0.5,
      extras: {},
    );
    expect(
      [StrokeStyle.minWidth, StrokeStyle.maxWidth, StrokeStyle.minOpacity],
      [0.1, 30.0, 0.05],
    );
    final StrokeStyle s2 = style.copyWith(
      tool: PenTool.marker,
      colorArgb: 0,
      width: 1,
      opacity: 1,
      pressureSensitivity: 1,
      pressureCurve: curve,
      smoothing: 0,
      extras: const {},
    );
    expect([
      s2.normalized(),
      style.effectiveAlpha,
      StrokeStyle.fromJson(style.toJson()),
    ], hasLength(3));
    const patch = StrokeStylePatch(
      colorArgb: 0,
      width: 1,
      widthScale: 1,
      opacity: 1,
    );
    expect(patch.applyTo(style), isA<StrokeStyle>());
    expect(patch.isEmpty, isFalse);

    const size = PageSize(1, 2);
    expect([
      PageSize.a4Portrait,
      PageSize.letterPortrait,
      PageSize.widescreen16x9,
    ], hasLength(3));
    expect([
      size.isLandscape,
      size.landscape,
      size.portrait,
      size.clamped(),
    ], hasLength(4));
    final PageSizePreset? Function(PageSize) match = PageSizePreset.match;
    expect(match(PageSizePreset.letter.portrait), PageSizePreset.letter);
    expect(
      [PageSizeLimits.userMinSidePt, PageSizeLimits.userMaxSidePt],
      [100, 3000],
    );
    expect(PageTemplateKind.values, hasLength(6));
    const template = PageTemplate(
      kind: PageTemplateKind.planner,
      spacing: null,
      lineColorArgb: null,
      lineWidth: null,
      extras: {TemplateExtrasKeys.plannerLayout: 'weekly'},
    );
    expect(PageTemplate.fromJson(template.toJson()), template);
    expect(PageTemplate.defaults(PageTemplateKind.lined).spacing, isNull);
    expect([
      TemplateExtrasKeys.marginTop,
      TemplateExtrasKeys.marginLeft,
      TemplateExtrasKeys.showMarginLine,
      TemplateExtrasKeys.headerHeight,
      TemplateExtrasKeys.cueColumnWidth,
      TemplateExtrasKeys.summaryHeight,
      TemplateExtrasKeys.staffGap,
      TemplateExtrasKeys.plannerLayout,
    ], hasLength(8));
    final double Function(int) lum = PaperColors.luminance;
    final bool Function(int) dark = PaperColors.isDark;
    expect([lum, dark, PaperColors.all], hasLength(3));
    const backgrounds = <PageBackground>[
      BlankBackground(paperColorArgb: PaperColors.white),
      TemplateBackground(template: template, paperColorArgb: PaperColors.ivory),
      PdfBackground(
        assetId: 'a',
        pdfPageIndex: 0,
        paperColorArgb: PaperColors.gray,
      ),
      ImageBackground(
        assetId: 'a',
        fit: ImageFit.contain,
        paperColorArgb: PaperColors.black,
      ),
    ];
    final PageBackground Function(Map<String, Object?>) bg =
        PageBackground.fromJson;
    expect(backgrounds.map((b) => bg(b.toJson())), backgrounds);
    const page = Page(
      id: 'p',
      noteId: 'n',
      sortKey: 'a0',
      size: size,
      background: BlankBackground(),
      createdAt: 0,
      updatedAt: 0,
      deletedAt: null,
      version: null,
      contentRevision: 0,
    );
    final Page pageCopy = page.copyWith(
      sortKey: 'a1',
      size: size,
      background: const BlankBackground(),
      updatedAt: 1,
      deletedAt: 1,
      clearDeletedAt: true,
      version: Hlc.zero,
      contentRevision: 1,
    );
    expect([pageCopy, Page.fromJson(page.toJson()), page.kind], hasLength(3));

    const folder = Folder(
      id: 'f',
      ownerId: 'o',
      parentId: null,
      name: 'n',
      colorArgb: null,
      icon: null,
      sortKey: 'a0',
      createdAt: 0,
      updatedAt: 0,
      deletedAt: null,
      trashRootId: null,
      version: null,
    );
    expect(
      folder.copyWith(
        ownerId: 'o',
        parentId: 'p',
        clearParentId: true,
        name: 'n',
        colorArgb: 0,
        clearColor: true,
        icon: 'i',
        clearIcon: true,
        sortKey: 'a0',
        updatedAt: 0,
        deletedAt: 0,
        clearDeletedAt: true,
        trashRootId: 't',
        clearTrashRootId: true,
        version: Hlc.zero,
      ),
      isA<Folder>(),
    );
    const note = Note(
      id: 'n',
      ownerId: 'o',
      folderId: null,
      title: 't',
      cover: FirstPageCover(),
      tags: [],
      isFavorite: false,
      sortKey: 'a0',
      schemaVersion: kNoteSchemaVersion,
      createdAt: 0,
      updatedAt: 0,
      deletedAt: null,
      trashRootId: null,
      version: null,
      pageCount: 0,
      firstPageId: null,
      lastOpenedAt: null,
    );
    expect(
      note.copyWith(
        ownerId: 'o',
        folderId: 'f',
        clearFolderId: true,
        title: 't',
        cover: const ColorCover(0),
        tags: const [],
        isFavorite: true,
        sortKey: 'a0',
        schemaVersion: 1,
        updatedAt: 0,
        deletedAt: 0,
        clearDeletedAt: true,
        trashRootId: 't',
        clearTrashRootId: true,
        version: Hlc.zero,
        pageCount: 1,
        firstPageId: 'p',
        clearFirstPageId: true,
        lastOpenedAt: 1,
      ),
      isA<Note>(),
    );
    expect(note.requiresNewerApp, isFalse);
    final NoteCover Function(Map<String, Object?>) cover = NoteCover.fromJson;
    expect(cover(const AssetCover('a').toJson()), const AssetCover('a'));
    final preset = PenPreset(
      id: 'p',
      ownerId: 'o',
      name: 'n',
      style: style,
      group: null,
      pinned: true,
      sortKey: 'a0',
      createdAt: 0,
      updatedAt: 0,
      deletedAt: null,
      version: null,
    );
    expect(
      preset.copyWith(
        ownerId: 'o',
        name: 'n',
        style: style,
        group: 'g',
        clearGroup: true,
        pinned: false,
        sortKey: 'a0',
        updatedAt: 0,
        deletedAt: 0,
        clearDeletedAt: true,
        version: Hlc.zero,
      ),
      isA<PenPreset>(),
    );
    expect(AssetType.values, hasLength(3));
    const asset = Asset(
      id: 'a',
      ownerId: 'o',
      type: AssetType.pdf,
      mimeType: 'application/pdf',
      size: 1,
      fileName: null,
      createdAt: 0,
      storagePath: null,
      deletedAt: null,
      version: null,
      hasLocalBytes: true,
    );
    const recording = Recording(
      id: 'r',
      noteId: 'n',
      assetId: 'a',
      durationMs: 1,
      startedAt: 0,
      createdAt: 0,
      updatedAt: 0,
      deletedAt: null,
      version: null,
    );
    const setting = SettingValue(
      key: 'k',
      valueJson: '1',
      updatedAt: 0,
      deletedAt: null,
      version: null,
    );
    // v2 (7.2.2, 7.2.5): EntityKind.pageObject / handwriting
    final object = ShapeObject(
      id: 'o',
      pageId: 'p',
      shapeKind: ShapeKind.line,
      geometry: const PolylineGeometry([
        PagePoint(0, 0),
        PagePoint(1, 1),
      ], closed: false),
      style: const ShapeStyle(strokeColorArgb: 0xFF000000),
      createdAt: 0,
    );
    final handwriting = HandwritingText(
      noteId: 'n',
      pageId: 'p',
      engineId: 'fake',
      sourceRev: '0000000000000000',
      lines: const [],
      createdAt: 0,
    );
    final entities = <SyncEntity>[
      folder,
      note,
      page,
      stroke,
      preset,
      asset,
      recording,
      setting,
      object,
      handwriting,
      _Entity(),
    ];
    expect(entities.map((x) => x.kind).toSet(), EntityKind.values.toSet());
    final SyncEntity Function(EntityKind, Map<String, Object?>) decode =
        EntityJson.decode;
    expect(decode(EntityKind.setting, setting.toJson()), setting);
    expect(
      [kNoteSchemaVersion, kDatabaseSchemaVersion, kStrokePointsFormatVersion],
      [1, 1, 1],
    );
  });

  test('7.2.7 edit commands and history', () {
    const positions = <PagePosition>[
      PageAtStart(),
      PageAtEnd(),
      PageBefore('p'),
      PageAfter('p'),
    ];
    // ignore: use_named_constants
    const draft = PageDraft(
      id: 'p2',
      size: PageSize.letterPortrait,
      background: BlankBackground(),
      strokes: [],
    );
    final PageDraft Function(PageContent) copyOf = PageDraft.copyOf;
    expect([draft, PageDraft.blankA4, copyOf], hasLength(3));
    expect(StrokeFilter.values, hasLength(3));
    final commands = <EditCommand>[
      const AddStrokes(pageId: 'p', strokes: []),
      const RemoveStrokes(pageId: 'p', strokeIds: []),
      const SplitStrokes(pageId: 'p', removedIds: [], added: []),
      const TransformElements(
        pageId: 'p',
        elementIds: [],
        transform: Affine2.identity,
        scaleStrokeWidth: true,
      ),
      const RestyleStrokes(
        pageId: 'p',
        strokeIds: [],
        patch: StrokeStylePatch(),
      ),
      const ClearPage(pageId: 'p', filter: StrokeFilter.all),
      InsertPages(drafts: const [draft], position: positions.first),
      const DeletePages(pageIds: []),
      const DuplicatePages(pageIds: []),
      const MovePages(pageIds: [], position: PageAtEnd()),
      const SetPageBackground(pageIds: [], background: BlankBackground()),
      const ResizePages(pageIds: [], size: PageSize.a4Portrait),
      const CompositeCommand([], label: 'composite'),
    ];
    expect(commands.map(_exhaustiveCommand).toSet(), hasLength(13));
    const delta = EntityDelta(
      kind: EntityKind.stroke,
      id: 's',
      before: null,
      after: null,
    );
    const edit = AppliedEdit(
      label: 'l',
      deltas: [delta],
      version: Hlc.zero,
      affectedPageIds: {},
      insertedPageIds: [],
      insertedElementIds: [],
    );
    expect([edit.isEmpty, edit.estimatedBytes], hasLength(2));
    final receipt = CommandReceipt(edit: edit, persisted: Future<void>.value());
    expect(receipt.persisted, completes);
    const limits = HistoryLimits(maxSteps: 100, maxBytes: 64 * 1024 * 1024);
    expect(HistoryLimits.platformDefault.maxSteps, limits.maxSteps);
    // ignore: use_named_constants
    const state = HistoryState(
      canUndo: false,
      canRedo: false,
      undoDepth: 0,
      redoDepth: 0,
      undoLabel: null,
      redoLabel: null,
      retainedBytes: 0,
    );
    expect(state, HistoryState.empty);
    const result = UndoRedoResult(
      applied: true,
      edit: edit,
      skippedEntities: 0,
      skippedEntries: 0,
    );
    final Set<PageId> affected = result.affectedPageIds;
    expect([affected, UndoRedoResult.nothing], hasLength(2));
  });

  test('7.2.8 note session', () {
    final content = PageContent(
      page: const Page(
        id: 'p',
        noteId: 'n',
        sortKey: 'a0',
        size: PageSize.a4Portrait,
        background: BlankBackground(),
        createdAt: 0,
        updatedAt: 0,
      ),
      strokes: const [],
      revision: 0,
    );
    final Stroke? Function(ElementId) byId = content.strokeById;
    expect([byId('x'), content.strokeCount], [null, 0]);
    expect(ChangeOrigin.values, hasLength(5));
    final change = PageContentChange(
      content: content,
      origin: ChangeOrigin.load,
      added: const {},
      removed: const {},
      updated: const {},
      pageChanged: false,
    );
    expect(change.origin, ChangeOrigin.load);
    const options = NoteSessionOptions(
      maxCachedPages: 8,
      history: HistoryLimits.platformDefault,
    );
    expect(options.maxCachedPages, 8);
    final NoteSession session = _Session();
    expect(session, isA<NoteSession>());
  });

  test('7.2.9 repositories', () {
    const refs = <LibraryItemRef>[FolderRef('f'), NoteRef('n')];
    expect(LibrarySortField.values, hasLength(4));
    const q = LibraryQuery(
      folderId: null,
      sort: LibrarySortField.updatedAt,
      descending: true,
    );
    expect(q, const LibraryQuery());
    const listing = LibraryListing(folderId: null, folders: [], notes: []);
    const search = LibrarySearchResult(query: 'q', folders: [], notes: []);
    final tree = FolderTree(const []);
    final List<List<FolderId>> Function() cycles = tree.findCycles;
    expect([
      listing,
      search,
      tree.length,
      tree.folders,
      tree.roots,
      cycles(),
    ], hasLength(6));
    expect(tree.childrenOf(null), isEmpty);
    expect(tree.byId('x'), isNull);
    expect(tree.pathTo('x'), isEmpty);
    expect(tree.descendantsOf('x'), isEmpty);
    expect(tree.isSelfOrDescendant('x', of: 'x'), isTrue);
    final items = <TrashItem>[
      const TrashedFolder(
        folder: Folder(
          id: 'f',
          ownerId: 'o',
          name: 'n',
          sortKey: 'a0',
          createdAt: 0,
          updatedAt: 0,
          deletedAt: 5,
        ),
        folderCount: 0,
        noteCount: 0,
        expiresAt: 9,
      ),
      const TrashedNote(
        note: Note(
          id: 'n',
          ownerId: 'o',
          title: 't',
          sortKey: 'a0',
          createdAt: 0,
          updatedAt: 0,
          deletedAt: 5,
        ),
        expiresAt: 9,
      ),
    ];
    expect(
      items.map((i) => (i.ref, i.name, i.deletedAt, i.expiresAt)),
      hasLength(2),
    );
    expect(SettingScope.values, hasLength(2));
    final keys = <SettingKey<Object?>>[
      SettingKey<int>(
        'editor.x',
        defaultValue: 1,
        encode: (v) => v,
        decode: (j) => j! as int,
        scope: SettingScope.device,
      ),
      SettingKey.boolean('editor.a', false, scope: SettingScope.synced),
      SettingKey.integer('editor.b', 0),
      SettingKey.number('editor.c', 0),
      SettingKey.string('editor.d', ''),
      SettingKey.intList('editor.e', const []),
      SettingKey.stringList('editor.f', const [], scope: SettingScope.synced),
      SettingKey.jsonMap(
        'editor.g',
        defaultValue: const {},
        scope: SettingScope.synced,
      ),
    ];
    expect(
      keys.map((k) => (k.name, k.defaultValue, k.encode, k.decode, k.scope)),
      hasLength(8),
    );
    const snapshot = SettingsSnapshot({});
    expect(snapshot.get(SettingKey.integer('editor.b', 3)), 3);
    final repos = <Object>[
      _Library(),
      _Trash(),
      _Presets(),
      _Settings(),
      _Reader(),
    ];
    expect(repos, hasLength(5));
    expect(refs, hasLength(2));
  });

  test('7.2.10 change log and sync window', () {
    expect(OutboxOp.values, hasLength(2));
    expect(kAllFields, '*');
    const ref = EntityRef(EntityKind.note, 'n');
    final entry = OutboxEntry(
      seq: 1,
      rev: 0,
      kind: EntityKind.stroke,
      entityId: 's',
      noteId: 'n',
      pageId: 'p',
      op: OutboxOp.upsert,
      changedFields: const {kAllFields},
      hlc: Hlc.zero,
      enqueuedAt: 0,
    );
    final OutboxAck ack = entry.ack;
    final EntityRef entryRef = entry.ref;
    expect([ack, entryRef, ref, const OutboxAck(1, 0)], hasLength(4));
    const versions = EntityFieldVersions(Hlc.zero, {});
    final Hlc Function(String) of = versions.of;
    expect([
      of('x'),
      versions.max,
      EntityFieldVersions.fromJson(versions.toJson()),
    ], hasLength(3));
    final ve = VersionedEntity(_Entity(), versions);
    const changes = <RemoteChange>[RemotePurge(EntityKind.note, 'n')];
    final upsert = RemoteUpsert(_Entity(), versions);
    final decisions = <MergeDecision>[
      const KeepLocal(),
      const TakeRemote(dropPendingLocal: true),
      WriteMerged(_Entity(), versions, fieldsToUpload: const {}),
    ];
    final RemoteMergePolicy policy = testing.newerVersionWinsPolicy;
    expect(policy(null, ve, null), isA<TakeRemote>());
    expect(
      _exhaustiveSealed(
        const BlankBackground(),
        const FirstPageCover(),
        const PageAtEnd(),
        const NoteRef('n'),
        const TrashedNote(
          note: Note(
            id: 'n',
            ownerId: 'o',
            title: 't',
            sortKey: 'a0',
            createdAt: 0,
            updatedAt: 0,
          ),
          expiresAt: 0,
        ),
        upsert,
        decisions.last,
      ),
      'blankfirstentnuw',
    );
    const report = RemoteApplyReport(
      taken: 0,
      kept: 0,
      merged: 0,
      purged: 0,
      affectedNoteIds: {},
    );
    final RepairWrite repair = (entity: _Entity(), fields: const {'title'});
    final SyncStore sync = _Sync();
    // Removed members (contract 7.2.10 'Removed').
    final Absent r1 = sync.readEntities();
    final Absent r2 = sync.readCursor();
    expect([changes, report, repair, r1, r2], hasLength(5));
    const change = EntityChange(
      kind: EntityKind.stroke,
      id: 's',
      noteId: 'n',
      pageId: 'p',
      deleted: false,
      purged: false,
    );
    const batch = ChangeBatch(
      origin: ChangeOrigin.local,
      changes: [change],
      committedAt: 0,
    );
    expect(batch.changes.single, change);
  });

  test('7.2.11 assets, thumbnails, remote assets', () {
    const usage = AssetStorageUsage(
      assetCount: 0,
      totalBytes: 0,
      thumbnailBytes: 0,
    );
    final thumb = PageThumbnail(
      pageId: 'p',
      contentRevision: 0,
      width: 1,
      height: 1,
      mimeType: 'image/png',
      bytes: Uint8List(0),
    );
    final bool Function(Page) stale = thumb.isStaleFor;
    expect([usage, stale], hasLength(2));
    expect(RemoteAssetState.values, hasLength(6));
    const progress = RemoteAssetProgress(
      RemoteAssetState.downloading,
      received: 1,
      total: 2,
    );
    final services = <Object>[_Assets(), _Thumbs(), _Renderer(), _Fetcher()];
    expect([progress, services], hasLength(2));
  });

  test('7.2.12 store bundle, status, open', () {
    const status = PersistenceStatus(
      pendingOps: 0,
      isWriting: false,
      lastCommittedAt: null,
      lastCommitLatency: null,
      lastError: null,
      lastErrorAt: null,
      consecutiveFailures: 0,
    );
    expect(StorageBackend.values, hasLength(7));
    const info = StorageInfo(
      backend: StorageBackend.nativeFile,
      missingBrowserFeatures: [],
      persistGranted: null,
      usageBytes: null,
      quotaBytes: null,
    );
    expect([info.isDurable, info.isMultiTabSafe], [true, true]);
    expect(StorageWarning.values, hasLength(2));
    final StorageWarning? Function(StorageInfo, PersistenceStatus) warn =
        storageWarningOf;
    expect(warn(info, status), isNull);
    const web = WebStorageConfig(
      sqlite3WasmPath: 'sqlite3.wasm',
      driftWorkerPath: 'drift_worker.js',
      blobDatabaseName: 'noteapp_blobs',
    );
    final config = NoteStoreConfig(
      databaseName: 'noteapp',
      ownerId: kLocalOwnerId,
      web: web,
      nativeDatabasePath: null,
      inMemory: false,
      trashRetention: const Duration(days: 30),
      requestPersistentStorage: true,
      seedDefaultPenPresets: true,
      clock: const Clock(),
      idGenerator: SequentialIdGenerator(),
    );
    final Future<NoteStore> Function(NoteStoreConfig) open = openNoteStore;
    final Future<void> Function(NoteStoreConfig) delete = deleteLocalNoteData;
    final NoteStore store = _Store();
    expect([config, open, delete, store], hasLength(4));
  });

  test('7.2.13 sync badge + 7.2.14 providers', () {
    expect(SyncDisplayState.values, hasLength(5));
    // ignore: use_named_constants
    const badge = SyncBadge(
      display: SyncDisplayState.off,
      pendingChanges: 0,
      lastSyncedAt: null,
      issueCode: null,
    );
    expect(badge, SyncBadge.off);
    final Duration? Function(int, Object) retry = noRetry;
    expect(retry(1, 'e'), isNull);
    const PageKey key = (noteId: 'n', pageId: 'p');
    expect(key.noteId, 'n');
    final providers = <String, ProviderOrFamily>{
      'noteStoreProvider': noteStoreProvider,
      'libraryRepositoryProvider': libraryRepositoryProvider,
      'trashRepositoryProvider': trashRepositoryProvider,
      'penPresetRepositoryProvider': penPresetRepositoryProvider,
      'settingsRepositoryProvider': settingsRepositoryProvider,
      'noteContentReaderProvider': noteContentReaderProvider,
      'assetStoreProvider': assetStoreProvider,
      'thumbnailCacheProvider': thumbnailCacheProvider,
      'syncStoreProvider': syncStoreProvider,
      'idGeneratorProvider': idGeneratorProvider,
      'clockProvider': clockProvider,
      'pageThumbnailRendererProvider': pageThumbnailRendererProvider,
      'remoteAssetFetcherProvider': remoteAssetFetcherProvider,
      'syncBadgeProvider': syncBadgeProvider,
      'folderTreeProvider': folderTreeProvider,
      'libraryListingProvider': libraryListingProvider,
      'noteProvider': noteProvider,
      'recentNotesProvider': recentNotesProvider,
      'favoriteNotesProvider': favoriteNotesProvider,
      'librarySearchProvider': librarySearchProvider,
      'trashItemsProvider': trashItemsProvider,
      'noteSessionProvider': noteSessionProvider,
      'notePagesProvider': notePagesProvider,
      'pageContentProvider': pageContentProvider,
      'historyStateProvider': historyStateProvider,
      'penPresetsProvider': penPresetsProvider,
      'settingsSnapshotProvider': settingsSnapshotProvider,
      'pageThumbnailProvider': pageThumbnailProvider,
      'persistenceStatusProvider': persistenceStatusProvider,
      'storageInfoProvider': storageInfoProvider,
      'syncPendingCountProvider': syncPendingCountProvider,
    };
    expect(providers, hasLength(31));
    for (final e in providers.entries) {
      expect(
        e.value.name,
        e.key,
        reason: 'name: argument == variable name (7.4.4)',
      );
    }
  });

  test('testing.dart / testing_vm.dart / dev_tools.dart', () async {
    final faults = testing.FakeNoteStoreFaults()
      ..failNextCommits(0, error: const FormatException('injected'))
      ..commitDelay = Duration.zero;
    final NoteStore Function({
      Clock? clock,
      IdGenerator? ids,
      OwnerId ownerId,
      bool seedDefaultPenPresets,
      StorageInfo storageInfo,
      testing.FakeNoteStoreFaults? faults,
    })
    create = testing.createFakeNoteStore;
    final store = create(
      clock: const Clock(),
      ids: SequentialIdGenerator(),
      ownerId: kLocalOwnerId,
      seedDefaultPenPresets: true,
      storageInfo: const StorageInfo(backend: StorageBackend.nativeFile),
      faults: faults,
    );
    final Stroke Function({
      required PageId pageId,
      required IdGenerator ids,
      int seed,
      int pointCount,
      double hz,
      PenTool tool,
      EpochMillis createdAt,
      bool hasTilt,
    })
    synthetic = testing.StrokeFixtures.synthetic;
    final List<Stroke> Function({
      required PageId pageId,
      required IdGenerator ids,
      required int count,
      int seed,
    })
    many = testing.StrokeFixtures.manySynthetic;
    final MergeDecision Function(
      VersionedEntity?,
      VersionedEntity,
      Set<String>?,
    )
    policy = testing.newerVersionWinsPolicy;
    // Referenced only: the body is UnimplementedError until CORE T6.
    final Future<NoteStore> Function({
      Clock? clock,
      IdGenerator? ids,
      OwnerId ownerId,
      String? filePath,
      String? deviceNodeId,
      bool seedDefaultPenPresets,
      StorageInfo? storageInfo,
    })
    openTest = testing_vm.openTestNoteStore;
    final Future<NoteId> Function(
      NoteStore, {
      String title,
      int pages,
      int strokesPerPage,
      int pointsPerStroke,
      int seed,
    })
    seed = dev.seedSyntheticNote;
    expect([synthetic, many, policy, openTest, seed], hasLength(5));
    // The barrel exports none of the test / dev / internal names.
    expect([
      createFakeNoteStore,
      newerVersionWinsPolicy,
      openTestNoteStore,
      seedSyntheticNote,
      normalizeForSearch,
      readVersion,
      checkSettingKeyName,
      decodeSetting,
      planSortKeys,
    ], everyElement(const Absent()));
    expect([
      FakeNoteStoreFaults,
      StrokeFixtures,
      SessionEngine,
      CommandResolver,
      EditHistory,
      FakeNoteStore,
      StrokeEraseSession,
      StorageUnavailableException,
    ], hasLength(8));
    await store.close();
  });

  test('contract-removed names stay removed', () {
    expect(kDefaultPressure, const Absent());
    expect(StrokeEraseSession, isNotNull);
    expect(StorageUnavailableException, isNotNull);
    unawaited(Future<void>.value());
  });

  // ---- v2: 2nd-round contract (B2-α) -------------------------------------------------

  test('v2 7.2.2 PagePoint, ElementFrame', () {
    const point = PagePoint(1, 2);
    final List<double> xy = [point.x, point.y];
    final PagePoint Function(Affine2) movePoint = point.transformed;
    const frame = ElementFrame(PageRect(0, 0, 10, 20), rotation: 0.5);
    const flat = ElementFrame(PageRect(0, 0, 10, 0));
    final PageRect rect = frame.rect;
    final double rotation = frame.rotation;
    expect(
      [xy, rect, rotation, flat.rotation],
      [
        [1, 2],
        const PageRect(0, 0, 10, 20),
        0.5,
        0,
      ],
    );
    final List<Object> geometry = [
      () => frame.center,
      () => frame.corners,
      () => frame.bounds,
    ];
    final ElementFrame Function(Affine2) moveFrame = frame.transformed;
    final bool Function(PagePoint, {double tolerance}) contains =
        frame.contains;
    final List<double> Function() toJson = frame.toJson;
    final ElementFrame Function(List<Object?>) fromJson = ElementFrame.fromJson;
    final ElementFrame Function() normalized = frame.normalized;
    const double maxSide = ElementFrame.maxSide;
    expect(maxSide, 14400);
    expect([
      movePoint,
      geometry,
      moveFrame,
      contains,
      toJson,
      fromJson,
      normalized,
    ], hasLength(7));
  });

  test('v2 7.2.2 page objects', () {
    expect(EntityKind.values.map((k) => k.name), [
      'folder',
      'note',
      'page',
      'stroke',
      'penPreset',
      'asset',
      'recording',
      'setting',
      'pageObject',
      'handwriting',
    ]);
    expect(ShapeKind.values.map((k) => k.name), [
      'line',
      'arrow',
      'rectangle',
      'ellipse',
      'triangle',
      'polygon',
      'star',
    ]);
    expect(LineDash.values.map((k) => k.name), ['solid', 'dashed', 'dotted']);
    expect(ArrowHeads.values.map((k) => k.name), ['none', 'end', 'both']);
    expect(TextAlignKind.values.map((k) => k.name), ['start', 'center', 'end']);
    expect(
      [
        PageObjectLimits.maxObjectsPerPage,
        PageObjectLimits.maxTextLength,
        PageObjectLimits.maxLatexLength,
        PageObjectLimits.maxPolylinePoints,
      ],
      [2000, 10000, 4000, 64],
    );

    const shapeStyle = ShapeStyle(
      strokeColorArgb: 0xFF000000,
      strokeWidth: 2.0,
      strokeOpacity: 1.0,
      dash: LineDash.solid,
      fillColorArgb: null,
      fillOpacity: 1.0,
      arrowHeads: ArrowHeads.none,
    );
    expect([ShapeStyle.minWidth, ShapeStyle.maxWidth], [0.1, 30.0]);
    final List<Object?> shapeStyleFields = [
      shapeStyle.strokeColorArgb,
      shapeStyle.strokeWidth,
      shapeStyle.strokeOpacity,
      shapeStyle.dash,
      shapeStyle.fillColorArgb,
      shapeStyle.fillOpacity,
      shapeStyle.arrowHeads,
    ];
    double arrowHeadLength() => shapeStyle.arrowHeadLength;
    final ShapeStyle Function() normalizeShape = shapeStyle.normalized;
    final ShapeStyle Function({
      int? strokeColorArgb,
      double? strokeWidth,
      double? strokeOpacity,
      LineDash? dash,
      int? fillColorArgb,
      bool clearFill,
      double? fillOpacity,
      ArrowHeads? arrowHeads,
    })
    copyShapeStyle = shapeStyle.copyWith;
    final Map<String, Object?> Function() shapeStyleJson = shapeStyle.toJson;
    final ShapeStyle Function(Map<String, Object?>) shapeStyleFrom =
        ShapeStyle.fromJson;

    const poly = PolylineGeometry([
      PagePoint(0, 0),
      PagePoint(10, 10),
    ], closed: false);
    const ellipse = EllipseGeometry(ElementFrame(PageRect(0, 0, 10, 10)));
    final List<PagePoint> points = poly.points;
    final bool closed = poly.closed;
    final ElementFrame ellipseFrame = ellipse.ellipseFrame;
    final ShapeGeometry Function(Affine2) moveGeometry = poly.transformed;
    ElementFrame geometryFrame() => poly.frame;
    final Object Function() geometryJson = poly.toJson;
    final ShapeGeometry Function(Object?) geometryFrom = ShapeGeometry.fromJson;
    final PolylineGeometry Function(PagePoint, PagePoint) line =
        ShapeGeometry.line;
    final PolylineGeometry Function(PageRect, {double rotation}) rectangle =
        ShapeGeometry.rectangle;
    final EllipseGeometry Function(PageRect, {double rotation}) ellipseOf =
        ShapeGeometry.ellipse;
    final PolylineGeometry Function(PageRect) triangle = ShapeGeometry.triangle;
    final PolylineGeometry Function(PageRect, int, {double rotation}) polygon =
        ShapeGeometry.regularPolygon;
    final PolylineGeometry Function(PageRect, {int points, double innerRatio})
    star = ShapeGeometry.star;

    final shape = ShapeObject(
      id: 's',
      pageId: 'p',
      shapeKind: ShapeKind.line,
      geometry: poly,
      style: shapeStyle,
      createdAt: 1,
      updatedAt: null,
      deletedAt: null,
      version: null,
    );
    final ShapeKind shapeKind = shape.shapeKind;
    final ShapeGeometry shapeGeometry = shape.geometry;
    final ShapeStyle shapeStyleOf = shape.style;
    final ShapeObject Function({
      ShapeKind? shapeKind,
      ShapeGeometry? geometry,
      ShapeStyle? style,
      EpochMillis? updatedAt,
    })
    copyShape = shape.copyWith;

    const textStyle = TextBoxStyle(
      fontSizePt: 16,
      colorArgb: 0xFF1A1A1A,
      bold: false,
      align: TextAlignKind.start,
      lineHeight: 1.4,
      backgroundArgb: null,
    );
    expect([TextBoxStyle.minFontSize, TextBoxStyle.maxFontSize], [6, 144]);
    final List<Object?> textStyleFields = [
      textStyle.fontSizePt,
      textStyle.colorArgb,
      textStyle.bold,
      textStyle.align,
      textStyle.lineHeight,
      textStyle.backgroundArgb,
    ];
    final TextBoxStyle Function() normalizeText = textStyle.normalized;
    final TextBoxStyle Function({
      double? fontSizePt,
      int? colorArgb,
      bool? bold,
      TextAlignKind? align,
      double? lineHeight,
      int? backgroundArgb,
      bool clearBackground,
    })
    copyTextStyle = textStyle.copyWith;
    final Map<String, Object?> Function() textStyleJson = textStyle.toJson;
    final TextBoxStyle Function(Map<String, Object?>) textStyleFrom =
        TextBoxStyle.fromJson;
    final text = TextBoxObject(
      id: 't',
      pageId: 'p',
      frame: const ElementFrame(PageRect(0, 0, 100, 20)),
      text: '안녕',
      style: textStyle,
      createdAt: 1,
      updatedAt: 2,
      deletedAt: null,
      version: null,
    );
    final List<Object> textFields = [text.frame, text.text, text.style];
    final TextBoxObject Function({
      ElementFrame? frame,
      String? text,
      TextBoxStyle? style,
      EpochMillis? updatedAt,
    })
    copyText = text.copyWith;

    final image = ImageObject(
      id: 'i',
      pageId: 'p',
      frame: const ElementFrame(PageRect(0, 0, 40, 30)),
      assetId: 'a' * 64,
      pixelWidth: 400,
      pixelHeight: 300,
      createdAt: 1,
      updatedAt: null,
      deletedAt: null,
      version: null,
    );
    final List<Object> imageFields = [
      image.frame,
      image.assetId,
      image.pixelWidth,
      image.pixelHeight,
    ];
    final ImageObject Function({ElementFrame? frame, EpochMillis? updatedAt})
    copyImage = image.copyWith;

    const mathStyle = MathStyle(colorArgb: 0xFF1A1A1A, fontSizePt: 18);
    expect([MathStyle.minFontSize, MathStyle.maxFontSize], [6, 144]);
    final MathStyle Function() normalizeMath = mathStyle.normalized;
    final MathStyle Function({int? colorArgb, double? fontSizePt})
    copyMathStyle = mathStyle.copyWith;
    final Map<String, Object?> Function() mathStyleJson = mathStyle.toJson;
    final MathStyle Function(Map<String, Object?>) mathStyleFrom =
        MathStyle.fromJson;
    final math = MathObject(
      id: 'm',
      pageId: 'p',
      frame: const ElementFrame(PageRect(0, 0, 40, 30)),
      latex: r'\frac{a}{b}',
      style: mathStyle,
      engineId: 'manual',
      createdAt: 1,
      updatedAt: null,
      deletedAt: null,
      version: null,
    );
    final List<Object?> mathFields = [
      math.frame,
      math.latex,
      math.style,
      math.engineId,
    ];
    final MathObject Function({
      ElementFrame? frame,
      String? latex,
      MathStyle? style,
      String? engineId,
      EpochMillis? updatedAt,
    })
    copyMath = math.copyWith;

    final UnknownObject Function(Map<String, Object?>) unknown =
        UnknownObject.new;
    String unknownMembers(UnknownObject u) =>
        '${u.type}${u.rawJson}${u.frame}${u.bounds}${u.referencedAssets}';

    final objects = <PageObject>[shape, text, image, math];
    for (final o in objects) {
      final PageElement element = o;
      final List<Object?> common = [
        o.kind,
        o.type,
        o.id,
        o.pageId,
        o.createdAt,
        o.updatedAt,
        o.deletedAt,
        o.version,
        o.isDeleted,
        o.referencedAssets,
        element.createdAt,
      ];
      final PageObject Function(Affine2, {bool scaleWidth}) transformed =
          o.transformed;
      final PageObject Function({
        required ElementId id,
        required PageId pageId,
        required EpochMillis createdAt,
      })
      copyTo = o.copyTo;
      final PageObject Function({
        EpochMillis? updatedAt,
        EpochMillis? deletedAt,
        bool clearDeletedAt,
        Hlc? version,
      })
      copyWithMeta = o.copyWithMeta;
      int estimate() => o.estimatedBytes;
      ElementFrame frame() => o.frame;
      final Map<String, Object?> Function() json = o.toJson;
      expect(o.kind, EntityKind.pageObject);
      expect([
        common,
        transformed,
        copyTo,
        copyWithMeta,
        estimate,
        frame,
        json,
      ], hasLength(7));
    }
    expect(objects.map((o) => o.type), ['shape', 'text', 'image', 'math']);
    final PageObject Function(Map<String, Object?>) fromJson =
        PageObject.fromJson;
    final int Function(PageElement, PageElement) order = Stroke.compareOrder;
    expect(objects.map(_exhaustiveElement), ['shape', 'text', 'image', 'math']);
    expect(_exhaustiveObject(shape, ellipse), 'ke');
    expect([
      shapeStyleFields,
      arrowHeadLength,
      normalizeShape,
      copyShapeStyle,
      shapeStyleJson,
      shapeStyleFrom,
      points,
      closed,
      ellipseFrame,
      moveGeometry,
      geometryFrame,
      geometryJson,
      geometryFrom,
      line,
      rectangle,
      ellipseOf,
      triangle,
      polygon,
      star,
      shapeKind,
      shapeGeometry,
      shapeStyleOf,
      copyShape,
      textStyleFields,
      normalizeText,
      copyTextStyle,
      textStyleJson,
      textStyleFrom,
      textFields,
      copyText,
      imageFields,
      copyImage,
      normalizeMath,
      copyMathStyle,
      mathStyleJson,
      mathStyleFrom,
      mathFields,
      copyMath,
      unknown,
      unknownMembers,
      fromJson,
      order,
    ], hasLength(42));
  });

  test('v2 7.2.3 page content, drafts, commands', () {
    const page = Page(
      id: 'p',
      noteId: 'n',
      sortKey: 'a0',
      size: PageSize.a4Portrait,
      background: BlankBackground(),
      createdAt: 0,
      updatedAt: 0,
    );
    final content = PageContent(
      page: page,
      strokes: const [],
      objects: const [],
      revision: 0,
    );
    final List<PageObject> objects = content.objects;
    final PageObject? Function(ElementId) objectById = content.objectById;
    final PageElement? Function(ElementId) elementById = content.elementById;
    final int objectCount = content.objectCount;
    expect(
      [objects, objectById('x'), elementById('x'), objectCount],
      [isEmpty, null, null, 0],
    );
    const draft = PageDraft(
      id: 'p2',
      size: PageSize.letterPortrait,
      background: BlankBackground(),
      strokes: [],
      objects: [],
    );
    final List<PageObject> draftObjects = draft.objects;
    final PageDraft Function(PageContent) copyOf = PageDraft.copyOf;
    expect([draftObjects, copyOf], hasLength(2));
    const add = AddObjects(pageId: 'p', objects: []);
    const update = UpdateObjects(pageId: 'p', objects: []);
    const remove = RemoveElements(pageId: 'p', elementIds: ['e']);
    const clear = ClearPage(
      pageId: 'p',
      filter: StrokeFilter.all,
      includeObjects: true,
    );
    final PageId addPage = add.pageId;
    final List<PageObject> addObjects = add.objects;
    final PageId updatePage = update.pageId;
    final List<PageObject> updateObjects = update.objects;
    final PageId removePage = remove.pageId;
    final List<ElementId> removeIds = remove.elementIds;
    final bool includeObjects = clear.includeObjects;
    expect(const ClearPage(pageId: 'p').includeObjects, isFalse);
    expect([add, update, remove].map(_exhaustiveCommand), [
      'add-objects',
      'update-objects',
      'remove-elements',
    ]);
    expect([
      addPage,
      addObjects,
      updatePage,
      updateObjects,
      removePage,
      removeIds,
      includeObjects,
    ], hasLength(7));
  });

  test('v2 7.2.4 recordings and audio ports', () {
    const recording = Recording(
      id: 'r',
      noteId: 'n',
      assetId: 'a',
      durationMs: 1,
      startedAt: 0,
      createdAt: 0,
      updatedAt: 0,
      deletedAt: null,
      version: null,
      title: '녹음',
    );
    final String? title = recording.title;
    final Recording Function({
      int? durationMs,
      EpochMillis? updatedAt,
      EpochMillis? deletedAt,
      bool clearDeletedAt,
      Hlc? version,
      String? title,
      bool clearTitle,
    })
    copy = recording.copyWith;
    expect(title, '녹음');
    const draft = RecordingDraft(
      draftId: 'd',
      recordingId: 'r',
      noteId: 'n',
      mimeType: 'audio/mp4',
      startedAt: 0,
      chunkCount: 0,
      bytes: 0,
      activeMs: 0,
      updatedAt: 0,
    );
    final List<Object> draftFields = [
      draft.draftId,
      draft.recordingId,
      draft.noteId,
      draft.mimeType,
      draft.startedAt,
      draft.chunkCount,
      draft.bytes,
      draft.activeMs,
      draft.updatedAt,
    ];
    expect(AudioSupport.values.map((v) => v.name), [
      'supported',
      'unsupported',
      'permissionDenied',
      'permissionPermanentlyDenied',
    ]);
    expect(RecorderPhase.values.map((v) => v.name), [
      'idle',
      'starting',
      'recording',
      'paused',
      'finishing',
    ]);
    expect(PlaybackPhase.values.map((v) => v.name), [
      'idle',
      'loading',
      'ready',
      'playing',
      'paused',
      'completed',
      'failed',
    ]);
    const recorder = RecorderStatus(
      phase: RecorderPhase.idle,
      recordingId: null,
      noteId: null,
      activeMs: 0,
      backgroundCapable: false,
      interrupted: false,
      mimeType: null,
      crossPlatformPlayable: true,
      error: null,
    );
    final List<Object?> recorderFields = [
      recorder.phase,
      recorder.recordingId,
      recorder.noteId,
      recorder.activeMs,
      recorder.backgroundCapable,
      recorder.interrupted,
      recorder.mimeType,
      recorder.crossPlatformPlayable,
      recorder.error,
    ];
    bool isActive() => recorder.isActive;
    final RecorderStatus Function({
      RecorderPhase? phase,
      RecordingId? recordingId,
      NoteId? noteId,
      int? activeMs,
      bool? backgroundCapable,
      bool? interrupted,
      String? mimeType,
      bool? crossPlatformPlayable,
      Object? error,
      bool clearRecording,
      bool clearError,
    })
    copyRecorder = recorder.copyWith;
    const playback = PlaybackStatus(
      phase: PlaybackPhase.idle,
      recordingId: null,
      durationMs: 0,
      speed: 1.0,
      unsupportedFormat: false,
      error: null,
    );
    final List<Object?> playbackFields = [
      playback.phase,
      playback.recordingId,
      playback.durationMs,
      playback.speed,
      playback.unsupportedFormat,
      playback.error,
    ];
    final PlaybackStatus Function({
      PlaybackPhase? phase,
      RecordingId? recordingId,
      int? durationMs,
      double? speed,
      bool? unsupportedFormat,
      Object? error,
      bool clearRecording,
      bool clearError,
    })
    copyPlayback = playback.copyWith;
    const AudioRecorderService unsupportedRecorder = UnsupportedAudioRecorder();
    const AudioPlaybackService unsupportedPlayback = UnsupportedAudioPlayback();
    final services = <Object>[
      _Recordings(),
      _Drafts(),
      _Recorder(),
      _Player(),
      unsupportedRecorder,
      unsupportedPlayback,
    ];
    expect([
      copy,
      draftFields,
      recorderFields,
      isActive,
      copyRecorder,
      playbackFields,
      copyPlayback,
      services,
    ], hasLength(8));
  });

  test('v2 7.2.5 handwriting results and search', () {
    const line = HandwritingLine(
      text: '안녕',
      alternatives: ['안냥'],
      rect: PageRect(0, 0, 10, 10),
      strokeIds: ['s'],
      languageTag: 'ko',
      userConfirmed: false,
    );
    final List<Object> lineFields = [
      line.text,
      line.alternatives,
      line.rect,
      line.strokeIds,
      line.languageTag,
      line.userConfirmed,
    ];
    final Map<String, Object?> Function() lineJson = line.toJson;
    final HandwritingLine Function(Map<String, Object?>) lineFrom =
        HandwritingLine.fromJson;
    final HandwritingLine Function({
      String? text,
      List<String>? alternatives,
      PageRect? rect,
      List<ElementId>? strokeIds,
      String? languageTag,
      bool? userConfirmed,
    })
    copyLine = line.copyWith;
    final result = HandwritingText(
      noteId: 'n',
      pageId: 'p',
      engineId: 'fake',
      sourceRev: '0000000000000000',
      lines: const [line],
      createdAt: 1,
      updatedAt: null,
      deletedAt: null,
      version: null,
    );
    final String Function(PageId) idFor = HandwritingText.idFor;
    final String Function(Iterable<Stroke>) sourceRevOf =
        HandwritingText.sourceRevOf;
    final bool Function(Stroke) isInput = HandwritingText.isRecognitionInput;
    final List<Object?> resultFields = [
      result.id,
      result.noteId,
      result.pageId,
      result.engineId,
      result.sourceRev,
      result.lines,
      result.createdAt,
      result.updatedAt,
      result.deletedAt,
      result.version,
      result.isDeleted,
      result.kind,
    ];
    final Map<String, Object?> Function() resultJson = result.toJson;
    final HandwritingText Function(Map<String, Object?>) resultFrom =
        HandwritingText.fromJson;
    final HandwritingText Function({
      String? engineId,
      String? sourceRev,
      List<HandwritingLine>? lines,
      EpochMillis? updatedAt,
      EpochMillis? deletedAt,
      bool clearDeletedAt,
      Hlc? version,
    })
    copyResult = result.copyWith;
    expect(result.kind, EntityKind.handwriting);

    expect(SearchSource.values.map((v) => v.name), [
      'ink',
      'pdf',
      'text',
      'math',
    ]);
    const unit = SearchUnitDraft(body: '안녕', rects: [], pdfPageAspect: null);
    final List<Object?> unitFields = [
      unit.body,
      unit.rects,
      unit.pdfPageAspect,
    ];
    const hit = PageSearchHit(
      noteId: 'n',
      pageId: 'p',
      source: SearchSource.ink,
      snippet: '안녕',
      matchRange: (0, 2),
      rects: [],
      score: 1,
    );
    final (int, int) range = hit.matchRange;
    final List<Object> hitFields = [
      hit.noteId,
      hit.pageId,
      hit.source,
      hit.snippet,
      hit.rects,
      hit.score,
    ];
    const status = SearchIndexStatus(
      pendingOwners: 0,
      rebuilding: false,
      lastRebuildAt: null,
    );
    final List<Object?> statusFields = [
      status.pendingOwners,
      status.rebuilding,
      status.lastRebuildAt,
    ];
    const int normalizerVersion = SearchText.normalizerVersion;
    expect(normalizerVersion, 1);
    final String Function(String) normalize = SearchText.normalize;
    final String Function(String) indexTerms = SearchText.indexTerms;
    final String? Function(String) matchQuery = SearchText.matchQuery;
    final SearchTextMapping Function(String) mapped =
        SearchText.normalizeMapped;
    final mapping = SearchTextMapping(
      text: 'a',
      sourceStart: Int32List.fromList([0]),
      sourceEnd: Int32List.fromList([1]),
    );
    final List<Object> mappingFields = [
      mapping.text,
      mapping.sourceStart,
      mapping.sourceEnd,
    ];
    const library = LibrarySearchResult(
      query: 'q',
      folders: [],
      notes: [],
      pages: [hit],
      pagesTruncated: false,
    );
    final List<PageSearchHit> pages = library.pages;
    final bool truncated = library.pagesTruncated;
    final writers = <SearchIndexWriter>[_Writer(), _Search()];
    final services = <Object>[_Handwriting(), ...writers];
    expect([
      lineFields,
      lineJson,
      lineFrom,
      copyLine,
      idFor,
      sourceRevOf,
      isInput,
      resultFields,
      resultJson,
      resultFrom,
      copyResult,
      unitFields,
      range,
      hitFields,
      statusFields,
      normalize,
      indexTerms,
      matchQuery,
      mapped,
      mappingFields,
      pages,
      truncated,
      services,
    ], hasLength(23));
  });

  test('v2 7.2.6 image import, assets, store bundle', () {
    expect(ImageImportSource.values.map((v) => v.name), [
      'photos',
      'camera',
      'files',
      'clipboard',
    ]);
    const asset = Asset(
      id: 'a',
      ownerId: kLocalOwnerId,
      type: AssetType.image,
      mimeType: 'image/png',
      size: 1,
      createdAt: 0,
    );
    const imported = ImportedImage(asset: asset, pixelWidth: 1, pixelHeight: 1);
    final List<Object> importedFields = [
      imported.asset,
      imported.pixelWidth,
      imported.pixelHeight,
    ];
    expect(
      [ImageImportLimits.maxLongSidePx, ImageImportLimits.maxBytes],
      [2048, 8 * 1024 * 1024],
    );
    const Set<String> stored = ImageImportLimits.storedMimeTypes;
    expect(stored, {'image/jpeg', 'image/png'});
    const usage = AssetStorageUsage(
      assetCount: 0,
      totalBytes: 0,
      thumbnailBytes: 0,
      bytesByType: {AssetType.audio: 0},
    );
    final Map<AssetType, int> byType = usage.bytesByType;
    expect(
      const AssetStorageUsage(
        assetCount: 0,
        totalBytes: 0,
        thumbnailBytes: 0,
      ).bytesByType,
      isEmpty,
    );
    const config = NoteStoreConfig(nativeAssetDirectoryPath: '/tmp/blobs');
    final String? blobRoot = config.nativeAssetDirectoryPath;
    final NoteStore store = _Store();
    RecordingRepository recordings() => store.recordings;
    RecordingDraftStore drafts() => store.recordingDrafts;
    HandwritingRepository handwriting() => store.handwriting;
    SearchIndex search() => store.search;
    expect([
      importedFields,
      byType,
      blobRoot,
      recordings,
      drafts,
      handwriting,
      search,
    ], hasLength(7));
  });

  test('v2 7.2.7 schema versions (DB v2 is CORE T24)', () {
    expect([kNoteSchemaVersion, kDatabaseSchemaVersion], [1, 1]);
  });

  test('v2 providers (7.2.4, 7.2.5)', () {
    final providers = <String, ProviderOrFamily>{
      'audioRecorderServiceProvider': audioRecorderServiceProvider,
      'audioPlaybackServiceProvider': audioPlaybackServiceProvider,
      'recordingRepositoryProvider': recordingRepositoryProvider,
      'noteRecordingsProvider': noteRecordingsProvider,
      'handwritingRepositoryProvider': handwritingRepositoryProvider,
      'searchIndexProvider': searchIndexProvider,
    };
    for (final e in providers.entries) {
      expect(
        e.value.name,
        e.key,
        reason: 'name: argument == variable name (7.4.4)',
      );
    }
    final Provider<AudioRecorderService> recorder =
        audioRecorderServiceProvider;
    final Provider<AudioPlaybackService> playback =
        audioPlaybackServiceProvider;
    final Provider<RecordingRepository> recordings =
        recordingRepositoryProvider;
    final ProviderListenable<AsyncValue<List<Recording>>> Function(NoteId)
    noteRecordings = noteRecordingsProvider.call;
    final Provider<HandwritingRepository> handwriting =
        handwritingRepositoryProvider;
    final Provider<SearchIndex> search = searchIndexProvider;
    expect([
      recorder,
      playback,
      recordings,
      noteRecordings,
      handwriting,
      search,
    ], hasLength(6));
  });

  test('v2 testing.dart / dev_tools.dart', () async {
    final ShapeObject Function({
      required String pageId,
      ShapeKind kind,
      PageRect rect,
      int createdAt,
      String? id,
    })
    shape = testing.PageObjectFixtures.shape;
    final TextBoxObject Function({
      required String pageId,
      String text,
      PageRect rect,
      int createdAt,
      String? id,
    })
    textBox = testing.PageObjectFixtures.textBox;
    final ImageObject Function({
      required String pageId,
      required AssetId assetId,
      PageRect rect,
      int pixelWidth,
      int pixelHeight,
      int createdAt,
      String? id,
    })
    image = testing.PageObjectFixtures.image;
    final MathObject Function({
      required String pageId,
      String latex,
      PageRect rect,
      int createdAt,
      String? id,
    })
    math = testing.PageObjectFixtures.math;
    final UnknownObject Function({
      required String pageId,
      String type,
      PageRect rect,
      String? id,
    })
    unknown = testing.PageObjectFixtures.unknown;
    final store = testing.createFakeNoteStore();
    addTearDown(store.close);
    final testing.FakeAudioRecorder Function({
      required NoteStore store,
      AudioSupport support,
    })
    makeRecorder = testing.FakeAudioRecorder.new;
    final recorder = makeRecorder(
      store: store,
      support: AudioSupport.supported,
    );
    final AudioRecorderService asPort = recorder;
    final void Function(Duration) advance = recorder.advance;
    final void Function() interrupt = recorder.interrupt;
    recorder.stopDurationErrorMs = 5;
    final int durationError = recorder.stopDurationErrorMs;
    final Future<void> Function() abandon = recorder.abandon;
    final testing.FakeAudioPlayback Function() makePlayback =
        testing.FakeAudioPlayback.new;
    final playback = makePlayback();
    final AudioPlaybackService asPlayer = playback;
    final void Function(int) setPosition = playback.setPositionMs;
    List<String> calls() => playback.calls;

    const info = dev.V1DatabaseCopyInfo(
      createdAt: 0,
      bytes: 0,
      normalOpens: 0,
      fileName: 'noteapp-v1-backup.sqlite',
      failure: null,
    );
    final List<Object?> infoFields = [
      info.createdAt,
      info.bytes,
      info.normalOpens,
      info.fileName,
      info.failure,
    ];
    final Future<dev.V1DatabaseCopyInfo?> Function(NoteStore) copyInfo =
        dev.v1DatabaseCopyInfo;
    final Stream<Uint8List> Function(NoteStore) readCopy =
        dev.readV1DatabaseCopy;
    final Future<void> Function(NoteStore) deleteCopy =
        dev.deleteV1DatabaseCopy;
    expect([
      shape,
      textBox,
      image,
      math,
      unknown,
      asPort,
      advance,
      interrupt,
      durationError,
      abandon,
      asPlayer,
      setPosition,
      calls,
      infoFields,
      copyInfo,
      readCopy,
      deleteCopy,
    ], hasLength(17));
  });

  test('v2 names that stay out of the barrel', () {
    // Test / developer helpers and internals (4.11: normalizeForSearch, DriftSearchIndex,
    // MemorySearchIndex, SearchIndexer, FileBlobDatabase, upgradeV1ToV2, searchMatches,
    // ftsCandidateMatches, canonicalDump, SearchRectsCodec).
    expect([
      openWebTestNoteStore,
      deleteWebTestNoteStore,
      v1DatabaseCopyInfo,
      readV1DatabaseCopy,
      deleteV1DatabaseCopy,
      upgradeV1ToV2,
      searchMatches,
      ftsCandidateMatches,
      canonicalDump,
      notYet,
      kCalligraphyNibAngleKey,
    ], everyElement(const Absent()));
    expect([
      PageObjectFixtures,
      FakeAudioRecorder,
      FakeAudioPlayback,
      V1DatabaseCopyInfo,
      DriftSearchIndex,
      MemorySearchIndex,
      SearchIndexer,
      FileBlobDatabase,
      SearchRectsCodec,
      EmptyRecordingRepository,
      EmptyRecordingDraftStore,
      EmptyHandwritingRepository,
      EmptySearchIndex,
    ], hasLength(13));
  });
}
