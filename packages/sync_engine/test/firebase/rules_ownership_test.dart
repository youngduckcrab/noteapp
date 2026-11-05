// T17: the security rules and indexes (6.14). fake_cloud_firestore checks rules only for
// document get / set / update / delete, without request.resource, request.time or rule
// functions, and has no `create` method (set is checked as `write`) — 7.3. So the rules run
// here reduced to their ownership part: comments, rules_version and functions removed, each
// condition that starts with isOwner(uid) replaced by isOwner's own body, `create` → `write`.
// Dropping the other conjuncts only widens access, so "another uid's documents and signed
// out → denied" on the reduced rules also holds for the real ones. The source text checks
// that every rule under /users/{uid} starts with isOwner(uid) (or is false), and the key
// lists, chunk id pattern, limits and indexes against what the adapters write. The full
// rules are checked with the emulator or on the project (9.2).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/firebase.dart';
import 'package:sync_engine/src/codec/chunk_id.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

String _read(String name) => File('firebase/$name').readAsStringSync();

String _withoutComments(String rules) =>
    rules.replaceAll(RegExp(r'//[^\n]*'), '');

final RegExp _allow = RegExp(
  r'allow\s+([a-z,\s]+?):\s*if\s+(.*?);',
  dotAll: true,
);

/// The body of `function name(...) { ... }` (quotes may hold braces).
(int, int) _functionAt(String rules, Match start) {
  var depth = 0;
  var quoted = false;
  for (var i = rules.indexOf('{', start.start); i < rules.length; i++) {
    final c = rules[i];
    if (c == "'") quoted = !quoted;
    if (quoted) continue;
    if (c == '{') depth++;
    if (c == '}' && --depth == 0) return (start.start, i + 1);
  }
  throw StateError('unclosed function');
}

String _isOwnerBody(String rules) {
  final m = RegExp(r'function isOwner\(uid\)\s*\{\s*return\s+(.*?);\s*\}')
      .firstMatch(rules)!;
  return m[1]!;
}

/// The ownership part of firestore.rules for fake_cloud_firestore (see the header).
String _ownershipRules(String rules) {
  var s = _withoutComments(rules)
      .replaceFirst(RegExp(r"rules_version = '2';\s*"), '');
  final owner = _isOwnerBody(s);
  final function = RegExp(r'^\s*function\s', multiLine: true);
  for (var m = function.firstMatch(s); m != null; m = function.firstMatch(s)) {
    final (start, end) = _functionAt(s, m);
    s = s.replaceRange(start, end, '');
  }
  return s.replaceAllMapped(_allow, (m) {
    final condition = m[2]!.trim();
    final methods = [
      for (final method in m[1]!.split(','))
        method.trim() == 'create' ? 'write' : method.trim(),
    ].join(', ');
    final reduced = condition.startsWith('isOwner(uid)') ? owner : condition;
    return 'allow $methods: if $reduced;';
  });
}

/// The quoted names of `<prefix>.hasOnly([...])`.
Set<String> _hasOnly(String text) {
  final m = RegExp(r'hasOnly\(\[([^\]]*)\]\)').firstMatch(text)!;
  return {for (final q in RegExp(r"'([^']*)'").allMatches(m[1]!)) q[1]!};
}

/// The text of the `match /<path> {` block up to its first allow rules.
String _block(String rules, String match) =>
    rules.substring(rules.indexOf('match $match {'));

ChunkWrite _chunk(ChunkKind kind) {
  final payload = Uint8List.fromList([1, 2, 3]);
  return ChunkWrite(
    id: chunkIdOf('0123456789abcdef', payload),
    scope: 'lib',
    authorNodeId: '0123456789abcdef',
    recordCount: 1,
    format: 1,
    kind: kind,
    maxHlc: 'h',
    payload: payload,
  );
}

enum _Op { get, set, update, delete }

Future<bool> _allowed(FakeFirebaseFirestore db, String path, _Op op) async {
  final doc = db.doc(path);
  try {
    switch (op) {
      case _Op.get:
        await doc.get();
      case _Op.set:
        await doc.set({'a': 1});
      case _Op.update:
        await doc.update({'a': 2});
      case _Op.delete:
        await doc.delete();
    }
    return true;
  } on Exception catch (e) {
    if ('$e'.contains('is not allowed')) return false;
    rethrow;
  }
}

void main() {
  final rules = _read('firestore.rules');

  test('every rule under /users/{uid} is isOwner(uid) && … or false; '
      'isOwner = signed in with that uid', () {
    expect(
      _isOwnerBody(rules),
      'request.auth != null && request.auth.uid == uid',
    );
    final text = _withoutComments(rules);
    final users = text.substring(text.indexOf('match /users/{uid} {'));
    final allows = _allow.allMatches(users).toList();
    expect(allows, hasLength(10));
    for (final m in allows) {
      final condition = m[2]!.trim();
      expect(
        condition == 'false' ||
            condition == 'isOwner(uid)' ||
            condition.startsWith('isOwner(uid) &&') ||
            condition.startsWith('isOwner(uid)\n'),
        isTrue,
        reason: m[0],
      );
    }
    // Only the users tree is matched (devices and changes are inside
    // /users/{uid}); the profile document is never deleted.
    expect(
      RegExp(r'match (/[^ ]+) \{').allMatches(text).map((m) => m[1]).toList(),
      [
        '/databases/{database}/documents',
        '/users/{uid}',
        '/devices/{nodeId}',
        '/changes/{chunkId}',
      ],
    );
    expect(
      _allow
          .allMatches(_block(text, '/users/{uid}'))
          .firstWhere((m) => m[1]!.trim() == 'delete')[2],
      'false',
    );
  });

  test('ownership on fake_cloud_firestore: own documents allowed; another '
      "uid's documents, other collections and signed out denied", () async {
    final auth = MockFirebaseAuth(mockUser: MockUser(uid: 'alice'));
    final db = FakeFirebaseFirestore(
      securityRules: _ownershipRules(rules),
      authObject: auth.authForFakeFirestore,
    );
    final chunkId = _chunk(ChunkKind.delta).id;
    List<String> docs(String uid) => [
      'users/$uid',
      'users/$uid/devices/0123456789abcdef',
      'users/$uid/changes/$chunkId',
    ];

    for (final path in [...docs('alice'), ...docs('bob'), 'other/x']) {
      for (final op in _Op.values) {
        expect(await _allowed(db, path, op), isFalse, reason: '$op $path');
      }
    }

    await auth.signInWithCredential(null);
    for (final path in docs('alice')) {
      for (final op in [_Op.get, _Op.set, _Op.update]) {
        expect(await _allowed(db, path, op), isTrue, reason: '$op $path');
      }
    }
    for (final path in docs('alice').skip(1)) {
      expect(await _allowed(db, path, _Op.delete), isTrue, reason: path);
    }
    for (final path in [...docs('bob'), 'other/x']) {
      for (final op in _Op.values) {
        expect(await _allowed(db, path, op), isFalse, reason: '$op $path');
      }
    }
  });

  test('chunk rules = what FirestoreChunkMapper writes: fields, kinds, the '
      'chunk id pattern and its author prefix', () {
    final text = _withoutComments(rules);
    final valid = text.substring(text.indexOf('function validChunk()'));
    final fields = _hasOnly(valid);
    for (final kind in ChunkKind.values) {
      final doc = FirestoreChunkMapper.toFirestore(_chunk(kind));
      expect(doc.keys.toSet(), fields);
      expect(valid, contains("'${doc['kind']}'"));
    }
    expect(valid, contains("d.kind in ['delta', 'snapshot']"));

    final changes = _block(text, '/changes/{chunkId}');
    final pattern = RegExp(r"chunkId\.matches\('([^']*)'\)")
        .firstMatch(changes)![1]!;
    final chunk = _chunk(ChunkKind.delta);
    expect(RegExp(pattern).hasMatch(chunk.id), isTrue, reason: chunk.id);
    expect(chunk.id.split('-').first, chunk.authorNodeId);
    expect(
      changes,
      contains("chunkId.split('-')[0] == request.resource.data.by"),
    );
    // A lost-ack retry rewrites only su.
    expect(changes, contains("affectedKeys().hasOnly(['su'])"));
  });

  test('profile and device documents written by FirebaseSyncBackend use only '
      'the keys the rules allow', () async {
    final db = FakeFirebaseFirestore();
    final backend = FirebaseSyncBackend(
      firestore: db,
      blobs: FakeSyncServer(clock: const Clock()).blobsOf('alice'),
      uid: 'alice',
    );
    await backend.upsertProfile(
      const UserProfile(uid: 'alice', email: 'a@b.c', displayName: 'A'),
    );
    await backend.upsertDevice(
      const DeviceInfo(
        nodeId: '0123456789abcdef',
        platform: DevicePlatform.web,
        appVersion: '1.0.0',
        cursor: ServerCursor(42),
      ),
    );
    final text = _withoutComments(rules);
    final profile = (await db.doc('users/alice').get()).data()!;
    expect(_hasOnly(_block(text, '/users/{uid}')), containsAll(profile.keys));
    final device = (await db.doc('users/alice/devices/0123456789abcdef').get())
        .data()!;
    expect(
      _hasOnly(_block(text, '/devices/{nodeId}')),
      containsAll(device.keys),
    );
    expect(
      RegExp(r"nodeId\.matches\('([^']*)'\)")
          .firstMatch(_block(text, '/devices/{nodeId}'))![1],
      r'^[0-9a-f]{16}$',
    );
    await backend.close();
  });

  test('storage rules: the FirebaseBlobStore path, the upload limit and the '
      'sha256 metadata', () {
    final storage = _withoutComments(_read('storage.rules'));
    expect(storage, contains('match /users/{uid}/assets/{assetId} {'));
    const id =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    expect(
      FakeSyncServer(clock: const Clock()).blobsOf('alice').pathFor(id),
      'users/alice/assets/$id',
    );
    final limit = RegExp(r'request\.resource\.size <= (\d+) \* (\d+) \* (\d+)')
        .firstMatch(storage)!;
    expect(
      int.parse(limit[1]!) * int.parse(limit[2]!) * int.parse(limit[3]!),
      const SyncConfig().maxAssetUploadBytes,
    );
    expect(storage, contains("assetId.matches('^[0-9a-f]{64}\$')"));
    expect(storage, contains('request.resource.metadata.sha256 == assetId'));
    expect(storage, contains('allow update: if false;'));
    for (final m in _allow.allMatches(storage)) {
      final condition = m[2]!.trim();
      expect(
        condition == 'false' ||
            condition.startsWith(
              'request.auth != null && request.auth.uid == uid',
            ),
        isTrue,
        reason: m[0],
      );
    }
  });

  test('indexes: changes (scope, su) for fetchScope; the other chunk fields '
      'are not indexed', () {
    final json =
        jsonDecode(_read('firestore.indexes.json')) as Map<String, Object?>;
    final indexes = (json['indexes']! as List).cast<Map<String, Object?>>();
    expect(indexes, hasLength(1));
    expect(indexes.single['collectionGroup'], FirestoreChunkMapper.collection);
    expect(indexes.single['queryScope'], 'COLLECTION');
    expect(indexes.single['fields'], [
      {'fieldPath': 'scope', 'order': 'ASCENDING'},
      {'fieldPath': 'su', 'order': 'ASCENDING'},
    ]);
    final overrides = (json['fieldOverrides']! as List)
        .cast<Map<String, Object?>>();
    for (final o in overrides) {
      expect(o['collectionGroup'], FirestoreChunkMapper.collection);
      expect(o['indexes'], isEmpty);
    }
    final chunkFields = FirestoreChunkMapper.toFirestore(
      _chunk(ChunkKind.delta),
    ).keys.toSet();
    expect({
      for (final o in overrides) o['fieldPath'],
    }, chunkFields.difference({'scope', 'su'}));
  });
}
