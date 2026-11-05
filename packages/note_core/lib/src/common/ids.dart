// Contract 00-overview 7.2.2 / CORE 4.1: ids.
import 'package:clock/clock.dart';
import 'package:uuid/data.dart';
import 'package:uuid/uuid.dart';

typedef FolderId = String;
typedef NoteId = String;
typedef PageId = String;
typedef ElementId = String;
typedef PresetId = String;
typedef RecordingId = String;
typedef AssetId = String; // lowercase hex SHA-256 of the bytes (64 chars)
typedef OwnerId = String;
typedef EpochMillis = int; // UTC ms since epoch

const OwnerId kLocalOwnerId = 'local';

/// Lexicographic order of ids from one UuidV7IdGenerator follows creation time at
/// millisecond precision (ties are random).
abstract interface class IdGenerator {
  String newId();
} // production: UUIDv7 (36 chars)

/// RFC 9562 UUIDv7, lowercase, 36 chars. Backed by package:uuid `Uuid().v7()`.
final class UuidV7IdGenerator implements IdGenerator {
  UuidV7IdGenerator({this._clock = const Clock()});

  final Clock _clock;
  static const Uuid _uuid = Uuid();

  @override
  String newId() =>
      _uuid.v7(config: V7Options(_clock.now().millisecondsSinceEpoch, null));
}

/// Deterministic ids for tests: '$prefix-000001', '$prefix-000002', ...
final class SequentialIdGenerator implements IdGenerator {
  SequentialIdGenerator({this._prefix = 'id'});

  final String _prefix;
  int _count = 0;

  @override
  String newId() {
    _count++;
    return '$_prefix-${_count.toString().padLeft(6, '0')}';
  }
}

final RegExp _entityIdPattern = RegExp(r'^[0-9A-Za-z_-]{1,64}$');

bool isValidEntityId(String id) =>
    _entityIdPattern.hasMatch(id); // ^[0-9A-Za-z_-]{1,64}$
