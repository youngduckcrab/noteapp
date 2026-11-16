// lib/src/ui/top_bar/new_menu_button.dart — 05-library 6.2 top bar table:
// '새로 만들기' (FilledButton.tonal; a + icon button in the compact class)
// with 새 노트 · 새 폴더 · PDF 가져오기 (4.3: disabled while an import runs;
// (v2.14-ui, UI stage 1) hidden without the import slot — it was a disabled
// 'PDF 가져오기 · 준비 중'). The target is the folder of a folder section, 홈
// for every other section. 새 폴더 is also where the sidebar's '폴더 +' went.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show FolderId;

import '../../integration/pdf_flows.dart';
import '../../integration/pdf_slots.dart';
import '../../l10n/library_strings.dart';
import '../../model/section.dart';
import '../dialogs/create_flows.dart';
import '../layout/size_class.dart';

class NewMenuButton extends ConsumerWidget {
  const NewMenuButton({
    super.key,
    required this.section,
    required this.sizeClass,
  });

  final LibrarySection section;
  final LibrarySizeClass sizeClass;

  /// Where new items go: the folder of a folder section, else 홈 (null).
  static FolderId? targetOf(LibrarySection section) => switch (section) {
    FolderSection(:final folderId) => folderId,
    _ => null,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = targetOf(section);
    final importPdf = ref.watch(libraryPdfImportActionProvider);
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.note_add_outlined),
          onPressed: () => runNewNoteFlow(context, folderId: target),
          child: const Text(LibraryStrings.newNote),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.create_new_folder_outlined),
          onPressed: () => runNewFolderFlow(context, parentId: target),
          child: const Text(LibraryStrings.newFolder),
        ),
        if (importPdf != null)
          ValueListenableBuilder<bool>(
            valueListenable: libraryPdfImportRunning(context),
            builder: (_, running, _) => MenuItemButton(
              leadingIcon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: running
                  ? null
                  : () => runLibraryPdfImport(
                      context,
                      action: importPdf,
                      folderId: target,
                    ),
              child: const Text(LibraryStrings.importPdf),
            ),
          ),
      ],
      builder: (context, controller, _) {
        void toggle() =>
            controller.isOpen ? controller.close() : controller.open();
        if (sizeClass == LibrarySizeClass.compact) {
          return IconButton(
            icon: const Icon(Icons.add),
            tooltip: LibraryStrings.newMenu,
            onPressed: toggle,
          );
        }
        return FilledButton.tonalIcon(
          icon: const Icon(Icons.add),
          label: const Text(LibraryStrings.newMenu),
          onPressed: toggle,
        );
      },
    );
  }
}
