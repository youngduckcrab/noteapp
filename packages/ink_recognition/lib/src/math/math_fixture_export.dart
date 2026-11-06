// lib/src/math/math_fixture_export.dart — (internal, P-C) m5-7/05-library
// 6.14.7 (L2-22, SYNC X-6): the math pad's fixture mode turns its strokes
// and the expected LaTeX into one fixture of m5-7/07-sync 6.9.1
// (functions/tool/fixtures/math/*.json — read by functions/tool/math_eval.ts):
//
//   {"id":"user-20261106-100000","tags":[],"expected":"\\frac{a+b}{c}",
//    "strokes":{"x":[[312.4,313.1]],"y":[[88.0,88.6]],"t":[[0,8]]},
//    "source":"user-android-2026-11-06"}
//
// - One line; the keys of 6.9.1 in its order, without `png` (a file the user
//   would have to move separately — strokes only).
// - strokes: the callable request's shape and rules (6.11.3, CP-L8 — the
//   same mathStrokesOf: page pt with 1 decimal, t integer ms from the first
//   point of the first stroke, traces without points left out, thinned only
//   above 512 KB and RecognizerEngineError('too-large') past the last step).
//   No point at all → empty lists (the pad never offers that).
// - id 'user-<yyyyMMdd-HHmmss>' and source 'user-<platform>-<yyyy-MM-dd>'
//   from the fields of `now` as given (the pad passes the clock's local time).
// - expected as given (the pad passes the trimmed field).
// - Nothing is sent or stored: the user copies the line into the repository
//   (07-sync 6.9.1 — handwriting samples are formulas only, U18).
import 'dart:convert';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;

import '../model/handwriting_trace.dart';
import 'math_payload.dart';

/// The 6.9.1 fixture of [traces] (temporary page pt) with the answer
/// [expected], as one line of JSON. Deterministic: the same input gives the
/// same string.
String buildMathFixtureJson(
  List<HandwritingTrace> traces,
  String expected, {
  required DateTime now,
  required String platform,
}) {
  final strokes =
      mathStrokesOf(traces) ??
      const <String, List<List<num>>>{'x': [], 'y': [], 't': []};
  return jsonEncode(<String, Object?>{
    'id': mathFixtureId(now),
    'tags': const <String>[],
    'expected': expected,
    'strokes': strokes,
    'source': 'user-$platform-${_date(now)}',
  });
}

/// `user-<yyyyMMdd-HHmmss>` of [now]'s fields.
String mathFixtureId(DateTime now) =>
    'user-${_pad(now.year, 4)}${_pad(now.month)}${_pad(now.day)}-'
    '${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}';

/// The `<platform>` of the fixture's source: 'web', 'android', 'ios' (other
/// platforms by their lower-case name).
String mathFixturePlatform() =>
    kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();

String _date(DateTime now) =>
    '${_pad(now.year, 4)}-${_pad(now.month)}-${_pad(now.day)}';

String _pad(int value, [int width = 2]) => value.toString().padLeft(width, '0');
