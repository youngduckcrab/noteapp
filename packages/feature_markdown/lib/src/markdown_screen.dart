// The MD 문서 screen (08-markdown 8, C217M-14). FOUNDATION STUB: the public constructor is
// fixed; Track B replaces the body (view, editor, autosave, banners, menus) inside src/.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:ui_kit/ui_kit.dart';

import 'markdown_keys.dart';

/// One MD 문서, full screen: 보기 (rendered) ↔ 편집 (source) with one button.
///
/// Wrapped by the app in the editor style (`EditorStyleScope`) like the ink editor.
class MarkdownScreen extends ConsumerStatefulWidget {
  const MarkdownScreen({
    super.key,
    required this.noteId,
    this.initialQuery,
    this.initialEdit = false,
    required this.onClose,
    this.onOpenAsNote,
  });

  /// The MD 문서 (a note with `isMarkdown`).
  final NoteId noteId;

  /// Library search text: after the first frame the view scrolls to the first match and
  /// highlights it (08-markdown 8.8). null = top of the document.
  final String? initialQuery;

  /// Open in 편집 (a document just made with '새 MD 문서'); otherwise 보기.
  final bool initialEdit;

  /// Back: called after the screen has saved and flushed (or the user chose to leave
  /// after a failed save — the text is never dropped silently).
  final VoidCallback onClose;

  /// When [noteId] is a handwriting note: [노트로 열기]. null hides the button.
  final VoidCallback? onOpenAsNote;

  @override
  ConsumerState<MarkdownScreen> createState() => _MarkdownScreenState();
}

class _MarkdownScreenState extends ConsumerState<MarkdownScreen> {
  @override
  Widget build(BuildContext context) {
    final doc = ref.watch(markdownDocProvider(widget.noteId));
    final title = doc.value?.note.title ?? '';
    return Scaffold(
      key: MarkdownKeys.screen,
      appBar: AppBar(
        leading: IconButton(
          key: MarkdownKeys.back,
          onPressed: widget.onClose,
          icon: const AppIcon(AppIconKind.back),
        ),
        title: Text(title, key: MarkdownKeys.title),
      ),
      body: switch (doc) {
        AsyncData(value: final d?) => SingleChildScrollView(
          key: MarkdownKeys.view,
          padding: const EdgeInsets.all(16),
          child: SelectableText(d.text),
        ),
        AsyncData() => Center(
          key: MarkdownKeys.notMarkdown,
          child: widget.onOpenAsNote == null
              ? const Text('이 문서는 MD 문서가 아니에요')
              : TextButton(
                  key: MarkdownKeys.openAsNote,
                  onPressed: widget.onOpenAsNote,
                  child: const Text('노트로 열기'),
                ),
        ),
        AsyncError() => const Center(child: Text('문서를 열지 못했어요')),
        _ => const SizedBox.shrink(),
      },
    );
  }
}
