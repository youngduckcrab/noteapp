// Benchmark helpers (03-ink 9.1, T22): wall-clock timing with Stopwatch —
// unlike the unit tests, measuring real time is the point here; benchmark/
// is outside test/ so `flutter test` / `ws test` never run it.
//
// Every case prints ONE JSON line:
// {"bench":"B1","case":"outline 200 pt","platform":"vm","runs":40,
//  "median_ms":0.05,"mean_ms":…,"p95_ms":…,"max_ms":…,"min_ms":…,
//  "criteria":{"median_ms":0.15},"pass":true}
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

/// 'web' under dart2js / dart2wasm, else 'vm'.
const String benchPlatform = bool.fromEnvironment('dart.library.js_interop')
    ? 'web'
    : 'vm';

/// Times of the measured runs (ms each).
final class BenchStats {
  BenchStats(List<double> samplesMs)
    : samples = List.unmodifiable(samplesMs..sort());

  /// ascending
  final List<double> samples;

  int get runs => samples.length;
  double get min => samples.first;
  double get max => samples.last;
  double get mean => samples.fold(0.0, (a, b) => a + b) / samples.length;
  double get median => percentile(0.5);
  double get p95 => percentile(0.95);

  /// Nearest-rank percentile of the sorted samples.
  double percentile(double q) {
    final i = (q * samples.length).ceil() - 1;
    return samples[i.clamp(0, samples.length - 1)];
  }

  double valueOf(String stat) => switch (stat) {
    'median_ms' => median,
    'mean_ms' => mean,
    'p95_ms' => p95,
    'max_ms' => max,
    'min_ms' => min,
    _ => throw ArgumentError.value(stat, 'stat'),
  };
}

double _ms(Stopwatch w) => w.elapsedMicroseconds / 1000;

/// Runs [setUp] (untimed) then [body] (timed) [warmup] + [runs] times; with
/// [inner] > 1 each sample is the mean of [inner] calls of [body].
BenchStats measure(
  void Function() body, {
  void Function()? setUp,
  int warmup = 3,
  int runs = 20,
  int inner = 1,
}) {
  final out = <double>[];
  final w = Stopwatch();
  for (var r = 0; r < warmup + runs; r++) {
    setUp?.call();
    w
      ..reset()
      ..start();
    for (var k = 0; k < inner; k++) {
      body();
    }
    w.stop();
    if (r >= warmup) out.add(_ms(w) / inner);
  }
  return BenchStats(out);
}

/// [measure] for an async body.
Future<BenchStats> measureAsync(
  Future<void> Function() body, {
  Future<void> Function()? setUp,
  int warmup = 2,
  int runs = 10,
}) async {
  final out = <double>[];
  final w = Stopwatch();
  for (var r = 0; r < warmup + runs; r++) {
    await setUp?.call();
    w
      ..reset()
      ..start();
    await body();
    w.stop();
    if (r >= warmup) out.add(_ms(w));
  }
  return BenchStats(out);
}

/// Every sample of one long operation timed step by step (B2: one sample
/// of a live stroke): [step] is called with 0 … [count] − 1.
/// [record] receives the times in step order.
BenchStats measureSteps(
  int count,
  void Function(int i) step, {
  List<double>? record,
}) {
  final out = <double>[];
  final w = Stopwatch();
  for (var i = 0; i < count; i++) {
    w
      ..reset()
      ..start();
    step(i);
    w.stop();
    out.add(_ms(w));
  }
  record?.addAll(out);
  return BenchStats(out);
}

double _round(double v) => (v * 10000).roundToDouble() / 10000;

/// Prints the JSON line of one case and checks every criterion
/// (stat → limit in ms, e.g. {'median_ms': 0.15}). On the VM the limits are
/// the 9.1 VM baselines; on the web they are reported, not enforced
/// (03-ink 9.1: Chrome numbers are for reference only).
void report(
  String bench,
  String name,
  BenchStats stats, {
  required Map<String, double> criteria,
  Map<String, Object?> extra = const {},
}) {
  final pass = criteria.entries.every((e) => stats.valueOf(e.key) <= e.value);
  // ignore: avoid_print
  print(
    jsonEncode({
      'bench': bench,
      'case': name,
      'platform': benchPlatform,
      'runs': stats.runs,
      'median_ms': _round(stats.median),
      'mean_ms': _round(stats.mean),
      'p95_ms': _round(stats.p95),
      'max_ms': _round(stats.max),
      'min_ms': _round(stats.min),
      'criteria': criteria,
      'pass': pass,
      ...extra,
    }),
  );
  if (benchPlatform != 'vm') return;
  for (final MapEntry(key: stat, value: limit) in criteria.entries) {
    expect(
      stats.valueOf(stat),
      lessThanOrEqualTo(limit),
      reason: '$bench $name: $stat over the 9.1 VM baseline',
    );
  }
}
