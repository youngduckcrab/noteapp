// `ws web-budget measure|check` and tool/web_budget.yaml
// (docs/plans/m5-7/01-infra.md 4.2, 4.3.3, 6.15, 9.1 — J17): a fake build
// folder per case — within and over the limits, a forbidden font family,
// the gzip numbers (dart:io gzip of each file, summed), a per-bundle `null`
// limit = report only, the summary output — plus the committed budget file.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../src/cli.dart';
import '../src/web_budget.dart';
import 'support/fixture_workspace.dart';

/// Bytes that gzip poorly (so sizes are easy to push over a limit).
List<int> _noise(int length, int seed) {
  final random = Random(seed);
  return [for (var i = 0; i < length; i++) random.nextInt(256)];
}

final class _Build {
  _Build() : dir = Directory.systemTemp.createTempSync('ws_web_budget_');

  final Directory dir;
  final Map<String, List<int>> files = {};

  String get path => dir.path;

  void write(String relative, List<int> bytes) {
    files[relative] = bytes;
    File(p.join(dir.path, relative))
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
  }

  /// FontManifest.json with [families] → asset paths (written as files under
  /// assets/ unless listed in [absent]).
  void fonts(
    Map<String, List<String>> families, {
    int size = 1000,
    Set<String> absent = const {},
  }) {
    var seed = 10;
    final manifest = [
      for (final MapEntry(:key, :value) in families.entries)
        {
          'family': key,
          'fonts': [
            for (final asset in value) {'asset': asset},
          ],
        },
    ];
    write('assets/FontManifest.json', utf8.encode(jsonEncode(manifest)));
    for (final assets in families.values) {
      for (final asset in assets) {
        if (absent.contains(asset)) continue;
        write('assets/$asset', _noise(size, seed++));
      }
    }
  }

  int gzipOf(String relative) => gzip.encode(files[relative]!).length;

  void delete() => dir.deleteSync(recursive: true);
}

_Build _standardBuild({int mainLength = 5000}) {
  final build = _Build()..write('main.dart.js', _noise(mainLength, 1));
  build.fonts({
    'MaterialIcons': ['fonts/MaterialIcons-Regular.otf'],
    'packages/cupertino_icons/CupertinoIcons': [
      'packages/cupertino_icons/assets/CupertinoIcons.ttf',
    ],
    'packages/flutter_math_fork/KaTeX_Main': [
      'packages/flutter_math_fork/lib/katex_fonts/fonts/KaTeX_Main-Regular.ttf',
      'packages/flutter_math_fork/lib/katex_fonts/fonts/KaTeX_Main-Bold.ttf',
    ],
    'packages/flutter_math_fork/KaTeX_AMS': [
      'packages/flutter_math_fork/lib/katex_fonts/fonts/KaTeX_AMS-Regular.ttf',
    ],
  });
  build.write(
    'assets/packages/record_web/assets/js/record.worklet.js',
    utf8.encode('class X extends AudioWorkletProcessor {}'),
  );
  return build;
}

const String _budgetYaml = '''
baseline:
  main_dart_js_gzip: 4000
  main_dart_js_raw: 4000
limits:
  main_dart_js_gzip_growth_max: 2000
  main_dart_js_gzip_max: 6000
  startup_fonts_gzip_max: 10000
  startup_fonts_raw_max: 10000
  startup_font_bundles:
    katex: {family_prefix: packages/flutter_math_fork/, gzip_max: null}
    icons: {families: [MaterialIcons, packages/cupertino_icons/CupertinoIcons], gzip_max: 2500}
forbidden_font_families: [NoteSans, packages/ink_engine/NoteSans]
report_assets:
  - assets/packages/record_web/assets/js/record.worklet.js
  - assets/not/there.js
''';

/// The row whose item is [item] or starts with it and a space or a colon.
WebBudgetRow _row(WebBudgetReport report, String item) =>
    report.rows.singleWhere(
      (r) =>
          r.item == item ||
          r.item.startsWith('$item ') ||
          r.item.startsWith('$item:'),
    );

void main() {
  late _Build build;
  setUp(() => build = _standardBuild());
  tearDown(() => build.delete());

  group('WebBudget.parse', () {
    test('the 4.3.3 shape', () {
      final budget = WebBudget.parse(_budgetYaml);
      expect(budget.baselineMainGzip, 4000);
      expect(budget.mainGzipGrowthMax, 2000);
      expect(budget.mainGzipMax, 6000);
      expect(budget.startupFontsGzipMax, 10000);
      expect(budget.startupFontsRawMax, 10000);
      expect([for (final b in budget.bundles) b.name], ['katex', 'icons']);
      expect(budget.bundles.first.familyPrefix, 'packages/flutter_math_fork/');
      expect(budget.bundles.first.gzipMax, isNull);
      expect(budget.bundles.last.families, hasLength(2));
      expect(budget.bundles.last.gzipMax, 2500);
      expect(budget.forbiddenFontFamilies, contains('NoteSans'));
      expect(budget.reportAssets, hasLength(2));
    });

    test('malformed files are rejected with the key', () {
      for (final (yaml, message) in [
        ('- a list', 'YAML map'),
        ('limits: 3', '`limits` must be a map'),
        ('limits: {main_dart_js_gzip_max: -1}', 'main_dart_js_gzip_max'),
        ('limits: {main_dart_js_gzip_max: "1 MB"}', 'main_dart_js_gzip_max'),
        ('forbidden_font_families: NoteSans', 'forbidden_font_families'),
        (
          'limits: {startup_font_bundles: {katex: {gzip_max: 1}}}',
          'needs family_prefix or families',
        ),
        ('a: [', 'tool/web_budget.yaml'),
      ]) {
        expect(
          () => WebBudget.parse(yaml),
          throwsA(
            isA<WebBudgetException>().having(
              (e) => e.message,
              'message',
              contains(message),
            ),
          ),
          reason: yaml,
        );
      }
    });

    test('the committed tool/web_budget.yaml: the contract v2.7 C27-01 '
        'baseline (2차 integration build) and main.dart.js limit, and the '
        'contract v2.4 C24-01 bundle limits (KaTeX 380,000 B, icons 20,000 B '
        'gzip; their sum stays within the 400,000 B total)', () {
      final budget = WebBudget.load(p.join(repoRoot, webBudgetPath));
      expect(budget.baselineMainGzip, 1902969);
      expect(budget.baselineMainRaw, 6477160);
      expect(budget.mainGzipGrowthMax, 300000);
      expect(budget.mainGzipMax, 2000000);
      // C27-01: the limit leaves room below baseline + one round of growth.
      expect(
        budget.mainGzipMax!,
        lessThanOrEqualTo(budget.baselineMainGzip! + budget.mainGzipGrowthMax!),
      );
      expect(budget.startupFontsGzipMax, 400000);
      expect(budget.startupFontsRawMax, 700000);
      final bundles = {for (final b in budget.bundles) b.name: b};
      expect(bundles.keys, ['katex', 'icons']);
      expect(bundles['katex']!.familyPrefix, 'packages/flutter_math_fork/');
      expect(bundles['icons']!.families, [
        'MaterialIcons',
        'CupertinoIcons',
        'packages/cupertino_icons/CupertinoIcons',
      ]);
      expect(bundles['katex']!.gzipMax, 380000);
      expect(bundles['icons']!.gzipMax, 20000);
      expect(
        bundles['katex']!.gzipMax! + bundles['icons']!.gzipMax!,
        lessThanOrEqualTo(budget.startupFontsGzipMax!),
      );
      expect(budget.forbiddenFontFamilies, [
        'NoteSans',
        'packages/ink_engine/NoteSans',
      ]);
      expect(budget.reportAssets, [
        'assets/packages/record_web/assets/js/record.worklet.js',
      ]);
    });
  });

  group('measureWebBuild', () {
    test('main.dart.js raw / gzip, fonts per family (files summed), '
        'report assets (missing → null)', () {
      final m = measureWebBuild(
        build.path,
        reportAssets: WebBudget.parse(_budgetYaml).reportAssets,
      );
      expect(m.mainDartJs.raw, 5000);
      expect(m.mainDartJs.gzip, build.gzipOf('main.dart.js'));
      expect(m.fonts.map((f) => f.family), [
        'MaterialIcons',
        'packages/cupertino_icons/CupertinoIcons',
        'packages/flutter_math_fork/KaTeX_Main',
        'packages/flutter_math_fork/KaTeX_AMS',
      ]);
      final main = m.fonts[2];
      expect(main.files, 2);
      expect(main.size.raw, 2000);
      const base = 'assets/packages/flutter_math_fork/lib/katex_fonts/fonts';
      expect(
        main.size.gzip,
        build.gzipOf('$base/KaTeX_Main-Regular.ttf') +
            build.gzipOf('$base/KaTeX_Main-Bold.ttf'),
      );
      expect(m.fontsTotal.raw, 5000);
      const worklet = 'assets/packages/record_web/assets/js/record.worklet.js';
      expect(m.reportAssets[worklet]!.raw, build.files[worklet]!.length);
      expect(m.reportAssets['assets/not/there.js'], isNull);
    });

    test('no build / no main.dart.js / no FontManifest.json / bad JSON → '
        'WebBudgetException', () {
      expect(
        () => measureWebBuild(p.join(build.path, 'nope')),
        throwsA(isA<WebBudgetException>()),
      );
      File(p.join(build.path, 'assets', 'FontManifest.json'))
          .writeAsStringSync('{');
      expect(
        () => measureWebBuild(build.path),
        throwsA(isA<WebBudgetException>()),
      );
      File(p.join(build.path, 'assets', 'FontManifest.json')).deleteSync();
      expect(
        () => measureWebBuild(build.path),
        throwsA(isA<WebBudgetException>()),
      );
      File(p.join(build.path, 'main.dart.js')).deleteSync();
      expect(
        () => measureWebBuild(build.path),
        throwsA(isA<WebBudgetException>()),
      );
    });
  });

  group('webBudgetReport', () {
    final budget = WebBudget.parse(_budgetYaml);

    test('within the limits: ok rows, the null bundle limit = report', () {
      final report = webBudgetReport(
        measureWebBuild(build.path, reportAssets: budget.reportAssets),
        budget,
        check: true,
      );
      expect(report.violations, isEmpty);
      final main = report.rows.singleWhere((r) => r.item == 'main.dart.js');
      expect(main.result, 'ok');
      expect(main.limit, '6,000');
      final growth = _row(report, 'main.dart.js growth');
      expect(growth.result, 'ok');
      expect(growth.limit, '+2,000');
      expect(growth.gzip, startsWith('+'));
      expect(
        _row(report, 'startup fonts').item,
        contains('4 families, 5 files'),
      );
      expect(_row(report, 'startup fonts').result, 'ok');
      expect(_row(report, '└ katex').item, '└ katex (2 families)');
      expect(_row(report, '└ katex').result, 'report');
      expect(_row(report, '└ katex').limit, isNull);
      expect(_row(report, '└ icons').result, 'ok');
      expect(_row(report, 'forbidden fonts').result, 'ok');
      expect(_row(report, 'assets/not/there.js').result, 'missing');
      const worklet = 'assets/packages/record_web/assets/js/record.worklet.js';
      expect(_row(report, worklet).result, 'report');
      expect(
        report.format(command: 'check'),
        endsWith('ws web-budget check: 0 violation(s)\n'),
      );
    });

    test('over: main.dart.js size and growth, fonts total, a bundle', () {
      build
        ..write('main.dart.js', _noise(7000, 2))
        ..fonts({
          'MaterialIcons': ['fonts/MaterialIcons-Regular.otf'],
          'packages/flutter_math_fork/KaTeX_Main': [
            'packages/flutter_math_fork/lib/katex_fonts/fonts/a.ttf',
          ],
        }, size: 3000);
      final report = webBudgetReport(
        measureWebBuild(build.path),
        budget,
        check: true,
      );
      expect(
        [for (final r in report.violations) r.item.split(' (').first],
        [
          'main.dart.js',
          'main.dart.js growth vs baseline',
          // The fonts total (6,000 B) stays under 10,000; the icons bundle
          // (one 3,000 B family) is over its 2,500.
          '└ icons',
        ],
      );
      expect(_row(report, '└ icons').result, 'over');
      // A null limit never fails, however large.
      expect(_row(report, '└ katex').result, 'report');
    });

    test('the raw fonts limit alone fails the total', () {
      build.fonts({
        'packages/flutter_math_fork/KaTeX_Main': [
          for (var i = 0; i < 6; i++)
            'packages/flutter_math_fork/lib/katex_fonts/fonts/$i.ttf',
        ],
      }, size: 2000);
      final report = webBudgetReport(
        measureWebBuild(build.path),
        const WebBudget(startupFontsRawMax: 10000),
        check: true,
      );
      expect(_row(report, 'startup fonts').result, 'over');
      expect(_row(report, 'startup fonts').limit, 'raw 10,000');
    });

    test('a forbidden family in FontManifest.json is a violation', () {
      build.fonts({
        'MaterialIcons': ['fonts/MaterialIcons-Regular.otf'],
        'packages/ink_engine/NoteSans': [
          'packages/ink_engine/assets/fonts/NoteSans-Regular.ttf',
        ],
      });
      final report = webBudgetReport(
        measureWebBuild(build.path),
        budget,
        check: true,
      );
      final row = _row(report, 'forbidden fonts');
      expect(row.result, 'forbidden');
      expect(row.item, contains('packages/ink_engine/NoteSans'));
      expect(report.violations, [row]);
    });

    test('a listed font file missing from the build → a missing row, not a '
        'violation', () {
      build.fonts(
        {
          'MaterialIcons': ['fonts/MaterialIcons-Gone.otf'],
        },
        absent: {'fonts/MaterialIcons-Gone.otf'},
      );
      final report = webBudgetReport(
        measureWebBuild(build.path),
        budget,
        check: true,
      );
      expect(_row(report, 'font files not in the build').result, 'missing');
      expect(report.violations, isEmpty);
    });

    test('measure: no limit applied (every row report), summary line', () {
      build.write('main.dart.js', _noise(9000, 3));
      final report = webBudgetReport(
        measureWebBuild(build.path),
        budget,
        check: false,
      );
      expect(report.violations, isEmpty);
      expect(report.rows.map((r) => r.result).toSet(), {'report'});
      expect(
        report.format(command: 'measure'),
        endsWith('ws web-budget measure: measured (no limits applied)\n'),
      );
    });

    test('format: a Markdown table, grouped digits, — for empty cells', () {
      final text = webBudgetReport(
        measureWebBuild(build.path),
        budget,
        check: true,
      ).format(command: 'check');
      final lines = text.split('\n');
      expect(lines[0], '| item | raw | gzip | limit (gzip) | result |');
      expect(lines[1], '|---|---:|---:|---:|---|');
      expect(lines[2], startsWith('| main.dart.js | 5,000 | '));
      expect(text, contains('| — | — | — | ok |'));
      expect(groupBytes(1382988), '1,382,988');
      expect(groupBytes(-3231), '-3,231');
      expect(groupBytes(12), '12');
    });
  });

  group('ws web-budget', () {
    late Directory root;
    setUp(() {
      root = Directory.systemTemp.createTempSync('ws_web_budget_root_');
      File(p.join(root.path, 'tool', 'web_budget.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync(_budgetYaml);
      File(p.join(root.path, 'pubspec.yaml'))
          .writeAsStringSync('name: fake_root\nworkspace: []\n');
    });
    tearDown(() => root.deleteSync(recursive: true));

    Future<(int, String, String)> ws(
      List<String> args, {
      Map<String, String> environment = const {},
    }) async {
      final out = StringBuffer(), err = StringBuffer();
      final code = await runWs(
        args,
        context: WsContext(
          root: root.path,
          out: out,
          err: err,
          environment: environment,
          workingDirectory: root.path,
        ),
      );
      return (code, '$out', '$err');
    }

    test('check within the limits → 0 + the table; GITHUB_STEP_SUMMARY gets '
        'it too', () async {
      final summary = File(p.join(root.path, 'summary.md'));
      final (code, out, err) = await ws(
        ['web-budget', 'check', '--build-dir', build.path],
        environment: {'GITHUB_STEP_SUMMARY': summary.path},
      );
      expect(code, 0, reason: '$out$err');
      expect(out, startsWith('| item | raw | gzip | limit (gzip) | result |'));
      expect(out, endsWith('ws web-budget check: 0 violation(s)\n'));
      expect(
        summary.readAsStringSync(),
        startsWith('### Web budget (check)\n\n| item |'),
      );
    });

    test('check over a limit → 1; measure on the same build → 0', () async {
      build.write('main.dart.js', _noise(9000, 4));
      final (code, out, _) = await ws([
        'web-budget',
        'check',
        '--build-dir',
        build.path,
      ]);
      expect(code, 1);
      expect(out, contains('| over |'));
      final (measured, measureOut, _) = await ws([
        'web-budget',
        'measure',
        '--build-dir',
        build.path,
      ]);
      expect(measured, 0);
      expect(measureOut, isNot(contains('| over |')));
      expect(measureOut, contains('└ katex'));
    });

    test(
      '--budget picks another file; a missing build or budget → 3',
      () async {
        final other = File(p.join(root.path, 'other.yaml'))
          ..writeAsStringSync('limits: {main_dart_js_gzip_max: 10}\n');
        final (code, _, _) = await ws([
          'web-budget',
          'check',
          '--build-dir',
          build.path,
          '--budget',
          other.path,
        ]);
        expect(code, 1);

        final (missingBuild, _, err) = await ws([
          'web-budget',
          'check',
          '--build-dir',
          p.join(root.path, 'no-build'),
        ]);
        expect(missingBuild, environmentExitCode);
        expect(err, contains('flutter build web --release'));

        final (missingBudget, _, _) = await ws([
          'web-budget',
          'check',
          '--build-dir',
          build.path,
          '--budget',
          p.join(root.path, 'none.yaml'),
        ]);
        expect(missingBudget, environmentExitCode);
      },
    );

    test('measure without a budget file still measures', () async {
      File(p.join(root.path, 'tool', 'web_budget.yaml')).deleteSync();
      final (code, out, _) = await ws([
        'web-budget',
        'measure',
        '--build-dir',
        build.path,
      ]);
      expect(code, 0);
      expect(out, contains('| main.dart.js | 5,000 |'));
    });
  });
}
