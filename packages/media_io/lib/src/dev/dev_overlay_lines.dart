// lib/src/dev/dev_overlay_lines.dart — mediaDevOverlayLinesProvider (contract 7.2.12,
// m5-7/06-pdf 6.14).
//
// 2차 foundation step R2-B4 (T30, contract 7.6.2): an empty list. PDF T39 fills the lines of
// 6.14 (rec / enc / last / drafts / buf / web / fgs / play) from the recorder and player
// status streams.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Developer overlay lines: encoder support table, last recording MIME / duration / clock error (R-3).
final mediaDevOverlayLinesProvider = Provider<ValueListenable<List<String>>>((
  ref,
) {
  final lines = ValueNotifier<List<String>>(const []);
  ref.onDispose(lines.dispose);
  return lines;
}, name: 'mediaDevOverlayLinesProvider');
