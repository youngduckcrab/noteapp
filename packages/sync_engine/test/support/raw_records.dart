// Record bytes the Dart encoder cannot write (07-sync 3.1, S-13 tests): an upsert or a purge
// of a kind this app does not know, as a newer app writes it (codec v1 framing, 6.4.4).
import 'dart:convert';
import 'dart:typed_data';

import 'package:sync_engine/src/codec/canonical_json.dart';
import 'package:sync_engine/src/common/varuint.dart';

/// One upsert record of codec v1: op 0x01, varuint header length, canonical header
/// {"e": [entity], "fv": [fieldVersions], "id": entity id, "k": [kind]}, then the blob count
/// and [blobs] sorted by key (like ChunkCodec.encodeRecord; none by default). [kind] is any
/// name, e.g. 'bookmark'.
Uint8List rawUpsertRecord(
  String kind,
  Map<String, Object?> entity,
  Map<String, Object?> fieldVersions, {
  String idKey = 'id',
  Map<String, Uint8List> blobs = const {},
}) {
  final header = canonicalJsonBytes({
    'e': entity,
    'fv': fieldVersions,
    'id': entity[idKey],
    'k': kind,
  });
  final out = BytesBuilder(copy: false)..addByte(0x01);
  VarUint.write(out, header.length);
  out.add(header);
  final keys = blobs.keys.toList()..sort();
  VarUint.write(out, keys.length);
  for (final key in keys) {
    final k = utf8.encode(key);
    VarUint.write(out, k.length);
    out.add(k);
    VarUint.write(out, blobs[key]!.length);
    out.add(blobs[key]!);
  }
  return out.takeBytes();
}

/// One purge record of codec v1: op 0x02, varuint header length, canonical header
/// {"h": [hlc], "id": [id], "k": [kind]}.
Uint8List rawPurgeRecord(String kind, String id, String hlc) {
  final header = canonicalJsonBytes({'h': hlc, 'id': id, 'k': kind});
  final out = BytesBuilder(copy: false)..addByte(0x02);
  VarUint.write(out, header.length);
  out.add(header);
  return out.takeBytes();
}
