// lib/src/assets/file_blob_store_native.dart (internal) — the native file blobs of one note
// store (m5-7/02-core 6.15.3, 공통-1). connect_native.dart opens it when the config has both
// nativeDatabasePath and nativeAssetDirectoryPath; VM tests may open it on a temporary
// directory (openTestNoteStore keeps the in-memory IndexedDB of the 1st round).
//
// Layout under the root directory <dir>:
//   <dir>/blobs/<key>            one file per key; the '/' of a key are subdirectories
//                                ('<assetId>/000003', 'rd/<draftId>/000012', 'si/pdf/…')
//   <dir>/thumbs/<pageId>.bin    rev, width, height (uint32 LE each), MIME length (uint16 LE),
//                                MIME (UTF-8), the image bytes
// A write goes to '.<name>.tmp-<token>' in the same directory, is flushed and then renamed
// over the target, so a key is either all there or not there (the 1st-round 'one IndexedDB
// value is atomic'). Names that start with '.' are never keys: open deletes the temporary
// files an interrupted write left. The operations of one store run one at a time in call
// order (like the read-write transactions of one IndexedDB object store).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../common/ids.dart';
import 'asset_store.dart';
import 'blob_store.dart';

/// The subdirectory of the keyed values (6.15.3).
const String kFileBlobsDirectory = 'blobs';

/// The subdirectory of the page thumbnails (6.15.3).
const String kFileThumbnailsDirectory = 'thumbs';

/// The file name extension of a thumbnail.
const String kThumbnailFileExtension = '.bin';

/// The marker in the name of a temporary file (6.15.3 `.<name>.tmp-<random>`).
const String kTemporaryFileMarker = '.tmp-';

/// Bytes before the MIME type in a thumbnail file: rev, width, height, MIME length.
const int kThumbnailHeaderBytes = 14;

const int _maxUint32 = 0xFFFFFFFF;
const int _maxUint16 = 0xFFFF;

/// The file blobs of one note store under [root].
final class FileBlobDatabase implements BlobDatabase {
  FileBlobDatabase._(this.root)
    : blobsDirectory = Directory('$root/$kFileBlobsDirectory'),
      thumbnailsDirectory = Directory('$root/$kFileThumbnailsDirectory');

  /// Makes [root] and its 'blobs' and 'thumbs' subdirectories when they are missing,
  /// checks that each takes a write, and deletes the temporary files an interrupted write
  /// left (6.15.3). Throws the FileSystemException of a directory that cannot be made or
  /// written (connect_native.dart reports it as storageUnavailable).
  static Future<FileBlobDatabase> open(String root) async {
    final db = FileBlobDatabase._(root);
    for (final dir in [db.blobsDirectory, db.thumbnailsDirectory]) {
      await dir.create(recursive: true);
      await _checkWritable(dir);
      await removeTemporaryFiles(dir);
    }
    return db;
  }

  /// The root directory (NoteStoreConfig.nativeAssetDirectoryPath).
  final String root;
  final Directory blobsDirectory;
  final Directory thumbnailsDirectory;
  bool _closed = false;

  @override
  late final BlobStore chunks = _FileBlobStore(this);
  @override
  late final ThumbnailStore thumbnails = _FileThumbnailStore(this);

  final _Serial _chunkOps = _Serial();
  final _Serial _thumbnailOps = _Serial();

  /// Operations already called still finish; later ones fail with StateError.
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await Future.wait([_chunkOps.idle(), _thumbnailOps.idle()]);
  }

  Future<T> _run<T>(_Serial ops, Future<T> Function() body) {
    if (_closed) {
      return Future.error(StateError('The blob database is closed'));
    }
    return ops.run(body);
  }
}

/// Deletes every temporary file (a name that starts with '.' and holds '.tmp-') under
/// [dir]; a missing directory has none.
Future<int> removeTemporaryFiles(Directory dir) async {
  var removed = 0;
  if (!dir.existsSync()) return 0;
  await for (final e in dir.list(recursive: true, followLinks: false)) {
    if (e is! File || !_isTemporaryName(_baseName(e.path))) continue;
    try {
      await e.delete();
      removed++;
    } on PathNotFoundException {
      // Gone already.
    }
  }
  return removed;
}

bool _isTemporaryName(String name) =>
    name.startsWith('.') && name.contains(kTemporaryFileMarker);

String _baseName(String path) => path.substring(path.lastIndexOf('/') + 1);

final Random _random = Random.secure();
int _tokenCount = 0;

/// A temporary file name for [name] in its directory.
String _temporaryName(String name) {
  _tokenCount = (_tokenCount + 1) & 0x3FFFFFFF;
  final token =
      '${_random.nextInt(0x7FFFFFFF).toRadixString(16)}'
      '${_tokenCount.toRadixString(16)}';
  return '.$name$kTemporaryFileMarker$token';
}

/// A file write probe in [dir] (a read-only directory fails here, not at the first put).
Future<void> _checkWritable(Directory dir) async {
  final probe = File('${dir.path}/${_temporaryName('probe')}');
  await probe.writeAsBytes(const [0], flush: true);
  await probe.delete();
}

/// Writes [bytes] to [target] through a flushed temporary file in the same directory
/// and a rename (6.15.3 atomic write); the temporary file is deleted on failure.
Future<void> _writeAtomically(File target, List<int> bytes) async {
  final parent = target.parent;
  final tmp = File('${parent.path}/${_temporaryName(_baseName(target.path))}');
  try {
    await parent.create(recursive: true);
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(target.path);
  } on Object {
    try {
      if (tmp.existsSync()) await tmp.delete();
    } on Object {
      // The write error is the one to report; open removes the file later.
    }
    rethrow;
  }
}

/// The bytes of [file]; null when there is no such file (a directory is not one).
Future<Uint8List?> _readFile(File file) async {
  try {
    return await file.readAsBytes();
  } on PathNotFoundException {
    return null;
  } on FileSystemException {
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    rethrow;
  }
}

/// Whether [segment] can be one '/'-separated part of a stored key: not empty, not
/// starting with '.' (temporary files, '.', '..'), no backslash or NUL.
bool _isKeySegment(String segment) =>
    segment.isNotEmpty &&
    !segment.startsWith('.') &&
    !segment.contains(r'\') &&
    !segment.contains('\u0000');

bool _isKey(String key) => key.split('/').every(_isKeySegment);

/// The directory part of [prefix] (up to and with its last '/') and the rest; null when
/// the directory part cannot hold keys (then nothing starts with [prefix]).
(String dir, String name)? _splitPrefix(String prefix) {
  final i = prefix.lastIndexOf('/');
  final dir = prefix.substring(0, i + 1);
  final name = prefix.substring(i + 1);
  if (dir.isNotEmpty &&
      !dir.substring(0, dir.length - 1).split('/').every(_isKeySegment)) {
    return null;
  }
  if (name.contains(r'\') || name.contains('\u0000')) return null;
  return (dir, name);
}

final class _FileBlobStore implements BlobStore {
  _FileBlobStore(this._db);
  final FileBlobDatabase _db;

  Directory get _root => _db.blobsDirectory;

  File _fileOf(String key) => File('${_root.path}/$key');

  Future<T> _run<T>(Future<T> Function() body) => _db._run(_db._chunkOps, body);

  @override
  Future<void> put(String key, Uint8List bytes) {
    if (!_isKey(key)) {
      return Future.error(
        ArgumentError.value(
          key,
          'key',
          'not a file blob key (6.15.3: non-empty segments that do not start '
              'with ".")',
        ),
      );
    }
    // A copy now, like IndexedDB's clone at put: the caller may reuse its buffer.
    final copy = Uint8List.fromList(bytes);
    return _run(() => _writeAtomically(_fileOf(key), copy));
  }

  @override
  Future<Uint8List?> get(String key) =>
      _run(() async => _isKey(key) ? _readFile(_fileOf(key)) : null);

  @override
  Future<List<Uint8List?>> getMany(List<String> keys) async {
    if (keys.isEmpty) return const [];
    return _run(
      () => Future.wait([
        for (final k in keys)
          _isKey(k) ? _readFile(_fileOf(k)) : Future<Uint8List?>.value(),
      ]),
    );
  }

  @override
  Future<void> delete(String key) => _run(() async {
    if (!_isKey(key)) return;
    final file = _fileOf(key);
    try {
      await file.delete();
    } on PathNotFoundException {
      return;
    } on FileSystemException {
      // A directory is not a key: nothing to delete.
      if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return;
      }
      rethrow;
    }
    await _pruneEmptyParents(file.parent);
  });

  /// Removes the empty directories from [dir] up to (not including) the blobs root.
  Future<void> _pruneEmptyParents(Directory dir) async {
    var d = dir;
    while (d.path.length > _root.path.length &&
        d.path.startsWith('${_root.path}/')) {
      try {
        await d.delete();
      } on FileSystemException {
        return; // Not empty (or gone): stop.
      }
      d = d.parent;
    }
  }

  @override
  Future<void> deletePrefix(String prefix) => _run(() async {
    final split = _splitPrefix(prefix);
    if (split == null) return;
    final (dirPart, namePrefix) = split;
    final dir = dirPart.isEmpty
        ? _root
        : Directory(
            '${_root.path}/${dirPart.substring(0, dirPart.length - 1)}',
          );
    if (namePrefix.isEmpty && dirPart.isNotEmpty) {
      try {
        await dir.delete(recursive: true);
      } on PathNotFoundException {
        return;
      }
      await _pruneEmptyParents(dir.parent);
      return;
    }
    for (final e in await _children(dir)) {
      final name = _baseName(e.path);
      if (name.startsWith('.') || !name.startsWith(namePrefix)) continue;
      try {
        await e.delete(recursive: true);
      } on PathNotFoundException {
        // Gone already.
      }
    }
    if (dir.path != _root.path) await _pruneEmptyParents(dir);
  });

  @override
  Future<List<String>> keys(String prefix) => _run(() async {
    final split = _splitPrefix(prefix);
    if (split == null) return const <String>[];
    final (dirPart, namePrefix) = split;
    final dir = dirPart.isEmpty
        ? _root
        : Directory(
            '${_root.path}/${dirPart.substring(0, dirPart.length - 1)}',
          );
    final out = <String>[];
    for (final e in await _children(dir)) {
      final name = _baseName(e.path);
      if (name.startsWith('.') || !name.startsWith(namePrefix)) continue;
      if (e is File) {
        out.add('$dirPart$name');
      } else if (e is Directory) {
        await _collectFiles(e, '$dirPart$name/', out);
      }
    }
    return out..sort();
  });

  /// The entries directly in [dir]; empty when it is missing.
  Future<List<FileSystemEntity>> _children(Directory dir) async {
    try {
      return await dir.list(followLinks: false).toList();
    } on PathNotFoundException {
      return const [];
    }
  }

  /// Adds the key of every file under [dir] ([keyPrefix] = its key path with '/').
  Future<void> _collectFiles(
    Directory dir,
    String keyPrefix,
    List<String> out,
  ) async {
    for (final e in await _children(dir)) {
      final name = _baseName(e.path);
      if (name.startsWith('.')) continue;
      if (e is File) {
        out.add('$keyPrefix$name');
      } else if (e is Directory) {
        await _collectFiles(e, '$keyPrefix$name/', out);
      }
    }
  }
}

/// The thumbnail file name of [pageId]: percent-encoded (no '/'), never starting with '.'.
String thumbnailFileNameOf(PageId pageId) {
  final encoded = Uri.encodeComponent(pageId);
  final safe = encoded.startsWith('.') ? '%2E${encoded.substring(1)}' : encoded;
  return '$safe$kThumbnailFileExtension';
}

/// The bytes of a thumbnail file (6.15.3 header).
Uint8List encodeThumbnailFile(PageThumbnail t) {
  for (final (name, value) in [
    ('contentRevision', t.contentRevision),
    ('width', t.width),
    ('height', t.height),
  ]) {
    if (value < 0 || value > _maxUint32) {
      throw ArgumentError.value(value, name, 'not a uint32 (6.15.3)');
    }
  }
  final mime = utf8.encode(t.mimeType);
  if (mime.length > _maxUint16) {
    throw ArgumentError.value(t.mimeType, 'mimeType', 'too long');
  }
  final out = Uint8List(kThumbnailHeaderBytes + mime.length + t.bytes.length);
  ByteData.sublistView(out)
    ..setUint32(0, t.contentRevision, Endian.little)
    ..setUint32(4, t.width, Endian.little)
    ..setUint32(8, t.height, Endian.little)
    ..setUint16(12, mime.length, Endian.little);
  out
    ..setRange(kThumbnailHeaderBytes, kThumbnailHeaderBytes + mime.length, mime)
    ..setRange(kThumbnailHeaderBytes + mime.length, out.length, t.bytes);
  return out;
}

/// The thumbnail of [pageId] in [bytes]; null when they are not a thumbnail file (the
/// cache then reads as empty for that page, like the IndexedDB store).
PageThumbnail? decodeThumbnailFile(PageId pageId, Uint8List bytes) {
  if (bytes.length < kThumbnailHeaderBytes) return null;
  final data = ByteData.sublistView(bytes);
  final mimeLength = data.getUint16(12, Endian.little);
  final start = kThumbnailHeaderBytes + mimeLength;
  if (start > bytes.length) return null;
  final String mime;
  try {
    mime = utf8.decode(
      Uint8List.sublistView(bytes, kThumbnailHeaderBytes, start),
    );
  } on FormatException {
    return null;
  }
  return PageThumbnail(
    pageId: pageId,
    contentRevision: data.getUint32(0, Endian.little),
    width: data.getUint32(4, Endian.little),
    height: data.getUint32(8, Endian.little),
    mimeType: mime,
    bytes: Uint8List.fromList(Uint8List.sublistView(bytes, start)),
  );
}

final class _FileThumbnailStore implements ThumbnailStore {
  _FileThumbnailStore(this._db);
  final FileBlobDatabase _db;

  Directory get _root => _db.thumbnailsDirectory;

  File _fileOf(PageId pageId) =>
      File('${_root.path}/${thumbnailFileNameOf(pageId)}');

  Future<T> _run<T>(Future<T> Function() body) =>
      _db._run(_db._thumbnailOps, body);

  @override
  Future<void> put(PageThumbnail thumbnail) {
    final Uint8List bytes;
    try {
      bytes = encodeThumbnailFile(thumbnail);
    } on ArgumentError catch (e) {
      return Future.error(e);
    }
    return _run(() => _writeAtomically(_fileOf(thumbnail.pageId), bytes));
  }

  @override
  Future<PageThumbnail?> get(PageId pageId) => _run(() async {
    final bytes = await _readFile(_fileOf(pageId));
    return bytes == null ? null : decodeThumbnailFile(pageId, bytes);
  });

  @override
  Future<void> delete(Iterable<PageId> pageIds) {
    final ids = pageIds.toList();
    if (ids.isEmpty) return Future.value();
    return _run(() async {
      for (final id in ids) {
        try {
          await _fileOf(id).delete();
        } on PathNotFoundException {
          // Not cached.
        }
      }
    });
  }

  @override
  Future<int> totalBytes() => _run(() async {
    var total = 0;
    final List<FileSystemEntity> files;
    try {
      files = await _root.list(followLinks: false).toList();
    } on PathNotFoundException {
      return 0;
    }
    for (final e in files) {
      final name = _baseName(e.path);
      if (e is! File ||
          name.startsWith('.') ||
          !name.endsWith(kThumbnailFileExtension)) {
        continue;
      }
      total += await _imageBytesOf(e);
    }
    return total;
  });

  /// The image byte count of the thumbnail file [file] (its header only is read).
  Future<int> _imageBytesOf(File file) async {
    final RandomAccessFile raf;
    try {
      raf = await file.open();
    } on PathNotFoundException {
      return 0;
    }
    try {
      final length = await raf.length();
      final head = await raf.read(kThumbnailHeaderBytes);
      if (head.length < kThumbnailHeaderBytes) return 0;
      final mimeLength = ByteData.sublistView(head)
          .getUint16(12, Endian.little);
      final image = length - kThumbnailHeaderBytes - mimeLength;
      return image < 0 ? 0 : image;
    } finally {
      await raf.close();
    }
  }
}

/// Runs bodies one at a time in call order.
final class _Serial {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() body) {
    final result = _tail.then((_) => body());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// Completes when every body called so far has finished.
  Future<void> idle() => _tail;
}
