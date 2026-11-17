// lib/src/state/markdown_preview.dart — (v2.17-md, 08-markdown 9) the card preview of an MD
// 문서 for the library: CORE's markdownPreviewProvider (keyed by noteId + updatedAt), kept
// for 30 s after the last card using it is gone, so scrolling a grid back and forth does
// not read the bodies again (and the card does not flash empty).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_core/note_core.dart'
    show
        MarkdownLimits,
        MarkdownPreviewKey,
        markdownPreviewProvider,
        markdownRepositoryProvider;

const Duration kMarkdownPreviewCacheTime = Duration(seconds: 30);

void _keepFor30s(Ref ref) {
  final link = ref.keepAlive();
  Timer? timer;
  ref
    ..onCancel(() {
      timer = Timer(kMarkdownPreviewCacheTime, link.close);
    })
    ..onResume(() => timer?.cancel())
    ..onDispose(() => timer?.cancel());
}

final libraryMarkdownPreviewProvider = FutureProvider.autoDispose
    .family<String, MarkdownPreviewKey>((ref, key) async {
      _keepFor30s(ref);
      return ref.watch(markdownPreviewProvider(key).future);
    }, name: 'libraryMarkdownPreviewProvider');

/// The UTF-8 size of an MD 문서 for its list row ('… · 문서 · 2.1 KB'; null without a
/// body). Read once per (noteId, updatedAt) — not a watch of the body, so writes
/// elsewhere in the library do not read the bodies of the visible rows again.
final libraryMarkdownSizeProvider = FutureProvider.autoDispose
    .family<int?, MarkdownPreviewKey>((ref, key) async {
      _keepFor30s(ref);
      final doc = await ref.read(markdownRepositoryProvider).get(key.noteId);
      if (doc == null || !doc.bodyPresent) return null;
      return MarkdownLimits.utf8BytesOf(doc.text);
    }, name: 'libraryMarkdownSizeProvider');
