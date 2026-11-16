import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

import '../app/strings.dart';
import 'settings_sections.dart';

/// Scaffold + AppBar('설정', (v2.14-ui) ← back button → onClose; it was ✕) +
/// ListView of
/// [group header] + section header + section body; content width ≤ 720,
/// centered (iPad landscape).
///
/// The whole width scrolls (side padding instead of a narrow ListView). Each
/// section body is keyed with `ValueKey(entry.id)`.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, required this.onClose});
  final VoidCallback onClose;

  /// Widest content column.
  static const double maxContentWidth = 720;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = ref.watch(settingsSectionsProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const AppIcon(AppIconKind.back),
          tooltip: AppStrings.back,
          onPressed: onClose,
        ),
        title: const Text(AppStrings.settings),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final side = math.max(
            16.0,
            (constraints.maxWidth - maxContentWidth) / 2,
          );
          final children = <Widget>[];
          String? previousGroup;
          for (final entry in sections) {
            final group = entry.group;
            if (group != null && group != previousGroup) {
              children.add(_GroupHeader(title: group, theme: theme));
            }
            previousGroup = group;
            children
              ..add(_SectionHeader(id: entry.id, title: entry.title))
              ..add(
                KeyedSubtree(
                  key: ValueKey<String>(entry.id),
                  child: Builder(builder: entry.builder),
                ),
              );
          }
          return ListView(
            padding: EdgeInsets.fromLTRB(side, 8, side, 32),
            children: children,
          );
        },
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, required this.theme});

  final String title;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 4),
    child: Text(
      title,
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.primary,
      ),
    ),
  );
}

/// (UI stage 2) The line icon of each settings category (section id →
/// ui_kit AppIconKind); a section without one shows its title alone.
const Map<String, AppIconKind> settingsSectionIcons = {
  'app.homeStyle': AppIconKind.style,
  'app.editorStyle': AppIconKind.style,
  'app.brightness': AppIconKind.brightness,
  'app.hoverNames': AppIconKind.hoverName,
  'app.storage': AppIconKind.storage,
  'editor.input': AppIconKind.input,
  'editor.pen': AppIconKind.pen,
  'editor.page': AppIconKind.pages,
  'library.newNote': AppIconKind.notebook,
  'recog.settings': AppIconKind.recognition,
  'editor.developer': AppIconKind.developer,
  'app.features': AppIconKind.features,
  'app.v1Copy': AppIconKind.history,
  'app.about': AppIconKind.info,
};

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.id, required this.title});

  final String id;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = settingsSectionIcons[id];
    final text = Text(title, style: theme.textTheme.titleMedium);
    return Padding(
      key: ValueKey<String>('settings-header-$id'),
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Semantics(
        header: true,
        child: icon == null
            ? text
            : Row(
                children: [
                  AppIcon(
                    icon,
                    key: ValueKey<String>('settings-icon-$id'),
                    size: 22,
                    color: StyleTokens.of(context).textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: text),
                ],
              ),
      ),
    );
  }
}
