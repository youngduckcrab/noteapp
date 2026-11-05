import 'package:note_core/note_core.dart';

import 'records.dart';

/// Chunk routing (6.4.3). 'lib' for library-level kinds, else the note id.
abstract final class SyncScopes {
  static const String library = 'lib';

  static String scopeOf(UpsertRecord record, {NoteId? noteIdHint}) =>
      throw UnimplementedError('SYNC T2');

  /// Always 'lib'.
  static String scopeOfPurge(PurgeRecord record) =>
      throw UnimplementedError('SYNC T2');
}
