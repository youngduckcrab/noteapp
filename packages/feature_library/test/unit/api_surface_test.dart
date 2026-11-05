// Public surface of package:feature_library (contract 00-overview 7.2.18,
// 05-library 4.1, 9.1 '공개 표면').
//
// Imports only the entry point and uses all 11 exported names in the call
// shapes of the contract block, so a renamed / re-typed / missing name breaks
// the build. Names leaking beyond these 11 are checked by INFRA's R14 at the
// integration step.
import 'package:feature_library/feature_library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// pdf_io's importPdfAsNewNote shape (contract 7.2.19).
Future<String?> _importPdfAsNewNote(
  BuildContext context, {
  String? folderId,
}) async => null;

/// pdf_io's exportNotesAsPdf shape (contract 7.2.19).
Future<void> _exportNotesAsPdf(
  BuildContext context,
  List<String> noteIds,
) async {}

void main() {
  test('LibraryScreen has the contract constructor and fields', () {
    final folders = <String?>[];
    final notes = <String>[];
    var settings = 0;
    final home = LibraryScreen(
      onOpenFolder: folders.add,
      onOpenNote: notes.add,
      onOpenSettings: () => settings++,
    );
    final folder = LibraryScreen(
      key: const ValueKey('library'),
      folderId: 'folder-1',
      onOpenFolder: folders.add,
      onOpenNote: notes.add,
      onOpenSettings: () => settings++,
    );

    expect(home, isA<ConsumerStatefulWidget>());
    final String? homeId = home.folderId;
    expect(homeId, isNull);
    expect(folder.folderId, 'folder-1');
    expect(folder.key, const ValueKey('library'));

    final ValueChanged<String?> onOpenFolder = folder.onOpenFolder;
    final ValueChanged<String> onOpenNote = folder.onOpenNote;
    final VoidCallback onOpenSettings = folder.onOpenSettings;
    onOpenFolder(null);
    onOpenNote('note-1');
    onOpenSettings();
    expect(folders, [null]);
    expect(notes, ['note-1']);
    expect(settings, 1);
  });

  test('featureLibraryOverrides() is an empty list', () {
    final List<Override> overrides = featureLibraryOverrides();
    expect(overrides, isEmpty);
  });

  test('the PDF slots default to null', () {
    final container = ProviderContainer.test();
    final LibraryPdfImportAction? importAction = container.read(
      libraryPdfImportActionProvider,
    );
    final LibraryPdfExportAction? exportAction = container.read(
      libraryPdfExportActionProvider,
    );
    expect(importAction, isNull);
    expect(exportAction, isNull);
    expect(
      libraryPdfImportActionProvider.name,
      'libraryPdfImportActionProvider',
    );
    expect(
      libraryPdfExportActionProvider.name,
      'libraryPdfExportActionProvider',
    );
  });

  test('the PDF slots take the pdf_io function shapes (app shell wiring)', () {
    const LibraryPdfImportAction importAction = _importPdfAsNewNote;
    const LibraryPdfExportAction exportAction = _exportNotesAsPdf;
    final container = ProviderContainer.test(
      overrides: [
        libraryPdfImportActionProvider.overrideWithValue(importAction),
        libraryPdfExportActionProvider.overrideWithValue(exportAction),
      ],
    );
    expect(container.read(libraryPdfImportActionProvider), importAction);
    expect(container.read(libraryPdfExportActionProvider), exportAction);
  });

  test('LibrarySettingsSection is a const ConsumerWidget', () {
    const section = LibrarySettingsSection(key: ValueKey('section'));
    expect(section, isA<ConsumerWidget>());
    expect(const LibrarySettingsSection().key, isNull);
  });

  test('the appearance registry is exported (LIBRARY 4.4)', () {
    const String defaultKey = FolderIcons.defaultKey;
    const List<String> keys = FolderIcons.keys;
    final IconData icon = FolderIcons.iconFor(null);
    final String label = FolderIcons.labelFor(defaultKey);
    const List<int> folderColors = FolderPalette.colors;
    const List<String> folderNames = FolderPalette.names;
    const List<int> coverColors = CoverPalette.colors;
    const List<String> coverNames = CoverPalette.names;
    final Color foreground = coverForegroundFor(coverColors.first);

    expect(keys, contains(defaultKey));
    expect(icon, Icons.folder);
    expect(label, isNotEmpty);
    expect(folderColors, hasLength(folderNames.length));
    expect(coverColors, hasLength(coverNames.length));
    expect(foreground, isA<Color>());
  });
}
