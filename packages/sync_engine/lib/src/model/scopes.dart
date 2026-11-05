import 'package:note_core/note_core.dart';

import 'records.dart';

/// Chunk routing (6.4.3). 'lib' for library-level kinds, else the note id.
abstract final class SyncScopes {
  static const String library = 'lib';

  /// folder · note · penPreset · setting · asset → 'lib'; page → json['noteId'];
  /// stroke · recording → [noteIdHint] (OutboxEntry.noteId, always set — contract 7.2.10),
  /// recording falls back to json['noteId']. The engine resolves a missing stroke hint
  /// from the page record before calling this (6.4.3 step 1); otherwise 'lib'.
  static String scopeOf(UpsertRecord record, {NoteId? noteIdHint}) {
    final json = record.doc.json;
    final noteIdKey = switch (json['noteId']) {
      final String id when id.isNotEmpty => id,
      _ => null,
    };
    return switch (record.doc.kind) {
      EntityKind.folder ||
      EntityKind.note ||
      EntityKind.penPreset ||
      EntityKind.setting ||
      EntityKind.asset => library,
      EntityKind.page => noteIdKey ?? noteIdHint ?? library,
      EntityKind.stroke => noteIdHint ?? library,
      EntityKind.recording => noteIdHint ?? noteIdKey ?? library,
    };
  }

  /// Always 'lib'.
  static String scopeOfPurge(PurgeRecord record) => library;
}
