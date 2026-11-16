// lib/src/state/tape_state.dart — m5-7/04-editor 6.14.4, 6.19, I-10 (E2-02).
//
// The note-level memorization tape state: null = only the per-tape toggles
// (INK state per controller — U10, never stored); true = '테이프 모두 보이기',
// false = '테이프 모두 가리기'. setAll applies the value to every mounted
// page controller at once; PageMount applies `true` again after each
// updateContent (INK reveals only the tapes present at the call, so tapes
// that arrive later — drawn, undone, remote — would start covered). A page
// mounted later gets it with its first content; its new controller starts
// with every tape covered, which is what `false` means. The more menu items
// (E2-14 — the more menu) call setAll.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_core/note_core.dart' as core;

import '../document/mounted_pages.dart';
import '../scope/editor_scope.dart';

class TapesRevealedAllNotifier extends Notifier<bool?> {
  @override
  bool? build() {
    ref.watch(editorMountedPagesProvider);
    return null;
  }

  /// '모두 보이기' (true) / '모두 가리기' (false) on every mounted page now
  /// and on the pages mounted or updated later.
  void setAll(bool revealed) {
    state = revealed;
    final MountedPages pages = ref.read(editorMountedPagesProvider);
    for (final mount in pages.all) {
      if (mount.isDisposed) continue;
      mount.controller.setAllTapesRevealed(revealed);
    }
  }
}

final editorTapesRevealedAllProvider =
    NotifierProvider<TapesRevealedAllNotifier, bool?>(
      TapesRevealedAllNotifier.new,
      dependencies: [editorMountedPagesProvider],
      name: 'editorTapesRevealedAllProvider',
    );

/// (v2.14-ui review, UI stage 1) True once a page of this note was seen with
/// a tape stroke in this editor session: every content a mounted page gets
/// (EditorPageView) is checked until the first tape, and the flag then stays
/// true although the page leaves the page cache. The more menu lists 테이프
/// 모두 보이기 / 가리기 when this is true or a loaded page has a tape — so a
/// tape on page 2 still shows the item at page 30. Pages never shown in this
/// session are not read (CORE has no note-level tape flag). Never stored.
class NoteHadTapeNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(editorMountedPagesProvider);
    return false;
  }

  /// Checks [strokes] until the first tape (a no-op once true).
  void noteStrokes(Iterable<core.Stroke> strokes) {
    if (state) return;
    for (final stroke in strokes) {
      if (stroke.style.tool == core.PenTool.tape) {
        state = true;
        return;
      }
    }
  }
}

final editorNoteHadTapeProvider = NotifierProvider<NoteHadTapeNotifier, bool>(
  NoteHadTapeNotifier.new,
  dependencies: [editorMountedPagesProvider],
  name: 'editorNoteHadTapeProvider',
);
