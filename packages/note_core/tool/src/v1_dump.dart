// tool/src/v1_dump.dart — CORE T25a (docs/plans/m5-7/02-core.md 6.12.3, contract
// 00-overview 7.7.2 V7): the canonical dump of a SQLite database, used by the
// V7 fixture tools (make_v1_fixture.dart, v1_fixture_manifest.dart) and the
// fixture guard test. CORE T24 adds the same format to lib/ (internal
// storage/db/canonical_dump.dart — the web v1 copy and the V7 copy hash); its
// output must be byte-identical to this one for the same database.
//
// Format 'noteapp-v1-dump 1' (UTF-8, every line ends with '\n', the last too):
//
//   noteapp-v1-dump 1
//   #table <table> <column 1>,<column 2>,…
//   <row>
//   …
//
// * Tables in ascending name order (code units), every table of sqlite_master
//   except the `sqlite_` ones, unless a table list is given.
// * Columns in PRAGMA table_info order (cid), unless a column list is given
//   for that table (a subset dump — e.g. without the derived columns).
// * One line per row: SELECT quote(c1) || ',' || quote(c2) || … FROM t ORDER
//   BY 1 — SQLite writes every value as an SQL literal (integer 1762300000000,
//   real 0.30000000000000004 / 1.0, text 'it''s 한글', blob X'0102FF', NULL),
//   so the VM library and the web wasm build of the same SQLite produce the
//   same bytes. Rows are ordered by that line (BINARY collation), not by
//   rowid: VACUUM INTO may renumber the rowids of tables without an integer
//   primary key.
// * A newline inside a text value stays inside its quoted literal (the line
//   then spans two lines of the dump, deterministically); the V7 fixture has
//   none (JSON columns are single-line jsonEncode output).
// * Checked on the V7 fixture: the VM library and sqlite3.wasm in Chrome (both
//   SQLite 3.54.1, package:sqlite3 3.8.0) give byte-identical dumps.
import 'dart:convert';
import 'dart:typed_data';

/// First line of a dump.
const String kV1DumpHeader = 'noteapp-v1-dump 1';

/// Runs [sql] and returns the first column of every result row as text (null
/// is never asked for: every query of the dump returns non-null text).
typedef DumpQuery = Future<List<String>> Function(String sql);

/// `"name"` with inner quotes doubled.
String quoteIdentifier(String name) => '"${name.replaceAll('"', '""')}"';

/// Every table of the database except SQLite's own, in ascending name order.
Future<List<String>> dumpTables(DumpQuery query) async {
  final names = await query(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  );
  return [
    for (final n in names)
      if (!n.startsWith('sqlite_')) n,
  ]..sort();
}

/// The columns of [table] in PRAGMA table_info (cid) order.
Future<List<String>> dumpColumns(DumpQuery query, String table) => query(
  'SELECT name FROM pragma_table_info(${_quoteText(table)}) ORDER BY cid',
);

/// The dump of [tables] (null = every table, see [dumpTables]) with the
/// columns of [columns] for the tables it names (others: every column).
Future<Uint8List> canonicalDump(
  DumpQuery query, {
  Iterable<String>? tables,
  Map<String, List<String>> columns = const {},
}) async {
  final out = StringBuffer()
    ..write(kV1DumpHeader)
    ..write('\n');
  final names = tables == null
      ? await dumpTables(query)
      : ([...tables]..sort());
  for (final table in names) {
    final cols = columns[table] ?? await dumpColumns(query, table);
    if (cols.isEmpty) {
      throw StateError('table $table has no columns to dump');
    }
    out
      ..write('#table ')
      ..write(table)
      ..write(' ')
      ..write(cols.join(','))
      ..write('\n');
    final expr = cols
        .map((c) => 'quote(${quoteIdentifier(c)})')
        .join(" || ',' || ");
    final rows = await query(
      'SELECT $expr FROM ${quoteIdentifier(table)} ORDER BY 1',
    );
    for (final row in rows) {
      out
        ..write(row)
        ..write('\n');
    }
  }
  return Uint8List.fromList(utf8.encode(out.toString()));
}

String _quoteText(String value) => "'${value.replaceAll("'", "''")}'";
