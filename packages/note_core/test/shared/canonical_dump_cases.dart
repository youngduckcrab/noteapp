// Edge-case tables of the canonical dump (CORE T24, m5-7/02-core 6.12.3): the same tables and
// the same expected bytes on the VM (test/storage/canonical_dump_test.dart, also against the
// T25a tool) and in Chrome (test/web/canonical_dump_browser_test.dart, sqlite3.wasm).
// Web-safe.
// SQL statements are written as adjacent literals with SQL quotes inside.
// ignore_for_file: no_adjacent_strings_in_list, prefer_single_quotes

/// Creates and fills the edge tables (one statement each).
const List<String> kDumpEdgeStatements = [
  // Text keys where one is a prefix of another and the next character sorts below the
  // quote (0x27): the line order is the order of quote(id)||',' (6.12.3), not of id.
  'CREATE TABLE edge_text (id TEXT NOT NULL PRIMARY KEY, v)',
  "INSERT INTO edge_text VALUES ('ab', 1), ('ab!', 2), ('ab''', 3), ('ab ', 4), "
      "('a', 5), ('한글', 6), ('it''s 한글', 7), ('ab' || char(10) || 'c', 8), ('', 9), "
      "('ab#', 10), ('ab%', 11), ('ab&', 12), ('ab(', 13), ('ab''''x', 14)",
  // Integer keys sort as text in the dump ('10' < '9').
  'CREATE TABLE edge_int (seq INTEGER NOT NULL PRIMARY KEY, r REAL, b BLOB, t TEXT)',
  "INSERT INTO edge_int VALUES (1, 0.1 + 0.2, X'0102FF', NULL), (2, 1.0, NULL, 'x'), "
      "(9, -0.5, X'', ''), (10, 1e300, NULL, 'it''s 한글'), (100, 2.5e-7, NULL, NULL), "
      '(-5, 3.0, NULL, NULL), (1762300000000, NULL, NULL, NULL)',
  // No primary key (duplicate rows): read in one query.
  'CREATE TABLE edge_nopk (a, b)',
  "INSERT INTO edge_nopk VALUES (1, 'x'), (1, 'x'), (NULL, 'y'), ('1', 2.5)",
  // A composite key: read in one query.
  'CREATE TABLE edge_composite (a TEXT NOT NULL, b INTEGER NOT NULL, c, '
      'PRIMARY KEY (a, b))',
  "INSERT INTO edge_composite VALUES ('k', 2, NULL), ('k', 1, 'one'), ('j', 9, X'00')",
];

/// The edge tables.
const List<String> kDumpEdgeTables = [
  'edge_composite',
  'edge_int',
  'edge_nopk',
  'edge_text',
];

/// The dump of [kDumpEdgeTables] (SQLite 3.54.1 — VM library and sqlite3.wasm). Note the
/// line order: '10' < '9' for integers, and `'ab'` after `'ab'''` (',' sorts above the
/// doubled quote).
const String kDumpEdgeExpected =
    'noteapp-v1-dump 1\n'
    '#table edge_composite a,b,c\n'
    "'j',9,X'00'\n"
    "'k',1,'one'\n"
    "'k',2,NULL\n"
    '#table edge_int seq,r,b,t\n'
    '-5,3.0,NULL,NULL\n'
    "1,0.30000000000000004,X'0102FF',NULL\n"
    "10,1.0e+300,NULL,'it''s 한글'\n"
    '100,2.5e-07,NULL,NULL\n'
    '1762300000000,NULL,NULL,NULL\n'
    "2,1.0,NULL,'x'\n"
    "9,-0.5,X'',''\n"
    '#table edge_nopk a,b\n'
    "'1',2.5\n"
    "1,'x'\n"
    "1,'x'\n"
    "NULL,'y'\n"
    '#table edge_text id,v\n'
    "'',9\n"
    "'a',5\n"
    "'ab\nc',8\n"
    "'ab ',4\n"
    "'ab!',2\n"
    "'ab#',10\n"
    "'ab%',11\n"
    "'ab&',12\n"
    "'ab''''x',14\n"
    "'ab''',3\n"
    "'ab',1\n"
    "'ab(',13\n"
    "'it''s 한글',7\n"
    "'한글',6\n";
