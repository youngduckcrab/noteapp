// Internal (not exported). Checks on a received record before it is applied (6.3.5).
// Pure: the caller passes the chunk fields, the reference time g (6.2.5) and the
// permanent-deletion view; the gate reads no clock and no store.
import 'package:note_core/note_core.dart';

import '../common/server_cursor.dart';
import '../model/records.dart';
import '../model/scopes.dart';
import '../status/sync_issue.dart';

sealed class GateVerdict {
  const GateVerdict();
}

/// Apply the record.
final class GateAccept extends GateVerdict {
  const GateAccept();
}

/// Irreversible rejection with a non-blocking issue (malformedRemoteData,
/// foreignOwnerData); the cursor moves on.
final class GateSkip extends GateVerdict {
  const GateSkip(this.code, this.reason);
  final SyncIssueCode code;
  final String reason;

  @override
  String toString() => 'GateSkip(${code.name}: $reason)';
}

/// Irreversible, log only: the entity (or its note) is permanently deleted.
final class GateDrop extends GateVerdict {
  const GateDrop(this.reason);
  final String reason;

  @override
  String toString() => 'GateDrop($reason)';
}

/// K1 (6.2.5): not applied now, kept in `sync.held` until the reference time
/// reaches [releaseAtMillis] (= versions.max.millis − limit).
final class GateHold extends GateVerdict {
  const GateHold(this.releaseAtMillis);
  final int releaseAtMillis;

  @override
  String toString() => 'GateHold(releaseAt: $releaseAtMillis)';
}

abstract final class RecordGate {
  /// The record clock limit (6.2.5) = SyncConfig.clockSkewLimit default.
  static const Duration defaultLimit = Duration(hours: 24);

  /// g = min(chunk serverTime, wall) on receipt; g' = min(serverNow(), wall)
  /// on release (6.2.5). Milliseconds.
  static int referenceMillis(ServerCursor serverTime, int wallMillis) {
    final server = serverTime.micros ~/ 1000;
    return server < wallMillis ? server : wallMillis;
  }

  /// K2: a hold is released when g' >= releaseAt.
  static bool isReleased(int releaseAtMillis, int referenceMillis) =>
      referenceMillis >= releaseAtMillis;

  /// Table 6.3.5, in this order: malformed → foreign owner → permanently
  /// deleted (the entity, or the note of a page / recording / stroke) → K1 hold.
  ///
  /// [scope] is the chunk scope (stroke's note when not 'lib'); [isPurged]
  /// is the permanent-deletion view for folder / note refs (stored set, unsent
  /// local purges and the purges of the current apply group); [strokeNoteId]
  /// is the note of a 'lib'-scope stroke's page when the pipeline found it.
  static GateVerdict check(
    SyncRecord record, {
    required String scope,
    required int referenceMillis,
    required String uid,
    required bool Function(EntityRef ref) isPurged,
    String? strokeNoteId,
    Duration limit = defaultLimit,
  }) {
    switch (record) {
      case PurgeRecord(:final ref):
        if (ref.kind != EntityKind.folder && ref.kind != EntityKind.note) {
          return _malformed('purge of a ${ref.kind.name}');
        }
        if (!isValidEntityId(ref.id)) return _malformed('purge id ${ref.id}');
        return const GateAccept();
      case UpsertRecord(:final doc, :final versions):
        final valid = doc.kind == EntityKind.setting
            ? doc.id.isNotEmpty
            : isValidEntityId(doc.id);
        if (!valid) return _malformed('${doc.kind.name} id "${doc.id}"');
        final Hlc? version;
        try {
          version = doc.version;
        } on FormatException catch (e) {
          return _malformed('${doc.ref}: ${e.message}');
        }
        if (version == null) return _malformed('${doc.ref}: no version');
        if (version != versions.max) {
          return _malformed('${doc.ref}: version $version != fv.max');
        }
        try {
          record.toRemoteChange();
        } on FormatException catch (e) {
          return _malformed('${doc.ref}: ${e.message}');
        }
        final hasOwner = switch (doc.kind) {
          EntityKind.folder ||
          EntityKind.note ||
          EntityKind.penPreset ||
          EntityKind.asset => true,
          _ => false,
        };
        if (hasOwner && doc.ownerId != uid) {
          return GateSkip(
            SyncIssueCode.foreignOwnerData,
            '${doc.ref}: ownerId ${doc.ownerId}',
          );
        }
        if (_purged(record, scope, strokeNoteId, isPurged) case final why?) {
          return GateDrop(why);
        }
        final maxMillis = versions.max.millis;
        if (maxMillis > referenceMillis + limit.inMilliseconds) {
          return GateHold(maxMillis - limit.inMilliseconds);
        }
        return const GateAccept();
    }
  }

  static String? _purged(
    UpsertRecord record,
    String scope,
    String? strokeNoteId,
    bool Function(EntityRef ref) isPurged,
  ) {
    final doc = record.doc;
    String? note(Object? id) => id is String && id.isNotEmpty
        ? (isPurged(EntityRef(EntityKind.note, id)) ? id : null)
        : null;
    switch (doc.kind) {
      case EntityKind.folder || EntityKind.note:
        return isPurged(doc.ref) ? '${doc.ref} is permanently deleted' : null;
      case EntityKind.page || EntityKind.recording:
        final n = note(doc.json['noteId']);
        return n == null ? null : '${doc.ref} of permanently deleted note $n';
      case EntityKind.stroke:
        final n = note(scope == SyncScopes.library ? strokeNoteId : scope);
        return n == null ? null : '${doc.ref} of permanently deleted note $n';
      case EntityKind.penPreset || EntityKind.setting || EntityKind.asset:
        return null;
    }
  }

  static GateSkip _malformed(String reason) =>
      GateSkip(SyncIssueCode.malformedRemoteData, reason);
}
