// Public surface of package:feature_editor (contract 00-overview 7.2.17,
// 04-editor 4.1, 8.1 B5, 9.1 'api_surface_test'; 2nd round: contract
// m5-7/00-overview 7.2.10, m5-7/04-editor 4.1 and 8.1 R2-B5 — 14 new names).
//
// 1. Every exported name is used in the call shapes of the contract block, so
//    a renamed / re-typed / missing name breaks the build.
// 2. The barrel's `show` lists are read from the source and must be exactly
//    the 4.1 list: a name exported beyond it fails here, before INFRA's R14
//    (integration step).
@TestOn('vm')
library;

import 'dart:io';

import 'package:feature_editor/feature_editor.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

/// 04-editor 4.1 — every name `package:feature_editor/feature_editor.dart`
/// exports.
const _expectedExports = <String>{
  'EditorScreen',
  'featureEditorOverrides',
  'EditorExtensions',
  'EditorMenuItem',
  'EditorMenuContext',
  'editorExtensionsProvider',
  'DevOverlaySection',
  'devOverlaySectionsProvider',
  'StylusExtrasSource',
  'StylusExtraEvent',
  'StylusDoubleTap',
  'StylusSqueeze',
  'StylusBarrelRoll',
  'NoStylusExtras',
  'stylusExtrasProvider',
  'EditorSettings',
  'InputMode',
  'PageFlipMode',
  'PalmRejectionSettings',
  'GestureSettings',
  'EditorSettingsNotifier',
  'editorSettingsProvider',
  'EditorInputSettingsSection',
  'EditorPenSettingsSection',
  'EditorPageSettingsSection',
  'EditorDeveloperSettingsSection',
  // (v2.0) m5-7/04-editor 4.1 — 14 new names.
  'EditorSelectionContext',
  'EditorSelectionMenuItem',
  'EditorInsertContext',
  'EditorInsertMenuItem',
  'EditorPanelBuilder',
  'EditorPanelContext',
  'EditorImageImporter',
  'editorImageImporterProvider',
  'StylusHoverPose',
  'StylusPreferredAction',
  'StylusSqueezePhase',
  'StylusCapabilities',
  'EditorGesture',
  'EditorAction',
};

/// The 1st-round names (04-editor 4.1, v1.4): the v2 list keeps all of them.
const _v14ExportCount = 26;

/// The export directives of [source]: the URI and its `show` names (null
/// when the directive has no `show` combinator).
List<({String uri, List<String>? show, bool hides})> _exportsOf(String source) {
  final withoutComments = source
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp('//[^\n]*'), '');
  final directive = RegExp(r'''export\s+'([^']+)'([^;]*);''');
  return [
    for (final m in directive.allMatches(withoutComments))
      (
        uri: m.group(1)!,
        show: _combinator(m.group(2)!, 'show'),
        hides: RegExp(r'\bhide\b').hasMatch(m.group(2)!),
      ),
  ];
}

List<String>? _combinator(String tail, String keyword) {
  final m = RegExp('\\b$keyword\\b([^;]*)').firstMatch(tail);
  if (m == null) return null;
  final names = m.group(1)!.split(RegExp(r'\b(?:show|hide)\b')).first;
  return [
    for (final name in names.split(','))
      if (name.trim().isNotEmpty) name.trim(),
  ];
}

/// pdf_io's menu action shape that INFRA converts to an EditorMenuItem
/// (contract 7.3.3, 06-pdf 5.5).
Future<void> _pdfExport(BuildContext context, EditorMenuContext menu) async {}

bool _enabledWithPages(EditorMenuContext menu) => menu.pageIds.isNotEmpty;

String _describe(StylusExtraEvent event) => switch (event) {
  // Exhaustive over the sealed family: a new or missing subtype breaks this.
  StylusDoubleTap() => 'double tap',
  StylusSqueeze(:final hoverPosition) => 'squeeze at $hoverPosition',
  StylusBarrelRoll(:final angle) => 'barrel roll $angle',
  StylusHoverPose(:final position) => 'hover at $position',
};

/// recog's selection item shape (05-library 6.x — toText and friends).
Future<void> _toText(
  BuildContext context,
  EditorSelectionContext selection,
) async {}

bool _hasStrokes(EditorSelectionContext selection) =>
    selection.strokes.isNotEmpty;

/// recog's insert item shape (mathPad).
Future<void> _mathPad(BuildContext context, EditorInsertContext insert) async {}

/// media_io's RecordingPanel builder shape.
Widget _recordingPanel(BuildContext context, EditorPanelContext panel) =>
    const SizedBox();

/// media_io's picker shape.
Future<core.ImportedImage?> _pick(
  BuildContext context,
  core.ImageImportSource source,
) async => null;

/// INFRA's PencilStylusExtrasSource shape (pencil_bridge, B8b): implements
/// the three members.
final class _PencilLike implements StylusExtrasSource {
  @override
  bool get isSupported => true;
  @override
  StylusCapabilities get capabilities =>
      const StylusCapabilities(doubleTap: true, hoverPose: true);
  @override
  Stream<StylusExtraEvent> get events => const Stream.empty();
}

void main() {
  group('barrel', () {
    test('exports exactly the 04-editor 4.1 names, all through show', () {
      final source = File('lib/feature_editor.dart').readAsStringSync();
      final exports = _exportsOf(source);
      expect(exports, isNotEmpty);
      final names = <String>[];
      for (final e in exports) {
        expect(e.show, isNotNull, reason: '${e.uri} must use `show`');
        expect(e.hides, isFalse, reason: '${e.uri} must not use `hide`');
        expect(e.uri, startsWith('src/'));
        names.addAll(e.show!);
      }
      expect(names.toSet(), hasLength(names.length), reason: 'duplicates');
      expect(names.toSet(), _expectedExports);
      expect(_expectedExports, hasLength(_v14ExportCount + 14));
      // m5-7/04-editor 4.1 (수정 1회차): both stay internal / out.
      expect(names, isNot(contains('PlaybackHighlightStyle')));
      expect(names, isNot(contains('WebTextInputMode')));
    });

    test('lib/ has a single entry point, feature_editor.dart (7.1)', () {
      final topLevel = [
        for (final entity in Directory('lib').listSync())
          if (entity is File && entity.path.endsWith('.dart'))
            entity.uri.pathSegments.last,
      ];
      expect(topLevel, ['feature_editor.dart']);
    });

    test('the export reader sees show lists and hide', () {
      final exports = _exportsOf('''
// export 'src/commented.dart';
export 'src/a.dart' show A, b;
export 'src/b.dart'
    show
        C,
        D;
export 'src/c.dart';
export 'src/d.dart' hide E;
''');
      expect(exports.map((e) => e.uri), [
        'src/a.dart',
        'src/b.dart',
        'src/c.dart',
        'src/d.dart',
      ]);
      expect(exports[0].show, ['A', 'b']);
      expect(exports[1].show, ['C', 'D']);
      expect(exports[2].show, isNull);
      expect(exports[3].show, isNull);
      expect(exports[3].hides, isTrue);
    });
  });

  group('EditorScreen', () {
    test('has the contract constructor and fields', () {
      final closes = <String>[];
      final minimal = EditorScreen(
        noteId: 'note-1',
        onClose: () => closes.add('close'),
      );
      final full = EditorScreen(
        key: const ValueKey('note-2'),
        noteId: 'note-2',
        initialPageId: 'page-1',
        onClose: () => closes.add('close-2'),
        onOpenSettings: () => closes.add('settings'),
      );

      expect(minimal, isA<ConsumerStatefulWidget>());
      final String noteId = full.noteId;
      final String? initialPageId = full.initialPageId;
      final VoidCallback onClose = full.onClose;
      final VoidCallback? onOpenSettings = full.onOpenSettings;
      expect(noteId, 'note-2');
      expect(initialPageId, 'page-1');
      expect(full.key, const ValueKey('note-2'));
      expect(minimal.initialPageId, isNull);
      expect(minimal.onOpenSettings, isNull);
      onClose();
      onOpenSettings!();
      expect(closes, ['close-2', 'settings']);
    });

    test('(v2.0) initialFocusRectPt: Rect?, default null', () {
      final screen = EditorScreen(
        noteId: 'note-3',
        initialPageId: 'page-7',
        initialFocusRectPt: const Rect.fromLTWH(10, 20, 30, 40),
        onClose: () {},
      );
      final Rect? focus = screen.initialFocusRectPt;
      expect(focus, const Rect.fromLTWH(10, 20, 30, 40));
      expect(
        EditorScreen(noteId: 'n', onClose: () {}).initialFocusRectPt,
        isNull,
      );
    });

    test('featureEditorOverrides() is an empty list', () {
      final List<Override> overrides = featureEditorOverrides();
      expect(overrides, isEmpty);
    });
  });

  group('extension points', () {
    test('EditorMenuContext / EditorMenuItem / EditorExtensions shapes', () {
      final navigations = <(String, Rect?)>[];
      final menu = EditorMenuContext(
        noteId: 'n',
        pageIds: const ['p1', 'p2'],
        currentPageIndex: 1,
        navigateToPage: (pageId, focusRectPt) =>
            navigations.add((pageId, focusRectPt)),
      );
      final String noteId = menu.noteId;
      final List<String> pageIds = menu.pageIds;
      final int currentPageIndex = menu.currentPageIndex;
      final List<String> selected = menu.selectedPageIds;
      final String? currentPageId = menu.currentPageId;
      final void Function(String, Rect?) navigate = menu.navigateToPage;
      expect(noteId, 'n');
      expect(pageIds, ['p1', 'p2']);
      expect(currentPageIndex, 1);
      expect(selected, isEmpty);
      expect(currentPageId, 'p2');
      navigate('p1', const Rect.fromLTWH(1, 2, 3, 4));
      expect(navigations, [('p1', const Rect.fromLTWH(1, 2, 3, 4))]);

      const item = EditorMenuItem(
        id: 'pdf.export',
        label: 'PDF로 내보내기',
        icon: Icons.picture_as_pdf,
        onSelected: _pdfExport,
        isEnabled: _enabledWithPages,
      );
      final String id = item.id;
      final String label = item.label;
      final IconData icon = item.icon;
      final Future<void> Function(BuildContext, EditorMenuContext) onSelected =
          item.onSelected;
      final bool Function(EditorMenuContext)? isEnabled = item.isEnabled;
      expect(id, 'pdf.export');
      expect(label, isNotEmpty);
      expect(icon, Icons.picture_as_pdf);
      expect(onSelected, _pdfExport);
      expect(isEnabled!(menu), isTrue);

      const extensions = EditorExtensions(
        moreMenuItems: [item],
        addPageSources: [item],
      );
      final List<EditorMenuItem> more = extensions.moreMenuItems;
      final List<EditorMenuItem> addPage = extensions.addPageSources;
      final WidgetBuilder? trailing = extensions.appBarTrailing;
      expect(more, [item]);
      expect(addPage, [item]);
      expect(trailing, isNull);
    });

    test('editorExtensionsProvider defaults to empty extensions', () {
      final container = ProviderContainer.test();
      final EditorExtensions extensions = container.read(
        editorExtensionsProvider,
      );
      expect(extensions, const EditorExtensions());
      expect(extensions.moreMenuItems, isEmpty);
      expect(extensions.addPageSources, isEmpty);
      expect(extensions.appBarTrailing, isNull);
      expect(editorExtensionsProvider.name, 'editorExtensionsProvider');
    });

    test('the app shell can override the slots (7.3.3)', () {
      const extensions = EditorExtensions(
        moreMenuItems: [
          EditorMenuItem(
            id: 'pdf.export',
            label: 'PDF',
            icon: Icons.picture_as_pdf,
            onSelected: _pdfExport,
          ),
        ],
      );
      final lines = ValueNotifier<List<String>>(const ['pages 0']);
      addTearDown(lines.dispose);
      final section = DevOverlaySection(id: 'pdf', title: 'PDF', lines: lines);
      final container = ProviderContainer.test(
        overrides: [
          editorExtensionsProvider.overrideWithValue(extensions),
          devOverlaySectionsProvider.overrideWithValue([section]),
        ],
      );
      expect(container.read(editorExtensionsProvider), extensions);
      expect(container.read(devOverlaySectionsProvider), [section]);
    });

    test('DevOverlaySection / devOverlaySectionsProvider', () {
      final lines = ValueNotifier<List<String>>(const ['a', 'b']);
      addTearDown(lines.dispose);
      final section = DevOverlaySection(
        id: 'pdf.render',
        title: 'PDF',
        lines: lines,
      );
      final String id = section.id;
      final String title = section.title;
      final ValueListenable<List<String>> listenable = section.lines;
      expect(id, 'pdf.render');
      expect(title, 'PDF');
      expect(listenable.value, ['a', 'b']);

      final container = ProviderContainer.test();
      final List<DevOverlaySection> sections = container.read(
        devOverlaySectionsProvider,
      );
      expect(sections, isEmpty);
      expect(devOverlaySectionsProvider.name, 'devOverlaySectionsProvider');
    });

    test('(v2.0) EditorExtensions: selection / insert items and the '
        'recording panel', () {
      const selectionItem = EditorSelectionMenuItem(
        id: 'recog.toText',
        label: '텍스트로 바꾸기',
        icon: Icons.text_fields,
        onSelected: _toText,
        isVisible: _hasStrokes,
      );
      final String sId = selectionItem.id;
      final String sLabel = selectionItem.label;
      final IconData sIcon = selectionItem.icon;
      final Future<void> Function(BuildContext, EditorSelectionContext)
      sOnSelected = selectionItem.onSelected;
      final bool Function(EditorSelectionContext)? isVisible =
          selectionItem.isVisible;
      expect([sId, sLabel], ['recog.toText', '텍스트로 바꾸기']);
      expect(sIcon, Icons.text_fields);
      expect(sOnSelected, _toText);
      expect(isVisible, same(_hasStrokes));
      expect(
        const EditorSelectionMenuItem(
          id: 'x',
          label: 'x',
          icon: Icons.abc,
          onSelected: _toText,
        ).isVisible,
        isNull,
      );

      const insertItem = EditorInsertMenuItem(
        id: 'recog.mathPad',
        label: '수식',
        icon: Icons.functions,
        onSelected: _mathPad,
      );
      final String iId = insertItem.id;
      final String iLabel = insertItem.label;
      final IconData iIcon = insertItem.icon;
      final Future<void> Function(BuildContext, EditorInsertContext)
      iOnSelected = insertItem.onSelected;
      expect([iId, iLabel], ['recog.mathPad', '수식']);
      expect(iIcon, Icons.functions);
      expect(iOnSelected, _mathPad);

      const EditorPanelBuilder builder = _recordingPanel;
      const extensions = EditorExtensions(
        selectionMenuItems: [selectionItem],
        insertMenuItems: [insertItem],
        recordingPanel: builder,
      );
      final List<EditorSelectionMenuItem> selection =
          extensions.selectionMenuItems;
      final List<EditorInsertMenuItem> insert = extensions.insertMenuItems;
      final EditorPanelBuilder? panel = extensions.recordingPanel;
      expect(selection, [selectionItem]);
      expect(insert, [insertItem]);
      expect(panel, same(builder));
      const empty = EditorExtensions();
      expect(empty.selectionMenuItems, isEmpty);
      expect(empty.insertMenuItems, isEmpty);
      expect(empty.recordingPanel, isNull);
    });

    test('(v2.0) the three context types', () {
      final commands = <core.EditCommand>[];
      final cleared = <String>[];
      final stroke = StrokeFixtures.synthetic(
        pageId: 'p1',
        ids: core.SequentialIdGenerator(),
      );
      final shape = PageObjectFixtures.shape(pageId: 'p1', id: 'o1');
      final selection = EditorSelectionContext(
        noteId: 'n',
        pageId: 'p1',
        pageSize: core.PageSize.a4Portrait,
        strokes: [stroke],
        objects: [shape],
        boundsPt: const Rect.fromLTWH(0, 0, 300, 220),
        execute: commands.add,
        clearSelection: () => cleared.add('clear'),
      );
      final String noteId = selection.noteId;
      final String pageId = selection.pageId;
      final core.PageSize pageSize = selection.pageSize;
      final List<core.Stroke> strokes = selection.strokes;
      final List<core.PageObject> objects = selection.objects;
      final Rect bounds = selection.boundsPt;
      final void Function(core.EditCommand) execute = selection.execute;
      final VoidCallback clearSelection = selection.clearSelection;
      expect([noteId, pageId], ['n', 'p1']);
      expect(pageSize, core.PageSize.a4Portrait);
      expect(strokes, [stroke]);
      expect(objects, [shape]);
      expect(bounds.width, 300);
      const command = core.RemoveElements(pageId: 'p1', elementIds: ['o1']);
      execute(command);
      clearSelection();
      expect(commands, [command]);
      expect(cleared, ['clear']);

      final selected = <String>[];
      final insert = EditorInsertContext(
        noteId: 'n',
        pageId: 'p1',
        pageSize: core.PageSize.a4Portrait,
        visibleRectPt: const Rect.fromLTWH(0, 0, 595, 400),
        execute: commands.add,
        selectObject: selected.add,
      );
      final String insertNoteId = insert.noteId;
      final String insertPageId = insert.pageId;
      final core.PageSize insertPageSize = insert.pageSize;
      final Rect visible = insert.visibleRectPt;
      final void Function(core.EditCommand) insertExecute = insert.execute;
      final void Function(String) selectObject = insert.selectObject;
      expect([insertNoteId, insertPageId], ['n', 'p1']);
      expect(insertPageSize, core.PageSize.a4Portrait);
      expect(visible.center, const Offset(297.5, 200));
      insertExecute(command);
      selectObject('o1');
      expect(commands, [command, command]);
      expect(selected, ['o1']);

      final tapToSeek = ValueNotifier<bool>(true);
      addTearDown(tapToSeek.dispose);
      final closes = <String>[];
      final panel = EditorPanelContext(
        noteId: 'n',
        tapToSeek: tapToSeek,
        setTapToSeek: (value) => tapToSeek.value = value,
        close: () => closes.add('close'),
      );
      final String panelNoteId = panel.noteId;
      final ValueListenable<bool> flag = panel.tapToSeek;
      final ValueChanged<bool> setFlag = panel.setTapToSeek;
      final VoidCallback close = panel.close;
      expect(panelNoteId, 'n');
      setFlag(false);
      expect(flag.value, isFalse);
      close();
      expect(closes, ['close']);
    });

    test('(v2.0) EditorImageImporter / editorImageImporterProvider', () {
      const importer = EditorImageImporter(
        sources: {core.ImageImportSource.photos, core.ImageImportSource.files},
        pick: _pick,
      );
      final Set<core.ImageImportSource> sources = importer.sources;
      final Future<core.ImportedImage?> Function(
        BuildContext,
        core.ImageImportSource,
      )
      pick = importer.pick;
      expect(sources, {
        core.ImageImportSource.photos,
        core.ImageImportSource.files,
      });
      expect(pick, _pick);

      final Provider<EditorImageImporter?> provider =
          editorImageImporterProvider;
      expect(provider.name, 'editorImageImporterProvider');
      final container = ProviderContainer.test();
      expect(container.read(provider), isNull, reason: 'null → hidden');
      final overridden = ProviderContainer.test(
        overrides: [editorImageImporterProvider.overrideWithValue(importer)],
      );
      expect(overridden.read(editorImageImporterProvider), importer);
    });

    test('stylus extras: sealed events and the unsupported default', () async {
      expect(_describe(const StylusDoubleTap()), 'double tap');
      expect(
        _describe(const StylusSqueeze(hoverPosition: Offset(1, 2))),
        contains('Offset(1.0, 2.0)'),
      );
      expect(const StylusSqueeze().hoverPosition, isNull);
      expect(_describe(const StylusBarrelRoll(0.5)), 'barrel roll 0.5');

      final container = ProviderContainer.test();
      final StylusExtrasSource source = container.read(stylusExtrasProvider);
      expect(source, isA<NoStylusExtras>());
      expect(source.isSupported, isFalse);
      final Stream<StylusExtraEvent> events = source.events;
      expect(await events.isEmpty, isTrue);
      expect(stylusExtrasProvider.name, 'stylusExtrasProvider');
      final StylusCapabilities capabilities = source.capabilities;
      expect(capabilities, StylusCapabilities.none);
    });

    test('(v2.0) stylus extras v2: the contract fields and defaults', () {
      const doubleTap = StylusDoubleTap(
        preferredAction: StylusPreferredAction.switchEraser,
        hoverPosition: Offset(3, 4),
        timestamp: Duration(milliseconds: 5),
      );
      final StylusPreferredAction tapAction = doubleTap.preferredAction;
      final Offset? tapHover = doubleTap.hoverPosition;
      final Duration? tapTime = doubleTap.timestamp;
      expect(tapAction, StylusPreferredAction.switchEraser);
      expect(tapHover, const Offset(3, 4));
      expect(tapTime, const Duration(milliseconds: 5));
      const plainTap = StylusDoubleTap();
      expect(plainTap.preferredAction, StylusPreferredAction.unknown);
      expect(plainTap.hoverPosition, isNull);
      expect(plainTap.timestamp, isNull);

      const squeeze = StylusSqueeze();
      final StylusSqueezePhase phase = squeeze.phase;
      final StylusPreferredAction squeezeAction = squeeze.preferredAction;
      expect(phase, StylusSqueezePhase.ended);
      expect(squeezeAction, StylusPreferredAction.unknown);
      expect(squeeze.timestamp, isNull);
      expect(
        const StylusSqueeze(
          phase: StylusSqueezePhase.began,
          timestamp: Duration(seconds: 1),
        ).timestamp,
        const Duration(seconds: 1),
      );

      const roll = StylusBarrelRoll(0.25, timestamp: Duration(seconds: 2));
      final double angle = roll.angle;
      expect(angle, 0.25);
      expect(roll.timestamp, const Duration(seconds: 2));
      expect(const StylusBarrelRoll(1).timestamp, isNull);

      const pose = StylusHoverPose(
        position: Offset(10, 20),
        height: 0.5,
        altitude: 1,
        azimuth: 2,
        roll: 3,
        timestamp: Duration(milliseconds: 9),
      );
      final Offset position = pose.position;
      final double? height = pose.height;
      final double? altitude = pose.altitude;
      final double? azimuth = pose.azimuth;
      final double? rollAngle = pose.roll;
      expect(position, const Offset(10, 20));
      expect([height, altitude, azimuth, rollAngle], [0.5, 1, 2, 3]);
      const bare = StylusHoverPose(position: Offset.zero);
      expect(
        [bare.height, bare.altitude, bare.azimuth, bare.roll],
        [null, null, null, null],
      );
      expect(_describe(pose), 'hover at Offset(10.0, 20.0)');

      expect(StylusPreferredAction.values, [
        StylusPreferredAction.ignore,
        StylusPreferredAction.switchEraser,
        StylusPreferredAction.switchPrevious,
        StylusPreferredAction.showColorPalette,
        StylusPreferredAction.showInkAttributes,
        StylusPreferredAction.showContextualPalette,
        StylusPreferredAction.runSystemShortcut,
        StylusPreferredAction.unknown,
      ]);
      expect(StylusSqueezePhase.values, [
        StylusSqueezePhase.began,
        StylusSqueezePhase.changed,
        StylusSqueezePhase.ended,
        StylusSqueezePhase.cancelled,
      ]);

      const capabilities = StylusCapabilities(
        doubleTap: true,
        squeeze: true,
        barrelRoll: true,
        hoverPose: true,
        prefersPencilOnlyDrawing: true,
      );
      final List<bool> flags = [
        capabilities.doubleTap,
        capabilities.squeeze,
        capabilities.barrelRoll,
        capabilities.hoverPose,
        capabilities.prefersPencilOnlyDrawing,
      ];
      expect(flags, everyElement(isTrue));
      const StylusCapabilities none = StylusCapabilities.none;
      expect([
        none.doubleTap,
        none.squeeze,
        none.barrelRoll,
        none.hoverPose,
        none.prefersPencilOnlyDrawing,
      ], everyElement(isFalse));

      final container = ProviderContainer.test(
        overrides: [stylusExtrasProvider.overrideWithValue(_PencilLike())],
      );
      final source = container.read(stylusExtrasProvider);
      expect(source.isSupported, isTrue);
      expect(
        source.capabilities,
        const StylusCapabilities(doubleTap: true, hoverPose: true),
      );
    });
  });

  group('settings', () {
    test('EditorSettings model types (EDITOR 4.8)', () {
      const settings = EditorSettings();
      final InputMode inputMode = settings.inputMode;
      final PalmRejectionSettings palm = settings.palmRejection;
      final GestureSettings gestures = settings.gestures;
      final PageFlipMode flip = settings.pageFlipMode;
      final ink.PressureMode pressure = settings.pressureMode;
      final bool dev = settings.showDevOverlay;
      final bool stylusSeen = settings.stylusSeen;
      final bool penOnly = settings.isPenOnlyEffective;
      expect(inputMode, InputMode.auto);
      expect(flip, PageFlipMode.verticalScroll);
      expect(pressure, ink.PressureMode.auto);
      expect([dev, stylusSeen, penOnly], [false, false, false]);
      expect(InputMode.values, [
        InputMode.auto,
        InputMode.penOnly,
        InputMode.fingerDrawing,
      ]);
      expect(PageFlipMode.values, [
        PageFlipMode.verticalScroll,
        PageFlipMode.horizontalPaged,
      ]);

      final Duration cooldown = palm.penCooldown;
      final bool hover = palm.treatHoverAsPenActivity;
      final double radius = palm.maxTouchRadius;
      expect(
        [cooldown, hover, radius],
        [const Duration(milliseconds: 400), true, 45.0],
      );
      final bool twoFinger = gestures.twoFingerTapUndo;
      final bool threeFinger = gestures.threeFingerTapRedo;
      final bool longPress = gestures.longPressMenu;
      expect([twoFinger, threeFinger, longPress], [true, true, true]);

      final Map<String, Object?> device = settings.toJson(
        core.SettingScope.device,
      );
      final Map<String, Object?> synced = settings.toJson(
        core.SettingScope.synced,
      );
      final EditorSettings back = EditorSettings.fromJson(
        device: device,
        synced: synced,
      );
      expect(back, settings);
      final PalmRejectionSettings palmBack = PalmRejectionSettings.fromJson(
        palm.toJson(),
      );
      final GestureSettings gesturesBack = GestureSettings.fromJson(
        gestures.toJson(),
      );
      expect(palmBack, palm);
      expect(gesturesBack, gestures);

      // (v2.0) m5-7/04-editor 4.3.3: three optional fields.
      final bool shapeAssist = settings.shapeAssist;
      final ink.InkPlaybackStyle highlight = settings.playbackHighlight;
      final bool tapToSeek = settings.tapToSeek;
      expect(shapeAssist, isTrue);
      expect(highlight, ink.InkPlaybackStyle.dimUnwritten);
      expect(tapToSeek, isTrue);
      expect(
        settings.copyWith(
          inputMode: InputMode.penOnly,
          palmRejection: palm.copyWith(maxTouchRadius: 60),
          gestures: gestures.copyWith(longPressMenu: false),
          pageFlipMode: PageFlipMode.horizontalPaged,
          pressureMode: ink.PressureMode.alwaysReal,
          showDevOverlay: true,
          stylusSeen: true,
          shapeAssist: false,
          playbackHighlight: ink.InkPlaybackStyle.highlightRecent,
          tapToSeek: false,
        ),
        isA<EditorSettings>(),
      );
    });

    test('(v2.0) EditorGesture / EditorAction / GestureSettings v2', () {
      expect(EditorGesture.values, [
        EditorGesture.twoFingerTap,
        EditorGesture.threeFingerTap,
        EditorGesture.fingerLongPress,
        EditorGesture.penButton,
        EditorGesture.invertedStylus,
        EditorGesture.pencilDoubleTap,
        EditorGesture.pencilSqueeze,
      ]);
      expect(EditorAction.values, [
        EditorAction.none,
        EditorAction.undo,
        EditorAction.redo,
        EditorAction.contextMenu,
        EditorAction.eraserWhileHeld,
        EditorAction.lassoWhileHeld,
        EditorAction.toggleEraser,
        EditorAction.previousTool,
        EditorAction.toolPalette,
        EditorAction.colorPalette,
        EditorAction.followSystem,
      ]);

      const gestures = GestureSettings(
        twoFingerTapUndo: true,
        threeFingerTapRedo: true,
        longPressMenu: true,
        actions: {EditorGesture.penButton: EditorAction.lassoWhileHeld},
      );
      final Map<EditorGesture, EditorAction> actions = gestures.actions;
      final EditorAction action = gestures.actionFor(EditorGesture.penButton);
      final EditorAction byDefault = GestureSettings.defaultFor(
        EditorGesture.twoFingerTap,
      );
      final Set<EditorAction> allowed = GestureSettings.allowedFor(
        EditorGesture.fingerLongPress,
      );
      final Map<String, Object?> json = gestures.toJson();
      final GestureSettings back = GestureSettings.fromJson(json);
      expect(actions, {EditorGesture.penButton: EditorAction.lassoWhileHeld});
      expect(action, EditorAction.lassoWhileHeld);
      expect(byDefault, EditorAction.undo);
      expect(allowed, {EditorAction.none, EditorAction.contextMenu});
      expect(back, gestures);
      expect(GestureSettings.defaults.actions, isEmpty);
    });

    test('editorSettingsProvider / EditorSettingsNotifier members', () {
      // From E-06 the notifier loads from core.settingsRepositoryProvider.
      final store = createFakeNoteStore();
      addTearDown(store.close);
      final container = ProviderContainer.test(
        overrides: [core.noteStoreProvider.overrideWithValue(store)],
      );
      final NotifierProvider<EditorSettingsNotifier, EditorSettings> provider =
          editorSettingsProvider;
      expect(provider.name, 'editorSettingsProvider');
      final EditorSettings settings = container.read(provider);
      expect(settings, const EditorSettings());

      final EditorSettingsNotifier notifier = container.read(provider.notifier);
      final bool isLoaded = notifier.isLoaded;
      final void Function(InputMode) setInputMode = notifier.setInputMode;
      final void Function(PalmRejectionSettings) setPalm =
          notifier.setPalmRejection;
      final void Function(GestureSettings) setGestures = notifier.setGestures;
      final void Function(PageFlipMode) setPageFlip = notifier.setPageFlipMode;
      final void Function(ink.PressureMode) setPressure =
          notifier.setPressureMode;
      final void Function(bool) setDev = notifier.setShowDevOverlay;
      final void Function() toggleDev = notifier.toggleDevOverlay;
      final void Function() markStylusSeen = notifier.markStylusSeen;
      final void Function() reset = notifier.resetToDefaults;
      final Future<void> Function() flush = notifier.flush;
      expect(isLoaded, isFalse, reason: 'the load completes after an await');
      expect([
        setInputMode,
        setPalm,
        setGestures,
        setPageFlip,
        setPressure,
        setDev,
        toggleDev,
        markStylusSeen,
        reset,
        flush,
      ], everyElement(isA<Function>()));
    });

    test('the four settings sections are const ConsumerWidgets', () {
      const sections = <ConsumerWidget>[
        EditorInputSettingsSection(),
        EditorPenSettingsSection(),
        EditorPageSettingsSection(),
        EditorDeveloperSettingsSection(key: ValueKey('dev')),
      ];
      expect(sections, hasLength(4));
      expect(sections.last.key, const ValueKey('dev'));
    });
  });
}
