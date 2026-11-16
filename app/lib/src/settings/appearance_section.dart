/// '화면' group of the settings screen: 홈 화면 스타일, 필기 화면 스타일 and
/// 밝기 (01-infra 14.3).
///
/// All write device settings (AppearanceKeys); NoteApp and EditorStyleScope
/// rebuild their themes from appAppearanceProvider, so a choice shows at
/// once. The settings screen itself has the home style.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart'
    show SettingKey, settingsRepositoryProvider;
import 'package:ui_kit/ui_kit.dart';

import '../app/appearance.dart';
import '../app/strings.dart';
import '../errors/app_error_log.dart';
import '../providers.dart';

/// Which style setting an [AppStyleSection] edits.
enum StyleTarget {
  /// 홈 화면 스타일: the app theme (library, settings, their dialogs).
  home,

  /// 필기 화면 스타일: the note-editor route (EditorStyleScope).
  editor;

  SettingKey<String> get key => switch (this) {
    StyleTarget.home => AppearanceKeys.homeStyle,
    StyleTarget.editor => AppearanceKeys.editorStyle,
  };

  AppStyle of(AppAppearance appearance) => switch (this) {
    StyleTarget.home => appearance.homeStyle,
    StyleTarget.editor => appearance.editorStyle,
  };
}

/// Widget keys of the '화면' sections (tests, V5 smoke).
abstract final class AppearanceSectionKeys {
  /// The card of [style] in the [target] block.
  static ValueKey<String> styleOf(StyleTarget target, AppStyle style) =>
      ValueKey<String>('app.appearance.${target.name}Style.${style.wireName}');
  static const ValueKey<String> brightness = ValueKey<String>(
    'app.appearance.brightness',
  );

  /// The save-failed line of the [target] block.
  static ValueKey<String> messageOf(StyleTarget target) =>
      ValueKey<String>('app.appearance.${target.name}Style.message');

  /// The brightness block's save-failed line.
  static const ValueKey<String> message = ValueKey<String>(
    'app.appearance.message',
  );

  /// The note under the [target] block's cards.
  static ValueKey<String> noteOf(StyleTarget target) =>
      ValueKey<String>('app.appearance.${target.name}Style.note');
  static const ValueKey<String> layoutNote = ValueKey<String>(
    'app.appearance.layoutNote',
  );
}

/// Writes one '화면' key; logs and reports a failure through [onFailed].
Future<void> _write<T>(
  WidgetRef ref,
  SettingKey<T> key,
  T value,
  VoidCallback onFailed,
) async {
  try {
    await ref.read(settingsRepositoryProvider).set(key, value);
  } on Object catch (error, stackTrace) {
    ref
        .read(appErrorLogProvider)
        .add(
          AppErrorRecord.fromError(
            error,
            stackTrace,
            source: AppErrorSource.manual,
          ),
        );
    onFailed();
  }
}

/// '홈 화면 스타일' / '필기 화면 스타일' ([target]): three cards (preview
/// swatch + name + one line), the chosen one marked, and a note on where
/// the style shows. The swatches follow the current brightness; the home
/// swatch is a small library, the editor swatch a toolbar over a page.
///
/// From [compactWidth] down (phones) the three cards stay in one row with
/// the swatch and the name only; the chosen style's line shows under the
/// row, so the two blocks stay short.
class AppStyleSection extends ConsumerStatefulWidget {
  const AppStyleSection({super.key, required this.target});

  final StyleTarget target;

  /// Below this the cards drop their one-line hints.
  static const double compactWidth = 480;

  @override
  ConsumerState<AppStyleSection> createState() => _AppStyleSectionState();
}

class _AppStyleSectionState extends ConsumerState<AppStyleSection> {
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    final target = widget.target;
    final current = target.of(ref.watch(appAppearanceProvider));
    final brightness = Theme.of(context).brightness;
    final theme = Theme.of(context);
    final noteStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < AppStyleSection.compactWidth;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, style) in AppStyle.values.indexed) ...[
                  if (i > 0) SizedBox(width: compact ? 8 : 12),
                  Expanded(
                    child: _StyleCard(
                      key: AppearanceSectionKeys.styleOf(target, style),
                      style: style,
                      target: target,
                      brightness: brightness,
                      selected: style == current,
                      compact: compact,
                      onTap: () {
                        setState(() => _failed = false);
                        unawaited(
                          _write(ref, target.key, style.wireName, () {
                            if (mounted) setState(() => _failed = true);
                          }),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
            if (compact)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${_styleName(current)} · ${_styleHint(current)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: StyleTokens.of(context).textPrimary,
                  ),
                ),
              ),
            // On phones the editor block's two notes run as one paragraph,
            // so the grey text between the cards and 밝기 stays short.
            if (compact && target == StyleTarget.editor)
              KeyedSubtree(
                key: AppearanceSectionKeys.layoutNote,
                child: Padding(
                  key: AppearanceSectionKeys.noteOf(target),
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${AppStrings.editorStyleNote} '
                    '${AppStrings.styleLayoutNote}',
                    style: noteStyle,
                  ),
                ),
              )
            else
              Padding(
                key: AppearanceSectionKeys.noteOf(target),
                padding: EdgeInsets.only(top: compact ? 6 : 8),
                child: Text(switch (target) {
                  StyleTarget.home => AppStrings.homeStyleNote,
                  StyleTarget.editor => AppStrings.editorStyleNote,
                }, style: noteStyle),
              ),
            // (review) the previews show where each style is heading; the
            // per-style toolbar layouts arrive in a later stage.
            if (target == StyleTarget.editor && !compact)
              Padding(
                key: AppearanceSectionKeys.layoutNote,
                padding: const EdgeInsets.only(top: 4),
                child: Text(AppStrings.styleLayoutNote, style: noteStyle),
              ),
            if (_failed)
              Padding(
                key: AppearanceSectionKeys.messageOf(target),
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  AppStrings.featureSaveFailed,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

String _styleName(AppStyle style) => switch (style) {
  AppStyle.craft => AppStrings.styleCraft,
  AppStyle.calm => AppStrings.styleCalm,
  AppStyle.studio => AppStrings.styleStudio,
};

String _styleHint(AppStyle style) => switch (style) {
  AppStyle.craft => AppStrings.styleCraftHint,
  AppStyle.calm => AppStrings.styleCalmHint,
  AppStyle.studio => AppStrings.styleStudioHint,
};

class _StyleCard extends StatelessWidget {
  const _StyleCard({
    super.key,
    required this.style,
    required this.target,
    required this.brightness,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final AppStyle style;
  final StyleTarget target;
  final Brightness brightness;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = StyleTokens.of(context);
    final name = _styleName(style);
    final radius = BorderRadius.circular(tokens.radiusMedium);
    return Semantics(
      selected: selected,
      button: true,
      label: name,
      hint: compact ? _styleHint(style) : null,
      child: Material(
        color: selected ? tokens.accentSoft : tokens.card,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? tokens.accent : tokens.hairline,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(compact ? 6 : 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 10,
                  child: StylePreviewSwatch(
                    tokens: styleTokensFor(style, brightness),
                    home: target == StyleTarget.home,
                  ),
                ),
                SizedBox(height: compact ? 6 : 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: selected
                              ? tokens.onAccentSoft
                              : tokens.textPrimary,
                        ),
                      ),
                    ),
                    if (selected)
                      Icon(
                        Icons.check_circle,
                        size: compact ? 16 : 18,
                        color: tokens.accent,
                      ),
                  ],
                ),
                if (!compact) ...[
                  const SizedBox(height: 2),
                  Text(
                    _styleHint(style),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: selected
                          ? tokens.onAccentSoft
                          : tokens.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small picture of a style: its canvas, a toolbar strip (studio: a left
/// rail), a page of paper with two ink lines and the accent dot. With
/// [home]: a small library instead — a sidebar with the chosen folder in the
/// accent, a header strip and a grid of note covers.
class StylePreviewSwatch extends StatelessWidget {
  const StylePreviewSwatch({
    super.key,
    required this.tokens,
    this.home = false,
  });

  final StyleTokens tokens;

  /// The library picture (홈 화면 스타일).
  final bool home;

  @override
  Widget build(BuildContext context) {
    if (home) return _homeSwatch();
    final t = tokens;
    final small = Radius.circular(t.radiusSmall / 2);
    final rail = t.style == AppStyle.studio;
    final floating = t.style == AppStyle.calm;
    Widget bar(double width) => Container(
      width: width,
      height: 3,
      decoration: BoxDecoration(
        color: t.textSecondary,
        borderRadius: BorderRadius.circular(2),
      ),
    );
    final toolbar = Container(
      height: 12,
      margin: floating
          ? const EdgeInsets.fromLTRB(18, 4, 18, 0)
          : EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: t.toolbar,
        borderRadius: floating ? BorderRadius.all(small) : null,
        border: floating
            ? Border.all(color: t.hairline)
            : Border(bottom: BorderSide(color: t.hairline)),
      ),
      child: Row(
        children: [
          bar(10),
          const Spacer(),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          bar(8),
        ],
      ),
    );
    final page = Center(
      child: FractionallySizedBox(
        widthFactor: 0.46,
        heightFactor: 0.82,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.inkSwatch,
            borderRadius: BorderRadius.all(small),
            boxShadow: t.shadows(),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 10, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (w, c) in const [
                  (0.9, Color(0xFF26324F)),
                  (0.6, Color(0xFF26324F)),
                  (0.75, Color(0xFF2F6FDB)),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: FractionallySizedBox(
                      widthFactor: w,
                      child: Container(height: 2, color: c),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(t.radiusSmall),
      child: ColoredBox(
        color: t.canvas,
        child: rail
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 14,
                    color: t.rail,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        for (final c in [
                          t.accent,
                          t.textSecondary,
                          t.textSecondary,
                        ])
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(bottom: 4),
                            decoration: BoxDecoration(
                              color: c,
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        toolbar,
                        Expanded(child: page),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  toolbar,
                  Expanded(child: page),
                ],
              ),
      ),
    );
  }
}

extension on StylePreviewSwatch {
  /// The library picture. Each style gets its own signature so the three
  /// cards read apart even at phone width (review):
  /// - 크래프트: paper sidebar, notebook covers with a coloured spine, a
  ///   soft shadow and the larger radius;
  /// - 미니멀: no sidebar border, a floating header pill, flat covers with
  ///   hairline borders only and more air between them;
  /// - 스튜디오: a full-height darker rail, a flat header bar and a dense
  ///   grid of small square-cornered covers.
  Widget _homeSwatch() {
    final t = tokens;
    final craft = t.style == AppStyle.craft;
    final calm = t.style == AppStyle.calm;
    final studio = t.style == AppStyle.studio;
    final small = Radius.circular(t.radiusSmall / 2);
    Widget line(double width, Color color) => Container(
      width: width,
      height: 3,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
    final railColor = studio
        ? Color.lerp(t.rail, t.textPrimary, 0.14)!
        : calm
        ? t.canvas
        : t.panel;
    final sidebar = Container(
      width: studio ? 22 : 30,
      padding: EdgeInsets.fromLTRB(studio ? 3 : 4, 6, studio ? 3 : 4, 0),
      decoration: BoxDecoration(
        color: railColor,
        border: calm ? null : Border(right: BorderSide(color: t.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 7,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            alignment: AlignmentDirectional.centerStart,
            decoration: BoxDecoration(
              color: studio ? t.accent : t.accentSoft,
              borderRadius: BorderRadius.all(small),
            ),
            child: line(studio ? 8 : 12, studio ? t.onAccent : t.accent),
          ),
          SizedBox(height: studio ? 4 : 5),
          for (final w
              in studio
                  ? const [12.0, 9.0, 11.0, 8.0]
                  : const [16.0, 12.0, 14.0]) ...[
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: line(w, t.textSecondary),
            ),
            SizedBox(height: studio ? 4 : 5),
          ],
        ],
      ),
    );
    final headerRow = Row(
      children: [
        line(14, t.textPrimary),
        const Spacer(),
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
        ),
      ],
    );
    final header = calm
        ? Container(
            height: 10,
            margin: const EdgeInsets.fromLTRB(10, 4, 10, 0),
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: t.toolbar,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: t.hairline),
            ),
            child: headerRow,
          )
        : Container(
            height: studio ? 10 : 12,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: t.toolbar,
              border: Border(bottom: BorderSide(color: t.hairline)),
            ),
            child: headerRow,
          );
    final coverRadius = BorderRadius.all(
      craft
          ? Radius.circular(t.radiusSmall * 0.6)
          : studio
          ? const Radius.circular(1.5)
          : small,
    );
    Widget cover(int i) {
      final highlighted = i == 1;
      final box = DecoratedBox(
        decoration: BoxDecoration(
          color: highlighted ? t.accentSoft : t.inkSwatch,
          borderRadius: coverRadius,
          border: craft
              ? null
              : Border.all(color: highlighted ? t.accent : t.hairline),
          boxShadow: craft ? t.shadows() : null,
        ),
        child: craft
            ? Align(
                alignment: AlignmentDirectional.centerStart,
                child: FractionallySizedBox(
                  heightFactor: 1,
                  widthFactor: 0.16,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: highlighted ? t.accent : t.paperHighlight,
                      borderRadius: BorderRadiusDirectional.horizontal(
                        start: coverRadius.topLeft,
                      ),
                    ),
                  ),
                ),
              )
            : null,
      );
      return box;
    }

    final columns = studio ? 4 : 3;
    final gap = studio
        ? 3.0
        : calm
        ? 7.0
        : 5.0;
    final grid = Padding(
      padding: EdgeInsets.all(
        calm
            ? 8
            : studio
            ? 5
            : 6,
      ),
      child: Column(
        children: [
          for (final row in const [0, 1]) ...[
            if (row > 0) SizedBox(height: gap),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var col = 0; col < columns; col++) ...[
                    if (col > 0) SizedBox(width: gap),
                    Expanded(child: cover(row * columns + col)),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(t.radiusSmall),
      child: ColoredBox(
        color: t.canvas,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            sidebar,
            Expanded(
              child: Column(
                children: [
                  header,
                  Expanded(child: grid),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// '밝기': 시스템 따라 / 밝게 / 어둡게.
class AppBrightnessSection extends ConsumerStatefulWidget {
  const AppBrightnessSection({super.key});

  @override
  ConsumerState<AppBrightnessSection> createState() =>
      _AppBrightnessSectionState();
}

class _AppBrightnessSectionState extends ConsumerState<AppBrightnessSection> {
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(appAppearanceProvider).brightness;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<AppBrightnessMode>(
          key: AppearanceSectionKeys.brightness,
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: AppBrightnessMode.system,
              icon: Icon(Icons.brightness_auto_outlined),
              label: Text(AppStrings.brightnessSystem),
            ),
            ButtonSegment(
              value: AppBrightnessMode.light,
              icon: Icon(Icons.light_mode_outlined),
              label: Text(AppStrings.brightnessLight),
            ),
            ButtonSegment(
              value: AppBrightnessMode.dark,
              icon: Icon(Icons.dark_mode_outlined),
              label: Text(AppStrings.brightnessDark),
            ),
          ],
          selected: {current},
          onSelectionChanged: (selection) {
            setState(() => _failed = false);
            unawaited(
              _write(
                ref,
                AppearanceKeys.brightness,
                selection.single.wireName,
                () {
                  if (mounted) setState(() => _failed = true);
                },
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            AppStrings.brightnessPaperNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (_failed)
          Padding(
            key: AppearanceSectionKeys.message,
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              AppStrings.featureSaveFailed,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}
