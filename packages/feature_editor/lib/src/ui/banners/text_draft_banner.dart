// lib/src/ui/banners/text_draft_banner.dart — m5-7/04-editor 6.11.2 (E2-10b,
// P-B — review S-11), appendix C (editor.textDraft.restore · .discard).
//
// Opening a note whose text draft was left in editor.textDraft (a reloaded
// web tab, an app that died during a long session): '저장되지 않은 글이 있어요
// [되살리기] [버리기]' above the toolbar. 되살리기 = a new box (one
// AddObjects, EditorCommands.restoreTextDraft), 버리기 = the key removed;
// either way the banner goes. A draft of another note shows nothing.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../scope/editor_scope.dart';
import '../../text/text_draft_store.dart';
import '../editor_strings.dart';

class TextDraftBanner extends ConsumerStatefulWidget {
  const TextDraftBanner({super.key});

  static const bannerKey = ValueKey('editor.textDraft.banner');
  static const restoreKey = ValueKey('editor.textDraft.restore');
  static const discardKey = ValueKey('editor.textDraft.discard');

  @override
  ConsumerState<TextDraftBanner> createState() => _TextDraftBannerState();
}

class _TextDraftBannerState extends ConsumerState<TextDraftBanner> {
  TextDraft? _draft;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final draft = await ref.read(editorTextDraftStoreProvider).load();
    if (!mounted || draft == null) return;
    setState(() => _draft = draft);
  }

  Future<void> _restore(TextDraft draft) async {
    if (_busy) return;
    setState(() => _busy = true);
    final store = ref.read(editorTextDraftStoreProvider);
    final restored = await ref
        .read(editorCommandsProvider)
        .restoreTextDraft(draft.draft);
    if (restored) await store.remove(draft);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (restored) _draft = null;
    });
  }

  Future<void> _discard(TextDraft draft) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _draft = null;
    });
    await ref.read(editorTextDraftStoreProvider).remove(draft);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    if (draft == null) return const SizedBox.shrink();
    final readOnly = ref.watch(editorReadOnlyProvider);
    final scheme = Theme.of(context).colorScheme;
    final foreground = scheme.onTertiaryContainer;
    return Material(
      key: TextDraftBanner.bannerKey,
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: Row(
          children: [
            Icon(Icons.restore_page_outlined, size: 18, color: foreground),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                EditorStrings.textDraftFound,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: foreground),
              ),
            ),
            TextButton(
              key: TextDraftBanner.restoreKey,
              // A read-only note would refuse the command (N-4).
              onPressed: readOnly || _busy
                  ? null
                  : () => unawaited(_restore(draft)),
              child: const Text(EditorStrings.textDraftRestore),
            ),
            TextButton(
              key: TextDraftBanner.discardKey,
              onPressed: _busy ? null : () => unawaited(_discard(draft)),
              child: const Text(EditorStrings.textDraftDiscard),
            ),
          ],
        ),
      ),
    );
  }
}
