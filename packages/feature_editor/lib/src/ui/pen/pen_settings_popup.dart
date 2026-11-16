// lib/src/ui/pen/pen_settings_popup.dart — 04-editor 6.9.3.
//
// E-13 opens this panel from the toolbar (the active pen tapped again).
// E-14: the colour part (#4 picker, #5 recent colours, #6 palette). E-15: pen
// types (#1), width + preview (#2), opacity (#3) and '고급' (#7). (v2,
// m5-7/04-editor 6.14.2–6.14.3 — E2-14) '고급' also holds PenExtrasControls;
// the laser has no colour rows (INK draws its trail in InkTuning.laserArgb).
//
// (v2.15-ui, UI stage 4 — m5-7/04-editor 22.2) The pen picker: '무슨 펜' on
// the left (pen cards with the drawing, the real stroke and the name,
// grouped 필기 / 질감 / 꾸미기 + 발표·공부 도구) and '어떻게 쓸지' on the right
// (big preview, 12 colours first, 스포이드, 다른 색…, recent colours, five
// real-width strokes, opacity only where it means something, '고급' folded,
// [트레이에 꽂기]). It fits a tablet in landscape without scrolling; a narrow
// screen splits it into the tabs '펜 / 색·굵기'.
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:ui_kit/ui_kit.dart';

import '../../scope/editor_scope.dart';
import '../../state/color_palette.dart';
import '../../state/preset_bar.dart';
import '../../tools/tool_controller.dart';
import '../color/basic_colors_row.dart';
import '../color/color_picker_panel.dart';
import '../color/opacity_slider.dart';
import '../color/recent_colors_row.dart';
import '../color/user_palette_grid.dart';
import '../editor_strings.dart';
import '../presets/save_preset_dialog.dart' show runPresetWrite;
import 'pen_advanced_controls.dart';
import 'pen_art_view.dart';
import 'pen_extras_controls.dart';
import 'pen_preview.dart';
import 'pen_type_selector.dart';
import 'quick_pen_popup.dart';
import 'width_slider.dart';

/// Pens whose opacity the picker offers (the others are always opaque ink).
bool penHasOpacity(core.PenTool tool) => switch (tool) {
  core.PenTool.highlighter ||
  core.PenTool.watercolor ||
  core.PenTool.neon ||
  core.PenTool.jelly ||
  core.PenTool.rainbow ||
  core.PenTool.glitter => true,
  _ => false,
};

/// The pen picker ([PenSettingsPopup]): two sides from [wideMinWidth], else
/// the tabs '펜 / 색·굵기'.
class PenSettingsPanel extends ConsumerStatefulWidget {
  const PenSettingsPanel({super.key});

  static const panelKey = ValueKey('editor.popup.penSettings');
  static const advancedKey = ValueKey('editor.popup.penSettings.advanced');

  /// [트레이에 꽂기].
  static const pinKey = ValueKey('editor.popup.penSettings.pin');
  static const otherColorKey = ValueKey('editor.popup.penSettings.otherColor');
  static const otherColorBackKey = ValueKey(
    'editor.popup.penSettings.otherColor.back',
  );
  static const eyedropperKey = ColorPickerPanel.eyedropperKey;
  static const tabPenKey = ValueKey('editor.popup.penSettings.tab.pen');
  static const tabStyleKey = ValueKey('editor.popup.penSettings.tab.style');
  static ValueKey<String> widthKey(int index) =>
      ValueKey('editor.pen.widthChoice.$index');

  /// The screen width from which the two sides show side by side.
  static const double wideMinWidth = 900;

  /// Width of the two-sided panel / of the left side.
  static const double wideWidth = 860;
  static const double leftWidth = 452;

  @override
  ConsumerState<PenSettingsPanel> createState() => _PenSettingsPanelState();
}

class _PenSettingsPanelState extends ConsumerState<PenSettingsPanel> {
  /// Narrow: 0 = 펜, 1 = 색·굵기.
  int _tab = 0;

  /// '다른 색…' is open (the wheel / HEX replace the colour rows).
  bool _otherColor = false;

  @override
  Widget build(BuildContext context) {
    final tokens = StyleTokens.of(context);
    final screen = MediaQuery.sizeOf(context);
    final wide = screen.width >= PenSettingsPanel.wideMinWidth;
    final width = wide
        ? PenSettingsPanel.wideWidth
        // (v2.15-ui review) Narrow: the content width less 32 (it was at
        // most 520 and left 200 px empty at 800 portrait).
        : math.max(280.0, math.min(760.0, screen.width - 32));
    final style = _StyleSide(
      otherColor: _otherColor,
      onOtherColor: (open) => setState(() => _otherColor = open),
    );
    final body = wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                width: PenSettingsPanel.leftWidth,
                child: _PenCards(columns: 4),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: tokens.hairline)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 20),
                    child: style,
                  ),
                ),
              ),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 0,
                    label: Text(
                      EditorStrings.pickerTabPen,
                      key: PenSettingsPanel.tabPenKey,
                    ),
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Text(
                      EditorStrings.pickerTabStyle,
                      key: PenSettingsPanel.tabStyleKey,
                    ),
                  ),
                ],
                selected: {_tab},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
              const SizedBox(height: 12),
              if (_tab == 0) const _PenCards(columns: 4) else style,
            ],
          );
    return Material(
      key: PenSettingsPanel.panelKey,
      color: tokens.popover,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusLarge + 4),
        side: tokens.popoverSide,
      ),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(boxShadow: tokens.shadows(3)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: width,
            maxWidth: width,
            maxHeight: math.max(200, screen.height - 72),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: body,
          ),
        ),
      ),
    );
  }
}

/// '무슨 펜': the pen cards by group, [columns] a row, then 발표·공부 도구.
class _PenCards extends ConsumerWidget {
  const _PenCards({required this.columns});

  final int columns;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = StyleTokens.of(context);
    final theme = Theme.of(context);
    final current = ref.watch(editorToolProvider.select((s) => s.penType));
    final styles = ref.watch(editorToolProvider.select((s) => s.penStyles));
    final controller = ref.read(editorToolProvider.notifier);
    final readOnly = ref.watch(editorReadOnlyProvider);
    Widget header(PenTypeGroup group) => Padding(
      key: PenTypeSelector.groupKeyOf(group),
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(
        EditorStrings.penGroupName(group.name),
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: tokens.textSecondary,
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final cardWidth =
            ((constraints.maxWidth - gap * (columns - 1)) / columns)
                .floorToDouble();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final MapEntry(key: group, value: tools)
                in PenTypeSelector.cardGroups.entries) ...[
              header(group),
              Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final tool in tools)
                    _PenCard(
                      key: PenTypeSelector.keyOf(tool),
                      style: styles[tool]!,
                      width: cardWidth,
                      selected: tool == current,
                      onTap: readOnly
                          ? null
                          : () => controller.selectPenType(tool),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Row(
              key: PenTypeSelector.groupKeyOf(PenTypeGroup.tools),
              children: [
                Text(
                  EditorStrings.penGroupName(PenTypeGroup.tools.name),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
                const SizedBox(width: 10),
                for (final tool in PenTypeSelector.toolPens) ...[
                  _ToolChip(
                    key: PenTypeSelector.keyOf(tool),
                    style: styles[tool]!,
                    label: tool == core.PenTool.laser
                        ? EditorStrings.laserPointer
                        : EditorStrings.penTypeName(tool),
                    selected: tool == current,
                    onTap: readOnly
                        ? null
                        : () => controller.selectPenType(tool),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ],
        );
      },
    );
  }
}

/// A 발표·공부 도구 chip: the tool's drawing (top) and its name.
class _ToolChip extends StatelessWidget {
  const _ToolChip({
    super.key,
    required this.style,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final core.StrokeStyle style;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = StyleTokens.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? tokens.accentSoft : tokens.card,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? tokens.accent : tokens.hairline,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 30,
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        maxHeight: 60,
                        child: PenArt.of(
                          style,
                          width: 12,
                          height: 60,
                          rimLight: PenTrayStyle.cardRimLightOf(tokens),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: selected
                          ? tokens.onAccentSoft
                          : tokens.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One pen card: the drawing at the left (bottom cut off), the real stroke
/// on a paper-light inset and the name; the selected one has the accent
/// border.
class _PenCard extends StatelessWidget {
  const _PenCard({
    super.key,
    required this.style,
    required this.width,
    required this.selected,
    required this.onTap,
  });

  final core.StrokeStyle style;
  final double width;
  final bool selected;
  final VoidCallback? onTap;

  static const double height = 82;

  /// (v2.15-ui review) The drawing stands 10 px in from the rounded edge.
  static const double _artLeft = 10;
  static const double _textLeft = 32;

  @override
  Widget build(BuildContext context) {
    final tokens = StyleTokens.of(context);
    final theme = Theme.of(context);
    final name = EditorStrings.penTypeName(style.tool);
    // (v2.15-ui review) A dark style: the stroke on a tinted inset (not a
    // white patch on a dark card), the drawing with a rim light.
    final inset = tokens.isDark
        ? Color.lerp(tokens.inkSwatch, tokens.card, .12)!
        : tokens.inkSwatch;
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      excludeSemantics: true,
      child: Material(
        color: tokens.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          side: BorderSide(
            color: selected ? tokens.accent : tokens.hairline,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              children: [
                Positioned(
                  left: _artLeft,
                  top: 10,
                  child: PenArt.of(
                    style,
                    width: 16,
                    height: 96,
                    rimLight: PenTrayStyle.cardRimLightOf(tokens),
                  ),
                ),
                Positioned(
                  left: _textLeft,
                  right: 6,
                  top: 7,
                  height: 44,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: inset,
                      borderRadius: BorderRadius.circular(tokens.radiusSmall),
                    ),
                    child: LayoutBuilder(
                      builder: (context, c) => InkStroke(
                        style: _cardStyle(style),
                        size: Size(c.maxWidth, c.maxHeight),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: _textLeft,
                  right: 4,
                  bottom: 7,
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? tokens.accent : tokens.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The stroke a card shows: the pen's own style at a width that reads
  /// in 70 × 44.
  static core.StrokeStyle _cardStyle(core.StrokeStyle s) => s.copyWith(
    width: switch (s.tool) {
      core.PenTool.highlighter || core.PenTool.tape => 10,
      core.PenTool.marker ||
      core.PenTool.crayon ||
      core.PenTool.chalk ||
      core.PenTool.watercolor ||
      core.PenTool.spray => 4.5,
      core.PenTool.neon ||
      core.PenTool.jelly ||
      core.PenTool.rainbow ||
      core.PenTool.glitter => 4,
      _ => 2.4,
    },
  );
}

/// '어떻게 쓸지': the current pen's look.
class _StyleSide extends ConsumerWidget {
  const _StyleSide({required this.otherColor, required this.onOtherColor});

  final bool otherColor;
  final ValueChanged<bool> onOtherColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = StyleTokens.of(context);
    final theme = Theme.of(context);
    final pen = ref.watch(editorToolProvider.select((s) => s.currentPen));
    final controller = ref.read(editorToolProvider.notifier);
    final colours = pen.tool != core.PenTool.laser;
    final label = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w700,
      color: tokens.textSecondary,
    );
    if (otherColor && colours) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TextButton.icon(
                key: PenSettingsPanel.otherColorBackKey,
                onPressed: () => onOtherColor(false),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text(EditorStrings.pickerBack),
              ),
              const SizedBox(width: 4),
              Text(EditorStrings.pickerOtherColorTitle, style: label),
            ],
          ),
          const SizedBox(height: 8),
          const ColorPickerPanel(),
          const SizedBox(height: 12),
          const UserPaletteGrid(),
        ],
      );
    }
    final widths = penWidthChoices(pen.tool);
    // The built-in colour the pen's ink reads as (the stock navy is ringed
    // on 남색 though it is not exactly #1A237E).
    final ringed = nearestBasicColorIndex(pen.colorArgb);
    final recent = ref.watch(
      editorColorPaletteProvider.select((s) => s.recent),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              EditorStrings.penTypeName(pen.tool),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
              ),
            ),
            const Spacer(),
            Text(
              '${pen.width.toStringAsFixed(1)}pt',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        PenPreview(style: pen, size: const Size(420, 84)),
        if (colours) ...[
          const SizedBox(height: 14),
          Text(EditorStrings.pickerColor, style: label),
          const SizedBox(height: 2),
          Wrap(
            children: [
              for (var i = 0; i < kBasicColors.length; i++)
                InkDot(
                  key: BasicColorsRow.swatchKey(i),
                  argb: kBasicColors[i],
                  label: EditorStrings.basicColorNames[i],
                  selected: i == ringed,
                  onTap: () => controller.setColor(kBasicColors[i]),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              OutlinedButton.icon(
                key: PenSettingsPanel.eyedropperKey,
                onPressed: () =>
                    ref.read(editorCommandsProvider).startEyedropper(),
                icon: const Icon(Icons.colorize_rounded, size: 18),
                label: const Text(EditorStrings.eyedropper),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                key: PenSettingsPanel.otherColorKey,
                onPressed: () => onOtherColor(true),
                child: const Text(EditorStrings.pickerOtherColor),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 44,
            child: Row(
              children: [
                Text(
                  EditorStrings.pickerRecent,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
                const SizedBox(width: 4),
                if (recent.isEmpty)
                  Expanded(
                    child: Text(
                      EditorStrings.noRecentColors,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.textTertiary,
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ClipRect(
                      child: Row(
                        children: [
                          for (var i = 0; i < math.min(8, recent.length); i++)
                            Transform.scale(
                              scale: 0.8,
                              child: InkDot(
                                key: RecentColorsRow.swatchKey(i),
                                argb: recent[i],
                                label: inkColorName(recent[i]),
                                selected:
                                    recent[i] & 0xFFFFFF ==
                                    pen.colorArgb & 0xFFFFFF,
                                onTap: () => controller.setColor(recent[i]),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        Text(EditorStrings.pickerWidth, style: label),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < widths.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: WidthChoice(
                  key: PenSettingsPanel.widthKey(i),
                  style: pen.copyWith(width: widths[i]),
                  selected: pen.width == widths[i],
                  onTap: () => controller.setWidth(widths[i]),
                ),
              ),
            ],
          ],
        ),
        if (colours && penHasOpacity(pen.tool)) ...const [
          SizedBox(height: 10),
          OpacitySlider(),
        ],
        const SizedBox(height: 10),
        Material(
          color: tokens.rail,
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          clipBehavior: Clip.antiAlias,
          child: Theme(
            // No divider lines around the expansion tile inside the panel.
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: const ExpansionTile(
              key: PenSettingsPanel.advancedKey,
              tilePadding: EdgeInsets.symmetric(horizontal: 14),
              childrenPadding: EdgeInsets.fromLTRB(14, 0, 14, 8),
              dense: true,
              title: Text(EditorStrings.advanced),
              subtitle: Text(
                EditorStrings.pickerAdvancedSummary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              children: [
                WidthSlider(),
                PenAdvancedControls(),
                PenExtrasControls(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const _PinButton(),
      ],
    );
  }
}

/// [트레이에 꽂기]: the current pen as a new pinned preset (CORE
/// createPreset, named "{펜} {굵기}pt"); disabled while the tray shows it
/// already; at [kTrayMaxPens] pinned pens it says the tray is full.
/// '꽂았어요' shows once the write is done.
class _PinButton extends ConsumerWidget {
  const _PinButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = StyleTokens.of(context);
    final pen = ref.watch(editorToolProvider.select((s) => s.currentPen));
    // (v2.15-ui review) The pens the tray shows (the first kTrayMaxPens
    // pinned): a pinned preset past them is not "in the tray".
    final presets = ref.watch(editorTrayPresetsProvider).value;
    final inTray = presets?.any((p) => p.style == pen.normalized()) ?? false;
    final readOnly = ref.watch(editorReadOnlyProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          key: PenSettingsPanel.pinKey,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          onPressed: inTray || readOnly || presets == null
              ? null
              : () => _pin(context, ref, pen),
          child: Text(
            inTray ? EditorStrings.pinnedInTray : EditorStrings.pinToTray,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          EditorStrings.pinToTrayHint,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: tokens.textTertiary),
        ),
      ],
    );
  }

  void _pin(BuildContext context, WidgetRef ref, core.StrokeStyle pen) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (ref.read(editorPinnedCountProvider) >= kTrayMaxPens) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(EditorStrings.trayFull(kTrayMaxPens))),
        );
      return;
    }
    final repo = ref.read(core.penPresetRepositoryProvider);
    runPresetWrite(
      context,
      'pinning the pen to the tray',
      () => repo.createPreset(
        name: EditorStrings.presetDefaultName(pen.tool, pen.width),
        style: pen.normalized(),
      ),
      onDone: (messenger) => messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text(EditorStrings.pinnedToTray)),
        ),
    );
  }
}
