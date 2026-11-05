// lib/src/ui/pages/add_page_sheet.dart — 04-editor 6.11.4 (페이지 추가 시트,
// EDITOR-2-3 — contract 7.2.15 v1.1 C11-17, 7.2.16 v1.1 C11-19).
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../../di/editor_extensions.dart';
import '../../scope/editor_scope.dart';
import '../../state/popup.dart';
import '../editor_strings.dart';
import '../popup_host.dart';
import 'page_choices.dart';

/// [current] = the current page (core.Page); [size] = the size row's value with the
/// orientation applied (the last valid one while the custom fields are out of range).
Widget templatePreviewCell(
  WidgetRef ref,
  core.Page current,
  TemplateChoice choice,
  int color,
  core.PageSize size,
) {
  return ink.InkPageThumbnail(
    key: ValueKey((choice, color, size)), // one widget (State) per cell
    content: ink.InkPageContent.fromCore(
      // the ONLY InkPageContent constructor
      page: current.copyWith(
        size: size,
        background: backgroundFor(choice, color),
      ),
      strokes: const [],
      revision: 0,
    ),
    width: 64,
    backgroundBuilders: ref.watch(
      ink.pageBackgroundBuildersProvider,
    ), // read only
    pencilGrain: ref.watch(ink.pencilGrainProvider),
  );
}

/// The add-page sheet (width 420, centred by PopupHost):
///
/// | 위치 | 현재 페이지 앞 / 뒤 / 맨 끝 | popup.initialPlacement |
/// | 속지 | 빈 페이지 + 6 kinds, each with a [templatePreviewCell] | like the page |
/// | 색 | core.PaperColors.all | the page's paper (white when not listed) |
/// | 크기 | A4 · Letter · 16:9 · 사용자 지정 (100–3000 pt) | PageSizePreset.match |
/// | 방향 | 세로 / 가로 | the page's |
/// | 다른 소스 | EditorExtensions.addPageSources | — |
///
/// Initial values come from the anchor page (popup.anchorPageId — the panel
/// item's ⋯ menu) or else the current page; a PDF / image page gives a blank
/// page of its paper colour. [추가] closes the sheet and runs
/// EditorCommands.addPage; a '다른 소스' item closes it and runs
/// onSelected(context, commands.menuContext()) through PopupHost.runMenuItem.
class AddPageSheet extends ConsumerStatefulWidget {
  const AddPageSheet({super.key, required this.popup});

  final AddPagePopup popup;

  static const panelKey = ValueKey('editor.addPage.panel');
  static const addKey = ValueKey('editor.addPage.add');
  static const cancelKey = ValueKey('editor.addPage.cancel');
  static const widthFieldKey = ValueKey('editor.addPage.width');
  static const heightFieldKey = ValueKey('editor.addPage.height');
  static const rangeErrorKey = ValueKey('editor.addPage.rangeError');
  static const portraitKey = ValueKey('editor.addPage.portrait');
  static const landscapeKey = ValueKey('editor.addPage.landscape');

  static ValueKey<String> placementKey(AddPagePlacement p) =>
      ValueKey('editor.addPage.placement.${p.name}');
  static ValueKey<String> templateKey(TemplateChoice c) =>
      ValueKey('editor.addPage.template.${_choiceName(c)}');
  static ValueKey<String> colorKey(int argb) =>
      ValueKey('editor.addPage.color.$argb');
  static ValueKey<String> sizeKey(core.PageSizePreset? preset) =>
      ValueKey('editor.addPage.size.${preset?.name ?? 'custom'}');
  static ValueKey<String> sourceKey(String id) =>
      ValueKey('editor.addPage.source.$id');

  static String _choiceName(TemplateChoice c) => switch (c) {
    BlankChoice() => 'blank',
    KindChoice(:final kind) => kind.name,
  };

  @override
  ConsumerState<AddPageSheet> createState() => _AddPageSheetState();
}

class _AddPageSheetState extends ConsumerState<AddPageSheet> {
  late core.Page _base;
  late AddPagePlacement _placement;
  late TemplateChoice _template;
  late int _color;
  core.PageSizePreset? _preset; // null = custom
  late bool _landscape;
  final TextEditingController _width = TextEditingController();
  final TextEditingController _height = TextEditingController();
  late core.PageSize _lastValidCustom;

  @override
  void initState() {
    super.initState();
    final session = ref.read(editorSessionValueProvider);
    final pages = session.pages;
    final anchorId = widget.popup.anchorPageId;
    final index = ref
        .read(editorCurrentPageIndexProvider)
        .clamp(0, pages.length - 1);
    _base = pages.firstWhere(
      (p) => p.id == anchorId,
      orElse: () => pages[index],
    );
    _placement = widget.popup.initialPlacement;
    _template = TemplateChoice.of(_base.background);
    _color = paperColorChoiceOf(_base.background.paperColorArgb);
    _preset = core.PageSizePreset.match(_base.size);
    _landscape = _base.size.isLandscape;
    _lastValidCustom = _base.size;
    _width.text = _format(_base.size.width);
    _height.text = _format(_base.size.height);
  }

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  static String _format(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  /// The custom fields' size, or null when a side is not a number in
  /// PageSizeLimits.userMinSidePt..userMaxSidePt.
  core.PageSize? get _customSize {
    double? side(TextEditingController c) {
      final v = double.tryParse(c.text.trim());
      if (v == null ||
          v < core.PageSizeLimits.userMinSidePt ||
          v > core.PageSizeLimits.userMaxSidePt) {
        return null;
      }
      return v;
    }

    final w = side(_width), h = side(_height);
    return w == null || h == null ? null : core.PageSize(w, h);
  }

  bool get _valid => _preset != null || _customSize != null;

  /// The size row's value with the orientation applied.
  core.PageSize get _size {
    final preset = _preset;
    final base = preset != null
        ? preset.portrait
        : (_customSize ?? _lastValidCustom);
    return _landscape ? base.landscape : base.portrait;
  }

  void _customChanged() {
    final size = _customSize;
    setState(() {
      if (size != null) _lastValidCustom = size;
    });
  }

  void _add() {
    if (!_valid) return;
    final request = AddPageRequest(
      placement: _placement,
      size: _size,
      background: backgroundFor(_template, _color),
      anchorPageId: _placement == AddPagePlacement.end
          ? null
          : widget.popup.anchorPageId,
    );
    final commands = ref.read(editorCommandsProvider);
    ref.read(editorPopupProvider.notifier).close();
    unawaited(commands.addPage(request));
  }

  void _runSource(EditorMenuItem item) {
    final menu = ref.read(editorCommandsProvider).menuContext();
    final run = PopupHost.runMenuItem(context, item, menu);
    ref.read(editorPopupProvider.notifier).close();
    unawaited(run);
  }

  Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 6),
    child: Text(text, style: Theme.of(context).textTheme.labelLarge),
  );

  @override
  Widget build(BuildContext context) {
    final readOnly = ref.watch(editorReadOnlyProvider);
    final sources = ref.watch(editorExtensionsProvider).addPageSources;
    final scheme = Theme.of(context).colorScheme;
    final size = _size;
    final custom = _preset == null;
    final menu = sources.isEmpty
        ? null
        : ref.read(editorCommandsProvider).menuContext();
    return PopupPanelFrame(
      key: AddPageSheet.panelKey,
      title: EditorStrings.addPageTitle,
      width: 420,
      children: [
        _label(context, EditorStrings.placement),
        SegmentedButton<AddPagePlacement>(
          showSelectedIcon: false,
          segments: [
            for (final (p, text) in const [
              (AddPagePlacement.before, EditorStrings.placementBefore),
              (AddPagePlacement.after, EditorStrings.placementAfter),
              (AddPagePlacement.end, EditorStrings.placementEnd),
            ])
              ButtonSegment(
                value: p,
                label: Text(text, key: AddPageSheet.placementKey(p)),
              ),
          ],
          selected: {_placement},
          onSelectionChanged: (s) => setState(() => _placement = s.first),
        ),
        _label(context, EditorStrings.template),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final choice in TemplateChoice.all)
              _TemplateCell(
                key: AddPageSheet.templateKey(choice),
                label: templateLabel(choice),
                selected: choice == _template,
                onTap: () => setState(() => _template = choice),
                preview: templatePreviewCell(ref, _base, choice, _color, size),
              ),
          ],
        ),
        _label(context, EditorStrings.paperColor),
        Wrap(
          spacing: 4,
          children: [
            for (final argb in core.PaperColors.all)
              Semantics(
                label: paperColorLabel(argb),
                selected: argb == _color,
                button: true,
                child: InkResponse(
                  key: AddPageSheet.colorKey(argb),
                  onTap: () => setState(() => _color = argb),
                  radius: 22,
                  child: SizedBox.square(
                    dimension: 44,
                    child: Center(
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Color(argb),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: argb == _color
                                ? scheme.primary
                                : scheme.outlineVariant,
                            width: argb == _color ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        _label(context, EditorStrings.pageSize),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final preset in <core.PageSizePreset?>[
              ...core.PageSizePreset.values,
              null,
            ])
              ChoiceChip(
                key: AddPageSheet.sizeKey(preset),
                label: Text(pageSizeLabel(preset)),
                selected: preset == _preset,
                onSelected: (_) => setState(() => _preset = preset),
              ),
          ],
        ),
        if (custom) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: AddPageSheet.widthFieldKey,
                  controller: _width,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: EditorStrings.widthPt,
                  ),
                  onChanged: (_) => _customChanged(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: AddPageSheet.heightFieldKey,
                  controller: _height,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: EditorStrings.heightPt,
                  ),
                  onChanged: (_) => _customChanged(),
                ),
              ),
            ],
          ),
          if (_customSize == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                EditorStrings.customSizeOutOfRange,
                key: AddPageSheet.rangeErrorKey,
                style: TextStyle(color: scheme.error),
              ),
            ),
        ],
        _label(context, EditorStrings.orientation),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: false,
              icon: Icon(Icons.crop_portrait),
              label: Text(
                EditorStrings.portrait,
                key: AddPageSheet.portraitKey,
              ),
            ),
            ButtonSegment(
              value: true,
              icon: Icon(Icons.crop_landscape),
              label: Text(
                EditorStrings.landscape,
                key: AddPageSheet.landscapeKey,
              ),
            ),
          ],
          selected: {_landscape},
          onSelectionChanged: (s) => setState(() => _landscape = s.first),
        ),
        if (menu != null) ...[
          _label(context, EditorStrings.otherSources),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final item in sources)
                ActionChip(
                  key: AddPageSheet.sourceKey(item.id),
                  avatar: Icon(item.icon, size: 18),
                  label: Text(item.label),
                  onPressed: !readOnly && (item.isEnabled?.call(menu) ?? true)
                      ? () => _runSource(item)
                      : null,
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              key: AddPageSheet.cancelKey,
              onPressed: () => ref.read(editorPopupProvider.notifier).close(),
              child: const Text(EditorStrings.cancel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: AddPageSheet.addKey,
              onPressed: _valid && !readOnly ? _add : null,
              child: const Text(EditorStrings.add),
            ),
          ],
        ),
      ],
    );
  }
}

/// One template choice: the preview (width 64) over its label; the chosen
/// one has a 2 px primary border.
class _TemplateCell extends StatelessWidget {
  const _TemplateCell({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.preview,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: selected ? scheme.primary : scheme.outlineVariant,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 96),
                  child: ClipRect(child: preview),
                ),
              ),
              const SizedBox(height: 4),
              Text(label, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}
