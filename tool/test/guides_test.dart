// docs/guides checks (docs/plans/01-infra.md 6.16 and the 9.1 guides_test
// row, I14; v2 — docs/plans/m5-7/01-infra.md 3.7 and 6.21, J18): the nine
// files, working relative links, the common form (time · things to prepare ·
// what to tell Claude on top, '확인 방법' and '문제 해결' at the end, the
// screenshot fallback, 해요체), and the facts each guide must carry. UI words
// quoted in guide 04 are compared with the app's own strings (AppStrings,
// index.html loader), the names in guides 02, 05, 06 and 07 with the
// workflows, and the items of guide 08 with the contract's device checklist
// (docs/plans/m5-7/00-overview.md 7.8) word for word, so a rename or a
// contract edit shows up here.

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
  '07-android-signing.md',
  '08-device-checklist.md',
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

String _appStringsSource() =>
    File(p.join(repoRoot, 'app', 'lib', 'src', 'app', 'strings.dart'))
        .readAsStringSync();

/// `static const String <name> = '<value>';` of the app strings.
Map<String, String> _appStrings() {
  final source = _appStringsSource();
  return {
    for (final m in RegExp(
      r"static const String (\w+) =\s*'([^']*)';",
    ).allMatches(source))
      m.group(1)!: m.group(2)!,
  };
}

/// Lines of guide 08 copied word for word from the contract: the checklist
/// items (`- [ ] **A-1** …`) and the section quotes (`> …`).
final _verbatimLine = RegExp(r'^(- \[ \] \*\*[ABC]-\d+\*\* |> )');

/// Contract 7.8 text as the guide carries it: without the `(v2.1) ` revision
/// marks and the bold marks (they belong to the plan, not to the sentence).
String _plain(String cell) =>
    cell.replaceAll('(v2.1) ', '').replaceAll('**', '').trim();

/// The device checklist of the contract (00-overview 7.8): the three section
/// lines (`A. …`, `B. …`, `C. …`) and the rows `| A-1 | <확인> | … |`.
({Map<String, String> headers, Map<String, String> items}) _contract78() {
  final text = File(p.join(repoRoot, 'docs', 'plans', 'm5-7', '00-overview.md'))
      .readAsStringSync();
  final start = text.indexOf('\n### 7.8 ');
  final end = text.indexOf('\n### 7.9 ', start);
  expect(start, greaterThan(0));
  expect(end, greaterThan(start));
  final headers = <String, String>{};
  final items = <String, String>{};
  for (final line in text.substring(start, end).split('\n')) {
    final header = RegExp(r'^([ABC])\. (.+)$').firstMatch(line);
    if (header != null) headers[header.group(1)!] = _plain(header.group(2)!);
    final row = RegExp(r'^\| ([ABC]-\d+) \| (.+?) \|( .* \|)?$')
        .firstMatch(line);
    if (row != null) items[row.group(1)!] = _plain(row.group(2)!);
  }
  return (headers: headers, items: items);
}

void main() {
  test('the nine files of 3.7 exist, and nothing else', () {
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

  test(
    'README: every guide, in the order 01 → 02 → 04 → 08, then the rest',
    () {
      final readme = _read('README.md');
      final order = [
        for (final m in RegExp(r'\]\((0\d-[^)]+\.md)\)').allMatches(readme))
          m.group(1)!,
      ];
      expect(order, [
        '01-firebase-project.md',
        '02-github-secrets.md',
        '04-ipad-web-test.md',
        '08-device-checklist.md',
        '03-budget-alert.md',
        '05-android-apk.md',
        '07-android-signing.md',
        '06-ios-testflight.md',
      ]);
      expect(readme, contains('01 → 02 → 04 → 08 순서로'));
      expect(readme, contains('Hosting(Spark 무료)만'));
      expect(
        File(p.join(repoRoot, 'README.md')).readAsStringSync(),
        contains('(docs/guides/README.md)'),
      );
    },
  );

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
        // 해요체: no 합니다체 or 한다체 sentence endings. Guide 08 quotes
        // the contract's checklist sentences word for word (한다체); those
        // lines are left out here and compared with the contract below.
        final own = text
            .split('\n')
            .where((line) => !_verbatimLine.hasMatch(line))
            .join('\n');
        expect(
          RegExp(r'(습니다|합니다|입니다|십시오|한다|된다|있다|없다|했다)\.')
              .allMatches(_prose(own))
              .map((m) => m.group(0)),
          isEmpty,
        );
      });
    }
  });

  test('01: Hosting only on Spark first (contract 3.7), the real-connection '
      'section, M4 location advice, authDomain', () {
    final text = _read('01-firebase-project.md');
    final first = text.substring(text.indexOf('\n\n') + 2).split('\n\n').first;
    for (final phrase in [
      '2차 라운드에서는 Hosting만 써요',
      'Spark(무료) 요금제, 결제 계정 없음',
      'Blaze',
      '실연결',
      'Hosting(Spark)은 실연결이 아니에요',
    ]) {
      expect(first, contains(phrase));
    }
    expect(text, contains('Spark로 프로젝트 만들기 → Hosting 시작 → [02]'));
    expect(text, contains('약 15분'));
    final headings = _headings(text);
    expect(headings, contains('실연결 때 정할 것 (지금은 하지 않음)'));
    expect(
      headings.indexOf('실연결 때 정할 것 (지금은 하지 않음)'),
      greaterThan(headings.indexOf('따라 하기')),
    );
    for (final phrase in [
      'M4',
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
      'Functions) 배포는 실연결 미니 라운드에서 해요',
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

    test('2차: B-1 in four steps, B-15 and B-16, recording, no web rollback, '
        'items in 08 (6.21)', () {
      expect(text, contains('[08. 실기기 체크리스트](08-device-checklist.md)'));
      final b1 = text.substring(
        text.indexOf('\n### 10단계 — 2차 판으로 옮기기 (08 B-1)'),
        text.indexOf('\n### 녹음할 때'),
      );
      final steps = [
        for (final m in RegExp(
          r'^(\d)\. \*\*([^*]+)\*\*',
          multiLine: true,
        ).allMatches(b1))
          '${m.group(1)} ${m.group(2)}',
      ];
      expect(steps, [
        '1 배포 전에 백업 내보내기',
        '2 2차 배포',
        '3 첫 실행',
        '4 ${_appStrings()['sectionV1Copy']} 확인',
      ]);
      // Step 1: the source (live after main, the development branch preview
      // before) — the 1차 paragraph of step 1 stays above.
      for (final phrase in [
        '`main`이 생긴 뒤면 live 주소, 그 전이면 위 1단계의 개발 브랜치 미리보기 주소',
        '2차 DB v2가 든 병합 푸시가 곧 그 주소로의 배포',
        '그 병합 전에 1번(백업)을 먼저 요청해요',
        '노트가 그대로 열리는지',
        '**설정 → ${_appStrings()['sectionV1Copy']}**',
        '실제 노트가 없으면 1차 판으로 노트를 몇 개 만든 뒤 같은 순서',
      ]) {
        expect(b1, contains(phrase));
      }
      // The V1CopySection line starts the way the app writes it.
      final present = RegExp(r"v1CopyPresent\(\{[^}]*\}\) => '([^$]+)\$")
          .firstMatch(_appStringsSource());
      expect(present, isNotNull);
      expect(b1, contains("'${present!.group(1)}"));
      for (final heading in [
        'B-15 하는 법 — 키보드 없이 텍스트 상자 편집',
        'B-16 하는 법 — 녹음된 글씨 위에 점 찍기',
      ]) {
        expect(text, contains('\n### $heading\n'));
      }
      for (final phrase in [
        '**두 번 탭**',
        '**손잡이**',
        '**붙여넣기**',
        '**두 손가락으로 스크롤**',
        '**핀치**',
        '글자가 튀거나',
        '**재생은 누르지 않아요.**',
        '**마침표**',
        '**손가락으로 탭**',
        '쓴 시점부터 재생돼요',
        // Recording on the web (6.21).
        '**aA** → **웹 사이트 설정** → **마이크** → **허용**',
        '**녹음 중에는 탭을 닫거나 새로고침하지 마세요.**',
        "**'복구된 녹음'**",
        '**웹 배포를 옛 판으로 되돌리지 마세요.**',
        _appStrings()['reloadBlockedByRecording']!,
      ]) {
        expect(text, contains(phrase));
      }
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
    // 2차 J2 (m5-7/01-infra 6.10.3): the name tells the signing —
    // noteapp-apk-<run> (fixed key) or noteapp-debug-signed-<run>. Guide v2
    // (J18, 6.21) names both, from the workflow's expression.
    final name = '${upload['name']}';
    final names = RegExp(
      r"^noteapp-\$\{\{ steps\.signing\.outputs\.mode == 'release' && "
      r"'([\w-]+)' \|\| '([\w-]+)' \}\}-\$\{\{ github\.run_number \}\}$",
    ).firstMatch(name);
    expect(names, isNotNull, reason: name);
    final artifact = 'noteapp-${names!.group(1)}-';
    final debugArtifact = 'noteapp-${names.group(2)}-';
    expect(artifact, 'noteapp-apk-');
    expect(debugArtifact, 'noteapp-debug-signed-');
    expect(text, contains('`$artifact<번호>`'));
    expect(text, contains('`$debugArtifact<번호>`'));
    for (final phrase in [
      // 2차 v2 lines (6.21, INFRA-M15, contract 7.8 A-1).
      '고정 키 등록은 [07. 안드로이드 고정 서명 키 등록하기](07-android-signing.md)를 보세요',
      '파일 두 개로 건네요',
      'Claude는 GitHub 설정을 직접 바꿀 수 없어요',
      '**처음 한 번은 기존 앱을 지우고 설치해요.**',
      '그 뒤로는 덮어 설치해요',
      "**'앱이 설치되지 않음'이 뜨면 앱을 지우지 말고 Claude에게 알려 주세요.**",
      '**덮어 설치할 수 없는 시험판**',
      '**실제 노트가 든 기기에는 설치하지 마세요.**',
      '**마이크**와 **알림**',
      '**Wi-Fi에 연결된 상태에서**',
      '앱을 지우거나 기기를 바꾸면 노트가 돌아오지 않아요. 백업 내보내기를 해 두세요',
      '[08. 실기기 체크리스트](08-device-checklist.md)',
    ]) {
      expect(text, contains(phrase));
    }
    // The 1차 advice to remove the app on an install error is gone.
    expect(text, isNot(contains('기존 필기노트 앱을 지운 뒤 설치해요')));
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
    // 2차 (6.21): the iOS compile check, the export question, web notes.
    final compile = _workflow('ios-compile.yml');
    expect(text, contains('**${compile['name']}**'));
    final inputs =
        ((compile['on'] as YamlMap)['workflow_dispatch'] as YamlMap)['inputs']
            as YamlMap;
    for (final input in inputs.keys) {
      expect(text, contains('**$input**'));
    }
    final compileJob = (compile['jobs'] as YamlMap).values.single as YamlMap;
    expect('${compileJob['if']}', "inputs.confirm == 'yes'");
    final upload = [
      for (final step in compileJob['steps'] as YamlList)
        if ('${(step as YamlMap)['uses']}'.startsWith(
          'actions/upload-artifact',
        ))
          '${(step['with'] as YamlMap)['name']}',
    ].first;
    expect(upload, r'ios-compile-${{ github.run_number }}');
    expect(text, contains('`ios-compile-<번호>`'));
    for (final phrase in [
      '## iOS 컴파일 확인 (계정 없이)',
      '**첫 TestFlight 빌드 전에 꼭**',
      '**10배**',
      '`ITSAppUsesNonExemptEncryption`',
      '**웹에서 쓴 노트는 아직 앱으로 옮길 수 없어요.**',
    ]) {
      expect(text, contains(phrase));
    }
    expect(
      File(p.join(repoRoot, 'app', 'ios', 'Runner', 'Info.plist'))
          .readAsStringSync(),
      matches(RegExp(r'<key>ITSAppUsesNonExemptEncryption</key>\s*<false/>')),
    );
  });

  test('07: the secret and variable names of android.yml, the two files, the '
      'error and summary lines (6.10.4, 6.21)', () {
    final text = _read('07-android-signing.md');
    final source = File(p.join(repoRoot, '.github', 'workflows', 'android.yml'))
        .readAsStringSync();
    final job =
        (_workflow('android.yml')['jobs'] as YamlMap).values.single as YamlMap;
    final env = job['env'] as YamlMap;
    final secrets = <String>[];
    final variables = <String>[];
    for (final entry in env.entries) {
      final value = '${entry.value}';
      final secret = RegExp(r'secrets\.(\w+)').firstMatch(value);
      final variable = RegExp(r'vars\.(\w+)').firstMatch(value);
      if (secret != null) secrets.add(secret.group(1)!);
      if (variable != null) variables.add(variable.group(1)!);
    }
    expect(secrets, [
      'ANDROID_KEYSTORE_BASE64',
      'ANDROID_KEYSTORE_PASSWORD',
      'ANDROID_KEY_ALIAS',
      'ANDROID_KEY_PASSWORD',
    ]);
    expect(variables, ['ANDROID_CERT_SHA256']);
    // The secrets table: one row per secret, the variable in step 3.
    final rows = [
      for (final m in RegExp(
        r'^\| `(ANDROID_\w+)` \|',
        multiLine: true,
      ).allMatches(text))
        m.group(1)!,
    ];
    expect(rows, secrets);
    expect(text, contains('**Name** 칸에 `${variables.single}`'));
    for (final phrase in [
      '`noteapp-signing-secrets.txt`',
      '`noteapp-sideload.p12`',
      '**파일 두 개**',
      'Claude는 이 저장소의 GitHub 설정을 직접 바꿀 수 없어요(권한이 없어요)',
      '**Settings** → 왼쪽 **Secrets and variables** → **Actions**',
      '**앞뒤 공백이나 줄바꿈이 들어가지 않게**',
      '따로 보관',
      '`noteapp-apk-<번호>`',
      '`noteapp-debug-signed-<번호>`',
      '한 번만 기존 앱을 지우고 설치해요',
      '[05. 안드로이드 APK 설치하기](05-android-apk.md)',
    ]) {
      expect(text, contains(phrase));
    }
    // The workflow's messages point at this guide; the guide quotes them.
    final errors = [
      for (final m in RegExp(r'::error::([^"]+)"').allMatches(source))
        if (m.group(1)!.contains('docs/guides/07-android-signing.md'))
          m.group(1)!,
    ];
    expect(errors, hasLength(2));
    expect(errors.first, startsWith('고정 키 서명 재료가 없어요 — '));
    expect(text, contains("'고정 키 서명 재료가 없어요'"));
    expect(errors.last, contains('ANDROID_CERT_SHA256와 달라요'));
    expect(text, contains("'… ANDROID_CERT_SHA256와 달라요'"));
    for (final summary in ['서명: 고정 키 (', '서명: debug 키 ']) {
      expect(source, contains('echo "$summary'));
    }
    expect(text, contains("'서명: 고정 키 (…)'"));
    expect(text, contains("'서명: debug 키 …'"));
  });

  group('08 (contract 7.8 word for word)', () {
    late String text;
    late ({Map<String, String> headers, Map<String, String> items}) contract;
    setUp(() {
      text = _read('08-device-checklist.md');
      contract = _contract78();
    });

    test('the contract has A-1~A-6, B-1~B-16, C-1~C-4', () {
      expect(contract.items.keys, [
        for (var i = 1; i <= 6; i++) 'A-$i',
        for (var i = 1; i <= 16; i++) 'B-$i',
        for (var i = 1; i <= 4; i++) 'C-$i',
      ]);
      expect(contract.headers.keys, ['A', 'B', 'C']);
    });

    test('every item, in order, with the contract sentence', () {
      final items = <String, String>{
        for (final m in RegExp(
          r'^- \[ \] \*\*([ABC]-\d+)\*\* (.+)$',
          multiLine: true,
        ).allMatches(text))
          m.group(1)!: m.group(2)!,
      };
      expect(items.keys, contract.items.keys);
      for (final id in contract.items.keys) {
        expect(items[id], contract.items[id], reason: id);
      }
      // Each item says what to look at and how to report it.
      final lines = text.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].startsWith('- [ ] **')) continue;
        expect(
          lines[i + 1],
          matches(RegExp(r'^  - (하는 법|알려 줄 것): ')),
          reason: lines[i],
        );
        expect(lines[i + 1], contains('알려 줄 것: '), reason: lines[i]);
      }
    });

    test('the three section lines, under their headings', () {
      for (final MapEntry(:key, :value) in contract.headers.entries) {
        final heading = text.indexOf('\n## $key. ');
        expect(heading, greaterThan(0), reason: key);
        final quote = text.indexOf('\n> $value\n', heading);
        expect(quote, greaterThan(heading), reason: key);
        expect(text.indexOf('\n## ', heading + 1), greaterThan(quote));
      }
      // B's 'live 채널' is the development branch preview before main (04).
      expect(text, contains('`main`이 생기기 전에는'));
      expect(text, contains('개발 브랜치 미리보기 주소가 그 자리예요'));
    });

    test('the report form, the B-13 order, C-1 restart, the guides it '
        'leans on', () {
      final form = RegExp(
        r'```text\n(.*?)```',
        dotAll: true,
      ).firstMatch(text.substring(text.indexOf('\n## 확인 방법')));
      expect(form, isNotNull);
      expect(
        [
          for (final line in form!.group(1)!.trim().split('\n'))
            line.split(':').first,
        ],
        ['기기', '판', '항목', '결과', '메모'],
      );
      expect(form.group(1), contains('통과 / 실패 / 못 함'));
      final order = text.substring(
        text.indexOf('\n### B-13 순서'),
        text.indexOf('\n## C. '),
      );
      expect(
        RegExp(r'^\d\. ', multiLine: true).allMatches(order).length,
        greaterThanOrEqualTo(8),
      );
      for (final phrase in [
        '200쪽',
        '이미지 20개',
        '30분',
        'PDF로 내보내요',
        '캐시 합계',
        '500쪽',
      ]) {
        expect(order, contains(phrase));
      }
      expect(text, contains('**앱을 완전히 닫았다 열어요**'));
      for (final link in [
        '04-ipad-web-test.md',
        '05-android-apk.md',
        '06-ios-testflight.md',
        '07-android-signing.md',
      ]) {
        expect(_relativeLinks(text), contains(link));
      }
      // The section titles it names are the app's.
      final strings = _appStrings();
      for (final name in [
        'sectionDeveloper',
        'sectionFeatures',
        'sectionV1Copy',
        'featureOffInBuild',
      ]) {
        expect(text, contains(strings[name]), reason: 'AppStrings.$name');
      }
    });
  });
}
