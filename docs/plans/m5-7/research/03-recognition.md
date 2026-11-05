# 2차 라운드 기술 조사 03 — 손글씨·수식 인식 엔진과 검색 색인

> 상태: 조사 완료(2026-11-05) · 담당: 2차 라운드 기술 조사(인식) · 기준 계약: [00-overview.md 7장 v1.4](../../00-overview.md#7-통합-계약) · 마스터 기획서: [PLAN.md](../../../PLAN.md) F-10·F-11·F-14, 5.1·5.2 검색, 6.2 세부 스택, 10장 M5·M7 · 함께 읽을 문서: [01-hooks.md](01-hooks.md)(3.10 검색 자리, 4.1 FTS5 실험, R7 인식 결과 동기화)
>
> 이 문서는 M7(손글씨→텍스트, 손글씨 검색 색인, 수식 인식·렌더링)과 M5 자동 도형 보정의 **엔진·패키지 조사**다. 후보마다 임시 프로젝트에서 의존성 해석과 컨테이너에서 돌릴 수 있는 실험을 했고, 설계 결정은 하지 않는다. 조사자의 의견은 11절 '권장안', 결정할 것은 12절 '열린 질문'으로 분리한다.

표기

| 표시 | 뜻 |
|---|---|
| **[확인]** | 소스를 읽거나 명령을 실행해 직접 확인한 사실(경로·줄 번호·명령을 함께 적음) |
| **[문서]** | 이 저장소의 계획서·계약, 또는 이 세션의 Claude API 참고 자료(claude-api 스킬, 2026-10-06 캐시)에 적힌 내용 |
| **[검색 요약]** | 웹 검색 결과 요약으로만 본 내용. 원문 페이지는 세션 네트워크 허용 목록 밖이라 직접 열지 못했다(2.3절). 출처 URL을 함께 적는다 |
| **[추측]** | 확인하지 않은 판단(조사자의 기존 지식 포함). 근거를 함께 적고, 설계·구현 전에 확인이 필요하다 |
| **[추정]** | 공개 단가에 가정한 사용량을 곱한 계산. 가정을 함께 적는다 |

---

## 1. 요약 — 핵심 사실

1. **`google_mlkit_digital_ink_recognition` 최신은 0.16.1(2026-08-17)이고 Flutter 3.47.9에서 계약 고정 버전들과 함께 해석된다.** `sdk ^3.12.0`, `flutter >=3.44.0`, 의존은 `google_mlkit_commons 0.13.0`. 플러그인 플랫폼은 **android·ios 둘뿐**이고 README가 "Web or any other platform is not supported"라고 적는다. 네이티브 라이브러리는 안드로이드 `com.google.mlkit:digital-ink-recognition:19.0.0`(compileSdk 36, minSdk 21), iOS `GoogleMLKit/DigitalInkRecognition ~> 9.0.0`(배포 대상 **15.5 이상**). [확인]
2. **입력은 점 `(x, y, t)` 목록의 획 목록, 출력은 후보 문자열 + 점수뿐이다.** `t`는 `int` 밀리초. 문맥으로 `preContext`(앞 글자)와 `WritingArea(width, height)`를 줄 수 있다. 후보에는 글자·단어별 위치(분할) 정보가 없다 — 검색 하이라이트용 위치는 우리가 획 묶음(줄)에서 구해야 한다. 점수는 "낮을수록 유력, 지원하는 모델만" 채워지고 플러그인은 없으면 `0.0`을 넣는다. [확인 — Dart·Kotlin·Swift 소스]
3. **모델은 실행 중 내려받는다.** `DigitalInkRecognizerModelManager`의 `isModelDownloaded`·`downloadModel(isWifiRequired: true 기본)`·`deleteModel`. 안드로이드는 Wi-Fi 조건을 지키지만 **iOS 구현은 이 인자를 무시하고 항상 셀룰러를 허용**한다. 모델이 없으면 `recognize`가 "Model has not been downloaded yet" 오류로 끝난다. 모델 크기는 언어당 약 20MB라는 공식 블로그 문구가 검색된다. [확인 — 소스 / 크기는 검색 요약]
4. **한국어 모델은 있다(검색 요약). 태그는 `ko`로 추정한다.** Google 공식 예제 앱(googlesamples/mlkit, 2026-10-21 커밋)은 텍스트 모델을 `allModelIdentifiers()`로 나열하므로 태그 목록이 소스에 없다. 잘못된 태그는 플러그인이 "Failed to create model identifier"/"No model was found" 오류를 돌려주므로 첫 실기기 실험에서 바로 판정된다. 한국어 모델이 라틴 문자도 같이 읽는지(혼용)는 **확인하지 못했다**. [확인 — 예제·플러그인 소스 / 한국어 존재는 검색 요약 / 태그·혼용은 추측]
5. **ML Kit에는 텍스트 외 모델이 세 개 있다: `zxx-Zsym-x-autodraw`, `zxx-Zsye-x-emoji`, `zxx-Zsym-x-shapes`.** 그 밖에 언어별 `-x-gesture` 제스처 분류 모델도 있다. 도형 모델이 돌려주는 것은 후보 문자열(라벨)뿐이라 반듯한 도형의 기하(꼭짓점·중심·회전)는 어차피 우리가 맞춰야 하고, 웹에서는 돌지 않는다. [확인 — 예제 소스 `NON_TEXT_MODELS`·`GESTURE_EXTENSION` / 라벨 형식은 추측]
6. **자동 도형 보정은 자체 기하 알고리즘이 낫다(실험).** 순수 Dart 시제품(279줄)을 합성 손그림 1,400개(7종 × 200)로 돌리니 원 100%, 직선 87%, 사각형 87%, 타원 86%, 삼각형 79%, 오각형 98%, 낙서 거부 94%였고 한 획당 약 66µs(VM 디버그)다. 같은 입력에서 `one_dollar_unistroke_recognizer 1.3.5`(Saber 노트 앱용, BSD-3)는 타원·오각형을 '원'(오각형은 전부)으로 보고, 사각형 34%·삼각형 36%만 맞추고, 낙서의 44%를 '별'로 봤다. 문턱값은 실제 iPad 획으로 다시 맞춰야 한다. [확인 — 4.2절 실험]
7. **웹(iPad Safari)에는 쓸 만한 기기 안 손글씨 인식이 없다.** Chromium의 Handwriting Recognition API는 ChromeOS 한정이고 Safari 지원 근거가 없다. 웹에서 ML Kit 호출은 응답이 오지 않았다(헤드리스 Chrome 테스트에서 5초 시간 초과). 웹은 '네이티브가 만든 인식 결과를 동기화해 검색만' 하거나 서버 함수 경유 엔진을 써야 한다. [확인 — Chrome 실험 / ChromeOS 한정은 검색 요약]
8. **수식 인식 3후보는 모두 '키를 서버에 두는' 구조로 쓸 수 있다.** Mathpix: 스트로크 입력 전용 `v3/strokes`(x·y 배열, 본문 512KB 제한), 이미지 `v3/text`, 서버가 발급하는 5분짜리 `app_token`으로 앱이 키 없이 직접 호출 가능, 요청당 $0.002 + 1회 설정비 $19.99(테스트 크레딧 $29). MyScript: Cloud 월 2,000건 무료(초과 1,000건당 $10 — 포럼 답변), 네이티브 iink SDK는 가격 비공개·Flutter 플러그인 없음. Claude: 이미지 → LaTeX, 구조화 출력 지원, 요청당 약 $0.0002~0.0006(Haiku 5.5) ~ $0.005~0.013(Sonnet 5.5) [추정]. [검색 요약·문서·추정 — 6절]
9. **`flutter_math_fork 0.7.4`(2025-05-21, 순수 Dart)는 Flutter 3.47.9 VM과 Chrome에서 렌더된다.** 인식기 출력에 흔한 LaTeX 43개 중 42개를 해석했다(행렬·`cases`·Mathpix식 연립 `\left\{\begin{array}`·`\operatorname`·`\mathbb`·`\xrightarrow`·한글 `\text{}` 포함). 실패는 `\tag{}` 하나. 주의: ① `textStyle`에 `fontSize`·`color`를 주지 않으면 `DefaultTextStyle` 기본값에서 null 검사로 죽는다 ② `SelectableMath`는 `package:flutter/material.dart`의 `Theme`을 읽으므로 `material_ui` 앱에서는 쓰지 않는다 ③ KaTeX 글꼴 20개(640KB, gzip 371KB)가 웹 시작 때 **모두** 내려받아진다. [확인 — 8절 실험·엔진 소스]
10. **수식을 PDF에 벡터로 넣는 길은 지금 없다.** 1차 PDF 합성은 경로 채우기·선 긋기 명령만 받고(06-pdf 6.11), Flutter에는 글리프 외곽선을 꺼내는 API가 없다. 고해상도 래스터(이미지 객체) → PDF가 현실적인 1단계다. [확인 — 계획서·엔진 API / 대안 비용은 추측]
11. **FTS5는 웹(`sqlite3.wasm`)·네이티브 모두 쓸 수 있고(01-hooks 4.1), 한국어는 '음절 바이그램을 Dart에서 만들어 `unicode61` 테이블에 넣는' 방식이 가장 잘 맞았다.** 같은 데이터에서 `trigram`은 2글자 질의(`회의`·`정식`)를 못 찾고, `unicode61` 접두사는 낱말 중간(`의록`)을 못 찾는다. 바이그램 + 구(phrase) 질의는 2글자·3글자·낱말 중간·영문 접두사·여러 낱말 AND를 모두 찾았고, 5,000쪽 합성 색인에서 크기는 trigram의 56%, 질의는 약 0.2ms였다(LIKE 전체 훑기는 7~11ms). [확인 — 9.2절 실험]
12. **손글씨 색인은 1차 7.8에서 미룬 '라이브러리 전역 PDF 텍스트 색인'과 같은 테이블·같은 질의로 갈 수 있다.** 단위(쪽 또는 줄)마다 정규화한 본문 + 위치 사각형 + 출처 판(rev)을 두면 출처만 `pdf`/`ink`(/`text` 상자)로 다르다. PDF 쪽 텍스트는 이미 `PdfTextService.pageText(assetId, pdfPageIndex)` → `PdfPageTextData(text, charRects)`가 있다(pdf_io `src/text/text_service.dart` 25–27). [확인 — PDF 작업 트리 `cc59da5`]
13. **`cloud_functions 7.0.1`(2026-10-23)이 계약의 `firebase_core 5.1.0`과 맞는다.** 서버 함수 경유 엔진의 앱 쪽 호출은 이 패키지로 된다(웹 구현 `cloud_functions_web 5.1.15` 포함). [확인 — 해석]
14. **iOS 앱 배포 대상을 올려야 한다.** 지금 INFRA 앱은 `IPHONEOS_DEPLOYMENT_TARGET = 15.0`이고 ML Kit는 15.5 이상을 요구한다. 안드로이드는 Flutter 기본 compileSdk 36·minSdk 24라 그대로 맞는다. [확인 — `/home/user/wt/infra/app/ios/Runner.xcodeproj/project.pbxproj` 363·490, `FlutterExtension.kt`]

---

## 2. 조사 기준과 방법

### 2.1 환경 · 작업 위치

- 컨테이너: Linux, Flutter 3.47.9 / Dart 3.13.7(`/opt/flutter`), 헤드리스 Chrome(`/usr/local/bin/chrome-nosandbox`). iOS·안드로이드 기기 없음 → ML Kit 실제 인식은 실행하지 못했다.
- 임시 작업: `/tmp/claude-0/plan57-scratch/recog/` — `probe/`(Flutter 해석·실험 프로젝트), `fts2/`(FTS5 한국어 실험, 순수 Dart), `dl/`(pub.dev 보관 파일 압축 해제), `gh/`(공개 저장소 sparse clone). 작업 트리와 `/home/user/noteapp`은 읽기만 했다.
- 읽은 작업 트리: CORE `/home/user/wt/core`(`4336967`), PDF `/home/user/wt/pdf`(`cc59da5`), INFRA `/home/user/wt/infra`(앱 iOS·안드로이드 설정만).

### 2.2 실행한 명령 (요약)

```bash
export PATH=/opt/flutter/bin:$PATH CHROME_EXECUTABLE=/usr/local/bin/chrome-nosandbox
# pub.dev 메타데이터·검색
curl -s https://pub.dev/api/packages/<name>            # 15개 이상 패키지
curl -s "https://pub.dev/api/search?q=myscript"         # mathpix, digital ink, shape recognition, latex render …
# 보관 파일 받기·해시 대조(pub.dev archive_sha256과 같음)
curl -sL https://pub.dev/api/archives/google_mlkit_digital_ink_recognition-0.16.1.tar.gz | sha256sum   # c0483cef…9395
# Google 공식 예제 소스(텍스트 외 모델 태그)
git clone --depth 1 --filter=blob:none --sparse https://github.com/googlesamples/mlkit.git && git sparse-checkout set android/digitalink
# 의존성 해석 (계약 고정 버전 + 후보)
cd /tmp/claude-0/plan57-scratch/recog/probe && flutter pub get && flutter pub deps --style=compact
# 실험 (모두 단일 파일, 가벼움)
flutter test test/shape_fit_test.dart                     # 4.2절
flutter test test/math_render_test.dart                   # 8.1절 (VM)
flutter test --platform chrome test/web_probe_test.dart   # 8.1절·3.6절 (Chrome)
cd ../fts2 && dart pub get --offline && dart run bin/probe.dart   # 9.2절
# Flutter 엔진 소스: 웹 글꼴 적재
grep -n loadAssetFonts /opt/flutter/engine/src/flutter/lib/web_ui/lib/src/engine/initialization.dart
```

### 2.3 출처

| 출처 | 접근 | 쓴 곳 |
|---|---|---|
| https://pub.dev/api/packages/{google_mlkit_digital_ink_recognition, google_mlkit_commons, flutter_math_fork, one_dollar_unistroke_recognizer, cloud_functions, drift, sqlite3, flutter_tex, latext, katex_flutter, flutter_myscript, myscriptwidget, digital_ink_recognition_mlkit, hyper_render_math, http} | 받아서 읽음(`recog/*.json`), 보관 파일 4개는 압축 해제 후 소스 읽음 | 3·4·8·13절 |
| https://github.com/googlesamples/mlkit (커밋 `8cb8b879`, 2026-10-21) `android/digitalink/…/kotlin/DigitalInkMainActivity.kt` 107–181 | sparse clone | 3.3절 |
| https://raw.githubusercontent.com/MyScript/iinkTS/master/README.md, `package.json`(iink-ts 4.1.0, Apache-2.0) | 받아서 읽음 | 6.3절 |
| https://github.com/Mathpix/api-examples (2019, `v3/latex` 시절 예제) | clone — 현재 API와 달라 참고만 | 6.2절 |
| Flutter 3.47.9 엔진·도구 소스 `/opt/flutter` | 직접 읽음 | 8.2절, 1절 14 |
| claude-api 스킬(모델 표 2026-10-06 캐시, `shared/model-migration.md` 고해상도 이미지 절) | 읽음 | 6.4절 |
| https://developers.google.com/ml-kit/…, https://developers.google.cn/…, https://docs.mathpix.com, https://mathpix.com, https://mathpix.github.io, https://developer.myscript.com, `dl.google.com`(Maven AAR) | **접근 불가**(세션 네트워크 허용 목록 밖 — `getaddrinfo ENOTFOUND` 또는 프록시 403). 아래 검색 요약으로 대신했다. 이 호스트들을 허용하면 3.3·6.2·6.3절의 [검색 요약]을 원문으로 다시 확인할 수 있다 | — |
| 웹 검색(요약): https://developers.googleblog.com/digital-ink-recognition-in-ml-kit/ · https://developers.google.com/android/reference/com/google/mlkit/vision/digitalink/recognition/DigitalInkRecognitionModelIdentifier · https://docs.mathpix.com/guides/strokes · https://docs.mathpix.com/reference/post-v3-strokes · https://docs.mathpix.com/reference/authentication · https://mathpix.com/pricing/api · https://mathpix.com/docs/convert/billing · https://developer-support.myscript.com/support/discussions/topics/16000030978 · https://developer.myscript.com/doc/interactive-ink/4.0/web/rest/architecture · https://www.spotsaas.com/product/myscript/pricing · https://web.dev/handwriting-recognition/ · https://developer.chrome.com/docs/web-platform/handwriting-recognition | 검색 결과 요약만 | 3·5·6절 [검색 요약] |

---

## 3. ML Kit Digital Ink Recognition (`google_mlkit_digital_ink_recognition`)

### 3.1 패키지 · 버전 · 플랫폼

| 항목 | 값 | 근거 |
|---|---|---|
| 최신 버전 | 0.16.1 (2026-08-17), 보관 파일 sha256 `c0483cef…9395` | pub.dev API [확인] |
| 환경 | `sdk: ^3.12.0`, `flutter: >=3.44.0` → Dart 3.13.7 / Flutter 3.47.9 만족 | pubspec [확인] |
| 의존 | `google_mlkit_commons ^0.13.0` → 0.13.0 | 해석 결과 [확인] |
| 플랫폼 | `flutter.plugin.platforms` = android, ios. 웹 구현 없음 | pubspec, README [확인] |
| 안드로이드 | `implementation("com.google.mlkit:digital-ink-recognition:19.0.0")`, `compileSdk = 36`, `minSdk = 21` | `android/build.gradle` 33·45·49 [확인] |
| iOS | `GoogleMLKit/DigitalInkRecognition ~> 9.0.0`, `ios.deployment_target = '15.5'`, 정적 프레임워크, armv7 제외 필요(README) | podspec [확인] |
| 우리 앱과의 차이 | 안드로이드: Flutter 기본 compileSdk 36·minSdk 24(`FlutterExtension.kt` 26 근처) → 맞음. iOS: INFRA 앱 배포 대상 15.0 → **15.5로 올려야 함** | [확인] |
| 해석 | 계약 고정(`flutter_riverpod 3.4.3`, `material_ui 1.10.0`, `drift 2.35.3`, `sqlite3 3.8.0`, `firebase_core 5.1.0` …)과 함께 `flutter pub get` 성공 | 13절 [확인] |
| 유지 상태 | flutter-ml/google_ml_kit_flutter 커뮤니티 플러그인(구글 비공식). 0.15.0에서 안드로이드 Kotlin·iOS Swift로 재작성, 0.16.0에서 채널 이름 수정 | CHANGELOG [확인] |

대체 패키지 `digital_ink_recognition_mlkit 0.1.1`(2026-07-30, 개인 저작)·`learning_digital_ink_recognition 0.0.2`(2021)는 채택 이유가 없다. [확인 — pub.dev 메타데이터]

### 3.2 API 형식 — 입력 · 출력 · 문맥

```dart
// package:google_mlkit_digital_ink_recognition 0.16.1 (lib/src/digital_ink_recognizer.dart 요지)
final r = DigitalInkRecognizer(languageCode: 'ko');          // BCP-47 태그
final ink = Ink()..strokes = [Stroke()..points = [StrokePoint(x: 10, y: 20, t: 1730790000000), …]];
final List<RecognitionCandidate> cs = await r.recognize(ink,
    context: DigitalInkRecognitionContext(preContext: '오늘 ', writingArea: WritingArea(width: 595, height: 40)));
cs.first.text; cs.first.score;   // score: 낮을수록 유력, 지원 모델만(없으면 플러그인이 0.0)
await r.close();                 // 네이티브 인스턴스(id = 생성 시각 µs) 해제
```

- 점: `x`, `y`는 `double`(오른쪽·아래로 증가), `t`는 **`int` 밀리초**. 안드로이드는 `Ink.Point.create(x, y, t)`, iOS는 `t`가 없으면 0을 넣는다. [확인 — Kotlin `DigitalInkRecognizer.kt` 93–101, Swift `GoogleMlKitDigitalInkRecognitionPlugin.swift` 76–80]
- 우리 획에서 변환: CORE `StrokePoint.x/y`(페이지 pt), `t`는 `Stroke.createdAt`부터의 ms(실수, 분할 조각도 원래 기준 유지) → `t_abs = (stroke.createdAt + point.t).round()`. [문서 — 계약 7.2.3]
- 출력: `RecognitionCandidate(text, score)` 목록뿐. 글자·단어별 획 대응이나 경계 상자는 플러그인 Dart·Kotlin·Swift 어디에도 없다. → **검색 하이라이트 위치는 우리가 인식 단위(줄)를 만들 때 그 줄 획들의 경계로 정한다.** [확인]
- 문맥: `preContext`(앞에 이미 있는 글자 — 같은 페이지의 앞 줄 인식 결과를 넣음), `WritingArea`(획과 같은 단위). 유효하지 않으면(둘 다 null) 문맥 없이 호출한다. [확인 — Dart `_isValid`]
- 인식 단위: ML Kit 텍스트 모델은 한 줄(또는 한 낱말) 잉크를 받는 것을 전제로 설계됐다고 본다. 여러 줄을 한 `Ink`로 넣으면 결과가 나빠질 것이다. → 줄 나누기(3.5절)가 필요하다. [추측 — 공식 문서 원문 미확인]

### 3.3 모델 태그 · 크기 · 다운로드 관리

| 항목 | 내용 | 근거 |
|---|---|---|
| 텍스트 모델 | 300개 넘는 언어, 25개 넘는 문자 체계, 한국어 포함 | [검색 요약] 구글 개발자 블로그 |
| 한국어 태그 | 안드로이드 API 문서에 "Korean, Korean script"와 "Gesture classifier, Korean, Korean script" 항목이 있다. 태그 문자열은 `ko`(제스처는 `ko-x-gesture` 형식)로 추정 | [검색 요약] / 태그는 [추측] |
| 영어 태그 | `en`(라틴 문자), 지역 변형 `en-US` 등 | [검색 요약] / 공식 예제 iOS 기본값 `"en"` [확인] |
| 텍스트 외 모델 | `zxx-Zsym-x-autodraw`(Autodraw), `zxx-Zsye-x-emoji`(Emoji), `zxx-Zsym-x-shapes`(Shapes) | [확인] googlesamples/mlkit `DigitalInkMainActivity.kt` 171–179 |
| 제스처 모델 | 태그가 `-x-gesture`로 끝나는 언어별 분류 모델(예제가 "Script gesture classifier"로 따로 나열) | [확인] 같은 파일 131–139·180. 무엇을 분류하는지(지우기 낙서 등)는 [추측] |
| 크기 | 언어 모델당 약 20MB, 필요할 때 내려받음 | [검색 요약] 구글 개발자 블로그 |
| 관리 API | `isModelDownloaded(tag)`, `downloadModel(tag, isWifiRequired: true)`, `deleteModel(tag)` | [확인] commons `model_manager.dart` 17–45 |
| Wi-Fi 조건 | 안드로이드: `DownloadConditions.Builder().requireWifi()` 적용. **iOS: `allowsCellularAccess: true` 고정 — 인자 무시** | [확인] `GenericModelManager.kt` 38–45, `GenericModelManager.swift` 67–70 |
| 잘못된 태그 | 안드로이드 `fromLanguageTag` 실패 → `"Failed to create model identifier"`, null → `"No model was found"`. iOS → `invalid_model` | [확인] Kotlin `getModel`, `GoogleMlKitDigitalInkRecognitionPlugin.swift` 44–45·139–140 |
| 받기 전 인식 | 안드로이드 `"Model has not been downloaded yet"`, iOS 같은 문구의 `FlutterError` | [확인] |
| 동시 받기 | iOS는 같은 모델을 이미 받는 중이면 `download_in_progress` 오류 | [확인] commons `GenericModelManager.swift` 39–40 |

관리 정책(제안 재료): 한국어·영어 모델(약 40MB)을 '인식 켜기' 때 Wi-Fi에서 받고, 설정 화면에 받은 모델 목록·삭제를 둔다. iOS는 플러그인이 셀룰러를 막지 않으므로 앱이 연결 상태(`connectivity_plus` — SYNC가 이미 씀)를 보고 받기를 미룬다. [추측]

### 3.4 한국어 + 영어 혼용 전략

PLAN F-10은 "한국어 + 영어 혼용 인식 필수"다. ML Kit는 모델 하나가 한 언어(문자 체계)를 맡는다.

| 전략 | 방법 | 장점 | 단점 |
|---|---|---|---|
| A. `ko` 하나 | 줄마다 `ko`로만 인식 | 호출 1회, 간단 | 한국어 모델이 라틴 문자·숫자를 얼마나 읽는지 **미확인**. 구글 필기 입력기 계열 CJK 모델은 보통 ASCII도 포함한다 [추측] |
| B. 두 모델 결과 선택 | 같은 잉크를 `ko`·`en`으로 인식하고, `ko` 1순위에 한글이 있으면 `ko`, 라틴만 있으면 `en` 결과와 비교해 고름 | 영어 줄 정확도 향상 | 호출 2배. **두 모델의 점수는 서로 비교할 수 없다**(점수는 모델별 문턱 용도 — 플러그인 주석) → 문자 체계·사전 규칙으로 골라야 함 |
| C. 낱말 단위 결합 | 줄을 가로 간격으로 낱말 조각으로 나눠 조각마다 B | 한 줄 안 혼용("오늘 meeting 정리")까지 | 한글은 음절 간격과 낱말 간격 구분이 어렵다. 조각이 짧아 문맥 손실 |
| D. 사용자 지정 | 변환 창에서 언어 선택(자동/한국어/영어) | 확실 | 손이 감. 검색 색인(자동 인식)에는 못 씀 |

판단 재료: 실기기에서 혼용 문장 30줄로 A와 B의 문자 오류율을 재는 실험이 먼저다(12절 Q2). A가 영문 낱말을 대체로 읽으면 A + D(변환 창의 언어 바꾸기)로 충분하고, 아니면 색인은 A, 변환은 B로 나눈다. 후보 단어 UI는 `ko` 후보 목록(보통 여러 개) + (B일 때) `en` 1순위를 합쳐 보여 주면 된다. [추측]

### 3.5 ML Kit가 주지 않는 것 — 줄 나누기 · 위치 · 문맥

- **줄 나누기(우리가 만든다)**: 페이지 획(형광펜·도형·수식 영역 제외)을 세로 중심으로 정렬 → 세로 겹침 ≥ 50%·가로 간격 ≤ 중간 글자 높이 × k로 묶어 줄을 만들고, 줄 안은 x순. 줄 하나 = `Ink` 하나 = 색인 단위 하나. 올가미 '텍스트로 변환'(F-10)도 같은 함수로 여러 줄을 나눈다. 순수 Dart라 컨테이너에서 합성 획으로 시험할 수 있다. [추측 — 알고리즘 제안]
- **위치**: 줄 경계 사각형(획 `pointBounds` 합집합)을 결과와 함께 저장 → 검색 결과 하이라이트·페이지 이동(`focusRectPt`)에 쓴다. 낱말 단위 하이라이트가 필요하면 결과 문자열의 공백 수와 줄 안 가로 간격 군집을 맞춰 근사한다(정확하지 않음). [추측]
- **문맥**: 같은 페이지 앞 줄 결과 끝 20자 정도를 `preContext`로 넣는다. `WritingArea`는 (페이지 폭, 줄 높이 × 1.5). [추측 — 공식 '정확도 높이기' 팁 원문 미확인]
- **낡음 판정**: 결과에 대상 획 id와 각 획의 판(`version`)을 묶은 해시를 둔다. 획이 바뀌면 그 줄만 다시 인식한다. 이동·크기 조절만 된 획은 글자가 같으므로 위치 사각형만 갱신해도 된다. [추측]

### 3.6 웹에서의 동작

- 패키지는 웹으로 컴파일된다(Dart 쪽은 `MethodChannel`만 씀, `dart:io` 없음). [확인 — 소스, Chrome 테스트 컴파일 성공]
- 하지만 웹에는 플랫폼 구현이 없어 호출이 끝나지 않을 수 있다: 헤드리스 Chrome의 `flutter test --platform chrome`에서 `DigitalInkRecognizerModelManager().isModelDownloaded('ko')`가 응답 없이 5초 시간 초과(`TimeoutException`)로 끝났다. 실제 웹 앱에서 `MissingPluginException`으로 끝나는지는 확인하지 않았다. → **웹에서는 아예 부르지 않는다**(조건부 import로 웹 구현을 '지원 안 함' 스텁으로). [확인 — 실험 / 실제 앱 동작은 추측]
- 계약 7.4.3(웹 우선 규칙)에 맞추려면 플러그인 import는 `*_native.dart`에만 두고 진입점은 조건부 import로 고른다(1차 PDF의 `pdfium_dart` 방식과 같음).

---

## 4. 자동 도형 보정 (M5 F-11) — ML Kit 도형 모델 vs 자체 기하 알고리즘

### 4.1 후보 비교

| 기준 | ML Kit `zxx-Zsym-x-shapes` | `one_dollar_unistroke_recognizer 1.3.5` | **자체 기하 알고리즘** |
|---|---|---|---|
| 웹(iPad Safari) | 불가 | 가능(순수 Dart, `dart:ui` Offset) | 가능(순수 Dart, `dart:math`만) |
| 결과 | 라벨 문자열(추측) — 꼭짓점·회전은 따로 맞춰야 | 라벨 + 맞춤(`convertToLine/Circle/Oval/Rect/CanonicalPolygon`). 사각형은 축 정렬 경계 상자만 | 종류 + 기하(꼭짓점, 중심·반지름·회전) 직접 |
| 종류 | 미확인 | 직선·원·사각형·삼각형·별(사용자 템플릿 추가 가능) | 직선·원·타원·삼각형·사각형(회전 포함)·사각형 아닌 사각형·다각형 5~8, 낙서 거부 |
| 모델 받기 | 필요(크기 미확인) | 없음 | 없음 |
| 컨테이너 테스트 | 불가 | 가능 | 가능 |
| 상태 | — | 전역 가변 목록 `referenceUnistrokes`로 템플릿 교체(전역 상태) | 자체 소유 |
| 라이선스 | ML Kit 약관 | BSD-3 | 자체 |

### 4.2 실험 — 합성 손그림 1,400개

`/tmp/claude-0/plan57-scratch/recog/probe/test/shape_fit_test.dart`: 종류마다 200개, 크기 80~300pt, 임의 회전, 닫힌 도형은 임의 시작점 + 겹침/틈 −6%~+8%, 점 잡음(σ = 크기의 0.6%) + 저주파 흔들림(크기의 1.5%), 직선은 ±2% 휨. 시드 고정(`Random(20261105)`).

```text
$ flutter test test/shape_fit_test.dart
per class 200, prototype avg 66 us/stroke (VM, debug test)
line      prototype={line: 174, none: 26}                          one_dollar={line: 200}
circle    prototype={circle: 200}                                  one_dollar={circle: 200}
ellipse   prototype={ellipse: 171, polygon: 18, quad: 4, none: 7}  one_dollar={circle: 145, rectangle: 55}
triangle  prototype={triangle: 158, none: 19, quad: 23}            one_dollar={circle: 129, triangle: 71}
rectangle prototype={rectangle: 173, polygon: 15, none: 12}        one_dollar={rectangle: 67, circle: 133}
pentagon  prototype={polygon: 195, none: 5}                        one_dollar={circle: 200}
scribble  prototype={none: 187, polygon: 13}                       one_dollar={none: 113, star: 87}
00:00 +1: All tests passed!
```

해석
- 시제품은 문턱값을 세 번만 고친 1차본이다. 틀린 경우의 상당수가 `none`(획으로 남김)이라 사용자 피해가 작다. 잘못 바꾸는 경우(삼각형 → 사각형 23건, 타원 → 다각형 18건)는 문턱값·꼭짓점 병합 규칙으로 더 줄일 수 있다. [확인 — 수치 / 개선 여지는 추측]
- `one_dollar`는 회전·크기를 정규화한 템플릿 비교라 원 템플릿이 넓게 이긴다. 타원·오각형 템플릿이 없고, 사각형 맞춤이 축 정렬이라 회전된 사각형을 반듯하게 만들 수 없다. [확인 — 수치·README]
- 합성 데이터는 실제 Apple Pencil·S펜 획과 다르다. **문턱값은 실제 획으로 다시 맞춰야** 하며, 이를 위해 EDITOR 개발자 메뉴에 '마지막 획 JSON 복사'를 두고 사용자가 그린 표본을 테스트 고정 자료(fixture)로 모으는 방법을 제안한다. [추측]

### 4.3 시제품 알고리즘 개요 (`probe/lib/shape_fit.dart`, 279줄)

1. 경로 길이 기준 64점 재표본화. 경계 대각선 8pt 미만은 무시.
2. **직선**: 현/경로 길이 ≥ 0.85이고 현에서 최대 수직 거리/현 ≤ 0.065.
3. 닫힘 검사: 끝점 간격/경로 길이 ≤ 0.2. 총 회전각이 270°~540°가 아니면(낙서·두 바퀴) 거부.
4. **타원·원**: 점들의 공분산(PCA) → 축 길이 `a = √(2λ₁)`, `b = √(2λ₂)`, 회전각. 오차 = 정규화 반경 |r − 1|의 평균 ≤ 0.075. `b/a ≥ 0.82`이면 원.
5. **다각형**: 시작점에서 가장 먼 점으로 둘로 나눠 Ramer–Douglas–Peucker(ε = 대각선 × 0.055) → 회전각 28° 미만 꼭짓점 제거 → 둘레의 8%보다 가까운 꼭짓점 병합. 다각형 오차(점–변 거리 평균/대각선)와 타원 오차를 비교해 고른다. 3개 = 삼각형, 4개 = 모든 각 90° ± 16°이면 사각형 아니면 사각형 아닌 사각형, 5~8개 = 다각형(오차 ≤ 0.03), 그 밖 = 거부.
6. (미구현, 제안) 반듯하게 다듬기: 사각형은 가장 긴 변 방향으로 최소 경계 사각형, 축에서 ±8° 이내면 축에 맞춤. 직선 각도는 INK `SelectionGeometry.snapAngle`(15°, ±3°)과 같은 규칙. 별은 꼭짓점 10개 + 오목·볼록 교대로 따로 판정.
7. 발동: 펜이 닿은 채 마지막 점 주위 반경 r 안에 500ms 머물면 `fitShape` → 미리보기 → 펜을 떼면 도형 요소로 바꿈(되돌리기 1단계). INK 입력 파이프라인 안의 타이머이므로 가짜 시계로 컨테이너에서 시험할 수 있다. [추측 — 값은 제안]

결론: M5 자동 도형 보정은 **INK가 소유하는 순수 Dart 기하 판정**으로 하고 ML Kit 도형 모델·`one_dollar`는 쓰지 않는 것을 권한다(11절 R4).

---

## 5. 웹(iPad Safari)에서의 손글씨 인식 대안

| 대안 | 방법 | 웹 | 비용 · 조건 | 판단 |
|---|---|---|---|---|
| W1. 네이티브 전용 + 결과 동기화 | 안드로이드(나중에 iPad 네이티브)가 인식해 결과를 엔티티로 동기화. 웹은 받은 결과로 검색만, '텍스트로 변환'은 "앱에서 사용 가능" 안내 | 검색 가능, 변환 불가 | 0. 단 동기화 실연결(M4)이 있어야 웹에 결과가 간다 | **기본안**. 01-hooks R7과 같음 |
| W2. 서버 함수 경유 — 이미지 OCR | 선택 영역을 PNG로 그려 서버 함수 → 멀티모달 AI(Claude) 또는 Google Cloud Vision 손글씨 OCR(`DOCUMENT_TEXT_DETECTION`, 언어 힌트 ko·en) | 가능 | Firebase 종량제(Blaze) + 외부 API 비용, 온라인 필요 | 변환 기능을 웹에서도 원할 때 추가. Cloud Vision 단가·한국어 손글씨 품질은 [추측] |
| W3. 서버 함수 경유 — 스트로크 | MyScript Cloud REST(스트로크 입력, 월 2,000건 무료) | 가능 | 한국어 지원 여부 **미확인** | 수식 엔진을 MyScript로 정할 때만 검토 |
| W4. 브라우저 API | Chromium `navigator.createHandwritingRecognizer` | **Safari 없음**(ChromeOS 한정) | — | 제외 [검색 요약] |
| W5. 웹 전용 기기 안 모델 | TF.js/ONNX 등으로 한국어 필기 모델을 웹에서 직접 | 이론상 가능 | 모델 확보·크기(수십 MB)·성능 | 제외(비용 큼) [추측] |

이번 라운드에는 W1만 구현하고, 어댑터 구조(7절)에 W2 자리를 둔다. 수식 인식은 어차피 서버(또는 서버가 발급한 토큰)로 가므로 웹·네이티브가 같은 경로다.

---

## 6. 수식 인식 엔진 비교 (F-14)

### 6.1 비교표

| 기준 | Mathpix | MyScript iink | 멀티모달 AI(Claude) — 서버 함수 경유 |
|---|---|---|---|
| 입력 | 스트로크(`v3/strokes`: 획별 x·y 배열) 또는 이미지(`v3/text`: `src` data URI) [검색 요약] | 스트로크(x·y·t) — 네이티브 SDK 또는 Cloud(REST·WebSocket) [검색 요약·iinkTS README] | 이미지(PNG/JPEG). 스트로크를 좌표 텍스트로 줄 수도 있으나 이미지가 자연스러움 [추측] |
| 출력 | LaTeX(`latex_styled`), 텍스트(Mathpix Markdown), 신뢰도 [추측 — 필드 이름은 기존 지식] | LaTeX·MathML·JIIX [검색 요약·추측] | 구조화 출력(`output_config.format`)으로 `{latex, confidence, alternatives}` 같은 JSON 강제 가능 [문서] |
| 기기 안 | 아니오(클라우드) | 네이티브 SDK는 기기 안 실시간. iinkTS(웹)는 Cloud | 아니오 |
| 키 보호 | 서버 함수가 `app_token`(기본 5분, 발급 무료)을 발급 → 앱이 키 없이 직접 호출. 또는 서버 함수가 대리 호출 [검색 요약] | Cloud는 `applicationKey` + HMAC 키 — 웹 클라이언트에 두면 유출 → REST를 서버 함수로 대리 [검색 요약·추측] | 서버 함수가 대리 호출(Secret Manager) [추측] |
| 실시간 미리보기 | 스트로크 세션(라이브 갱신, 세션 단위 과금) 지원 [검색 요약] | 네이티브·WebSocket 모두 실시간 설계 | 부적합(초 단위 지연·요청당 과금) → 쓰기 멈춤 뒤 1회 |
| 가격 | 요청당 $0.002(월 100만 건까지), 1회 설정비 $19.99, 테스트 크레딧 $29. 라이브 세션은 월 1,000건 무료 후 세션당 $0.01 [검색 요약 — 출처 간 일부 불일치] | Cloud 월 2,000건 무료, 초과 1,000건당 $10(포럼 답변). 네이티브 SDK는 가격 비공개·영업 문의 [검색 요약] | 6.4절 [문서·추정] |
| 지연 | 미확인(전문 엔진이라 수백 ms 대로 기대) [추측] | 기기 안은 실시간, Cloud 미확인 [추측] | 수 초(생각 단계 포함) [추측] |
| Flutter 연동 | 서버 함수 대리면 앱은 `cloud_functions`만. `app_token` 직접 호출이면 HTTP(`http 1.6.0` — `flutter_math_fork`를 넣으면 간접 의존으로 이미 들어옴) | **공식 Flutter 플러그인 없음.** pub.dev `flutter_myscript 0.0.6`(2023, `sdk <3.0.0` → Dart 3.13에서 해석 불가)·`myscriptwidget 1.0.0`(2024, android·ios) 둘 다 쓸 수 없음 → 직접 플랫폼 채널 플러그인 작성 + 인증서 파일을 앱에 넣음 | `cloud_functions 7.0.1`로 호출 [확인] |
| 한국어 혼합 수식(`\text{단,}`) | 미확인 | 미확인 | 가능할 것 [추측] |
| 교체 비용 | 낮음(서버 함수 안) | 네이티브는 높음, Cloud는 낮음 | 낮음(서버 함수 안) |

### 6.2 Mathpix

- 스트로크 요청(검색 요약, docs.mathpix.com/guides/strokes·reference/post-v3-strokes): `POST https://api.mathpix.com/v3/strokes`, 본문 `{"strokes": {"strokes": {"x": [[…], […]], "y": [[…], […]]}}}`(획마다 하위 배열), 선택 `strokes_session_id`. 본문 제한 512KB(다른 엔드포인트보다 작음). 인증 헤더는 `app_id` + `app_key` 또는 `app_token` + `strokes_session_id`.
- `app_token`: 서버가 키로 발급, 기본 5분 유효, 발급 무료. 세션 과금은 토큰 발급이 아니라 첫 스트로크 전송 때. → 서버 함수 `mathpixToken`이 토큰만 주고 앱이 직접 호출하면 키가 앱에 없고 지연도 한 단계 줄어든다. [검색 요약]
- 이미지 요청: `v3/text`에 `src`(data URI)와 `formats`(`text`, `latex_styled` 등). 12줄 넘는 텍스트 이미지는 PDF 쪽 단가로 과금. [검색 요약 / `formats` 값은 2019 예제(`api-examples/python/formats.py` 20행)에서도 확인]
- 단가 근거끼리 일부 다르다(2022 블로그 vs 현재 가격 페이지). 가격 페이지가 기준이라고 문서가 말한다. [검색 요약]

### 6.3 MyScript iink

- 네이티브 SDK(iOS·안드로이드·macOS, 2026-01 iink SDK 4.3 언급)는 기기 안 실시간 인식이지만 가격이 공개되지 않았고 기기 수만큼 라이선스를 사야 한다는 포럼 답변이 있다. Flutter 플러그인이 없어 안드로이드 AAR·iOS 프레임워크를 감싸는 플러그인을 우리가 만들어야 한다. [검색 요약 / 비용 판단은 추측]
- 웹: `iink-ts 4.1.0`(Apache-2.0) — 텍스트·수식, 수학 기호 200개 이상, 72개 언어, Cloud 키(`applicationKey`·`hmacKey`)를 브라우저 설정에 넣는 예제. 키를 앱에 넣지 않는다는 PLAN F-14 원칙과 맞추려면 REST(`/api/v4.0/iink/recognize/`, `applicationKey` 헤더 + HMAC)를 서버 함수에서 부른다. [확인 — README / REST 형식은 검색 요약]
- 요청 계산: WebSocket은 연결~종료가 1건(최대 5분), REST는 호출당. [검색 요약 — 포럼]

### 6.4 멀티모달 AI (Claude) — 서버 함수 경유

- 모델·단가(입력/출력, 100만 토큰당): Claude Opus 5.5 `claude-opus-5-5` $4/$20, Claude Sonnet 5.5 `claude-sonnet-5-5` $2/$10, Claude Haiku 5.5 `claude-haiku-5-5` $0.10/$0.50(10만 토큰 이하 요청). [문서 — claude-api 스킬 모델 표, 2026-10-06 캐시]
- 이미지: 현 세대는 긴 변 2576px까지, 이미지당 최대 약 4,784 토큰. 필요 없으면 줄여서 보낸다. [문서 — `model-migration.md`] 이미지 토큰 ≈ 가로×세로/750은 [추측 — 기존 지식].
- 응답 형식: `output_config.format`(구조화 출력)으로 JSON 스키마를 강제할 수 있다. Opus 5.5는 생각 단계를 끌 수 없고 effort 기본이 `medium`, Sonnet 5.5는 기본 `high` — 수식 한 개 변환은 `low`로 시험한다. 응답 `stop_reason == "refusal"` 처리를 서버 함수에 둔다. [문서]
- 요청당 비용 [추정]: 수식 영역 1000×400px PNG(약 530 이미지 토큰 — 추측 공식) + 지시문 300 토큰 입력, 출력 LaTeX 80 토큰 + 생각 200~1,000 토큰 가정 →
  - Haiku 5.5: 약 $0.0002~0.0006
  - Sonnet 5.5: 약 $0.005~0.013
  - Opus 5.5: 약 $0.01~0.025
- 품질은 손글씨로 직접 비교해야 한다(PLAN F-14 방침). 지연은 수 초로 본다 [추측].

### 6.5 개인 사용량 비용 추정 [추정]

가정: 하루 수식 30개 × 30일 = 월 900건.

| 엔진 | 월 비용 | 고정 비용 | 비고 |
|---|---|---|---|
| Mathpix 스트로크·이미지 | 약 $1.8 | 설정비 $19.99(크레딧 $29 ≈ 14,500건분) | 라이브 미리보기 세션은 월 1,000건까지 무료로 검색됨 |
| MyScript Cloud | $0(월 2,000건 무료 안) | 없음 | 네이티브 SDK는 별도 견적 |
| Claude Haiku 5.5 | 약 $0.2~0.5 | 없음 | 품질 미확인 |
| Claude Sonnet 5.5 | 약 $4.5~12 | 없음 | |
| 공통 | Firebase 서버 함수는 종량제(Blaze) 등록 필요(PLAN 6.3과 같은 판단), 개인 사용량의 호출 수는 무료 사용량 안일 것 | — | [추측] 예산 알림 소액 설정(PLAN 6.3) |

### 6.6 비교 실험 방법 (M7 착수 시 — PLAN F-14 "직접 손글씨로 비교")

1. iPad(웹) 또는 안드로이드 앱의 수식 입력 영역에서 50개를 쓰고, 획 JSON과 정답 LaTeX(사용자가 입력)를 고정 자료로 저장한다(분수·지수·루트·적분·시그마·극한·행렬·그리스 문자·연립방정식 — F-14 범위를 고르게).
2. 저장소 `tool/`의 평가 CLI가 엔진별로 호출한다. 키는 개발자 환경 변수에서만 읽는다(앱·저장소에 넣지 않음). 비용 상한: Mathpix 50 × $0.002 = $0.1(설정비 별도), Claude Sonnet 5.5 약 $0.5, MyScript 무료 안. [추정]
3. 채점: ① 정규화 LaTeX 일치(공백·`\left`/`\right`·중괄호 정리 후) ② `flutter_math_fork` 해석 성공률 ③ 지연 중앙값 ④ 사람 판정(렌더 결과 나란히 보기 — 사용자). 결과표를 M7 계획서에 붙인다.
4. 보조 자료: Google의 온라인 손글씨 수식 공개 자료(MathWriting, 2024)를 컨테이너 평가에 쓸 수 있는지 라이선스(비상업 조건으로 기억함)·접근을 확인한다. [추측]

---

## 7. 엔진 교체형 어댑터 구조 제안

### 7.1 패키지 · 소유 (01-hooks R6과 같은 방향)

| 패키지(가칭) | 소유 | 내용 | 웹 |
|---|---|---|---|
| `ink_recognition` | 새 영역 | 인터페이스·데이터 타입(순수 Dart), 줄 나누기, 결과 병합 규칙, 가짜 엔진(`testing.dart`), ML Kit 어댑터(`*_native.dart`), 서버 함수 어댑터(`cloud_functions`) | 인터페이스·가짜·서버 어댑터는 웹 가능, ML Kit는 스텁 |
| `ink_engine`(INK) | INK | 자동 도형 판정(`fitShape`)·발동 타이머 — 인식 패키지에 두지 않는다(입력 파이프라인 안, 웹 필수) | 가능 |
| `note_core`(CORE) | CORE | 인식 결과 엔티티(동기화)·검색 색인 테이블·질의 API | 가능 |
| 서버 함수(`functions/`, TypeScript) | INFRA(배포) | `recognizeMath`(엔진 선택), `mathpixToken`, 나중에 `recognizeHandwriting`(W2) | — |

EDITOR·LIBRARY는 자기 패키지의 자리 provider(`handwritingRecognizerProvider` 등)를 읽고, 앱 셸이 7.3.3 표에 행을 더해 override한다. EDITOR 위젯 테스트는 가짜 엔진으로 돈다.

### 7.2 Dart 인터페이스 초안 (설계 재료 — 최종 정의는 계약에서)

```dart
// package:ink_recognition/ink_recognition.dart (pure Dart; no plugin imports)
final class InkTrace {                       // one stroke, page pt, absolute ms
  const InkTrace(this.xs, this.ys, this.ts, {this.strokeId});
  final Float32List xs, ys;
  final Int64List ts;                        // createdAt + point.t, rounded
  final String? strokeId;
}

final class InkLineInput {
  const InkLineInput(this.traces, {this.preContext = '', this.writingAreaPt});
  final List<InkTrace> traces;
  final String preContext;
  final Size? writingAreaPt;
}

final class TextCandidate {
  const TextCandidate(this.text, {this.score, required this.languageTag});
  final String text;
  final double? score;                       // engine-specific, lower = better (ML Kit); never compared across engines
  final String languageTag;
}

sealed class RecognitionFailure implements Exception {}
final class RecognizerUnsupported extends RecognitionFailure {}    // web + ML Kit
final class ModelNotReady extends RecognitionFailure { ModelNotReady(this.languageTag); final String languageTag; }
final class RecognizerOffline extends RecognitionFailure {}
final class RecognizerQuotaExceeded extends RecognitionFailure {}
final class RecognizerEngineError extends RecognitionFailure { RecognizerEngineError(this.code, this.message); final String code, message; }

abstract interface class HandwritingRecognizer {
  String get engineId;                       // 'mlkit-digital-ink/19.0.0', 'fake', 'server/claude'
  bool get isAvailableOnThisPlatform;
  Future<ModelState> modelState(String languageTag);               // notDownloaded | downloading | ready | unsupported
  Future<void> ensureModel(String languageTag, {bool wifiOnly = true});
  Future<List<TextCandidate>> recognizeLine(InkLineInput line, {required String languageTag});
  Future<void> dispose();
}

final class MathInput {
  const MathInput({required this.traces, this.png, this.pngPxPerPt});
  final List<InkTrace> traces;               // Mathpix/MyScript use strokes
  final Uint8List? png;                      // multimodal engines use the image
  final double? pngPxPerPt;
}

final class MathResult {
  const MathResult({required this.latex, this.confidence, this.alternatives = const [],
      required this.engineId, required this.latency});
  final String latex;                        // validated by flutter_math_fork parse before showing
  final double? confidence;                  // 0..1 when the engine gives one
  final List<String> alternatives;
  final String engineId;
  final Duration latency;
}

abstract interface class MathRecognizer {
  String get engineId;
  Future<MathResult> recognize(MathInput input, {Future<void>? cancel});
}

/// Pure-Dart line grouping used by both search indexing and lasso conversion.
List<List<InkTrace>> groupIntoLines(List<InkTrace> traces, {double gapFactor = 1.2});
```

설계 메모 [추측]
- 엔진 식별자(`engineId`)는 결과 엔티티에 같이 저장한다. 엔진이나 모델 판이 바뀌면 '다시 인식' 대상을 고를 수 있다.
- 인식 결과(손글씨)는 기능 스위치(PLAN 7.6)로 켜고 끈다. 수식 인식은 유료가 될 수 있는 기능이므로 스위치 + 월 사용량 표시를 둔다.
- 수식 결과 LaTeX는 화면에 넣기 전에 `flutter_math_fork`로 해석해 본다. 실패하면 원문 LaTeX + 오류를 보여 주고 직접 편집하게 한다. 알려진 미지원(`\tag`)은 서버 함수에서 지운다.

### 7.3 서버 함수 형식 (초안)

```text
callable recognizeMath (Firebase Callable, App Check 필수, 로그인 필수)
  in : { engine: 'mathpix' | 'claude' | 'myscript', strokes?: { x: number[][], y: number[][], t?: number[][] },
         png?: base64, hints?: { locale: 'ko' } }
  out: { latex: string, confidence?: number, alternatives?: string[], engine: string, engineVersion: string, ms: number }
  err: 'quota-exceeded' | 'unauthenticated' | 'engine-error' | 'invalid-argument'
callable mathpixToken → { appToken, strokesSessionId, expiresAt }   // 라이브 미리보기용(선택)
```

- 키: Secret Manager(`defineSecret`)에만. 사용자별 일일 호출 상한을 Firestore 카운터로 둔다(유출된 계정 토큰 남용 방지). [추측 — Firebase 기능 이름은 기존 지식]
- Firebase 프로젝트가 아직 없으므로 이번 라운드에는 **함수 코드 + 에뮬레이터용 설정까지만** 두고 배포·실호출 검증은 프로젝트 생성 뒤로 미루는 것이 현실적이다(12절 Q6). 앱 쪽 `CallableMathRecognizer`는 `FirebaseFunctions` 인스턴스를 주입받게 해 가짜로 시험한다.

### 7.4 가짜 엔진과 컨테이너 테스트

| 가짜 | 동작 | 쓰는 테스트 |
|---|---|---|
| `FakeHandwritingRecognizer` | 획 집합 해시(또는 테스트가 붙인 `strokeId` 목록) → 미리 정한 후보 목록. 지연·`ModelNotReady`·`RecognizerOffline` 주입, 호출 기록 | 색인기(획 변경 → 줄 단위 재인식 범위), 변환 창 후보 선택, 웹 경로(Unsupported) |
| `FakeMathRecognizer` | 입력 해시 → LaTeX, 지연·실패·취소 주입. 해석 실패 LaTeX(`\tag{1}`)도 돌려줄 수 있음 | 수식 객체 생성·다시 편집·오류 표시 |
| 합성 획 생성기 | 줄·낱말 배치(줄 간격·기울기·흔들림)를 만드는 순수 Dart 도우미 | `groupIntoLines` 정확도, 4.2절 같은 도형 판정 |
| 고정 자료 | 실기기에서 모은 획 JSON(사용자 동의) | 도형 문턱값 회귀 테스트, 수식 평가 CLI |

ML Kit 어댑터 자체는 컨테이너에서 실행할 수 없다. 채널 인자 변환(우리 `InkTrace` → 플러그인 `Ink`)만 단위 테스트하고, 실제 인식은 안드로이드 APK 실기기 확인 목록(사용자)으로 넘긴다.

---

## 8. LaTeX 렌더링

### 8.1 `flutter_math_fork 0.7.4` — 해석 · 웹 · 지원 범위 (실험)

| 항목 | 결과 | 근거 |
|---|---|---|
| 버전 | 0.7.4 (2025-05-21, 1년 반 갱신 없음), 플러그인 아님, `sdk >=3.0.0 <4.0.0` | pub.dev [확인] |
| 의존 | `flutter_svg 2.3.2`(→ `vector_graphics 1.2.6`·`http 1.6.0`), `provider 6.1.5+1`, `tuple 2.0.2`, `meta`, `collection` — 계약 고정과 충돌 없음 | 해석 [확인] |
| 대안 | `flutter_tex 5.3.0`은 WebView(`webview_flutter_plus`) 기반 — 캔버스 위 객체·PDF에 부적합. `latext 0.5.1`·`hyper_render_math 1.7.0`·`flutter_markdown_latex`는 모두 `flutter_math_fork`를 감쌈. `katex_flutter`(2020, `sdk <3.0.0`) 해석 불가 | pub.dev [확인] |
| VM 렌더 | 43개 표본 중 42개 해석, `Math.tex` 빌드·배치 예외 없음(`Directionality`만, Material 조상 없음) | `test/math_render_test.dart` [확인] |
| Chrome 렌더 | `\left\{\begin{array}{l}…\right.` + `\int_0^1 \frac{\sin x}{x}\,dx` 배치 성공(438×60) | `flutter test --platform chrome test/web_probe_test.dart` [확인] |
| 해석 실패 | `\tag{1}` → "Undefined control sequence: \gdef" | [확인] |
| 해석 성공 예 | `\frac`, `\dfrac`, `\sqrt[3]`, `\int`·`\iint`·`\oint`, `\sum\limits`, `\lim_{x\to0}`, `pmatrix`·`bmatrix`·`vmatrix`, `cases`, `aligned`, `array{cc}`, Mathpix식 연립(`\left\{\begin{array}{l}`), `\operatorname`, `\mathrm`, `\mathbb`, `\mathcal`, `\boldsymbol`, `\vec`·`\hat`·`\overline`, `\text{ if }`, `\text{ (단, }`, `\xrightarrow`, `\binom`, `\partial`·`\nabla`, `\leq`·`\neq`·`\approx`·`\equiv`, `\cdots`, `f''`, `\underset`·`\overset`·`\stackrel`, `\displaystyle`, `\%`, `\color`, `^{\circ}`, `\angle`, `\therefore`, `\pm` | [확인] |

### 8.2 주의점

1. **`textStyle`에 `fontSize`와 `color`를 반드시 준다.** 주지 않으면 `DefaultTextStyle.of(context).style`을 쓰는데, 앱 테마 밖(빈 `DefaultTextStyle`)에서는 `effectiveTextStyle.fontSize!`(`lib/src/widgets/math.dart` 189)에서 "Unexpected null value"로 빌드가 실패했다(Chrome 실험 1차). 수식 객체는 자체 크기·색 데이터를 가지므로 항상 명시한다. [확인]
2. **`SelectableMath`는 쓰지 않는다.** `lib/src/widgets/selectable.dart` 263–298이 `package:flutter/material.dart`의 `Theme.of`·`TextSelectionTheme`·`materialTextSelectionControls`를 쓴다. 계약 7.4(`material_ui`만 사용) 앱에서는 테마가 연결되지 않는다. `Math.tex`는 material에서 `Colors.black` 상수만 쓴다. 수식 '다시 편집'은 LaTeX 입력란 + 미리보기로 한다. [확인]
3. **웹 첫 로드에 KaTeX 글꼴 640,372B(gzip 370,984B, 20개)가 더해진다.** 패키지 `pubspec.yaml`이 `flutter: fonts:`로 선언하고, Flutter 웹 엔진은 시작 때 `FontManifest.json`의 모든 글꼴을 내려받는다(`initialization.dart` 224 → `canvaskit/fonts.dart` 117–127, skwasm `font_collection.dart` 79–96). INFRA 웹 예산표(계약 7.4.10)에 올려야 한다. 지연 적재가 필요하면 패키지를 포크해 글꼴 선언을 빼고 `FontLoader`로 수식 첫 사용 때 적재하는 방법이 있다. [확인 — 크기·엔진 소스 / 포크 방법은 추측]
4. `\text{한글}`은 KaTeX_Main에 한글 글리프가 없어 대체 글꼴로 그려진다. 웹은 대체 글꼴을 `fonts.gstatic.com`에서 받는다(01-hooks 1절 14). 한글 글꼴을 번들하면(01-hooks R11) `textStyle.fontFamilyFallback`으로 지정할 수 있는지 확인이 필요하다. [추측]
5. 1년 반 갱신이 없다. 순수 Dart라 깨지면 포크해 고칠 수 있다(내부에서 `MediaQuery.textScaleFactorOf` 같은 옛 API를 쓴다 — `math.dart` 185행). [확인 — 소스 / 위험 평가는 추측]

### 8.3 PDF 벡터 출력 가능성

| 방법 | 내용 | 벡터 | 비용 | 판단 |
|---|---|---|---|---|
| P1. 래스터 | `Math.tex`를 화면 밖에서 그려 300dpi 정도 이미지 → PDF 이미지 객체(`FPDFImageObj_SetBitmap` — pdfium.wasm export 확인, 실행 미확인, 01-hooks 4.2) | 아니오 | 작음(PDF 명령 형식에 이미지 명령 추가) | **1단계 권장** |
| P2. 서버 SVG | 인식·편집 때 서버에서 MathJax SVG(글리프를 경로로) → 경로 데이터를 수식 객체에 함께 저장 → PDF 경로 명령 | 예 | 중간. LaTeX를 오프라인에서 직접 고치면 SVG가 낡음 | 나중 |
| P3. 자체 글리프 | KaTeX TTF 외곽선을 Dart로 읽고(`glyf`·`loca`·`cmap`), `flutter_math_fork` 배치 결과에서 글자 위치를 뽑아 경로로 | 예 | 큼(배치 트리에서 위치 추출이 공개 API 밖) | 제외 |
| P4. PDF 텍스트 객체 | KaTeX 글꼴을 PDF에 넣고(`FPDFText_LoadFont`) 글자 배치 | 예(검색도 됨) | P3과 같은 위치 문제 + 글꼴 넣기 | 제외 |

Flutter `dart:ui`에는 글리프 외곽선을 꺼내는 API가 없어(`Paragraph`는 그리기만) 위젯 렌더 결과를 벡터로 얻을 수 없다. PLAN F-15의 '필기는 벡터'는 획 이야기라 수식을 래스터로 내는 것은 사용자 확인 사항이다(12절 Q9). [추측 — `dart:ui` 공개 API 기준 판단]

---

## 9. 손글씨 검색 색인

### 9.1 FTS5 사용 가능 여부

- 웹: 계약의 `sqlite3.wasm`(sqlite3 3.8.0, SQLite 3.54.1)에서 `fts5` 가상 테이블·`MATCH`·`bm25`·`trigram`·`unicode61`이 헤드리스 Chrome에서 동작한다. [확인 — 01-hooks 4.1, 같은 날 같은 바이너리]
- 네이티브: sqlite3 3.8.0 빌드 훅의 미리 빌드 라이브러리가 `ENABLE_FTS5`. 이번에도 VM에서 SQLite 3.54.1로 `trigram`·`unicode61`·외부 내용(`content=`)·내용 없는(`content=''`) 테이블·`highlight()`를 실행했다. ICU 토크나이저는 없다. [확인 — 9.2 실험]
- drift: `drift 2.35.3`이 같은 `sqlite3`를 쓰므로 `customStatement`(마이그레이션 단계에서 `CREATE VIRTUAL TABLE`) + `customSelect`로 쓰거나, `drift_dev 2.35.2`의 `sqlite_modules: [fts5]` 옵션으로 `.drift` 파일에 가상 테이블을 선언할 수 있다(01-hooks 3.10). 어느 쪽이 CORE의 `drift_schemas/` 스냅샷·생성 마이그레이션 테스트와 잘 맞는지는 CORE가 정한다. [확인 — 옵션 존재 / 스냅샷 영향은 추측]

### 9.2 한국어 토큰화 비교 실험

`/tmp/claude-0/plan57-scratch/recog/fts2/bin/probe.dart`(sqlite3 3.8.0, VM). 바이그램 방식 = 색인 쪽에서 Dart가 공백 낱말을 소문자로 바꾸고, 한글이 든 낱말은 겹치는 음절 바이그램(`회의록을` → `회의 의록 록을`)으로, 한 음절 낱말은 그대로 둔 문자열을 `content=''`(내용 없는) `unicode61` 테이블에 넣는다. 질의는 2음절 이상 한글 낱말 → 바이그램 구(`"방정 정식"` — 이웃 토큰이라 연속 부분 문자열과 같음), 1음절·영문 → 접두사(`"정"*`), 여러 낱말 → `AND`.

출력(질의문 열은 줄이고 문서 목록·'2글자' 표시를 덧붙여 정리함):

```text
sqlite 3.54.1
문서: 1 '오늘 회의록을 정리했다 meeting notes'  2 '미분 방정식 풀이와 Laplace 변환'  3 '확률과 통계 Bayes 정리'
      4 '정식 계약서 검토'  5 '영어 단어 vocabulary 암기'
q=회의       LIKE=[1]       trigram=[] (2글자)  unicode61prefix=[1]     bigram=[1]
q=회의록      LIKE=[1]       trigram=[1]         unicode61prefix=[1]     bigram=[1]
q=의록       LIKE=[1]       trigram=[]          unicode61prefix=[]      bigram=[1]
q=정식       LIKE=[2, 4]    trigram=[]          unicode61prefix=[4]     bigram=[2, 4]
q=방정식      LIKE=[2]       trigram=[2]         unicode61prefix=[2]     bigram=[2]
q=정        LIKE=[1,2,3,4] trigram=[]          unicode61prefix=[1,3,4] bigram=[1,2,3,4]
q=록        LIKE=[1]       trigram=[]          unicode61prefix=[]      bigram=[1]
q=meet     LIKE=[1]       trigram=[1]         unicode61prefix=[1]     bigram=[1]
q=LAPLACE  LIKE=[2]       trigram=[2]         unicode61prefix=[2]     bigram=[2]
q=확률 통계    LIKE=[]        trigram=[]          unicode61prefix=[3]     bigram=[3]
q=단어 암기    LIKE=[]        trigram=[]          unicode61prefix=[5]     bigram=[5]
highlight(trigram): 미분 [방정식] 풀이와 Laplace 변환
indexed 5000 pages x 80 words in 2818 ms              (임의 음절 1~4자 낱말, 문서 표 + trigram + bigram 동시 삽입)
pages(4KiB): docs=963 tri*=2597 bip*=1455              (trigram은 detail='none', bigram은 기본 detail=full)
q=큐찐딐 trigram=1 (418us) bigramPhrase=1 (187us) LIKE=1 (6799us)
q=큐찐  trigram=-  (2글자)  bigramPhrase=1 (194us) LIKE=1 (11180us)
```

해석 [확인 — 수치 / 일반화는 추측]
- 바이그램 방식이 이번 질의를 모두 LIKE(정답)와 같거나 낫게(여러 낱말 AND) 찾았다. 한계: 1음절 질의는 '그 음절로 시작하는 바이그램'만 찾으므로 **낱말 끝 음절**(예: `방정식`의 `식`)은 못 찾는다 — 1음절 질의는 드물고 LIKE 대체 경로로 보완할 수 있다.
- 크기는 임의 음절(최악 조건)에서 trigram의 약 56%. 실제 한국어 문장은 음절 다양성이 낮아 더 작을 것이다.
- `bm25` 순위와 `highlight()`는 바이그램 내용 없는 테이블에서는 원문이 없어 쓸 수 없다 → 조각글·하이라이트는 우리 문서 표의 원문과 저장된 위치 사각형으로 만든다(어차피 손글씨는 문자 위치가 아니라 줄 사각형으로 하이라이트).
- 정규화는 PDF의 `PdfTextNormalizer` 규칙(자모 합성·소문자·공백 접기 — 06-pdf 6.10.1)과 **같은 함수**를 색인·질의 양쪽에 써야 한다. 지금 CORE `common/text_normalize.dart`(제목 검색)와 PDF 정규화가 따로 있으므로(01-hooks 3.10) 하나로 합칠지 정한다.

### 9.3 색인 구조 제안 — PDF 전역 검색과 공용

```sql
-- CORE 소유, 기기 로컬(동기화 안 함). 원천 데이터에서 언제든 다시 만들 수 있음.
CREATE TABLE search_units(
  id INTEGER PRIMARY KEY,
  source TEXT NOT NULL,        -- 'ink' | 'pdf' | 'text' (텍스트 상자, M5) | 'math' (LaTeX, 선택)
  owner_key TEXT NOT NULL,     -- ink: recognitionId#line, pdf: assetId#pdfPageIndex, text: elementId
  note_id TEXT, page_id TEXT,  -- pdf는 NULL(같은 PDF 에셋을 여러 노트가 공유) → 질의 때 pages(PdfBackground)로 풀어냄
  body TEXT NOT NULL,          -- 정규화한 본문(조각글·LIKE 대체용)
  rects BLOB,                  -- 줄(손글씨) / 글자(PDF) 사각형, 노트 페이지 pt 또는 PDF 표시 pt(source별 규칙)
  source_rev TEXT NOT NULL,    -- 낡음 판정: 획 집합 해시+엔진 / 에셋 sha256 / 요소 version
  UNIQUE(source, owner_key)
);
CREATE VIRTUAL TABLE search_fts USING fts5(g, content='', tokenize='unicode61');  -- rowid = search_units.id
```

- 채우는 쪽
  - `ink`: CORE가 동기화된 인식 결과 엔티티(01-hooks R7 — 줄별 `text`·후보·`strokeIds`·사각형·`engineId`·획 집합 해시)를 받는 즉시 내부에서 색인한다. 인식 자체(ML Kit 호출)는 `ink_recognition` + 앱 셸의 백그라운드 작업이 `NoteStore.changes`(`EntityChange` — 획은 `pageId` 항상 포함)로 바뀐 페이지만 골라 유휴 시간에 한다. [확인 — 변경 알림 형식은 01-hooks 3.10 / 나머지 추측]
  - `pdf`: 의존 방향상 CORE는 `pdf_io`를 모르므로(계약 7.1), `pdf_io`가 `PdfTextService.pageText(assetId, i)`로 추출해 CORE의 `SearchIndexWriter.upsert(source: 'pdf', ownerKey:, body:, rects:, sourceRev: 에셋 sha256)`를 부른다. 에셋 단위라 같은 PDF를 여러 노트에 넣어도 한 번만 색인한다. [추측]
  - `text`·`math`: M5 텍스트 상자·M7 수식 객체의 내용. CORE가 요소 엔티티를 가지므로 내부에서 색인한다. [추측]
- 질의: `normalize(q)` → 바이그램 질의 → `search_units` 조인 → 노트·페이지별 묶음, 최대 N개. LIBRARY 검색 화면(01-hooks 3.10의 '폴더·노트' 묶음 구조)에 '손글씨'·'PDF 텍스트' 묶음을 더하고, 결과를 누르면 페이지 + 사각형으로 연다(`onOpenNote`에 페이지·사각형을 넘기는 계약 추가 필요 — 01-hooks 3.10).
- 다시 만들기: 색인은 파생 데이터이므로 스키마 판을 올리거나 정규화 규칙이 바뀌면 지우고 다시 만든다(웹은 IndexedDB 용량 압박이 있으면 PDF 색인만 끄는 설정을 둘 수 있음). [추측]
- 결론: **같은 구조로 갈 수 있다.** 1차 7.8에서 미룬 라이브러리 전역 PDF 텍스트 검색을 M7 색인 작업에 묶어 한 번에 만드는 것이 비용상 유리하다(11절 R8).

### 9.4 인식 결과 엔티티(동기화)에 대한 보충

01-hooks R7(결과는 동기화, 색인은 기기별)에 동의하고 다음을 더한다. [추측]
- 단위는 '페이지별 결과 하나'(줄 목록을 JSON으로)가 동기화 문서 수·충돌 면에서 단순하다. 같은 페이지를 두 기기가 동시에 인식하면 나중 것(엔진 판이 같으면 `updatedAt`)이 이긴다 — 파생 데이터라 손실 위험이 작다.
- 결과에 `engineId`(`mlkit-digital-ink/19.0.0:ko`)를 둔다. 웹은 결과를 만들지 않으므로 받기만 한다.
- 사용자가 변환 창에서 고친 글자(후보 선택·직접 편집)는 '사용자 확정' 표시를 두어 자동 재인식이 덮어쓰지 않게 한다.

---

## 10. 실험 기록

| # | 실험 | 위치 · 명령 | 결과 |
|---|---|---|---|
| E1 | 후보 패키지 해석 | `recog/probe/pubspec.yaml`(계약 고정 `flutter_riverpod 3.4.3`·`material_ui 1.10.0`·`meta 1.19.0`·`collection 1.19.1`·`drift 2.35.3`·`sqlite3 3.8.0`·`firebase_core 5.1.0` + `cloud_functions 7.0.1`·`google_mlkit_digital_ink_recognition 0.16.1`·`flutter_math_fork 0.7.4`·`one_dollar_unistroke_recognizer 1.3.5`), `flutter pub get`(4초) | 성공. 해석 버전은 13절 |
| E2 | 도형 판정 | `flutter test test/shape_fit_test.dart` | 4.2절 표 |
| E3 | LaTeX 해석·렌더(VM) | `flutter test test/math_render_test.dart` | `parsed 42/43; failed: {tag: Undefined control sequence: \gdef}`, `build errors (1): [tag: …]` |
| E4 | 웹: 수식 렌더 + ML Kit 호출 | `flutter test --platform chrome test/web_probe_test.dart` | 1차: `textStyle` 없이 `Unexpected null value`(`math.dart` 189:46), ML Kit 30초 시간 초과. 2차: `textStyle` 지정 → `flutter errors: 0`, `math size … Size(438.2, 60.3)`, ML Kit `TimeoutException`(5초 제한) |
| E5 | FTS5 한국어 | `recog/fts2`, `dart pub get --offline && dart run bin/probe.dart`(8초) | 9.2절 |
| E6 | 예제 소스 | googlesamples/mlkit sparse clone(`8cb8b879`) | 3.3절 텍스트 외 모델·제스처 모델 |
| E7 | 웹 글꼴 적재 | 엔진 소스 grep | 8.2절 3 |
| E8 | KaTeX 글꼴 크기 | 20개 TTF 각각 `gzip -9` 후 바이트 합계 | 640,372B → 370,984B |

---

## 11. 권장안 (조사자 의견 — 설계에서 채택 여부 결정)

R1. **손글씨→텍스트 엔진은 계획대로 ML Kit(`google_mlkit_digital_ink_recognition 0.16.1`)로 하고, 첫 작업을 '안드로이드 APK 실기기 판정'으로 둔다.** 확인 목록: `ko` 태그로 모델 받기, 한국어 문장·혼용 문장 30줄 문자 오류율(`ko` 단독 vs `ko`+`en` 선택), 줄당 인식 시간, 모델 받기 크기. 선행 조건은 01-hooks R10(안드로이드 네이티브 저장)이다. iPad 네이티브는 Apple 계정·TestFlight 뒤에 같은 목록으로 확인하고, 그 전에 INFRA가 iOS 배포 대상을 15.5로 올려 둔다.

R2. **혼용 전략은 실험 전까지 'A(`ko` 단독) + 변환 창 언어 바꾸기(D)'를 기본으로 설계하고, 인터페이스는 B(두 모델 선택)를 넣을 수 있게 둔다.** `TextCandidate`에 `languageTag`를 두고 점수는 엔진·모델 안에서만 비교한다.

R3. **인식 단위는 '줄'이고 줄 나누기·낡음 판정·위치 사각형은 우리 순수 Dart 코드가 맡는다.** ML Kit가 위치를 주지 않으므로 검색 하이라이트는 줄 사각형으로 한다. `groupIntoLines`는 합성 획 테스트로 컨테이너에서 완료 판정한다.

R4. **자동 도형 보정은 INK의 순수 Dart 기하 판정(4.3절)으로 한다.** ML Kit 도형 모델(웹 불가, 기하 없음)과 `one_dollar_unistroke_recognizer`(타원·회전 사각형 약함, 전역 상태)는 쓰지 않는다. 문턱값은 상수 한 곳(`ShapeTuning` 같은)에 모으고, 실기기 획 고정 자료로 회귀 테스트를 만든다.

R5. **웹은 '인식하지 않고 동기화된 결과로 검색'(W1)을 이번 라운드 범위로 한다.** ML Kit 어댑터는 조건부 import로 네이티브에만, 웹 구현은 `RecognizerUnsupported`. 웹 변환(W2, 서버 이미지 OCR)은 Firebase 프로젝트가 생긴 뒤 어댑터 하나로 더한다.

R6. **수식 엔진은 서버 함수 뒤에 두는 교체형 어댑터(7절)로 만들고, 1순위 후보는 Mathpix(스트로크 입력·`app_token`·저비용), 비교 후보는 Claude(Sonnet 5.5 / Haiku 5.5, 이미지 + 구조화 출력)로 한다.** MyScript 네이티브 SDK는 Flutter 플러그인을 직접 만들어야 하고 가격이 비공개라 이번 라운드에서 제외하고, Cloud REST는 비교 실험에만 넣는다. 결정은 6.6절 실험(손글씨 50개) 결과로 한다.

R7. **이번 라운드 수식 범위는 '어댑터 + 가짜 엔진 + 수식 객체·렌더·LaTeX 직접 편집 + 서버 함수 코드(에뮬레이터)'까지로 하고, 실제 엔진 호출은 Firebase 프로젝트 생성 뒤 완료 판정한다.** Firebase가 없어도 LaTeX 직접 입력으로 수식 객체는 쓸 수 있게 해 둔다(엔진 없는 기능 경로).

R8. **검색 색인은 CORE가 소유하는 `search_units` + FTS5 바이그램 테이블 하나로 만들고, 1차 7.8에서 미룬 라이브러리 전역 PDF 텍스트 색인을 같은 작업에 묶는다.** 정규화 함수는 PDF·제목·손글씨가 하나를 쓰게 합친다. 색인은 기기 로컬·재구축 가능, 인식 결과는 동기화(01-hooks R7).

R9. **수식 렌더는 `flutter_math_fork 0.7.4`의 `Math.tex`만 쓰고(항상 `textStyle` 명시, `SelectableMath` 금지), KaTeX 글꼴 371KB(gzip)를 INFRA 웹 예산표에 올린다.** 갱신이 멈춘 패키지라 깨지면 포크한다. PDF 내보내기는 래스터(P1)를 1단계로 한다.

R10. **새 의존(정확한 버전 고정 후보)**: `google_mlkit_digital_ink_recognition: 0.16.1`(간접 `google_mlkit_commons 0.13.0`), `flutter_math_fork: 0.7.4`(간접 `flutter_svg 2.3.2`·`provider 6.1.5+1`·`tuple 2.0.2`), `cloud_functions: 7.0.1`. `one_dollar_unistroke_recognizer`는 넣지 않는다.

---

## 12. 열린 질문 (사용자 또는 총괄이 정할 것)

| # | 질문 | 왜 필요한가 | 조사자 기본안 |
|---|---|---|---|
| Q1 | 손글씨 자동 인식(검색 색인용)을 기본으로 켤 것인가, '인식 켜기'를 사용자가 고르게 할 것인가? | 모델 약 40MB 받기, 배터리·저장 공간, 결과 동기화 용량 | 설정에서 켜기(기본 꺼짐) + 처음 '텍스트로 변환' 때 안내 |
| Q2 | 혼용 인식을 `ko` 단독으로 시작해도 되는가? | 두 모델 병행은 호출 2배·규칙 필요 | 실기기 실험(R1) 뒤 결정, 그 전엔 A + D |
| Q3 | 웹(iPad Safari)에서 '텍스트로 변환'이 필요한가? | 필요하면 서버 OCR(W2) — Firebase 종량제·외부 API 비용 | 이번엔 불필요(검색만), 네이티브 전환 전 다시 판단 |
| Q4 | 수식 엔진 비교 실험에 쓸 유료 계정을 만들 것인가(Mathpix 설정비 $19.99, Anthropic API 키)? 키는 누구 계정인가? | 6.6절 실험은 실제 호출이 필요 | 사용자 계정으로 Mathpix + Anthropic 각각 소액 |
| Q5 | 손글씨 이미지·획을 외부 서비스(Mathpix·Anthropic·MyScript)로 보내는 것에 동의하는가? | 개인 노트 내용이 제3자에게 전송됨 | 수식 영역만 전송, 설정에 명시 |
| Q6 | 이번 라운드에 서버 함수(`functions/`)를 만들 것인가? 만들면 소유 영역은 INFRA인가 SYNC인가? | Firebase 프로젝트 없음 → 배포 검증 불가 | 코드 + 에뮬레이터 테스트만, 소유 INFRA |
| Q7 | 수식 '실시간 미리보기'(F-14)를 획마다로 할 것인가, 쓰기 멈춤 뒤 1회로 할 것인가? | 획마다는 Mathpix 라이브 세션(세션 과금) 또는 MyScript가 필요 | 멈춤(약 1초) 뒤 1회 |
| Q8 | 라이브러리 전역 PDF 텍스트 검색(1차 7.8 '이후')을 M7 색인과 함께 이번에 넣는가? | 같은 테이블·질의라 따로 만들면 중복 | 함께 넣음(R8) |
| Q9 | PDF 내보내기에서 수식을 래스터로 내도 되는가? | 벡터는 서버 SVG(P2) 등 비용 큼 | 래스터 300dpi로 시작 |
| Q10 | 웹 첫 로드에 KaTeX 글꼴(gzip 약 371KB)을 더해도 되는가, 아니면 포크해 지연 적재하는가? | 계약 7.4.10 웹 예산 | 더함(측정 후 초과 시 포크) |
| Q11 | 인식 결과 엔티티를 페이지 단위로 할 것인가, 줄(블록) 단위로 할 것인가? | SYNC 문서 수·충돌 단위, CORE 스키마 | 페이지 단위 JSON |
| Q12 | 자동 도형 보정의 발동 방식(펜을 댄 채 멈춤 500ms)과 지원 도형(별·화살표 포함 여부)은? | INK 입력 파이프라인·도형 요소 종류 | 멈춤 500ms, 직선·원·타원·삼각형·사각형·다각형 먼저, 별·화살표는 도형 도구로만 |
| Q13 | 실기기 획 표본(도형·손글씨·수식)을 테스트 고정 자료로 저장소에 넣어도 되는가? | 문턱값 회귀 테스트·엔진 평가에 필요, 개인 필기 내용이 저장소에 남음 | 도형·수식 표본만(내용이 개인적이지 않은 것) |

---

## 13. 확인한 버전

| 패키지 · 도구 | 버전 | 확인 방법 | 비고 |
|---|---|---|---|
| google_mlkit_digital_ink_recognition | 0.16.1 (2026-08-17, sdk ^3.12.0, flutter >=3.44.0, android·ios) | pub.dev API + 보관 파일(sha256 `c0483cef…9395`) 소스 + E1 해석 | 안드로이드 `digital-ink-recognition:19.0.0`, iOS `GoogleMLKit/DigitalInkRecognition ~> 9.0.0`, iOS 15.5 |
| google_mlkit_commons | 0.13.0 (2026-08-17) | pub.dev API + 보관 파일 소스 + E1 해석 | 모델 관리자. iOS Wi-Fi 인자 무시 |
| flutter_math_fork | 0.7.4 (2025-05-21) | pub.dev API + 보관 파일(sha256 `6d5f2f1a…a407`) + E1 해석 + E3(VM)·E4(Chrome) 실행 | `\tag` 미지원, `textStyle` 필수 |
| flutter_svg (간접) | 2.3.2 | E1 `flutter pub deps` | `vector_graphics 1.2.6`, `http 1.6.0` 끌어옴 |
| provider (간접) | 6.1.5+1 | E1 | |
| tuple (간접) | 2.0.2 | E1 | |
| one_dollar_unistroke_recognizer | 1.3.5 (2026-08-13, BSD-3) | pub.dev API + 보관 파일(sha256 `7bb8c50f…aabde`) + E1 + E2 실행 | 비교용. 채택 안 함 |
| cloud_functions | 7.0.1 (2026-10-23, firebase_core ^5.1.0) | pub.dev API 버전 목록 + E1 해석 | `cloud_functions_platform_interface 6.1.1`, `cloud_functions_web 5.1.15` |
| firebase_core | 5.1.0 | 계약 7.5 + E1 해석 | `firebase_core_web 4.1.0` |
| sqlite3 (Dart) / SQLite | 3.8.0 / 3.54.1 | E5 `dart run` 출력 `sqlite 3.54.1` | 최신 3.9.0(2026-11-05)은 채택하지 않음(01-hooks와 같음) |
| drift / drift_dev | 2.35.3 / 2.35.2 | 계약 7.5, E1 해석, 01-hooks 3.10 | `sqlite_modules: [fts5]` 지원 |
| iink-ts (웹, 참고) | 4.1.0 (Apache-2.0) | raw.githubusercontent.com `package.json` | Flutter 연동 없음 |
| flutter_tex / latext / katex_flutter (참고) | 5.3.0 / 0.5.1 / 4.0.2+26 | pub.dev API | WebView 기반 / fork 래퍼 / Dart 2 전용 |
| flutter_myscript / myscriptwidget (참고) | 0.0.6 / 1.0.0 | pub.dev API | 전자는 `sdk <3.0.0`으로 해석 불가 |
| Flutter / Dart | 3.47.9 / 3.13.7 | `/opt/flutter` | 기본 Android compileSdk 36·minSdk 24 |
| Claude 모델(서버 함수 후보) | `claude-sonnet-5-5`, `claude-haiku-5-5`, `claude-opus-5-5` | claude-api 스킬 모델 표(2026-10-06 캐시) | 단가는 6.4절. 실제 호출은 하지 않음 |

임시 작업 위치: `/tmp/claude-0/plan57-scratch/recog/`(`probe/` — `lib/shape_fit.dart`, `test/{shape_fit,math_render,web_probe}_test.dart`; `fts2/bin/probe.dart`; `dl/`; `gh/`; `*.json`). 작업 트리·`/home/user/noteapp`은 수정하지 않았다.
