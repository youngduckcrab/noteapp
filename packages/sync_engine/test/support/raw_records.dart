// Record bytes the Dart encoder cannot write (07-sync 3.1, S-13 tests): an upsert of a
// kind this app does not know, as a newer app writes it (codec v1 framing, 6.4.4).
import 'dart:typed_data';

import 'package:sync_engine/src/codec/canonical_json.dart';
import 'package:sync_engine/src/common/varuint.dart';

/// One upsert record of codec v1: op 0x01, varuint header length, canonical header
/// {"e": [entity], "fv": [fieldVersions], "id": entity id, "k": [kind]}, blob count 0.
/// [kind] is any name, e.g. 'bookmark'.
Uint8List rawUpsertRecord(
  String kind,
  Map<String, Object?> entity,
  Map<String, Object?> fieldVersions, {
  String idKey = 'id',
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
  VarUint.write(out, 0);
  return out.takeBytes();
}
