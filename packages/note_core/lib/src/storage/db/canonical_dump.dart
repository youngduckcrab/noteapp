// lib/src/storage/db/canonical_dump.dart (internal) — the canonical dump of a SQLite database
// (m5-7/02-core 6.12.3, 6.12.4): the web v1 copy and the V7 copy hash. Byte-identical to
// tool/src/v1_dump.dart (the V7 fixture tools) for the same database — canonical_dump_test
// compares the two on the V7 fixture and on edge-case tables, and the Chrome test checks the
// web bytes.
//
// Format 'noteapp-v1-dump 1' (UTF-8, every line ends with '\n', the last too):
//
//   noteapp-v1-dump 1
//   #table <table> <column 1>,<column 2>,…
//   <row>
//   …
//
// * Tables in ascending name order (code units), every table of sqlite_master except the
//   `sqlite_` ones, unless a table list is given. Columns in PRAGMA table_info (cid) order,
//   unless a column list is given for that table.
// * One line per row: quote(c1) || ',' || quote(c2) || … — every value as an SQL literal,
//   so the VM library and the web wasm build of the same SQLite give the same bytes. Rows
//   are in the order of that line (BINARY), not rowid (VACUUM INTO may renumber rowids).
// * Paging (this file only — the tool reads a table in one query): when the first dumped
//   column is the table's single NOT NULL primary key, rows are read [pageRows] at a time
//   by the key `quote(c1) || ','`. Those keys are unique and prefix-free (an SQL literal
//   never holds an unquoted ','), so their order is the order of the whole lines and a
//   page never splits rows that compare equal. Only the rows of one page are built as
//   lines (the inner query compares keys only); the next page starts after the key of
//   the last line (firstLiteralOf + ','). Other tables are read in one query.
import 'dart:convert';
import 'dart:typed_data';

/// First line of a dump.
const String kCanonicalDumpHeader = 'noteapp-v1-dump 1';

/// Rows read per query when a table pages by its key (6.12.4 'two thousand rows').
const int kCanonicalDumpPageRows = 2000;

/// Bytes per emitted chunk (6.12.4 '≤ 4 MiB').
const int kCanonicalDumpChunkBytes = 4 * 1024 * 1024;

/// Runs [sql] with [args] and returns the first column of every result row as text (every
/// query of the dump returns non-null text).
typedef CanonicalDumpQuery = Future<List<String>> Function(
  String sql,
  List<Object?> args,
);

/// `"name"` with inner quotes doubled.
String _quoteIdentifier(String name) => '"${name.replaceAll('"', '""')}"';

String _quoteText(String value) => "'${value.replaceAll("'", "''")}'";

/// Every table of the database except SQLite's own, in ascending name order.
Future<List<String>> canonicalDumpTables(CanonicalDumpQuery query) async {
  final names = await query(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
    const [],
  );
  return [
    for (final n in names)
      if (!n.startsWith('sqlite_')) n,
  ]..sort();
}

/// The dump in chunks of [chunkBytes] (the last one shorter; no empty chunk). The bytes of
/// all chunks joined are the dump.
Stream<Uint8List> canonicalDumpChunks(
  CanonicalDumpQuery query, {
  Iterable<String>? tables,
  Map<String, List<String>> columns = const {},
  int pageRows = kCanonicalDumpPageRows,
  int chunkBytes = kCanonicalDumpChunkBytes,
}) async* {
  if (pageRows < 1) throw ArgumentError.value(pageRows, 'pageRows');
  if (chunkBytes < 1) throw ArgumentError.value(chunkBytes, 'chunkBytes');
  final out = _Chunker(chunkBytes);
  out.addLine(kCanonicalDumpHeader);
  final names = tables == null
      ? await canonicalDumpTables(query)
      : ([...tables]..sort());
  for (final table in names) {
    final info = await _tableInfo(query, table);
    final cols = columns[table] ?? [for (final c in info) c.name];
    if (cols.isEmpty) {
      throw StateError('table $table has no columns to dump');
    }
    out.addLine('#table $table ${cols.join(',')}');
    for (final c in out.take()) {
      yield c;
    }
    final line = cols
        .map((c) => 'quote(${_quoteIdentifier(c)})')
        .join(" || ',' || ");
    final t = _quoteIdentifier(table);
    final keyColumn = _pagingKey(info, cols.first);
    if (keyColumn == null) {
      for (final row in await query(
        'SELECT $line FROM $t ORDER BY 1',
        const [],
      )) {
        out.addLine(row);
      }
      for (final c in out.take()) {
        yield c;
      }
      continue;
    }
    final k = _quoteIdentifier(keyColumn);
    final key = "quote($k) || ','";
    String? last;
    while (true) {
      final rows = await query(
        'SELECT $line FROM $t WHERE $k IN (SELECT $k FROM $t'
        '${last == null ? '' : ' WHERE $key > ?'} ORDER BY $key LIMIT $pageRows) '
        'ORDER BY $key',
        [?last],
      );
      for (final row in rows) {
        out.addLine(row);
      }
      for (final c in out.take()) {
        yield c;
      }
      if (rows.length < pageRows) break;
      last = '${firstLiteralOf(rows.last)},';
    }
  }
  for (final c in out.finish()) {
    yield c;
  }
}

/// The whole dump (tests, small databases).
Future<Uint8List> canonicalDump(
  CanonicalDumpQuery query, {
  Iterable<String>? tables,
  Map<String, List<String>> columns = const {},
  int pageRows = kCanonicalDumpPageRows,
}) async {
  final b = BytesBuilder(copy: false);
  await for (final chunk in canonicalDumpChunks(
    query,
    tables: tables,
    columns: columns,
    pageRows: pageRows,
  )) {
    b.add(chunk);
  }
  return b.takeBytes();
}

/// The first SQL literal of a dump line (what quote() wrote for the first column): a text
/// literal up to its closing quote ('' is a quote inside it), a blob literal X'…', or a
/// number / NULL up to the first ','.
String firstLiteralOf(String line) {
  if (line.startsWith("'")) {
    var i = 1;
    while (true) {
      final q = line.indexOf("'", i);
      if (q < 0) throw FormatException('Unterminated text literal', line);
      if (q + 1 < line.length && line.codeUnitAt(q + 1) == 0x27) {
        i = q + 2;
        continue;
      }
      return line.substring(0, q + 1);
    }
  }
  if (line.startsWith("X'")) {
    final q = line.indexOf("'", 2);
    if (q < 0) throw FormatException('Unterminated blob literal', line);
    return line.substring(0, q + 1);
  }
  final c = line.indexOf(',');
  return c < 0 ? line : line.substring(0, c);
}

typedef _Column = ({String name, int pk, bool notNull});

Future<List<_Column>> _tableInfo(CanonicalDumpQuery query, String table) async {
  final rows = await query(
    "SELECT name || ',' || pk || ',' || \"notnull\" FROM "
    'pragma_table_info(${_quoteText(table)}) ORDER BY cid',
    const [],
  );
  return [
    for (final r in rows)
      () {
        final i = r.lastIndexOf(',');
        final j = r.lastIndexOf(',', i - 1);
        return (
          name: r.substring(0, j),
          pk: int.parse(r.substring(j + 1, i)),
          notNull: r.substring(i + 1) == '1',
        );
      }(),
  ];
}

/// The column to page by: [first] when it is the single NOT NULL primary key column.
String? _pagingKey(List<_Column> info, String first) {
  final pks = [
    for (final c in info)
      if (c.pk > 0) c,
  ];
  if (pks.length != 1) return null;
  final pk = pks.single;
  return pk.name == first && pk.notNull ? pk.name : null;
}

/// UTF-8 lines into fixed-size chunks.
final class _Chunker {
  _Chunker(this._size);
  final int _size;
  BytesBuilder _b = BytesBuilder(copy: false);

  void addLine(String line) {
    _b
      ..add(utf8.encode(line))
      ..addByte(0x0A);
  }

  /// The full chunks gathered so far; the rest stays.
  Iterable<Uint8List> take() sync* {
    if (_b.length < _size) return;
    final bytes = _b.takeBytes();
    var start = 0;
    for (; bytes.length - start >= _size; start += _size) {
      yield Uint8List.sublistView(bytes, start, start + _size);
    }
    _b = BytesBuilder(copy: false)..add(Uint8List.sublistView(bytes, start));
  }

  /// Every byte left (no empty chunk).
  Iterable<Uint8List> finish() sync* {
    yield* take();
    if (_b.length > 0) yield _b.takeBytes();
  }
}
