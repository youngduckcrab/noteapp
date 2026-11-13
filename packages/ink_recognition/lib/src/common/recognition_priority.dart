// lib/src/common/recognition_priority.dart — (internal, text pen track —
// m5-7/05-library 6.24) the interactive lane of the handwriting engine.
//
// The native ML Kit recognizer runs one call at a time, FIFO, and the
// background indexer shares it. While the user waits for an answer — a text
// pen bubble, the conversion sheet — that request should not queue behind a
// page of indexer lines. A caller holds the priority for as long as it
// waits; while anything holds it the indexer starts no next line (the line
// in flight finishes — one line, normally well under a second), so the
// interactive request runs next.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final class RecognitionPriority {
  final ValueNotifier<bool> _interactive = ValueNotifier(false);
  int _holds = 0;
  bool _disposed = false;

  /// true while an interactive request holds the engine (the indexer
  /// yields).
  ValueListenable<bool> get interactive => _interactive;

  /// Holds the priority until the returned callback runs (idempotent).
  VoidCallback hold() {
    if (_disposed) return () {};
    _holds++;
    _interactive.value = true;
    var released = false;
    return () {
      if (released || _disposed) return;
      released = true;
      _holds--;
      if (_holds == 0) _interactive.value = false;
    };
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _interactive.dispose();
  }
}

/// One per container: the text pen sessions and the conversion sheet hold
/// it; handwritingIndexerProvider's indexer yields to it.
final recognitionPriorityProvider = Provider<RecognitionPriority>((ref) {
  final priority = RecognitionPriority();
  ref.onDispose(priority.dispose);
  return priority;
}, name: 'recognitionPriorityProvider');
