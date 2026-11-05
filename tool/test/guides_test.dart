// docs/guides checks (docs/plans/01-infra.md 6.16 and the 9.1 guides_test
// row, I14): the seven files of 3.7, working relative links, the common
// form (time · things to prepare · what to tell Claude on top, '확인 방법'
// and '문제 해결' at the end, the screenshot fallback, 해요체), and the
// facts each guide must carry. UI words quoted in guide 04 are compared with
// the app's own strings (AppStrings, index.html loader), and the names in
// guides 02, 05 and 06 with the workflows, so a rename shows up here.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'support/fixture_workspace.dart';

final _guidesDir = p.join(repoRoot, 'docs', 'guides');

const _guides = [
  '01-firebase-project.md',
  '02-github-secrets.md',
  '03-budget-alert.md',
  '04-ipad-web-test.md',
  '05-android-apk.md',
  '06-ios-testflight.md',
];

String _read(String name) => File(p.join(_guidesDir, name)).readAsStringSync();

YamlMap _workflow(String name) => loadYaml(
  File(p.join(repoRoot, '.github', 'workflows', name)).readAsStringSync(),
) as YamlMap;

/// `## ` headings of a Markdown file, in order.
List<String> _headings(String text) => [
  for (final line in text.split('\n'))
    if (line.startsWith('## ')) line.substring(3).trim(),
];

/// Text with fenced code blocks and inline code removed.
String _prose(String text) => text
    .replaceAll(RegExp(r'```.*?```', dotAll: true), '')
    .replaceAll(RegExp(r'`[^`\n]*`'), '');

/// Relative link targets of a Markdown file (`[text](target)`), without
/// web, mail and in-page links.
List<String> _relativeLinks(String text) => [
  for (final m in RegExp(r'\]\(([^)\s]+)\)').allMatches(_prose(text)))
    if (!RegExp(r'^(https?:|mailto:|#)').hasMatch(m.group(1)!)) m.group(1)!,
];

/// `static const String <name> = '<value>';` of the app strings.
Map<String, String> _appStrings() {
  final source = File(
    p.join(repoRoot, 'app', 'lib', 'src', 'app', 'strings.dart'),
  ).readAsStringSync();
  return {
    for (final m in RegExp(
      r"static const String (\w+) =\s*'([^']*)';",
    ).allMatches(source))
      m.group(1)!: m.group(2)!,
  };
}

void main() {
  test('the seven files of 3.7 exist, and nothing else', () {
    final names =
        Directory(_guidesDir)
            .listSync()
            .whereType<File>()
            .map((f) => p.basename(f.path))
            .toList()
          ..sort();
    expect(names, ['README.md', ..._guides]..sort());
  });

  test('every relative link points to an existing file', () {
    final files = [
      for (final name in ['README.md', ..._guides]) p.join(_guidesDir, name),
      p.join(repoRoot, 'README.md'),
    ];
    var count = 0;
    for (final file in files) {
      for (final link in _relativeLinks(File(file).readAsStringSync())) {
        count++;
        final target = p.normalize(
          p.join(p.dirname(file), Uri.decodeFull(link.split('#').first)),
        );
        expect(
          FileSystemEntity.typeSync(target),
          isNot(FileSystemEntityType.notFound),
          reason: '${p.relative(file, from: repoRoot)} → $link',
        );
      }
    }
    expect(count, greaterThan(10));
  });

  test('the link check sees a broken link', () {
    expect(_relativeLinks('[a](missing.md) [b](https://x.y) [c](#top)'), [
      'missing.md',
    ]);
    expect(_relativeLinks('`[a](in-code.md)`'), isEmpty);
  });

  test('README: every guide, in the order 01 → 02 → 04, then the rest', () {
    final readme = _read('README.md');
    final order = [
      for (final m in RegExp(r'\]\((0\d-[^)]+\.md)\)').allMatches(readme))
        m.group(1)!,
    ];
    expect(order, [
      '01-firebase-project.md',
      '02-github-secrets.md',
      '04-ipad-web-test.md',
      '03-budget-alert.md',
      '05-android-apk.md',
      '06-ios-testflight.md',
    ]);
    expect(
      File(p.join(repoRoot, 'README.md')).readAsStringSync(),
      contains('(docs/guides/README.md)'),
    );
  });

  group('common form (6.16)', () {
    for (final name in _guides) {
      test(name, () {
        final text = _read(name);
        expect(text, startsWith('# '));
        final headings = _headings(text);
        expect(headings.first, '준비물');
        expect(headings, containsAllInOrder(['준비물', '확인 방법', '문제 해결']));
        expect(headings.last, '문제 해결');
        final top = text.substring(0, text.indexOf('\n## 준비물'));
        expect(top, contains('소요 시간'));
        expect(top, contains('끝나면 Claude에게 알려줄 것'));
        expect(text, contains('스크린샷을 보내 주세요'));
        // 해요체: no 합니다체 or 한다체 sentence endings.
        expect(
          RegExp(r'(습니다|합니다|입니다|십시오|한다|된다|있다|없다)\.')
              .allMatches(_prose(text))
              .map((m) => m.group(0)),
          isEmpty,
        );
      });
    }
  });

  test('01: M4 location advice, marked unverified, and authDomain', () {
    final text = _read('01-firebase-project.md');
    for (final phrase in [
      'M4 때 정할 것 (지금은 만들지 않음)',
      '`asia-northeast3`(서울)',
      '`us-central1`',
      '만든 뒤에는 바꿀 수 없어요',
      '미확인',
      '`authDomain`',
      '`<프로젝트 ID>.web.app`',
      '승인된 도메인',
      'Google 애널리틱스',
      '프로젝트 ID',
      'Spark',
    ]) {
      expect(text, contains(phrase));
    }
  });

  test('02: the names the CI workflow reads, the four roles', () {
    final text = _read('02-github-secrets.md');
    final ci = _workflow('ci.yml');
    final env = ((ci['jobs'] as YamlMap).values.single as YamlMap)['env'];
    final secret = RegExp(r'secrets\.(\w+)')
        .firstMatch('${(env as YamlMap)['FIREBASE_SA']}')!
        .group(1)!;
    final variable = RegExp(r'vars\.(\w+)')
        .firstMatch('${env['FIREBASE_PROJECT_ID']}')!
        .group(1)!;
    expect(text, contains('`$secret`'));
    expect(text, contains('`$variable`'));
    expect(text, contains('**${ci['name']}**'));
    // The summary line of the CI workflow, word for word.
    const unset = 'Firebase 미설정 — docs/guides/02-github-secrets.md';
    expect(
      File(p.join(repoRoot, '.github', 'workflows', 'ci.yml'))
          .readAsStringSync(),
      contains(unset),
    );
    expect(text, contains(unset));
    for (final role in [
      'roles/firebasehosting.admin',
      'roles/firebaseauth.admin',
      'roles/run.viewer',
      'roles/serviceusage.apiKeysViewer',
    ]) {
      expect(text, contains('`$role`'));
    }
    for (final phrase in [
      'github-deploy',
      'JSON',
      'Secrets and variables',
      'iam.disableServiceAccountKeyCreation',
      '개인 Gmail',
      '지우',
      'M4',
    ]) {
      expect(text, contains(phrase));
    }
  });

  test('02, 04: live is main only; without main the development branch '
      'deploys a preview', () {
    final ci = _workflow('ci.yml');
    final steps = ((ci['jobs'] as YamlMap).values.single as YamlMap)['steps'];
    final channel = [
      for (final step in steps as YamlList)
        if ((step as YamlMap)['name'] == 'Channel') '${step['run']}',
    ].single;
    expect(channel, contains("'refs/heads/main'"));
    expect(channel, contains("echo 'id=live'"));
    expect(
      _read('02-github-secrets.md'),
      contains(
        '`main`이 아직 없는 지금은 개발 브랜치(저장소의 기본 브랜치)도 '
        '미리보기 주소로 가요',
      ),
    );
    expect(
      _read('04-ipad-web-test.md'),
      contains('live 주소에는 `main`에 올린 코드만 배포돼요'),
    );
  });

  test('03: budget alert only with Blaze, does not stop billing', () {
    final text = _read('03-budget-alert.md');
    for (final phrase in [
      'Spark',
      'Blaze',
      '예산 및 알림',
      '1000',
      '50%',
      '90%',
      '100%',
      '예산 알림은 요금을 멈추지 않아요',
      '릴리스 보관',
      '`10`',
      '미확인',
    ]) {
      expect(text, contains(phrase));
    }
  });

  group('04', () {
    late String text;
    setUp(() => text = _read('04-ipad-web-test.md'));

    test('preview data is separate and temporary; test use only', () {
      final preview = text
          .split('\n')
          .where((l) => l.contains('미리보기 주소는'))
          .toList();
      expect(preview, hasLength(1));
      for (final word in ['live', '데이터', '홈 화면 앱', '로그인', '따로', '임시', '7일']) {
        expect(preview.single, contains(word));
      }
      expect(text, contains('웹 버전은 테스트 전용이에요. 중요한 노트는 쓰지 마세요.'));
      expect(text, contains('필기는 홈 화면 앱으로 해요'));
      expect(text, contains('로그인·동기화 확인(M4)은 live 주소에서만'));
    });

    test('backup export with both buttons and the fallbacks', () {
      for (final phrase in [
        '**설정 → 앱 정보 → 백업 내보내기**',
        '**[내려받기]**',
        '**[공유 · 파일에 저장]**',
        '파일에 저장',
        '**홈 화면 앱에서는 [내려받기]가 아무 일도 하지 않을 수 있어요(미확인).**',
        '**두 버튼 모두 안 되면 아직 백업을 할 수 없는 상태예요. 바로 알려 주세요.**',
        '**[취소]**',
      ]) {
        expect(text, contains(phrase));
      }
    });

    test('quoted app words are the app strings', () {
      final strings = _appStrings();
      for (final name in [
        'settings',
        'sectionStorage',
        'sectionAbout',
        'aboutBuild',
        'aboutStandalone',
        'storagePersist',
        'storagePersistGranted',
        'storagePersistDenied',
        'checkForUpdate',
        'reload',
        'later',
        'backupExport',
        'backupPreparing',
        'backupReadyTitle',
        'backupDownload',
        'backupShare',
        'backupSlowWrites',
        'cancel',
        'copyDiagnostics',
        'startupFailedTitle',
        'retry',
        'resetLocalData',
      ]) {
        expect(strings, contains(name));
        expect(text, contains(strings[name]), reason: 'AppStrings.$name');
      }
      final banner =
          RegExp(
            r"'새 버전이 나왔어요 \(#\$buildNumber · \$shortSha\)\. ([^']+)'",
          ).firstMatch(
            File(p.join(repoRoot, 'app', 'lib', 'src', 'app', 'strings.dart'))
                .readAsStringSync(),
          );
      expect(banner, isNotNull);
      expect(text, contains('새 버전이 나왔어요 (#43 · b2c3d4e). ${banner!.group(1)}'));
      final storageUnavailable = strings['startupStorageUnavailable']!;
      expect(text, contains(storageUnavailable.substring(0, 20)));
    });

    test('loader texts and the backup file name are the app\'s', () {
      final index = File(p.join(repoRoot, 'app', 'web', 'index.html'))
          .readAsStringSync();
      for (final phrase in ['불러오는 중…', '30초 안에 앱이 시작되지 않았어요.']) {
        expect(index, contains(phrase));
        expect(text, contains(phrase));
      }
      expect(
        File(
          p.join(
            repoRoot,
            'app',
            'lib',
            'src',
            'settings',
            'backup_export.dart',
          ),
        ).readAsStringSync(),
        contains("'noteapp-backup-\$date-\$time.json'"),
      );
      expect(text, contains('`noteapp-backup-날짜-시각.json`'));
      expect(text, contains('`noteapp-backup-….json`'));
    });

    test('the 9.3 checklist rows', () {
      final section = text.substring(
        text.indexOf('\n## 확인 방법'),
        text.indexOf('\n## 문제 해결'),
      );
      final rows = [
        for (final m in RegExp(
          r'^\| (\d+[ab]?) \|',
          multiLine: true,
        ).allMatches(section))
          m.group(1)!,
      ];
      expect(rows, [
        for (var i = 1; i <= 17; i++) '$i',
        '18a',
        '18b',
        '19',
        '20',
      ]);
    });

    test('address, home screen, build label, update, quit, feedback', () {
      for (final phrase in [
        '`https://<프로젝트 ID>.web.app`',
        '**Summary**',
        '**홈 화면에 추가**',
        '`0.1.0 (#42 · a1b2c3d · main)`',
        '저절로 새로고침하지는 않아요',
        '앱 전환 화면',
        '**피드백** 양식',
        '설정 → 일반 → 정보 → 모델 이름',
        '펜슬 종류',
        '웹사이트 데이터',
        '**테스트 노트가 모두 지워져요.**',
      ]) {
        expect(text, contains(phrase));
      }
      final form = loadYaml(
        File(p.join(repoRoot, '.github', 'ISSUE_TEMPLATE', 'feedback.yml'))
            .readAsStringSync(),
      ) as YamlMap;
      expect(form['name'], '피드백');
    });
  });

  test('05: the APK workflow, artifact and file names', () {
    final text = _read('05-android-apk.md');
    final android = _workflow('android.yml');
    expect(text, contains('**${android['name']}**'));
    final upload = [
      for (final step
          in ((android['jobs'] as YamlMap).values.single as YamlMap)['steps']
              as YamlList)
        if ('${(step as YamlMap)['uses']}'.startsWith(
          'actions/upload-artifact',
        ))
          step['with'] as YamlMap,
    ].single;
    final artifact = '${upload['name']}'.split(r'${{').first;
    expect(artifact, 'noteapp-apk-');
    expect(text, contains('`$artifact<번호>`'));
    expect(text, contains('`${p.basename('${upload['path']}')}`'));
    expect(text, contains('${upload['retention-days']}일 뒤 사라져요'));
    for (final phrase in [
      '출처',
      '덮어 설치하지 못할 수 있어요',
      '노트도 지워져요',
      '**Run workflow**',
    ]) {
      expect(text, contains(phrase));
    }
    // 2차 R2-B1 (m5-7/01-infra 6.16): the APK is built by hand only — the
    // guide says so and walks through Run workflow on the default branch
    // (the development branch while there is no main).
    final on = android['on'] as YamlMap;
    expect(on.keys, ['workflow_dispatch']);
    for (final phrase in [
      '**Run workflow** 버튼을 눌렀을 때만 만들어져요',
      '자동으로 만들지 않아요',
      '### 1단계 — APK 만들기',
      '**Use workflow from**',
      '`claude/note-app-planning-bk29xb`',
      '저장소의 기본 브랜치에 있는 워크플로만',
      '기본 브랜치라 버튼이 보여요',
      '**Branch** 필터',
    ]) {
      expect(text, contains(phrase));
    }
    // No promise of an APK on every push any more.
    for (final phrase in ['올라갈 때마다 새 APK', '올라갈 때 만들어져요']) {
      expect(text, isNot(contains(phrase)));
    }
    expect(text, isNot(contains('버튼이 보이지 않아요')));
  });

  test('06: draft, the iOS workflow names and gate', () {
    final text = _read('06-ios-testflight.md');
    expect(text, contains('**초안이에요.**'));
    expect(text, contains('Claude가 그때의 최신 화면을 기준으로 다시 고쳐요'));
    final ios = _workflow('ios-testflight.yml');
    expect(text, contains('**${ios['name']}**'));
    final job = (ios['jobs'] as YamlMap).values.single as YamlMap;
    for (final name in (job['env'] as YamlMap).keys) {
      expect(text, contains('`$name`'));
    }
    final variable = RegExp(r'vars\.(\w+)').firstMatch('${job['if']}')!;
    expect(text, contains('`${variable.group(1)}`'));
    expect('${job['if']}', contains("inputs.confirm == 'yes'"));
    for (final phrase in [
      '`yes`',
      'App Manager',
      '`.p8`',
      'TestFlight',
      '10배',
      '번들 ID',
    ]) {
      expect(text, contains(phrase));
    }
  });
}
