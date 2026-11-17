// lib/src/state/markdown_preview.dart — (v2.17-md, 08-markdown 9) the card preview of an MD
// 문서 for the library: CORE's markdownPreviewProvider (keyed by noteId + updatedAt), kept
// for 30 s after the last card using it is gone, so scrolling a grid back and forth does
// not read the bodies again (and the card does not flash empty).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_core/note_core.dart'
    show MarkdownPreviewKey, markdownPreviewProvider;

const Duration kMarkdownPreviewCacheTime = Duration(seconds: 30);

final libraryMarkdownPreviewProvider = FutureProvider.autoDispose
    .family<String, MarkdownPreviewKey>((ref, key) async {
      final link = ref.keepAlive();
      Timer? timer;
      ref
        ..onCancel(() {
          timer = Timer(kMarkdownPreviewCacheTime, link.close);
        })
        ..onResume(() => timer?.cancel())
        ..onDispose(() => timer?.cancel());
      return ref.watch(markdownPreviewProvider(key).future);
    }, name: 'libraryMarkdownPreviewProvider');
