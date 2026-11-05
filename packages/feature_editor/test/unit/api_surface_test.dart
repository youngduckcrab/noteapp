// Public surface of package:feature_editor (contract 00-overview 7.2.17,
// 04-editor 4.1, 8.1 B5, 9.1 'api_surface_test').
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
};

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
};

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
      expect(
        settings.copyWith(
          inputMode: InputMode.penOnly,
          palmRejection: palm.copyWith(maxTouchRadius: 60),
          gestures: gestures.copyWith(longPressMenu: false),
          pageFlipMode: PageFlipMode.horizontalPaged,
          pressureMode: ink.PressureMode.alwaysReal,
          showDevOverlay: true,
          stylusSeen: true,
        ),
        isA<EditorSettings>(),
      );
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
