// Internal (not exported). Change chunk payload, binary format v1 (6.4.4):
//
//   'N' 'C' 0x01, varuint recordCount (1..5000), records, no trailing bytes
//   record: op 0x01 upsert | 0x02 purge, varuint headerLen (1..1,000,000), header (UTF-8
//           canonical JSON), upsert only: varuint blobCount (0..4), per blob varuint keyLen,
//           key, varuint dataLen, data
//   upsert header {"e": entity JSON without blob keys, "fv": field versions, "id", "k"}
//   purge header  {"h": hlc, "id", "k": "folder" | "note"}
//   blob keys: stroke "points" (CORE base64 decoded to raw bytes; decode re-encodes base64)
//
// (2nd round, S-13 — 07-sync 6.3.1) decodeTolerant: a well-formed record whose header kind
// 'k' this app does not know becomes an UnknownKindRecord holding its exact bytes, so the
// rest of the chunk applies and the record can be held until the app is updated.
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart';

import '../common/varuint.dart';
import '../model/records.dart';
import '../model/sync_doc.dart';
import 'canonical_json.dart';

/// A well-formed record whose header kind 'k' this app does not know (S-13).
@immutable
final class UnknownKindRecord {
  const UnknownKindRecord({
    required this.kindName,
    required this.op,
    required this.id,
    required this.header,
    required this.bytes,
    required this.index,
  });

  /// Header 'k'.
  final String kindName;

  /// 0x01 upsert | 0x02 purge.
  final int op;

  /// Header 'id' when it is a string (always, for a record decodeTolerant returns).
  final String? id;

  /// The record header JSON (the contract's rawJson).
  final Map<String, Object?> header;

  /// The exact encoded record: op, header, blobs.
  final Uint8List bytes;

  /// Position in the payload (0-based).
  final int index;

  @override
  String toString() => 'UnknownKindRecord($kindName, $id, op $op, #$index)';
}

/// What [ChunkCodec.decodeTolerant] returns.
@immutable
final class DecodedPayload {
  const DecodedPayload(this.records, this.unknown);

  /// Known kinds, payload order.
  final List<SyncRecord> records;

  /// Payload order.
  final List<UnknownKindRecord> unknown;

  bool get hasUnknown => unknown.isNotEmpty;
}

abstract final class ChunkCodec {
  static const int formatVersion = 1;
  static const int maxRecords = 5000;
  static const int maxHeaderBytes = 1000000;
  static const int maxBlobs = 4;

  static const int _opUpsert = 0x01;
  static const int _opPurge = 0x02;

  /// JSON keys carried as raw blobs per kind (base64 text in CORE JSON).
  static const Map<EntityKind, List<String>> blobKeys = {
    EntityKind.stroke: ['points'],
  };

  /// Payload of [records] in the given order. ArgumentError when empty or > [maxRecords].
  static Uint8List encode(List<SyncRecord> records) =>
      assemble([for (final r in records) encodeRecord(r)]);

  /// Payload from already encoded records ([encodeRecord]), in the given order.
  static Uint8List assemble(List<Uint8List> encodedRecords) {
    final n = encodedRecords.length;
    if (n < 1 || n > maxRecords) {
      throw ArgumentError.value(n, 'records', 'must hold 1..$maxRecords');
    }
    final out = BytesBuilder(copy: false)
      ..addByte(0x4E)
      ..addByte(0x43)
      ..addByte(formatVersion);
    VarUint.write(out, n);
    for (final r in encodedRecords) {
      out.add(r);
    }
    return out.takeBytes();
  }

  /// Payload length of a chunk whose encoded records total [recordBytes] bytes.
  static int payloadLength(int recordCount, int recordBytes) =>
      3 + VarUint.lengthOf(recordCount) + recordBytes;

  /// The bytes of one record as [encode] writes them.
  static Uint8List encodeRecord(SyncRecord record) {
    final out = BytesBuilder(copy: false);
    switch (record) {
      case UpsertRecord(:final doc, :final versions):
        final keys = blobKeys[doc.kind] ?? const <String>[];
        final entity = <String, Object?>{};
        final blobs = <(String, Uint8List)>[];
        for (final e in doc.json.entries) {
          final value = e.value;
          if (keys.contains(e.key) && value is String) {
            blobs.add((e.key, base64Decode(value)));
          } else {
            entity[e.key] = value;
          }
        }
        blobs.sort((a, b) => a.$1.compareTo(b.$1));
        final header = canonicalJsonBytes({
          'e': entity,
          'fv': versions.toJson(),
          'id': doc.id,
          'k': doc.kind.name,
        });
        _writeHeader(out, _opUpsert, header);
        VarUint.write(out, blobs.length);
        for (final (key, data) in blobs) {
          final k = utf8.encode(key);
          VarUint.write(out, k.length);
          out.add(k);
          VarUint.write(out, data.length);
          out.add(data);
        }
      case PurgeRecord(:final ref, :final hlc):
        if (ref.kind != EntityKind.folder && ref.kind != EntityKind.note) {
          throw ArgumentError.value(ref, 'purge', 'only folder or note');
        }
        final header = canonicalJsonBytes({
          'h': hlc.toString(),
          'id': ref.id,
          'k': ref.kind.name,
        });
        _writeHeader(out, _opPurge, header);
    }
    return out.takeBytes();
  }

  static void _writeHeader(BytesBuilder out, int op, Uint8List header) {
    if (header.length > maxHeaderBytes) {
      throw ArgumentError.value(
        header.length,
        'header',
        'longer than $maxHeaderBytes bytes',
      );
    }
    out.addByte(op);
    VarUint.write(out, header.length);
    out.add(header);
  }

  /// Records of a v1 payload, in payload order. FormatException on any malformed input
  /// (magic, version, count, lengths, trailing bytes, headers — 6.4.4), an unknown kind
  /// included.
  static List<SyncRecord> decode(Uint8List bytes) =>
      _decode(bytes, isKnownKind: null).records;

  /// (v2.0) decode() with S-13: a record whose 'k' fails [isKnownKind] (default: an
  /// EntityKind name) becomes an UnknownKindRecord; its header must still be a JSON object
  /// with string 'k' (and string 'id' for an upsert). Any other malformation still throws
  /// FormatException for the whole chunk (v1.4).
  ///
  /// An unknown upsert also needs object 'e' and 'fv' and well-formed blobs; an unknown purge
  /// needs string 'id' and 'h'. A name [isKnownKind] accepts that is not an EntityKind name
  /// cannot be decoded and is unknown as well.
  static DecodedPayload decodeTolerant(
    Uint8List bytes, {
    bool Function(String kindName)? isKnownKind,
  }) => _decode(bytes, isKnownKind: isKnownKind ?? _everyKind);

  /// With the EntityKind check of [_decode]: every EntityKind name.
  static bool _everyKind(String name) => true;

  /// [isKnownKind] null = strict (v1.4): an unknown kind is a FormatException.
  static DecodedPayload _decode(
    Uint8List bytes, {
    required bool Function(String kindName)? isKnownKind,
  }) {
    if (bytes.length < 4 || bytes[0] != 0x4E || bytes[1] != 0x43) {
      throw const FormatException('chunk: bad magic');
    }
    if (bytes[2] != formatVersion) {
      throw FormatException('chunk: format ${bytes[2]} is not $formatVersion');
    }
    var (count, i) = VarUint.read(bytes, 3);
    if (count < 1 || count > maxRecords) {
      throw FormatException('chunk: record count $count');
    }
    final records = <SyncRecord>[];
    final unknown = <UnknownKindRecord>[];
    for (var r = 0; r < count; r++) {
      if (i >= bytes.length) throw FormatException('chunk: record $r missing');
      final start = i;
      final op = bytes[i++];
      if (op != _opUpsert && op != _opPurge) {
        throw FormatException('chunk: unknown op $op');
      }
      final int headerLen;
      (headerLen, i) = VarUint.read(bytes, i);
      if (headerLen < 1 || headerLen > maxHeaderBytes) {
        throw FormatException('chunk: header length $headerLen');
      }
      final header = _jsonObject(_take(bytes, i, headerLen));
      i += headerLen;
      final kindName = _string(header, 'k');
      final known =
          isKnownKind == null ||
          (_kindOrNull(kindName) != null && isKnownKind(kindName));
      if (op == _opPurge) {
        if (known) {
          records.add(_purge(header));
        } else {
          final id = _string(header, 'id');
          _string(header, 'h');
          unknown.add(_unknown(kindName, op, id, header, bytes, start, i, r));
        }
        continue;
      }
      if (!known) {
        _string(header, 'id');
        _object(header, 'e');
        _object(header, 'fv');
      }
      final int blobCount;
      (blobCount, i) = VarUint.read(bytes, i);
      if (blobCount > maxBlobs) {
        throw FormatException('chunk: $blobCount blobs');
      }
      final blobs = <String, String>{};
      for (var b = 0; b < blobCount; b++) {
        final int keyLen;
        (keyLen, i) = VarUint.read(bytes, i);
        final key = _utf8(_take(bytes, i, keyLen));
        i += keyLen;
        final int dataLen;
        (dataLen, i) = VarUint.read(bytes, i);
        final data = _take(bytes, i, dataLen);
        if (known) blobs[key] = base64Encode(data);
        i += dataLen;
      }
      if (known) {
        records.add(_upsert(header, blobs));
      } else {
        final id = header['id']! as String;
        unknown.add(_unknown(kindName, op, id, header, bytes, start, i, r));
      }
    }
    if (i != bytes.length) {
      throw FormatException('chunk: ${bytes.length - i} trailing bytes');
    }
    return DecodedPayload(records, unknown);
  }

  static UnknownKindRecord _unknown(
    String kindName,
    int op,
    String id,
    Map<String, Object?> header,
    Uint8List bytes,
    int start,
    int end,
    int index,
  ) => UnknownKindRecord(
    kindName: kindName,
    op: op,
    id: id,
    header: header,
    bytes: Uint8List.fromList(Uint8List.sublistView(bytes, start, end)),
    index: index,
  );

  static Uint8List _take(Uint8List bytes, int offset, int length) {
    if (offset + length > bytes.length) {
      throw const FormatException('chunk: bytes end early');
    }
    return Uint8List.sublistView(bytes, offset, offset + length);
  }

  static String _utf8(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw const FormatException('chunk: invalid UTF-8');
    }
  }

  static Map<String, Object?> _jsonObject(Uint8List bytes) {
    final Object? value;
    try {
      value = jsonDecode(_utf8(bytes));
    } on FormatException {
      throw const FormatException('chunk: header is not JSON');
    }
    if (value is! Map<String, Object?>) {
      throw const FormatException('chunk: header is not an object');
    }
    return value;
  }

  static EntityKind _kind(Object? name) =>
      _kindOrNull(name) ?? (throw FormatException('chunk: unknown kind', name));

  static EntityKind? _kindOrNull(Object? name) {
    for (final k in EntityKind.values) {
      if (k.name == name) return k;
    }
    return null;
  }

  static Map<String, Object?> _object(Map<String, Object?> header, String key) {
    final v = header[key];
    if (v is! Map<String, Object?>) {
      throw FormatException('chunk: header "$key" missing');
    }
    return v;
  }

  static String _string(Map<String, Object?> header, String key) {
    final v = header[key];
    if (v is! String) throw FormatException('chunk: header "$key" missing');
    return v;
  }

  static PurgeRecord _purge(Map<String, Object?> header) {
    final kind = _kind(_string(header, 'k'));
    if (kind != EntityKind.folder && kind != EntityKind.note) {
      throw FormatException('chunk: purge of ${kind.name}');
    }
    return PurgeRecord(
      EntityRef(kind, _string(header, 'id')),
      Hlc.parse(_string(header, 'h')),
    );
  }

  static UpsertRecord _upsert(
    Map<String, Object?> header,
    Map<String, String> blobs,
  ) {
    final kind = _kind(_string(header, 'k'));
    final id = _string(header, 'id');
    final e = _object(header, 'e');
    final fv = _object(header, 'fv');
    final idKey = kind == EntityKind.setting ? 'key' : 'id';
    if (e[idKey] != id) {
      throw FormatException('chunk: e.$idKey != id', id);
    }
    final json = <String, Object?>{...e, ...blobs};
    return UpsertRecord(
      SyncDoc(kind: kind, id: id, json: json),
      EntityFieldVersions.fromJson(fv),
    );
  }

  /// Newest record HLC (ChunkWrite.maxHlc). ArgumentError when empty.
  static Hlc maxHlcOf(Iterable<SyncRecord> records) {
    Hlc? m;
    for (final r in records) {
      final v = switch (r) {
        UpsertRecord(:final versions) => versions.max,
        PurgeRecord(:final hlc) => hlc,
      };
      if (m == null || v > m) m = v;
    }
    if (m == null) throw ArgumentError.value(records, 'records', 'is empty');
    return m;
  }
}
