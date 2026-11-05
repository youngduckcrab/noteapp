// lib/src/common/errors.dart — contract 00-overview 7.2.2 / CORE 4.1.
// CORE 4.1 approved. Change: NoteStoreOpenException added, StorageUnavailableException removed.

sealed class NoteCoreException implements Exception {
  const NoteCoreException(this.message);
  final String message;

  String get _name;

  @override
  String toString() => '$_name: $message';
}

final class EntityNotFoundException extends NoteCoreException {
  const EntityNotFoundException(super.message);
  @override
  String get _name => 'EntityNotFoundException';
}

final class FolderCycleException extends NoteCoreException {
  const FolderCycleException(super.message);
  @override
  String get _name => 'FolderCycleException';
}

final class ReadOnlyNoteException extends NoteCoreException {
  const ReadOnlyNoteException(super.message);
  @override
  String get _name => 'ReadOnlyNoteException';
}

final class PageNotOpenException extends NoteCoreException {
  const PageNotOpenException(super.message);
  @override
  String get _name => 'PageNotOpenException';
}

final class LastPageDeletionException extends NoteCoreException {
  const LastPageDeletionException(super.message);
  @override
  String get _name => 'LastPageDeletionException';
}

final class SessionClosedException extends NoteCoreException {
  const SessionClosedException(super.message);
  @override
  String get _name => 'SessionClosedException';
}

final class AssetHashMismatchException extends NoteCoreException {
  const AssetHashMismatchException(super.message);
  @override
  String get _name => 'AssetHashMismatchException';
}

/// Why openNoteStore failed (startup error screen picks the message by reason, 6.18).
enum NoteStoreOpenFailure {
  storageUnavailable,
  migrationFailed,
  corrupted,
  newerSchema,
  unknown,
}

final class NoteStoreOpenException extends NoteCoreException {
  const NoteStoreOpenException(this.reason, super.message, {this.cause});
  final NoteStoreOpenFailure reason;
  final Object? cause;
  @override
  String get _name => 'NoteStoreOpenException(${reason.name})';
}
// Removed: StorageUnavailableException (→ NoteStoreOpenException(storageUnavailable, ...)).
