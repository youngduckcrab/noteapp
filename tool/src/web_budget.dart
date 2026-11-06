/// `ws web-budget measure|check` and `tool/web_budget.yaml`
/// (docs/plans/m5-7/01-infra.md 4.2, 4.3.3, 6.15; contract 7.4.5 v2.1).
///
/// Measures a web build: `main.dart.js` (raw and gzip), every font of
/// `assets/FontManifest.json` (per family, raw and gzip — the gzip of each
/// file summed, the same `dart:io` gzip as `ws finalize-web`), the startup
/// font bundles (KaTeX, icons) and the `report_assets`. `check` compares the
/// numbers with the limits: a limit whose value is `null` is reported only;
/// a forbidden font family in `FontManifest.json` (NoteSans is lazy-loaded)
/// is a violation.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Repo-relative path of the budget file.
const String webBudgetPath = 'tool/web_budget.yaml';

/// Thrown when the budget file or the build directory cannot be read.
final class WebBudgetException implements Exception {
  const WebBudgetException(this.message);

  final String message;

  @override
  String toString() => 'WebBudgetException: $message';
}

/// One startup font bundle of `limits.startup_font_bundles`: the families
/// whose name starts with [familyPrefix] or is one of [families].
final class FontBundle {
  const FontBundle({
    required this.name,
    this.familyPrefix,
    this.families = const [],
    this.gzipMax,
  });

  final String name;
  final String? familyPrefix;
  final List<String> families;

  /// null = report only (contract 7.4.5 v2.1 — until the per-bundle limits
  /// are decided).
  final int? gzipMax;

  bool matches(String family) =>
      families.contains(family) ||
      (familyPrefix != null && family.startsWith(familyPrefix!));
}

/// `tool/web_budget.yaml` (4.3.3). Every limit may be null (report only).
final class WebBudget {
  const WebBudget({
    this.baselineMainGzip,
    this.baselineMainRaw,
    this.mainGzipGrowthMax,
    this.mainGzipMax,
    this.startupFontsGzipMax,
    this.startupFontsRawMax,
    this.bundles = const [],
    this.forbiddenFontFamilies = const [],
    this.reportAssets = const [],
  });

  final int? baselineMainGzip;
  final int? baselineMainRaw;
  final int? mainGzipGrowthMax;
  final int? mainGzipMax;
  final int? startupFontsGzipMax;
  final int? startupFontsRawMax;
  final List<FontBundle> bundles;
  final List<String> forbiddenFontFamilies;

  /// Paths relative to the build directory, sizes reported only.
  final List<String> reportAssets;

  static WebBudget load(String path) {
    final file = File(path);
    if (!file.existsSync()) throw WebBudgetException('$path not found');
    return parse(file.readAsStringSync(), sourceUrl: path);
  }

  static WebBudget parse(String text, {String sourceUrl = webBudgetPath}) {
    final Object? yaml;
    try {
      yaml = loadYaml(text, sourceUrl: Uri.file(sourceUrl));
    } on YamlException catch (e) {
      throw WebBudgetException('$sourceUrl: ${e.message}');
    }
    if (yaml is! YamlMap) {
      throw WebBudgetException('$sourceUrl must be a YAML map');
    }
    Never bad(String what) => throw WebBudgetException('$sourceUrl: $what');
    YamlMap map(Object? value, String key) => switch (value) {
      null => YamlMap(),
      final YamlMap m => m,
      _ => bad('`$key` must be a map'),
    };
    int? bytes(YamlMap from, String key) => switch (from[key]) {
      null => null,
      final int v when v >= 0 => v,
      _ => bad('`$key` must be a byte count or null'),
    };
    List<String> strings(Object? value, String key) => switch (value) {
      null => const [],
      final YamlList list when list.every((e) => e is String) =>
        List.unmodifiable(list.cast<String>()),
      _ => bad('`$key` must be a list of strings'),
    };

    final baseline = map(yaml['baseline'], 'baseline');
    final limits = map(yaml['limits'], 'limits');
    final bundles = <FontBundle>[
      for (final MapEntry(:key, :value) in map(
        limits['startup_font_bundles'],
        'startup_font_bundles',
      ).entries)
        () {
          final name = '$key';
          final entry = map(value, 'startup_font_bundles.$name');
          final prefix = entry['family_prefix'];
          if (prefix != null && prefix is! String) {
            bad('`startup_font_bundles.$name.family_prefix` must be a string');
          }
          final families = strings(
            entry['families'],
            'startup_font_bundles.$name.families',
          );
          if (prefix == null && families.isEmpty) {
            bad('`startup_font_bundles.$name` needs family_prefix or families');
          }
          return FontBundle(
            name: name,
            familyPrefix: prefix as String?,
            families: families,
            gzipMax: bytes(entry, 'gzip_max'),
          );
        }(),
    ];
    return WebBudget(
      baselineMainGzip: bytes(baseline, 'main_dart_js_gzip'),
      baselineMainRaw: bytes(baseline, 'main_dart_js_raw'),
      mainGzipGrowthMax: bytes(limits, 'main_dart_js_gzip_growth_max'),
      mainGzipMax: bytes(limits, 'main_dart_js_gzip_max'),
      startupFontsGzipMax: bytes(limits, 'startup_fonts_gzip_max'),
      startupFontsRawMax: bytes(limits, 'startup_fonts_raw_max'),
      bundles: List.unmodifiable(bundles),
      forbiddenFontFamilies: strings(
        yaml['forbidden_font_families'],
        'forbidden_font_families',
      ),
      reportAssets: strings(yaml['report_assets'], 'report_assets'),
    );
  }
}

/// Raw and gzip bytes of one file or a sum of files.
typedef ByteSize = ({int raw, int gzip});

ByteSize _sizeOf(File file) {
  final bytes = file.readAsBytesSync();
  return (raw: bytes.length, gzip: gzip.encode(bytes).length);
}

ByteSize _sum(Iterable<ByteSize> sizes) => sizes.fold((
  raw: 0,
  gzip: 0,
), (a, b) => (raw: a.raw + b.raw, gzip: a.gzip + b.gzip));

/// One FontManifest.json family: its files summed.
final class FontFamilySize {
  const FontFamilySize(this.family, this.files, this.size, {this.missing = 0});
  final String family;
  final int files;
  final ByteSize size;

  /// Asset files listed but not in the build.
  final int missing;
}

/// What `ws web-budget measure` reads from a web build.
final class WebBuildMeasurement {
  const WebBuildMeasurement({
    required this.mainDartJs,
    required this.fonts,
    required this.reportAssets,
  });

  final ByteSize mainDartJs;
  final List<FontFamilySize> fonts;

  /// Path → size, null when the file is not in the build.
  final Map<String, ByteSize?> reportAssets;

  ByteSize get fontsTotal => _sum(fonts.map((f) => f.size));

  List<FontFamilySize> bundle(FontBundle bundle) => [
    for (final font in fonts)
      if (bundle.matches(font.family)) font,
  ];
}

/// Reads [buildDir] (`app/build/web`). Throws [WebBudgetException] when
/// `main.dart.js` or `assets/FontManifest.json` is missing or malformed.
WebBuildMeasurement measureWebBuild(
  String buildDir, {
  List<String> reportAssets = const [],
}) {
  if (!Directory(buildDir).existsSync()) {
    throw WebBudgetException(
      '$buildDir not found (run `flutter build web --release` in app/ first)',
    );
  }
  final main = File(p.join(buildDir, 'main.dart.js'));
  if (!main.existsSync()) {
    throw WebBudgetException('${main.path} not found');
  }
  final manifestFile = File(p.join(buildDir, 'assets', 'FontManifest.json'));
  if (!manifestFile.existsSync()) {
    throw WebBudgetException('${manifestFile.path} not found');
  }
  final Object? manifest;
  try {
    manifest = jsonDecode(manifestFile.readAsStringSync());
  } on FormatException catch (e) {
    throw WebBudgetException('${manifestFile.path}: ${e.message}');
  }
  if (manifest is! List) {
    throw WebBudgetException('${manifestFile.path} must be a JSON list');
  }
  final fonts = <FontFamilySize>[];
  for (final entry in manifest) {
    if (entry is! Map ||
        entry['family'] is! String ||
        entry['fonts'] is! List) {
      throw WebBudgetException(
        '${manifestFile.path}: every entry needs `family` and `fonts`',
      );
    }
    final sizes = <ByteSize>[];
    var missing = 0;
    var files = 0;
    for (final font in entry['fonts'] as List) {
      final asset = font is Map ? font['asset'] : null;
      if (asset is! String) continue;
      files++;
      final file = File(p.join(buildDir, 'assets', asset));
      if (file.existsSync()) {
        sizes.add(_sizeOf(file));
      } else {
        missing++;
      }
    }
    fonts.add(
      FontFamilySize(
        entry['family'] as String,
        files,
        _sum(sizes),
        missing: missing,
      ),
    );
  }
  return WebBuildMeasurement(
    mainDartJs: _sizeOf(main),
    fonts: List.unmodifiable(fonts),
    reportAssets: {
      for (final path in reportAssets)
        path: switch (File(p.join(buildDir, path))) {
          final file when file.existsSync() => _sizeOf(file),
          _ => null,
        },
    },
  );
}

/// One row of the report table.
final class WebBudgetRow {
  const WebBudgetRow({
    required this.item,
    this.raw,
    this.gzip,
    this.limit,
    required this.result,
  });

  final String item;
  final String? raw;
  final String? gzip;
  final String? limit;

  /// 'ok', 'over', 'report', 'forbidden', 'missing'.
  final String result;

  bool get isViolation => result == 'over' || result == 'forbidden';
}

final class WebBudgetReport {
  const WebBudgetReport(this.rows, {required this.checked});

  final List<WebBudgetRow> rows;

  /// false for `measure` (no limit is applied).
  final bool checked;

  List<WebBudgetRow> get violations => [
    for (final row in rows)
      if (row.isViolation) row,
  ];

  /// A Markdown table (readable in a terminal and in GITHUB_STEP_SUMMARY)
  /// and the summary line.
  String format({required String command}) {
    final out = StringBuffer()
      ..writeln('| item | raw | gzip | limit (gzip) | result |')
      ..writeln('|---|---:|---:|---:|---|');
    for (final row in rows) {
      out.writeln(
        '| ${row.item} | ${row.raw ?? '—'} | ${row.gzip ?? '—'} | '
        '${row.limit ?? '—'} | ${row.result} |',
      );
    }
    out.writeln(
      checked
          ? 'ws web-budget $command: ${violations.length} violation(s)'
          : 'ws web-budget $command: measured (no limits applied)',
    );
    return out.toString();
  }
}

/// `1,382,988`.
String groupBytes(int value) {
  final digits = '${value.abs()}';
  final out = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// The table rows for [measurement]. With [check] the limits of [budget]
/// decide 'ok' / 'over'; without, every row is 'report'.
WebBudgetReport webBudgetReport(
  WebBuildMeasurement measurement,
  WebBudget budget, {
  required bool check,
}) {
  String result(int value, int? max) => !check || max == null
      ? 'report'
      : value <= max
      ? 'ok'
      : 'over';
  String? limit(int? max) => max == null ? null : groupBytes(max);

  final rows = <WebBudgetRow>[];
  final main = measurement.mainDartJs;
  rows.add(
    WebBudgetRow(
      item: 'main.dart.js',
      raw: groupBytes(main.raw),
      gzip: groupBytes(main.gzip),
      limit: limit(budget.mainGzipMax),
      result: result(main.gzip, budget.mainGzipMax),
    ),
  );
  if (budget.baselineMainGzip case final base?) {
    final growth = main.gzip - base;
    final rawBase = budget.baselineMainRaw;
    rows.add(
      WebBudgetRow(
        item: 'main.dart.js growth vs baseline',
        raw: rawBase == null ? null : _signed(main.raw - rawBase),
        gzip: _signed(growth),
        limit: budget.mainGzipGrowthMax == null
            ? null
            : '+${groupBytes(budget.mainGzipGrowthMax!)}',
        result: result(growth, budget.mainGzipGrowthMax),
      ),
    );
  }
  final total = measurement.fontsTotal;
  final fileCount = measurement.fonts.fold(0, (n, f) => n + f.files);
  final overRaw =
      check &&
      budget.startupFontsRawMax != null &&
      total.raw > budget.startupFontsRawMax!;
  final totalResult = result(total.gzip, budget.startupFontsGzipMax);
  rows.add(
    WebBudgetRow(
      item:
          'startup fonts (${measurement.fonts.length} families, '
          '$fileCount files)',
      raw: groupBytes(total.raw),
      gzip: groupBytes(total.gzip),
      limit: [
        if (budget.startupFontsGzipMax != null)
          groupBytes(budget.startupFontsGzipMax!),
        if (budget.startupFontsRawMax != null)
          'raw ${groupBytes(budget.startupFontsRawMax!)}',
      ].join(' · ').emptyToNull,
      result: overRaw ? 'over' : totalResult,
    ),
  );
  for (final bundle in budget.bundles) {
    final fonts = measurement.bundle(bundle);
    final size = _sum(fonts.map((f) => f.size));
    rows.add(
      WebBudgetRow(
        item: '└ ${bundle.name} (${fonts.length} families)',
        raw: groupBytes(size.raw),
        gzip: groupBytes(size.gzip),
        limit: limit(bundle.gzipMax),
        result: result(size.gzip, bundle.gzipMax),
      ),
    );
  }
  final missingFonts = measurement.fonts.where((f) => f.missing > 0).toList();
  for (final font in missingFonts) {
    rows.add(
      WebBudgetRow(
        item: 'font files not in the build: ${font.family}',
        raw: '${font.missing} file(s)',
        result: 'missing',
      ),
    );
  }
  final families = {for (final f in measurement.fonts) f.family};
  if (budget.forbiddenFontFamilies.isNotEmpty) {
    final found = [
      for (final name in budget.forbiddenFontFamilies)
        if (families.contains(name)) name,
    ];
    rows.add(
      WebBudgetRow(
        item: found.isEmpty
            ? 'forbidden fonts (${budget.forbiddenFontFamilies.join(', ')})'
            : 'forbidden fonts in FontManifest.json: ${found.join(', ')}',
        result: found.isEmpty
            ? (check ? 'ok' : 'report')
            : (check ? 'forbidden' : 'report'),
      ),
    );
  }
  for (final MapEntry(:key, :value) in measurement.reportAssets.entries) {
    rows.add(
      WebBudgetRow(
        item: key,
        raw: value == null ? null : groupBytes(value.raw),
        gzip: value == null ? null : groupBytes(value.gzip),
        result: value == null ? 'missing' : 'report',
      ),
    );
  }
  return WebBudgetReport(List.unmodifiable(rows), checked: check);
}

String _signed(int value) =>
    value < 0 ? groupBytes(value) : '+${groupBytes(value)}';

extension on String {
  String? get emptyToNull => isEmpty ? null : this;
}
