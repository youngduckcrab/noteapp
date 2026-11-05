# INFRA 2차 계획서 검토 — `01-infra.md`

> 검토자: 총괄 대리 검토자 · 검토일 2026-11-05
> 대상: [01-infra.md](../01-infra.md)(2,665줄, 초안) — 기반 · 빌드 · 배포 · 플랫폼 설정 (+ `pencil_bridge`)
> 기준: 개요 [00-overview.md](../00-overview.md) 7장 통합 계약 v2.0 초안, 조사 01~04, PLAN.md(F-03·F-10~F-16, 7.6, 9.5, 10장), 1차 INFRA 작업 트리 `/home/user/wt/infra`(`1a62fba`), 1차 통합 진행 중인 `/home/user/noteapp`(HEAD `6c470ab`, 브랜치 `claude/note-app-planning-bk29xb`), 다른 영역 계획서 02~06(07-sync는 아직 없음)
> 확인 방법: 계획서 전 절을 읽고, 계약·다른 계획서의 맞닿은 절을 grep으로 대조하고, 1차 코드·pub 캐시·Flutter 엔진 소스·pub.dev API로 사실을 확인했다(임시 작업 `/tmp/claude-0/plan57-scratch/infra-review/`). 무거운 시험은 돌리지 않았다.

---

## 총평

계약 7장을 충실히 옮긴 꼼꼼한 계획서다. 특히 좋은 점:

- 컨테이너에서 네이티브를 빌드할 수 없다는 제약을 `native_config_test`·`ws native-reqs`(NR1~NR7)·Swift 와이어 대조 시험으로 메우는 구조가 구체적이고, 근거(pub 캐시 파일·줄 번호·Flutter 템플릿)를 대부분 실제로 확인했다. 내가 다시 본 것도 맞았다 — `flutter_foreground_task 11.0.3` 매니페스트(`RebootReceiver`·`RECEIVE_BOOT_COMPLETED`·`WAKE_LOCK`)·iOS 쪽 `BGTaskScheduler` 등록은 Info.plist 키가 없으면 건너뜀(크래시 없음), pbxproj 15.0 세 곳(363·490·542행), ML Kit README Podfile 줄, pub.dev 게시일(`shared_preferences_android 2.5.3` 10-22·`2.5.4` 10-27, `image_picker_ios +13` 10-22, `xml 7.0.1` 04-25), Flutter 엔진의 호버 인식기 `shouldRecognizeSimultaneously… → YES`(`FlutterViewController.mm` 2088행).
- 기여(`ShellContribution`)·유휴 작업(`AppIdleTask`)·`isEnabled`로 '꺼진 모듈은 시작도 연결도 안 한다'를 부트스트래퍼 한 곳에서 지키는 설계가 깔끔하고, 계약 7.3.3 표·X28~X35와 시그니처가 맞는다(`EditorPanelContext` → `RecordingPanel` 인자, `RecognitionTarget` ↔ 문맥 1:1, `LibraryOpenNoteAt` → `openNote(focusRectPt:)`, `StylusCapabilities` 대응 — 모두 계약 원문과 같음).
- 다른 영역에 보낸 요청(R-1~R-8, CP1~CP15)이 대부분 받아들여졌다(INK CP3·CP5·CP7 동의, PDF CP6=CP-PDF-3, LIBRARY CP4=CP-L2·CP13=CP-L3, R-3 멱등 `dispose` 양쪽 수락).

그러나 **그대로 승인할 수 없다(revise)**. 가장 큰 문제는 ① 바탕 코드를 1차 INFRA 작업 트리(`1a62fba`)로 잡아 **이미 끝난 1차 통합 결과(ink lab 멤버·`app_members`·`ws test` 시간 제한/재시도·`android.yml` 트리거·CI 25분 실측)를 반영하지 않았고**, '전체'라고 적은 설정 블록을 그대로 쓰면 워크스페이스가 깨진다는 점, ② 계약상 `final class`인 색인기를 '횟수 세는 가짜로 override'하는 시험을 완료 조건으로 삼아 **쓸 수 없는 시험**이 있다는 점, ③ `plugin_packages`·`pinned_external`이 자기 CP1과 PDF의 R2-B1 요청(CP-PDF-9)과 어긋나 **J22·V12에서 위반이 난다**는 점, ④ `FEATURE_MEDIA`가 P-A 기능인 **이미지 삽입까지 끈다**는 점이다. 그 밖에 R2-B8 작업 크기(모든 영역의 동시 개발 시작을 막음), CI 시간 예산, debug 서명 대체로 인한 노트 손실 경로, `PencilBridge.events` 캐시가 detach를 막는 문제를 고쳐야 한다.

---

## 반드시 고칠 것

### M-1. 1차 통합 결과를 반영하지 않았다 — '전체' 블록을 그대로 쓰면 워크스페이스가 깨진다

- **위치**: 머리말 7행(바탕 `1a62fba`, 'G1~G5만 남음'), 3.2 루트 `pubspec.yaml`(145~176행), 4.3.1 `workspace_rules.yaml` v2 '전체'(445~562행), 6.10.3 `android.yml` 트리거 '1차 그대로'(1981행~), 6.13·J15 `ws test` 설계(2178행).
- **문제**: `/home/user/noteapp` HEAD(`6c470ab`)에 1차 통합 커밋 `52de08c`(lock 정책·ink lab 멤버·R14)·`d5938c6`(개발 브랜치 APK)·`5adf710`(ws test 시간 제한·재시도·신호)가 이미 있다.
  - 루트 `pubspec.yaml`: `workspace`에 `packages/ink_engine/example`(ink lab), dev `analyzer: 13.3.0`.
  - `tool/workspace_rules.yaml`: `allowed_dependencies.ink_lab: [note_core, ink_engine]`, 새 키 `app_members: [noteapp, ink_lab]`(R14), `lib_exceptions`에 `packages/ink_engine/example/lib/`.
  - 계획서 3.2·4.3.1은 이 줄들이 없는데 '전체'라고 적었다. 그대로 쓰면 ink lab(`resolution: workspace`)이 워크스페이스 밖으로 밀려 `flutter pub get`이 실패하고 R8·R14·R4(ink lab `lib/`가 `testing.dart`를 import) 위반이 난다.
  - `ws test`: 통합에서 `--member-timeout`, chrome 15분 제한·1회 재시도, `resolveChrome`이 찾은 Chrome을 `CHROME_EXECUTABLE`로 내보내는 구조(`test_command.dart` 393행), 종료 코드 2·3·79가 생겼다. J15의 `media` 래퍼·전역 잠금은 이 구조 위에 얹혀야 하는데 계획서는 1차 작업 트리 기준으로 적었다.
  - `android.yml`: 통합에서 `push.branches`에 개발 브랜치를 더했고 'workflow_dispatch는 기본 브랜치에 파일이 있어야 보인다'는 주석이 생겼다. 계획서의 '영역 브랜치는 수동 실행만'은 이 조건을 모른다.
- **고칠 방향**: 바탕을 1차 통합 HEAD로 옮기거나, 최소한 '1차 통합에서 바뀐 것' 표(위 네 묶음)를 3절에 두고 3.2·4.3.1 블록에 ink lab 줄·`app_members`·`analyzer`를 넣는다. J15는 `resolveChrome` 결과를 `NOTEAPP_REAL_CHROME`으로, 래퍼를 `CHROME_EXECUTABLE`로 넘기고 재시도·`--member-timeout`과 잠금의 관계(재시도 동안 잠금 유지)를 적는다. 종료 코드 4가 비어 있는지는 확인했다(현재 2·3·79만 씀).

### M-2. 색인기 '가짜 override' 시험을 쓸 수 없다 (`final class`)

- **위치**: 5.8 표 ink_recognition·pdf_io 행(1671·1672행), J8 완료 조건 'start/dispose 횟수'(2410행), J10 'start 1회·dispose 1회'(2412행), 9.1 `pdf_module_test`·`recognition_module_test`.
- **문제**: 계약 7.2.12 `final class PdfSearchIndexer`, 7.2.11 `final class HandwritingIndexer`다. Dart 3에서 `final class`는 선언한 라이브러리 밖에서 `implements`·`extends`할 수 없고, provider 값 타입이 그 클래스(`Provider<PdfSearchIndexer>`, `Provider<HandwritingIndexer?>`)라서 '횟수를 세는 가짜 색인기로 override'는 컴파일되지 않는다. J8·J10의 완료 조건이 실행 불가능하다(동시 개발 중 가짜 부재).
- **고칠 방향**: 계약을 바꾸지 않고 INFRA 쪽 이음새로 푼다 — 예: 유휴 작업이 `({void Function() start, Future<void> Function() dispose}) Function(AppIdleContext)` 같은 주입 함수를 받아, 생산 코드는 provider를 읽어 감싸고 시험은 기록용 레코드를 넣는다(`PdfModule({… indexerHandle = readPdfSearchIndexer})`). 실제 색인기는 H2에서 가짜 저장소로 만들어 '두 번 dispose해도 안전'만 확인한다. 5.8·J8·J10·9.1 문구를 이에 맞춘다(C-2).

### M-3. `plugin_packages`·`pinned_external`·`media_io` pubspec이 CP1·PDF CP-PDF-9와 어긋난다 — NR6·R9(strict) 위반

- **위치**: 3.3 `media_io/pubspec.yaml` 블록(183~205행), 4.3.1 `pinned_external`·`plugin_packages`(552행), 6.3 NR6, 7.2 표.
- **문제**:
  1. CP1이 승인되면 `media_io`가 `shared_preferences_android`·`shared_preferences_foundation`(Flutter 플러그인)을 **직접** 의존한다. 그런데 `plugin_packages`에는 `shared_preferences`만 있고 두 패키지가 없다 → NR6('직접 의존 중 플러그인이 `plugin_packages`에 없음') 위반. 또 3.3 블록은 '승인 전에는 넣지 않음'이라면서 두 줄을 실제 값으로 적어 R2-B1에서 헷갈린다.
  2. PDF 계획서 3.4·7.2(CP-PDF-9)가 R2-B1 `media_io` pubspec에 직접 의존 7개를 요청한다: `flutter_web_plugins`(SDK), `record_web 2.1.3`, `just_audio_web 0.4.16`, `record_platform_interface 2.1.0`, `just_audio_platform_interface 4.6.0`, `image_picker_platform_interface 2.11.2`, `plugin_platform_interface 2.1.8`(모두 lock에 간접으로 있음 — PDF 확인). 계약 7.4.6이 `media` 시험에서 `RecordPluginWeb.registerWith`·`JustAudioPlugin.registerWith`를 직접 부르라고 하므로 사실상 필요하다. INFRA 3.3·`pinned_external`에 없어 R9w(`ws check --strict` 실패 — J22·H1 조건)이고, `record_web`·`just_audio_web`은 웹 플러그인이라 NR6에도 걸린다.
- **고칠 방향**: 3.3 블록을 PDF 3.4 확정본과 맞춘다(승인 대기 줄은 주석으로 표시). `pinned_external`에 7개(+ CP1 두 줄) 추가, `plugin_packages`에 `record_web`·`just_audio_web`·`shared_preferences_android`·`shared_preferences_foundation`(J21 뒤에는 `integration_test`도 — S-5) 추가. 또는 NR6 범위를 'R16 `plugin_free_members`의 직접 의존'으로 좁힌다(서비스 패키지·앱은 플러그인을 쓰는 게 정상이므로 이쪽이 더 단순하다). 12.2 표에 CP-PDF-9 수용 여부를 적는다(C-4).

### M-4. `FEATURE_MEDIA`가 P-A 기능인 이미지 삽입·이미지 페이지까지 끈다

- **위치**: 6.6 표 '녹음' 행(1830~1840행), 4.6.4 `MediaModule`, 9.1 `feature_switch_test` '차이가 녹음 버튼·인식 메뉴·수식 엔진·자동 도형 보정뿐'(2476행), CP14(2607행).
- **문제**: 이미지 가져오기(`editorImageImporterProvider`)가 `MediaModule`의 기여라서 '녹음' 스위치를 끄면 M5-3 이미지 삽입·M5-4 이미지 페이지(둘 다 P-A)가 함께 사라진다. PLAN 7.6이 스위치 대상으로 든 것은 '유료가 될 기능(수식 인식, 녹음 텍스트 변환 등)'이고 이미지 삽입은 아니다. 계약 V15('차이가 녹음 버튼·인식 메뉴·수식 엔진뿐')와도 충돌하는데, 계획서는 CP14로 '자동 도형 보정'만 더하고 이미지 삽입은 빠뜨렸다 — 계획대로 쓴 V15 시험은 목록에 없는 차이(이미지 삽입 메뉴·페이지 추가 시트 '이미지')로 실패하거나, 그 차이를 놓친 채 통과한다. 설정 화면의 '녹음' 스위치 문구도 사용자를 오도한다.
- **고칠 방향**(총괄 결정 필요 — Q-2): 권장안은 `FEATURE_MEDIA`가 녹음만(오디오 override·녹음 패널·초안 복구·이탈 경고) 끄고, 이미지 가져오기는 스위치와 무관하게 연결하는 것이다(예: `MediaModule`은 항상 시작하고 녹음 기여만 `featureOn(media)`로 거름, 또는 `ImageImportModule`을 따로 둠). 이 경우 '끄면 dart2js가 media_io를 버린다'는 6.6 문장은 '녹음 코드만'으로 고친다. 다른 안은 스위치 이름을 '녹음·이미지'로 바꾸고 CP14에 '이미지 삽입·이미지 페이지'를 더하는 것이다. 어느 쪽이든 6.6 표·9.1·CP14·V15를 한 문장으로 맞춘다(C-3).

### M-5. R2-B8이 한 세션에 끝나지 않고, 7개 영역 전체의 동시 개발 시작을 막는다

- **위치**: 8.1 R2-B8(2395행), 1.2 표.
- **문제**: 기반 단계 하나에 ①~⑩(기능 스위치, 부트스트랩 확장, 모듈 2개, 연결 v2·기여 합치기, 라우팅, `pencil_bridge` Dart 표면 + Swift 골격 + podspec + `Package.swift`, 어댑터, 네이티브 설정 6종 + `native_config.dart` + `native_config_test`, `overrides_unique_test` v2, 웹 빌드 실측 두 번)과 시험 파일 14개가 몰려 있다. 1차 INFRA 작업 기준으로 3~4세션 분량이다. 계약 7.6은 '기반 단계가 끝나면 동시 개발 시작'이라, 다른 영역은 앱 셸에 의존하지 않는데도 R2-B8이 늦어지면 모두 기다린다. 계획서의 '⑤⑥⑦⑧은 먼저 써 둔다'는 작성 시점만 당길 뿐 `main` 커밋 순서는 그대로다.
- **고칠 방향**: R2-B8을 계약 7.6 표의 최소 내용(모듈 2개·`AppFeatures`·7.3.3 연결·라우팅·`pencil_bridge` Dart 표면·어댑터)으로 줄이고, 세션 크기로 R2-B8a(부트스트랩 확장·`AppFeatures`·모듈·연결)·R2-B8b(라우팅·`pencil_bridge`·어댑터)처럼 나눠 각각 완료 조건을 둔다. 네이티브 설정 파일·`native_config_test`(⑧)와 웹 빌드 실측(⑩)은 동시 개발 첫 작업(J0 등)으로 내린다 — 둘 다 다른 영역이 기다릴 이유가 없다. 계약에는 'R2-B8은 다른 영역 동시 개발의 시작 조건이 아니다'를 제안한다(C-5).

### M-6. CI 시간·Actions 예산이 1차 통합 실측을 반영하지 않았다

- **위치**: 6.16 표(2235~2248행) — `ci.yml` 1회 9분·월 1,080분, 6.13 CI 단계 추가, J15.
- **문제**: 1차 통합 진행 기록(`/home/user/noteapp/docs/plans/progress/infra.md` 'Chrome 실행 안정화')이 이미 '7개 멤버 Chrome 단계만 로컬 약 8분 30초, `ci.yml` 잡 제한 25분에 R14(약 1분)·VM·도구 시험·웹 빌드가 함께 들어가므로 넘치면 잡 제한 또는 `--member-timeout`을 조정한다'고 적었다(`ci.yml`은 단일 잡, `timeout-minutes: 25`). 2차는 멤버 3개(각자 Chrome 시험), `media` 단계, `native-reqs`·`web-budget`, 통합 태그 확대가 붙는다. GitHub 비공개 저장소 표준 러너는 컨테이너(4 CPU)보다 느릴 수 있다. 9분 가정이면 main CI가 25분 제한에 걸려 실패하거나 월 2,000분을 넘는다(1,592분이라는 80% 계산이 무너짐).
- **고칠 방향**: R2-B8(또는 첫 체크포인트) 푸시에서 단계별 시간을 실측해 6.16을 다시 계산하는 것을 완료 조건으로 넣는다. 잡을 나누는 안(check·analyze·VM / Chrome / integration·media / 웹 빌드·배포)과 그때의 분 증가(병렬은 벽시계만 줄임)를 적고, 영역 브랜치 푸시는 affected만·`media`·integration은 main·수동만으로 한다. 25분 제한 대책을 J15 완료 조건에 넣는다.

### M-7. 고정 키를 쓰기로 한 뒤에도 debug 서명 APK가 조용히 나온다 — 노트 손실 경로

- **위치**: D2-7, 6.10.3 '서명 확인'(1989행), 안내서 05·07(6.21).
- **문제**: 저장소 변수 `ANDROID_CERT_SHA256`가 있는데(=고정 키를 쓰기로 함) 시크릿이 빠지면(삭제·이름 오타·`pull_request`·포크 실행) CI는 debug 서명 APK를 만들고 **성공**한다. 사용자가 그 아티팩트를 받아 설치하면 '앱이 설치되지 않음' → 지우고 설치 → 기기의 노트(공통-1 이후 파일 DB·블롭)가 사라진다(위험 5·A-1). '덮어 설치할 수 없어요'는 실행 요약에만 있어 아티팩트만 내려받는 사용자에게 보이지 않는다.
- **고칠 방향**: `ANDROID_CERT_SHA256`가 있는데 서명 재료가 없으면 잡을 실패시키거나 아티팩트를 올리지 않는다. debug 서명일 때는 아티팩트 이름에 드러낸다(예: `noteapp-debug-signed-<run>`). 안내서 05에 '설치가 안 되면 앱을 지우지 말고 Claude에게 알려 주세요'. `workflows_test`에 이 분기를 넣는다.

### M-8. `PencilBridge.events` 캐시가 마지막 취소의 detach를 막는다

- **위치**: 6.12.1(2102행) '`….where(non-null)`를 한 번 만들고 `.asBroadcastStream()`으로 캐시', 6.12.4 시험 '마지막 취소 1회 cancel'(2147행).
- **문제**: Dart `Stream.asBroadcastStream()`은 `onCancel` 콜백이 없으면 첫 구독 때 원본을 구독한 뒤 **원본이 끝날 때까지 구독을 유지한다**. 그래서 마지막 구독자가 취소해도 EventChannel `cancel`이 네이티브로 가지 않고, 계약 7.2.13 'detaches on last cancel'을 어긴다(호버·롤 인식기가 붙은 채 남음). 계획서 자신의 시험도 실패한다.
- **고칠 방향**: `receiveBroadcastStream()`은 이미 브로드캐스트이고 `map`·`where`도 브로드캐스트를 유지하므로 `asBroadcastStream()`을 빼고 그 결과를 캐시한다(또는 `asBroadcastStream(onCancel: (s) => s.cancel())`). 시험: 두 구독자 → 둘 다 취소 → mock cancel 1회 → 다시 구독 → listen 2회째.

---

## 권장

- **S-1 유휴 작업 순서**(S2-5, 777행; 6.17): `media.leaveGuard`는 구독 하나라 비용이 없는데 `pdf.searchIndexer`·`media.recoverDrafts` 뒤에 줄을 선다. 3시간 녹음 복구처럼 긴 작업(CORE 위험 8 — 웹 86 MB)이 앞에 있으면 그동안 시작한 녹음에 이탈 경고가 없다. 이탈 경고는 성공 화면 직후 바로(유휴 작업 밖) 걸고, 유휴 순서는 `media.recoverDrafts` → 색인기 둘로 한다. CP15의 '순서 pdf → media → recognition'도 '데이터 보호 먼저'로(C-6).
- **S-2 '`resumed`일 때만 실행'**(6.5.1 2번): Flutter 웹은 창 `blur`에 `inactive`를 보낸다(엔진 `app_lifecycle_state.dart` 95행). iPad에서 시스템 선택기·키보드 보조 창이 뜨는 동안에도 기다린다. `hidden`·`paused`·`detached`만 기다리고 `inactive`·`null`은 실행하는 편이 안전하다.
- **S-3 시간 초과 뒤 늦은 `contribute`**(6.4): 비필수 모듈의 `start`는 시간 초과 뒤에도 계속 돈다(1차 `onStartAbandoned` 규칙). 늦게 불린 `contribute`가 대체 기여와 겹치거나 `FeatureWiringModule`보다 늦게 들어오지 않게 '결과가 기록된 모듈의 `contribute`는 무시 + 기록'을 적고 `MediaModule.onStartAbandoned`를 정의한다.
- **S-4 전역 잠금 경로**(W2-6 426행, 2178행): `$TMPDIR`는 에이전트 세션마다 다를 수 있어 '컨테이너 전역'이 보장되지 않는다(이 세션은 비어 있어 `/tmp`). 고정 경로 `/tmp/noteapp-heavy-tests.lock`(환경 변수로 바꿀 수 있게)으로 한다.
- **S-5 `integration_test`(J21)**: SDK 패키지지만 `flutter_driver` → `webdriver`(3.2.0, 2026-09-09)·`sync_http`(0.3.1) 같은 hosted 항목을 lock에 새로 넣고(1차 lock에 없음 — 확인), 플러그인이라 `.flutter-plugins-dependencies`에 `integration_test`(dev)가 생겨 NR1에 걸린다(iOS `Package.swift` 있음 — NR5는 괜찮음). R2-B1에 함께 넣어 lock을 한 번에 만들거나, J21에 lock 변경 절차와 `plugins_without_requirements` 추가를 적는다.
- **S-6 R2-B1의 '빈 플러그인'**: `pluginClass: PencilBridgePlugin`만 있고 Swift 클래스가 없으면 iOS `GeneratedPluginRegistrant`가 없는 클래스를 참조해 R2-B1~R2-B8 사이 `main`의 iOS 빌드가 깨진다(각 단계 뒤 `main`이 빌드 가능해야 한다는 1차 규칙). R2-B1에 빈 `register(with:)`만 있는 Swift 파일·`Package.swift`·podspec을 같이 둔다.
- **S-7 위험 1의 대응 문장**(2550행): Swift 컴파일 오류는 '등록 실패 → 대체 능력'이 아니라 **앱 전체 iOS 빌드 실패**다. `ios-compile.yml` 1회를 Swift가 들어간 뒤 첫 TestFlight 빌드 전 필수로 두고(U19), 실패하면 앱 pubspec에서 `pencil_bridge`를 잠시 빼는 대안(영향은 `FeatureWiringModule` 한 곳)을 적는다.
- **S-8 Pencil attach 대상·인식기 동시 인식**(6.12.2): `FlutterPluginRegistrar.viewController`(Flutter `FlutterPlugin.h` 373행 — `image_picker_ios`·`url_launcher_ios`·`stylet`이 씀)를 `onListen`에서 먼저 쓰고, 키 창 탐색은 대체 경로로 둔다(외부 화면·여러 장면 한계 완화). 우리 `UIHoverGestureRecognizer`에도 delegate `shouldRecognizeSimultaneouslyWith → true`를 명시하고 와이어 대조 시험에 넣는다(엔진 쪽은 이미 YES).
- **S-9 스퀴즈·롤 능력의 뜻**(6.12.2 `capabilities`, 6.12.3): `squeeze`·`roll` = iOS 17.5 이상이라는 OS 가용성일 뿐 펜 종류가 아니다. Pencil 2·USB-C 펜슬에서도 스퀴즈 설정이 보인다(U1 기본값 '능력에 따라 숨김'과 어긋남). EDITOR와 '첫 스퀴즈·롤 이벤트를 받은 뒤 보이기' 또는 'Pencil Pro' 표기를 합의한다.
- **S-10 서명 키 전달**(6.10.4): 개인키 base64(4096비트 PKCS12 ≈ 3.5 KB)를 대화로 넘기면 대화 기록에 남고, iPad에서 GitHub 설정에 붙여 넣다 틀리기 쉽다. 컨테이너의 `gh secret set`·`gh variable set`이 이 저장소에 되는지 먼저 확인해 되면 Claude가 등록하고, 백업용 사본은 파일로 전달한다. 안 되면 지금 방식(Q1 ①)을 쓴다(Q-3).
- **S-11 `functions.yml` 골격**(6.14, 2216행): R2-B1 시점엔 `functions/`가 없다(R2-B7이 만듦). 그런데 트리거 경로에 `app/firebase.json`·워크플로 파일이 있어 R2-B1 푸시만으로 돌고, `setup-node`의 `cache-dependency-path: functions/package-lock.json`·`npm ci`가 실패한다. `if: hashFiles('functions/package.json') != ''` 가드를 둔다. 또 `.env.local`·`.secret.local`은 `.gitignore`라 CI에 없다 — 에뮬레이터 시험 전에 더미 값(엔진 `fake`, `OWNER_UIDS`)을 만드는 단계를 누가 맡는지 SYNC와 정한다(X-6).
- **S-12 V5 10단계 PDF 내보내기**(9.1 단계 표): 1차 V5는 가짜 PDF 동작만 썼다(`app/test/support/smoke_scenario.dart`). 실제 `exportNotesAsPdf`는 VM에서 PDFium 네이티브(빌드 훅), Chrome에서 PDFium wasm 자산이 필요하다. 어느 환경·태그로 확인하는지, 아니면 INK `InkPageVectors` 개수로 대신하는지 적는다.
- **S-13 초안 복구 시험의 가짜**(6.5.2 시험): 계약 7.6 `FakeAudioRecorder`에는 `pendingDrafts`를 채울 방법이 없다(CORE CP-8 `abandon()` 제안 중). INFRA 자체 `ScriptedAudioRecorder implements AudioRecorderService`를 `app/test/fakes/`에 두거나 CP-8 의존을 명시한다.
- **S-14 `.gitattributes`**: `* text=auto`가 자동 판정하지만, INK 글꼴(`*.ttf`, 약 933 KB — 03-ink Q6가 INFRA에 요청)·PDF 녹음 표본(`*.webm`·`*.m4a`)·`*.otf`를 `binary`로 명시한다.
- **S-15 시작 글꼴 예산 여유**(4.3.3 619행): KaTeX gzip 370,984 B + Material·Cupertino 약 7 KB ≈ 378 KB로 한도 400,000 B까지 약 22 KB다. 2차 UI가 아이콘을 늘리면 MaterialIcons(트리 셰이킹 결과)가 커진다. 글꼴 묶음별 한도(KaTeX / 아이콘)로 나누거나 R2-B8 실측 뒤 정한다.
- **S-16 네이티브 경로의 `assets/`**(6.9): CORE 계획서(6.15.3)는 블롭 루트를 만든다고 적지 않는다. INFRA가 `<support>/noteapp/assets`까지 만들거나 CORE와 확인한다.

---

## 다른 영역과 걸리는 것

- **X-1 (PDF)**: M-3 — CP-PDF-9 직접 의존 7개를 R2-B1 `media_io` pubspec·`pinned_external`·`plugin_packages`에 넣을지 결정. M-2 — `PdfSearchIndexer`가 `final class`라 INFRA는 주입 이음새로 시험(PDF 쪽 변경 없음). `NSPhotoLibraryUsageDescription` 문구가 PDF 부록 B('…열어야 해요')와 INFRA 6.11.4('…접근해야 해요')로 다르다 — INFRA 소유이므로 하나로 정해 PDF에 알린다. 일치 확인: `stopWithTask="true"`(PDF 부록 B·INFRA Q7), CP6 = CP-PDF-3, `dispose` 멱등(PDF 5.4).
- **X-2 (LIBRARY)**: M-2 — `HandwritingIndexer`도 `final class`. CP-L1(`HandwritingIndexerStatus` 필드)·CP-L2(INFRA CP4 지지)·CP-L3(CP13 지지) 수락 확인. LIBRARY는 `google_mlkit_commons`를 직접 의존하지 않는다(05-library 297행) → `pinned_external`의 '직접 쓰면' 줄은 주석으로 정리. R-7(`NOTEAPP_FUNCTIONS_URL`) 수락됨(05-library 1192·1666행). 에뮬레이터 소유자 UID·Auth REST 형식은 SYNC와 맞춰야 한다(05-library 12.2 Q4).
- **X-3 (EDITOR)**: CP-E6(`StylusExtraEvent`에 선택 `timestamp`)가 승인되면 INFRA 6.12.3 변환 표에 `PencilEvent.timestamp` 전달 열을 더한다. CP-E8(V5 '90° 회전'을 선택 메뉴 경로로)과 부록 C 위젯 키로 9.1 V5 단계 표를 갱신한다. EDITOR 1912행('`inkShapeFitterProvider is NoShapeFitter`면 도형 보정 토글 숨김')은 INFRA CP14와 맞는다.
- **X-4 (CORE)**: `android:allowBackup="false"`(INFRA Q13)는 CORE 권장(02-core 2272행 'DB·블롭은 백업 대상')과 반대다 — 총괄 결정이 필요하다. CP-8(`FakeAudioRecorder.abandon`)이 S-13에 걸린다. `app.*` 설정 키 접두사(CP12) 확인. CORE가 요청한 'sqlite3 3.8.0 빌드 훅이 CI에서 GitHub 릴리스를 받는다'(02-core 2269행) — `android.yml`·`ios-compile.yml`의 훅 캐시 키·네트워크 단계에 sqlite3을 명시한다. S-16(`assets/` 생성 주체).
- **X-5 (INK)**: CP3·CP5·CP7 동의 확인(03-ink 1997~1999행). S-14(글꼴 binary), S-15(KaTeX 예산 여유).
- **X-6 (SYNC)**: `07-sync.md`가 아직 없어 R-6·CP11(`functions/package.json`의 `firebase-tools 15.34.2` devDependency, 스크립트 이름 `build`·`test`·`test:emulator`, `--config ../app/firebase.json`)을 확인할 수 없다. `.env.local`·`.secret.local` 더미 생성 주체와 `OWNER_UIDS` 값(S-11, X-2), R2-B1 시점 `functions/` 부재(S-11)도 SYNC 계획서가 나오면 대조한다.

---

## 계약 문제

- **C-1 (7.8 A-1)**: 'A-1 고정 서명 APK 덮어 설치 → **1차·2차 노트**가 남아 있음'은 실현할 수 없다. 1차 APK는 러너마다 새 debug 키로 서명되고 앱 셸이 네이티브 경로를 넘기지 않아 노트 저장이 열리지 않았다(조사 04 요약 5). '고정 키 2차 APK 두 판 사이 덮어 설치 → 노트 유지(처음 한 번은 기존 앱을 지우고 설치)'로 고친다. 안내서 08이 계약 번호·문구를 그대로 옮기므로(번호 대조 시험) 계약에서 고쳐야 한다.
- **C-2 (7.2.11·7.2.12)**: 색인기가 `final class`라 앱 셸이 provider override로 가짜를 넣을 수 없다. INFRA 이음새로 풀되(M-2), 계약에 '색인기 시작·종료 시험은 앱 셸 주입 이음새로 한다'를 적어 다른 영역이 provider override 시험을 기대하지 않게 한다.
- **C-3 (D14·7.3.3·7.7 V15)**: 이미지 가져오기가 어느 스위치에 속하는지 정하고(M-4), V15 차이 목록을 그 결정과 CP14(자동 도형 보정)에 맞춘다.
- **C-4 (7.5·7.4.1)**: 7.5 표에 CP1(`shared_preferences_*` 간접 고정)·CP2(`xml`)·CP-PDF-9(7개) 행을 더한다. 7.4.1 R16의 '1차 `pdf_io`의 `file_picker`·`pdfium_dart`는 기존 예외'는 실제와 다르다 — `pdfium_dart`·`pdfrx` 모두 pubspec에 `flutter: plugin:`이 없고(pub 캐시 확인, 플러그인은 그 아래 `pdfium_flutter`), `pdf_io`가 직접 의존하는 플러그인은 `file_picker`뿐이다. INFRA 4.3.1의 `pdf_io: [pdfrx, file_picker]`도 함께 정리한다.
- **C-5 (7.6)**: CP8(R2-B8 경로에 `app/android/**`·`app/ios/**`·`native_config` 명시)과 함께 'R2-B8은 다른 영역 동시 개발의 시작 조건이 아니다(R2-B6까지 `main`에 있으면 시작)'를 넣는다(M-5).
- **C-6 (7.3.3 'override가 아닌 연결', CP15)**: 유휴 작업 순서를 모듈 순서가 아니라 우선순위(이탈 경고·초안 복구 → 색인기)로 정한다(S-1).
- **C-7 (7.7 V5)**: 한 문장 안에 '녹음기·…·수식 엔진은 가짜로 override'와 '7.3.3의 override가 모두 실제 구현이고 한 번씩'이 함께 있다. '가짜는 모듈 주입 인자로 넣고, override 출처·횟수는 실제 모듈 경로로 확인'으로 고친다(Riverpod는 같은 provider 두 번 override를 디버그에서 막는다 — 1차 `overrides_unique_test` 주석).
- **C-8 (7.3.2 M-2)**: 'M-2 … 다음 실행 때 `pendingDrafts()`로 복구를 **묻는다**'와 7.2.12·D13의 '**묻지 않고** 녹음으로 만든다'가 충돌한다(CORE CP-12와 같음). INFRA는 '묻지 않음'으로 구현하므로 계약 문장을 정리한다.

---

## 질문

- **Q-1**: 1차 통합(G4·G5)이 끝난 `main`을 바탕으로 이 계획서를 다시 맞추는 시점은 언제인가? '기반 단계 시작 때 고친다'로 두더라도 3.2·4.3.1처럼 '전체'라고 적은 블록은 지금 고쳐야 한다(M-1).
- **Q-2**: `FEATURE_MEDIA`의 범위 — 녹음만인가, 녹음 + 이미지 삽입인가(M-4)? 권장은 녹음만.
- **Q-3**: 이 세션의 GitHub 권한으로 `gh secret set`·`gh variable set`이 되는가(S-10)? 되면 개인키를 대화로 넘기지 않아도 된다.
- **Q-4**: R2-B8을 기다리지 않고 다른 영역의 동시 개발을 시작해도 되는가(M-5, C-5)?
- **Q-5**: `ios-compile.yml` 1회가 P-C(선택)라 Swift가 한 번도 컴파일되지 않은 채 2차가 끝날 수 있다. U19 기본값(통합 뒤 1회)을 '필수'로 확정할 것인가(S-7)?
