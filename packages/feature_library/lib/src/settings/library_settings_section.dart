// lib/src/settings/library_settings_section.dart — contract 00-overview 7.2.18
// and 7.4.11, 05-library 4.5.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Body of the app shell's settings section '일반 › 새 노트 기본값'
/// (section id `library.newNote`). The app shell draws the title and the group
/// header; this widget is a Column only (no Scaffold, no title) and takes the
/// parent's width.
///
/// Foundation step B6: an empty placeholder. The page size, orientation,
/// template and paper color pickers come with task L18 (05-library 4.5).
class LibrarySettingsSection extends ConsumerWidget {
  const LibrarySettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
    );
  }
}
