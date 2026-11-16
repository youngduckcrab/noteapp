/// '화면' group of the settings screen: 화면 스타일 and 밝기 (01-infra 14.3).
///
/// Both write device settings (AppearanceKeys); NoteApp rebuilds its theme
/// from appAppearanceProvider, so a choice shows at once.
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

/// Widget keys of the '화면' sections (tests, V5 smoke).
abstract final class AppearanceSectionKeys {
  static ValueKey<String> styleOf(AppStyle style) =>
      ValueKey<String>('app.appearance.style.${style.wireName}');
  static const ValueKey<String> brightness = ValueKey<String>(
    'app.appearance.brightness',
  );
  static const ValueKey<String> message = ValueKey<String>(
    'app.appearance.message',
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

/// '화면 스타일': three cards (preview swatch + name + one line), the chosen
/// one marked. The swatches follow the current brightness.
class AppStyleSection extends ConsumerStatefulWidget {
  const AppStyleSection({super.key});

  @override
  ConsumerState<AppStyleSection> createState() => _AppStyleSectionState();
}

class _AppStyleSectionState extends ConsumerState<AppStyleSection> {
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(appAppearanceProvider).style;
    final brightness = Theme.of(context).brightness;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final cards = [
              for (final style in AppStyle.values)
                _StyleCard(
                  key: AppearanceSectionKeys.styleOf(style),
                  style: style,
                  brightness: brightness,
                  selected: style == current,
                  onTap: () {
                    setState(() => _failed = false);
                    unawaited(
                      _write(ref, AppearanceKeys.style, style.wireName, () {
                        if (mounted) setState(() => _failed = true);
                      }),
                    );
                  },
                ),
            ];
            if (constraints.maxWidth < 420) {
              return Column(
                children: [
                  for (final card in cards)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: card,
                    ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: cards[i]),
                ],
              ],
            );
          },
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

class _StyleCard extends StatelessWidget {
  const _StyleCard({
    super.key,
    required this.style,
    required this.brightness,
    required this.selected,
    required this.onTap,
  });

  final AppStyle style;
  final Brightness brightness;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = StyleTokens.of(context);
    final (name, hint) = switch (style) {
      AppStyle.craft => (AppStrings.styleCraft, AppStrings.styleCraftHint),
      AppStyle.calm => (AppStrings.styleCalm, AppStrings.styleCalmHint),
      AppStyle.studio => (AppStrings.styleStudio, AppStrings.styleStudioHint),
    };
    final radius = BorderRadius.circular(tokens.radiusMedium);
    return Semantics(
      selected: selected,
      button: true,
      label: name,
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
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 10,
                  child: StylePreviewSwatch(
                    tokens: styleTokensFor(style, brightness),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: selected
                              ? tokens.onAccentSoft
                              : tokens.textPrimary,
                        ),
                      ),
                    ),
                    if (selected)
                      Icon(Icons.check_circle, size: 18, color: tokens.accent),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: selected
                        ? tokens.onAccentSoft
                        : tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small picture of a style: its canvas, a toolbar strip (studio: a left
/// rail), a page of paper with two ink lines and the accent dot.
class StylePreviewSwatch extends StatelessWidget {
  const StylePreviewSwatch({super.key, required this.tokens});

  final StyleTokens tokens;

  @override
  Widget build(BuildContext context) {
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
