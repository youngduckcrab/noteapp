// lib/src/settings/library_settings_section.dart — contract 00-overview 7.2.18
// and 7.4.11, 05-library 4.5.
import 'dart:async' show unawaited;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart'
    show settingsRepositoryProvider, settingsSnapshotProvider;

import '../common/report_error.dart';
import '../l10n/library_strings.dart';
import '../model/new_note_spec.dart';
import '../state/providers.dart';
import '../ui/dialogs/dialog_frame.dart';
import '../ui/pickers/page_size_picker.dart';
import '../ui/pickers/paper_color_picker.dart';
import '../ui/pickers/template_picker.dart';
import 'library_settings_keys.dart';

/// Body of the app shell's settings section '일반 › 새 노트 기본값'
/// (section id `library.newNote`). The app shell draws the title and the group
/// header; this widget is a Column only (no Scaffold, no title) and takes the
/// parent's width.
///
/// Page size (A4 · Letter · 16:9 · custom mm) · orientation · template ·
/// paper color — the new note dialog's pickers. Every change is saved at once
/// to library.newNote.defaults (NewNoteOptions.toJson, synced); the shown
/// value is newNoteDefaultsProvider. While the settings load it shows the
/// defaults with the inputs disabled (4.5).
class LibrarySettingsSection extends ConsumerWidget {
  const LibrarySettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = ref.watch(
      settingsSnapshotProvider.select((s) => s.hasValue),
    );
    return IgnorePointer(
      ignoring: !loaded,
      child: Opacity(
        opacity: loaded ? 1 : 0.38,
        child: const _NewNoteDefaultsForm(),
      ),
    );
  }
}

class _NewNoteDefaultsForm extends ConsumerStatefulWidget {
  const _NewNoteDefaultsForm();

  @override
  ConsumerState<_NewNoteDefaultsForm> createState() =>
      _NewNoteDefaultsFormState();
}

class _NewNoteDefaultsFormState extends ConsumerState<_NewNoteDefaultsForm> {
  /// What the form shows: the stored defaults, and a change at once (the
  /// settings snapshot follows a moment later — quick successive changes
  /// build on each other, not on a stale snapshot).
  late NewNoteOptions _value = ref.read(newNoteDefaultsProvider);

  void _change(NewNoteOptions next) {
    if (next == _value) return;
    setState(() => _value = next);
    unawaited(_save(next));
  }

  Future<void> _save(NewNoteOptions options) async {
    try {
      await ref
          .read(settingsRepositoryProvider)
          .set(LibrarySettingsKeys.newNoteDefaults, options.toJson());
    } on Object catch (error, stack) {
      reportLibraryError(error, stack, 'saving library.newNote.defaults');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Another device (or the first load) changed the stored defaults.
    ref.listen(newNoteDefaultsProvider, (_, next) {
      if (next != _value) setState(() => _value = next);
    });
    final value = _value;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DialogSection(
          label: LibraryStrings.fieldPageSize,
          child: PageSizePicker(value: value, onChanged: _change),
        ),
        DialogSection(
          label: LibraryStrings.fieldTemplate,
          child: TemplatePicker(
            value: value.template,
            onChanged: (kind) => _change(
              kind == null
                  ? value.copyWith(clearTemplate: true)
                  : value.copyWith(template: kind),
            ),
          ),
        ),
        DialogSection(
          label: LibraryStrings.fieldPaperColor,
          child: PaperColorPicker(
            value: value.paperColorArgb,
            onChanged: (argb) => _change(value.copyWith(paperColorArgb: argb)),
          ),
        ),
      ],
    );
  }
}
