# 2차 라운드 기술 조사 04 — 네이티브 빌드·실기기 테스트·서버 함수

> 상태: 조사 완료(2026-11-05) · 담당: 2차 라운드 기술 조사(네이티브 빌드·실기기 테스트·서버 함수) · 기준 계약: [00-overview.md 7장 v1.4](../../00-overview.md#7-통합-계약) · 1차 INFRA 계획: [01-infra.md](../../01-infra.md) 6.12~6.16 · 마스터 기획서: [PLAN.md](../../../PLAN.md) 6.2·6.3, 9.5, 10장 '네이티브 전환'·M5~M7, F-14(키는 서버 함수 경유) · 함께 볼 문서: [01-hooks.md](01-hooks.md) 3.12·요약 13(네이티브 저장 경로), [02-audio-stylus.md](02-audio-stylus.md) 4·7절(백그라운드 녹음·권한), [03-recognition.md](03-recognition.md)(인식 엔진 비교)
>
> M5~M7 기능 중 네이티브에서만 확인할 수 있는 것(백그라운드 녹음, ML Kit 손글씨 인식, Pencil 더블탭·스퀴즈, S펜 버튼)을 **실기기에서 시험할 경로**와 그에 필요한 네이티브 설정, 그리고 수식 인식 등 외부 API 키를 감출 **서버 함수(Firebase Functions)** 골격을 조사한다. 의존성 해석·웹 빌드·Chrome 실행·Firebase 에뮬레이터 실행은 임시 프로젝트에서 실제로 했다. 설계 결정은 하지 않는다. 조사자 의견은 9절 '권장안', 정해야 할 것은 10절 '열린 질문'으로 분리한다.

표기

| 표시 | 뜻 |
|---|---|
| **[확인]** | 이 컨테이너에서 명령을 실행하거나 소스(Flutter SDK·패키지·firebase-tools·podspec)를 읽어 직접 확인한 사실. 명령·경로·줄 번호를 함께 적는다 |
| **[문서]** | 공식 문서·패키지 README·계획서에 적힌 내용(실행으로 확인하지 않음). 출처를 함께 적는다 |
| **[2차]** | 블로그·포럼·검색 결과 요약으로만 본 내용. 공식 원문(docs.github.com, firebase.google.com, docs.cloud.google.com, blog.cocoapods.org)이 이 세션 네트워크 허용 목록 밖이라 열지 못했다 |
| **[추측]** | 확인하지 않은 판단. 근거를 함께 적고, 설계 전 또는 CI·실기기에서 확인이 필요하다 |

---

## 0. 요약 — 핵심 사실

1. **이 컨테이너에서는 안드로이드 Gradle 빌드를 할 수 없다.** Android SDK가 없고, `dl.google.com`이 프록시에서 막혀 있으며(`connect_rejected`), `maven.google.com`의 산출물 주소도 `dl.google.com`으로 301 이동하므로 AGP·AndroidX·ML Kit AAR을 받을 수 없다. `flutter build apk --config-only`도 "No Android SDK found"로 멈춘다. 컨테이너에서 할 수 있는 것은 Dart 분석·웹 빌드·Chrome 실행과 **설정 파일 정적 검사**(매니페스트·Info.plist·pbxproj·gradle·워크플로 YAML)와 **플러그인 요구 사항 스캔**(23행짜리 파이썬 시제품으로 실제로 만들어 봄, 3.7)뿐이다. [확인]
2. **현재 안드로이드 빌드 도구 조합은 Flutter 3.47.9의 검사 기준을 모두 통과한다.** 앱은 AGP 9.1.0·Gradle 9.3.1·Kotlin 2.4.0·Java 17 대상이고, Flutter의 경고 하한은 AGP 9.0.1·Gradle 9.1.0·KGP 2.3.20·Java 17·minSdk 24다. Flutter 기본값은 compileSdk 36·targetSdk 36·minSdk 24·NDK 28.2.13676358이다. 템플릿의 `android.builtInKotlin=false` 때문에 Flutter Gradle 플러그인이 플러그인 하위 프로젝트에 `kotlin-android`를 직접 적용한다. [확인 — `DependencyVersionChecker.kt` 94–117, `FlutterExtension.kt` 23–42, `FlutterPluginUtils.kt` 580]
3. **M5~M7 후보 플러그인의 안드로이드 minSdk는 모두 24 이하라 앱 기본값(24) 그대로 된다.** compileSdk는 `permission_handler_android 14.1.1`만 **37**이고 앱은 36이다. Flutter는 이것을 error 수준 **로그**로만 알리고 빌드를 멈추지 않는다. [확인 — 3.2 표, `ValidateCompileSdkVersionTask.kt` 101–119]
4. **릴리스 APK 매니페스트에 `INTERNET` 권한이 없다.** `app/android/app/src/main/AndroidManifest.xml`에는 없고 `debug`·`profile` 매니페스트에만 있다. `android.yml`은 `--release`로 빌드하므로 ML Kit 모델 내려받기·Firebase·서버 함수 호출이 막힐 수 있다(플러그인 AAR이 `INTERNET`을 병합해 줄 가능성은 있으나 AAR을 받을 수 없어 확인 못 함). 앱 이름도 안드로이드는 `noteapp`, iOS는 `필기노트`다. [확인 / 병합은 추측]
5. **지금 `android.yml`의 APK는 실기기 반복 시험에 맞지 않는다.** ① 러너마다 새 debug 키로 서명해 덮어 설치가 안 된다(INFRA 6.14가 이미 밝힘) ② 앱 셸이 `nativeDatabasePath`를 넘기지 않아 네이티브에서 노트 저장이 열리지 않는다(01-hooks 요약 13) ③ 위 4번. 셋 다 고쳐야 녹음·인식을 태블릿에서 이어서 시험할 수 있다. [확인]
6. **GitHub `ubuntu-24.04` 러너 이미지(20261026)는 Java 17 기본, android-36·37 플랫폼, build-tools 36·37, NDK 27.3(기본)·29·30을 갖고 있다. Flutter 기본 NDK 28.2는 없다.** 빌드 때 내려받게 된다. 또 PDF 영역의 `pdfium_dart` 빌드 훅이 안드로이드에서도 C 파일을 컴파일(NDK)하고 PDFium 바이너리를 GitHub 릴리스에서 내려받는다. [확인 — runner-images README, `pdfium_dart-0.4.1/hook/build.dart` 14–49 / 내려받기 시간은 추측]
7. **ML Kit iOS는 배포 대상 15.5 이상 + CocoaPods 전용이다.** `google_mlkit_digital_ink_recognition 0.16.1`·`google_mlkit_commons 0.13.0`은 podspec만 있고 `Package.swift`가 없다. CocoaPods 사양(`GoogleMLKit 9.0.0`, `MLKitCommon 14.0.0`, `MLKitDigitalInkRecognition 8.0.0`)도 모두 `ios: 15.5`다. 앱은 지금 15.0 + SwiftPM(Podfile 없음)이다. ML Kit을 넣으면 Flutter는 **SwiftPM + CocoaPods 혼합 모드**로 Podfile을 만들고 "This will become an error in a future version of Flutter" 경고를 낸다. [확인 — podspec, `darwin_dependency_management.dart` 90·292, `podhelper.rb` 327–334]
8. **CocoaPods 경로 자체가 저물고 있다.** CocoaPods trunk가 2026-12-02부터 읽기 전용(11-01~07 시험 운영 중)이고, `firebase_core 5.1.0`의 소스 주석은 "firebase-ios-sdk는 2026년 10월부터 CocoaPods에 새 버전을 올리지 않는다, CocoaPods 고정 12.19.3"이라고 적는다(SwiftPM은 13.1.1). ML Kit iOS는 Google 공식 SwiftPM 배포가 없다. 기존 pod는 계속 받을 수 있으나 ML Kit iOS 업데이트 경로가 불확실하다. [확인(소스 주석·pod 목록) / 2차(trunk 날짜)]
9. **혼합 모드에서 Firebase(SwiftPM)와 ML Kit(CocoaPods)이 같은 하위 라이브러리를 두 벌 넣을 위험이 있다.** `MLKitCommon 14.0.0`은 `GoogleUtilities ~> 8.0`·`GTMSessionFetcher/Core >= 3.3.2, < 4.0`·`GoogleDataTransport ~> 10.0`을 pod로 끌어오고, Firebase는 SwiftPM으로 같은 이름의 패키지를 넣는다. 같은 구성(Firebase SPM + ML Kit pod)에서 GoogleUtilities·FBLPromises 중복 문제를 겪었다는 보고가 있다. **단, 이번 범위 앱은 `sync_engine`에 의존하지 않아(계약 7.1) Firebase 네이티브 SDK가 iOS 빌드에 들어가지 않는다.** M4 연결이나 `cloud_functions`·`firebase_auth`를 앱에 넣는 순간 현실이 된다. [확인(podspec) / 2차(중복 보고) / 추측(우리 빌드에서의 결과)]
10. **macOS 러너: `macos-latest` = macOS 26 arm64, Xcode 26.6 기본, CocoaPods 1.17.0, fastlane 2.241.2.** Apple은 2026-04-28부터 App Store Connect 업로드에 **Xcode 26 + iOS 26 SDK**를 요구하고, 2026-09-09부터 iOS 13 이상 대상을 요구한다. Flutter 3.47.9는 Xcode 15 이상(권장 16), CocoaPods 1.10 이상(권장 1.16.2)을 요구한다. 리눅스 Flutter에는 `flutter build ios`·`ipa` 하위 명령 자체가 없다. [확인(runner-images·flutter_tools·리눅스 실행) / 문서(Apple 요구 사항 페이지)]
11. **TestFlight 자동 서명(`xcodebuild -allowProvisioningUpdates` + API 키)은 API 키가 Admin 역할이어야 배포 인증서를 만들 수 있다는 보고가 여럿 있다.** INFRA 안내서 06은 App Manager 키로 안내한다. App Manager로 가려면 배포 인증서(.p12)·프로비저닝 프로파일을 수동으로 만들어 시크릿에 넣는 경로가 필요하다. [2차 — Apple 개발자 포럼 스레드 698117 등]
12. **웹 빌드에 네이티브 전용 플러그인이 섞여도 컴파일은 된다. 문제는 실행이다.** `google_mlkit_digital_ink_recognition`(내부 `google_mlkit_commons`가 `dart:io` import)·`flutter_foreground_task`·`permission_handler`·`image_picker`·`cloud_functions`를 넣고 **가드 없이** 부르는 앱이 `flutter build web`(dart2js)과 **wasm dry run**을 모두 통과했다. 빌드한 앱을 헤드리스 Chrome에서 돌리면 ML Kit·포그라운드 서비스는 `MissingPluginException`, 초기화 전 `cloud_functions`는 null 검사 오류, `permission_handler`는 웹 구현이 있어 `denied`, `image_picker`는 지원을 낸다. ML Kit의 `Ink` 클래스는 `material_ui`의 `Ink` 위젯과 이름이 겹친다. 넣고 안 넣고의 `main.dart.js` 크기 차는 14 KB였다. [확인 — 7절]
13. **Firebase Functions 배포에는 Blaze(종량제)가 필요하다.** firebase-tools 소스가 "Cloud Functions deployment requires the pay-as-you-go (Blaze) billing plan"을 던진다. `asia-northeast3`(서울)은 `firebase-functions` 7.4.0의 `SupportedRegion`에 있다. Node 22 런타임은 GA이고 지원 중단 예정일은 2027-04-30이다(firebase-tools 15.34.2 표). [확인 — `deploy/functions/ensure.js` 39, `lib/v2/options.d.ts` 8, `runtimes/supported/types.js`]
14. **Firebase 프로젝트 없이 서버 함수를 개발·시험할 수 있다(실제로 함).** `demo-noteapp` 프로젝트 ID로 Functions + Auth 에뮬레이터를 띄워 TypeScript 골격(`onCall`, 지역 `asia-northeast3`, `defineSecret`, 로그인 필수, 입력 검사, 가짜 엔진)을 호출했다. 로그인 없이 → `UNAUTHENTICATED`, 잘못된 입력 → `INVALID_ARGUMENT`, 정상 → `{latex, confidence, engine}`. 비밀값은 `functions/.secret.local`, 설정값은 `.env.local`에서 읽혔다. **Dart `package:http`로 같은 함수를 호출하는 VM 프로그램**도 통과했다. `app/firebase.json`의 `functions.source: "../functions"`(저장소 루트의 `functions/`)도 동작한다. Firestore 에뮬레이터는 Java 21로 jar를 내려받아 문서 쓰기까지 됐다(SYNC 계획서 07-sync 55행의 '내려받기 가능 여부 미확인' 해소). [확인 — 6.4·6.5]
15. **Firebase AI Logic의 `gemini-developer-api` 공급자는 Spark(무료)에서 켤 수 있다**(Blaze가 필요한 것은 `gemini-agent-platform-api`뿐). 멀티모달 엔진을 Gemini로 정하면 서버 함수·Blaze 없이도 키가 앱에 들어가지 않는다. Mathpix 대리 호출·Claude 대리 호출이면 Functions(Blaze)가 필요하다. `api.mathpix.com`은 이 컨테이너에서 막혀 실제 호출 시험은 못 한다. [확인 — firebase-tools `gcp/ailogic.js` 316–335, 접속 시험]
16. **`permission_handler`는 이번 기능에 필요 없다.** 마이크는 `record`의 `hasPermission`, 알림은 `flutter_foreground_task`, 사진은 iOS PHPicker·안드로이드 사진 선택기(안드로이드 16+는 항상)가 권한 없이 처리한다. 남는 것은 '설정 앱 열기'뿐이다. 넣는다면 `permission_handler_apple 9.6.5`가 SwiftPM에서 Info.plist의 `NS*UsageDescription` 키로 권한 매크로를 자동으로 정한다(2026-11-02 게시, 3일 됨). [확인 — README·소스]
17. **비공개 저장소 Actions 무료 시간은 월 2,000분, macOS는 10배로 계산된다**(2026년 단가 인하 뒤에도 배수는 같다는 보고). iOS 컴파일 확인 1회를 15~25분으로 잡으면 150~250분이 든다. [2차 / 추측(시간)]

---

## 1. 조사 범위와 방법

### 1.1 질문

| # | 질문 | 답한 절 |
|---|---|---|
| N1 | 현재 저장소의 `app/android`·`app/ios`, `ci.yml`, INFRA 계획 6.13~6.15와 INFRA 작업 트리의 최신 상태 | 2 |
| N2 | 안드로이드: Actions에서 Flutter 3.47.9로 APK 빌드·내려받아 설치, JDK·Gradle·AGP·minSdk/targetSdk, 컨테이너 검증 범위, 플러그인 minSdk | 3 |
| N3 | iOS: 계정 없이 `--no-codesign` 컴파일 확인, 계정 뒤 TestFlight, 최소 버전, Info.plist 키, macOS 러너 비용 | 4 |
| N4 | 권한 처리 패키지 필요 여부·버전 | 5 |
| N5 | 서버 함수: TypeScript 골격, Blaze, 지역, 에뮬레이터, 프로젝트 없이 개발 | 6 |
| N6 | 웹 빌드에 네이티브 전용 플러그인이 섞일 때 | 7 |

### 1.2 확인 환경

- Flutter 3.47.9 stable(`c197ca5`) / Dart 3.13.7(`/opt/flutter`), OpenJDK 21.0.12, Node 22.23.4 / npm 10.9.9, 헤드리스 Chrome(`/usr/local/bin/chrome-nosandbox`) + Playwright(전역 설치본). Android SDK 없음, `/dev/kvm` 없음, 4 CPU, 메모리 15 GB.
- 네트워크: pub.dev·registry.npmjs.org·raw.githubusercontent.com·cdn.cocoapods.org·storage.googleapis.com·`*.googleapis.com` API 호스트는 열림. **dl.google.com·www.gstatic.com·firebase.google.com·docs.github.com·docs.cloud.google.com·blog.cocoapods.org·api.mathpix.com은 막힘**(프록시 `connect_rejected` 또는 WebFetch `ENOTFOUND`). 이 호스트를 허용하면 [2차] 항목을 원문으로 다시 확인할 수 있다.
- 임시 작업 위치(모두 `/tmp/claude-0/plan57-scratch/native/` 아래): `ws/`(1차 워크스페이스 pubspec·lock 복사 + 시험 멤버 `native_probe`), `webprobe/`(독립 Flutter 앱, 웹 빌드·Chrome 실행), `fbtools/`(firebase-tools 15.34.2), `fnrepo/`(`app/firebase.json` + `functions/` 골격), `dartclient/`(Dart HTTP 호출 시험), `pods/`(CocoaPods 사양 JSON), `scripts/`(시험 스크립트·플러그인 요구 스캐너).
- 기준 작업 트리(읽기 전용): `/home/user/noteapp`(`ec8366a`, 기반 단계), `/home/user/wt/infra`(`1a62fba`, I1~I15 완료). 영역 작업 트리 7개의 `pubspec.lock`은 noteapp과 같다(md5 앞 8자 `24867773` 모두 일치). [확인]

---

## 2. 현재 상태 — 저장소·INFRA 작업 트리

| 항목 | 위치 | 현재 값 | M5~M7에 필요한 것 | 근거 |
|---|---|---|---|---|
| 안드로이드 빌드 도구 | `app/android/settings.gradle.kts`, `gradle-wrapper.properties`, `app/build.gradle.kts` | AGP 9.1.0, Kotlin 2.4.0, Gradle 9.3.1, Java 17(`compileOptions`·`jvmTarget`) | 그대로 | [확인] |
| SDK 수준 | `app/build.gradle.kts` | `flutter.compileSdkVersion`(36)·`minSdkVersion`(24)·`targetSdkVersion`(36)·`ndkVersion`(28.2.13676358) | 그대로(3.2) | [확인 — `FlutterExtension.kt` 23–42] |
| `gradle.properties` | `app/android/gradle.properties` | `-Xmx8G`, `android.newDsl=false`, `android.builtInKotlin=false` | 그대로. 러너(7 GB)·컨테이너에서 `-Xmx8G`는 메모리보다 커서 실제로는 OS가 정함 [추측] | [확인] |
| 앱 ID | 안드로이드 `applicationId`, iOS `PRODUCT_BUNDLE_IDENTIFIER` | 둘 다 `dev.noteapp.noteapp` | 고정 서명·TestFlight 전에 확정(INFRA Q12) | [확인] |
| release 서명 | `app/build.gradle.kts` `buildTypes.release` | `signingConfigs.getByName("debug")` | 고정 키(3.5) | [확인] |
| 매니페스트 | `app/android/app/src/main/AndroidManifest.xml` | 권한 없음, `android:label="noteapp"`. `INTERNET`은 `debug`·`profile`에만 | `INTERNET`, 녹음 권한·포그라운드 서비스(02-audio 4.2), 라벨 `필기노트` | [확인] |
| iOS 배포 대상 | `Runner.xcodeproj/project.pbxproj` 363·490·542행 | `IPHONEOS_DEPLOYMENT_TARGET = 15.0`(Flutter 템플릿 기본), `TARGETED_DEVICE_FAMILY = "1,2"` | ML Kit 때문에 15.5 이상(4.3) | [확인] |
| iOS 의존 관리 | `app/ios/` | Podfile 없음(SwiftPM 기본 켜짐) | ML Kit이 들어오면 Podfile 필요(4.4) | [확인] |
| Info.plist | `app/ios/Runner/Info.plist` | `CFBundleDisplayName=필기노트`, UIScene 매니페스트(`SceneDelegate`), `UIApplicationSupportsIndirectInputEvents=true`, 권한 설명·`UIBackgroundModes` 없음 | 4.5 표 | [확인] |
| 내보내기 옵션 | `app/ios/ExportOptions.plist` | `method: app-store-connect`, `destination: upload`, `signingStyle: automatic`, `teamID` 빈 값(CI가 채움) | 서명 방식에 따라 바뀜(4.6) | [확인] |
| `ci.yml` | `.github/workflows/ci.yml` | noteapp은 B1 최소판(검사·분석·VM·Chrome 테스트·웹 빌드). INFRA 작업 트리는 17단계 완성판 | 서버 함수 시험 잡을 넣는다면 여기 또는 별도(6.6) | [확인] |
| `android.yml` | INFRA 작업 트리 | `main` 푸시·수동, `ubuntu-latest`, Java 17, `flutter build apk --release --split-per-abi`, `app-arm64-v8a-release.apk`를 7일 보관 | 3.4 | [확인] |
| `ios-testflight.yml` | INFRA 작업 트리 | 수동 + `confirm=yes` + 변수 `IOS_TESTFLIGHT_ENABLED`, `macos-latest`, 시크릿 4개, `flutter build ios --release --no-codesign` → `xcodebuild archive -allowProvisioningUpdates`(API 키) → `-exportArchive`(업로드) | 4.6 | [확인] |
| 워크플로 시험 | INFRA `tool/test/workflows_test.dart` | 42건(잡 시간 제한·권한·액션 버전·`ws` 호출 인자 해석·`bash -n` 등) | 새 워크플로도 같은 방식으로 시험(3.7) | [확인 — 진행 기록 I13] |
| 안내서 | INFRA `docs/guides/05-android-apk.md`, `06-ios-testflight.md` | 05: 덮어 설치가 안 될 수 있다고 안내. 06: API 키 액세스 **App Manager** | 3.5·4.6 결과로 갱신 | [확인] |
| 네이티브 저장 경로 | 앱 셸 → CORE `NoteStoreConfig.nativeDatabasePath` | 넘기지 않음 → 네이티브에서 `storageUnavailable` | 네이티브 시험의 선행 조건 | [확인 — 01-hooks 요약 13] |

---

## 3. 안드로이드

### 3.1 빌드 도구 요구 (Flutter 3.47.9 Gradle 플러그인) [확인]

`/opt/flutter/packages/flutter_tools/gradle/src/main/kotlin/DependencyVersionChecker.kt` 94–117:

| 항목 | 오류(빌드 중단) 기준 | 경고 기준 | 우리 앱 |
|---|---|---|---|
| Gradle | < 8.14.0 | < 9.1.0 | 9.3.1 ✔ |
| Java(Gradle 실행 JDK) | < 17 | < 17 | 러너 17(setup-java), 컨테이너 21 ✔ |
| AGP | < 8.11.1 | < 9.0.1 | 9.1.0 ✔ |
| Kotlin(KGP) | < 2.2.20 | < 2.3.20 | 2.4.0 ✔ |
| minSdk | < 23 | < 24 | 24 ✔ |

- AGP 9의 내장 Kotlin: 템플릿이 `android.builtInKotlin=false`를 두므로 Flutter가 `kotlin-android`를 적용하지 않은 플러그인 하위 프로젝트에 직접 적용한다(`FlutterPluginUtils.kt` 565–590). ML Kit 플러그인 0.16.0은 "AGP built-in Kotlin support(`compilerOptions`)"로 옮겼고 `kotlin {}` 블록만 쓰는데, 이 적용 덕분에 동작할 것이다 [확인(소스) / 실제 빌드는 추측]. FlutterFire 플러그인은 스스로 `android.builtInKotlin` 값을 보고 `kotlin-android`를 적용한다(`cloud_functions-7.0.1/android/build.gradle` 7–14) [확인].
- 플러그인 compileSdk가 앱보다 높으면 `validateCompileSdkVersion` 작업이 `logger.error`로 "Your project is configured to compile against Android SDK 36, but the following plugin(s) require …"를 출력하지만 예외는 던지지 않는다(`tasks/ValidateCompileSdkVersionTask.kt` 101–119) [확인].

### 3.2 플러그인 요구 표 [확인]

`.dart_tool/package_config.json`에서 플러그인 위치를 찾아 podspec·`Package.swift`·`android/build.gradle*`을 정규식으로 읽는 스캐너(`scripts/plugin_reqs.py`, 3.7)를 1차 워크스페이스 + M5~M7 후보(`native_probe`)에 돌린 결과다. 웹 전용 패키지가 잘못 잡힌 줄(`*_web`)은 뺐다.

| 플러그인(버전) | iOS(pod) | SwiftPM | 안드로이드 minSdk | compileSdk | 비고 |
|---|---|---|---|---|---|
| `google_mlkit_digital_ink_recognition` 0.16.1 | **15.5** | **없음** | 21 | 36 | 네이티브 `com.google.mlkit:digital-ink-recognition:19.0.0`, `GoogleMLKit/DigitalInkRecognition ~> 9.0.0` |
| `google_mlkit_commons` 0.13.0 | **15.5** | **없음** | 21 | 36 | `MLKitVision ~> 10.0.0`, lib에서 `dart:io` import |
| `record_android` 2.2.0 / `record_ios` 2.1.1 | 12.0 | 12.0 | 24 | 36 | 매니페스트에 `RECORD_AUDIO` 병합 |
| `just_audio` 0.10.6 / `audio_session` 0.2.4 | 12.0 | 12.0 | 16 / 24 | 35 | |
| `flutter_foreground_task` 11.0.3 | 12.0 | 13.0 | 21 | 35 | 안드로이드 백그라운드 녹음용(02-audio 4.2) |
| `image_picker_android` 0.8.13+25 / `image_picker_ios` 0.8.13+14 | 15.0 | 15.0 | 24 | Flutter 값 | `image_picker_ios`는 `flutter >=3.47.0`·`sdk ^3.13.0`, 2026-10-29 게시 |
| `permission_handler_android` 14.1.1 / `_apple` 9.6.5 | 12.0 | 12.0 | 24 | **37** | 5절 |
| `firebase_core` 5.1.0 · `cloud_functions` 7.0.1 · `firebase_auth` 7.0.1 · `cloud_firestore` 7.1.0 · `firebase_storage` 14.0.1 | 15.0 | 15.0 | `project.ext` = 24 | `project.ext` = 34 | FlutterFire 기본값 `firebase_core/android/local-config.gradle`, Android BoM 35.1.0 |
| `connectivity_plus` 7.3.2 | 12.0 | 13.0 | 21 | Flutter 값 | SYNC |
| `pdfium_flutter` 0.4.1 | 15.0 | 있음 | — | — | PDF |
| `url_launcher_*`, `shared_preferences_*`, `jni*` | ≤ 13.0 | 있음 | ≤ 24 | ≤ 35 | 간접 |

결론: **안드로이드 minSdk는 24 그대로, compileSdk는 36이면 되고 `permission_handler`를 넣을 때만 37 경고가 난다. iOS는 ML Kit 하나 때문에 15.5와 CocoaPods가 필요하다.**

### 3.3 매니페스트·권한 [확인 + 문서]

| 권한·선언 | 필요 이유 | 넣는 곳 | 근거 |
|---|---|---|---|
| `android.permission.INTERNET` | ML Kit 언어 모델 내려받기, Firebase, 서버 함수, 웹 자산 | **앱 `main` 매니페스트**(지금 없음) | [확인 — main에 없음] |
| `RECORD_AUDIO` | 녹음 | `record_android`가 병합 | [확인 — `record_android-2.2.0/android/src/main/AndroidManifest.xml`] |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MICROPHONE`, `POST_NOTIFICATIONS`, `<service … foregroundServiceType="microphone">` | 백그라운드 녹음(안드로이드 14+) | 앱 매니페스트 + `flutter_foreground_task` 병합 | 02-audio 4.2 [문서·확인] |
| (없음) 사진 읽기 권한 | 이미지 삽입 | `image_picker_android`는 안드로이드 16+에서 항상 사진 선택기(권한 불필요), 15 이하는 `useAndroidPhotoPicker` 설정으로 사용 | [문서 — `image_picker_android` README 'Photo Picker'] |
| S펜 버튼 | 매니페스트 불필요(엔진이 `buttons` 비트로 줌) | — | 02-audio 8.2 [확인] |

targetSdk 36(안드로이드 16)의 큰 화면(최소 폭 600dp 이상) 규칙: 방향·크기 조절 제한 선언을 무시하고 앱을 늘린다. Flutter 앱은 원래 크기 변화를 처리하므로 문제는 작지만, 태블릿 가로·세로·분할 화면을 실기기 점검표에 넣는다. [추측 — Android 16 동작 변경 내용 기억, 원문 미확인]

### 3.4 GitHub Actions APK 워크플로

러너 사실 [확인 — `https://raw.githubusercontent.com/actions/runner-images/main/images/ubuntu/Ubuntu2404-Readme.md`, 이미지 20261026.354.1]:

| 항목 | 값 |
|---|---|
| 라벨 | `ubuntu-latest` = Ubuntu 24.04(Ubuntu 26.04는 `ubuntu-26.04`로 따로 있음) |
| Java | 17.0.21(기본, `JAVA_HOME_17_X64`) — `setup-java`의 17과 같은 줄기 |
| Android | Command Line Tools 12.0, Platform-Tools 37.0.1, Build-tools 37.0.0·36.0.0·36.1.0·35.x·34.0.0, 플랫폼 android-37.x·36·36.1·35·34 |
| NDK | 27.3.13750724(기본)·29.0.14206865·30.0.16248370 — **Flutter 기본 28.2.13676358은 없음** |
| Node | 22.23.4(서버 함수 시험에 그대로 씀, 6.6) |
| Chrome | 156.0.8078.47 |

빌드 흐름에서 확인할 것:

1. **NDK 내려받기**: 앱 `ndkVersion`이 28.2이므로 AGP가 빌드 중 설치한다. 첫 실행에 몇 분이 더 들 수 있다. 첫 CI 실행 시간을 재고, 크면 `~/.android`·`/usr/local/lib/android/sdk/ndk/28.2.13676358`을 캐시하거나 `ndkVersion`을 러너 기본(27.3)으로 맞추는 안을 검토한다. [추측 — AGP 자동 설치 동작은 기억, 시간은 미측정]
2. **네이티브 에셋 훅**: `pdfium_dart` 훅이 `CBuilder.library(pdfrx_pdfium_gate)`로 C 파일을 컴파일하고(안드로이드는 NDK clang — `flutter_tools/lib/src/isolated/native_assets/android/native_assets.dart` 96–109가 가장 새 NDK를 찾음), `github.com/bblanchon/pdfium-binaries` 릴리스(`chromium/8125`)에서 ABI별 `libpdfium.so`를 내려받는다. INFRA의 빌드 훅 캐시(`.dart_tool/hooks_runner`)가 이것을 줄인다. [확인 — 훅 소스]
3. **release vs debug**: debug APK는 JIT라 필기 지연 판정에 쓸 수 없다. 지금처럼 `--release`(AOT)로 빌드하고 서명만 고정한다. [추측 — 일반 Flutter 성능 특성]
4. **트리거**: `main` 푸시 + 수동. `workflow_dispatch`는 워크플로 파일이 있는 브랜치면 영역 브랜치에서도 수동 실행이 된다. 동시 개발 중 실기기 시험이 필요하면 영역 브랜치에서 수동 실행한다(계약 7.4.12의 '체크포인트 때만 푸시'와 맞음). [추측 — GitHub 동작 기억]
5. **설치**: Actions 실행 → Artifacts → zip 내려받기 → 압축 풀기 → '출처를 알 수 없는 앱 설치' 허용 → 설치(INFRA 안내서 05). 아티팩트는 비공개 저장소라 태블릿 브라우저에서 GitHub 로그인이 필요하다. [문서]

선택 — **안드로이드 에뮬레이터 통합 시험 잡**: 리눅스 러너는 KVM 가속 에뮬레이터를 돌릴 수 있고, `reactivecircus/android-emulator-runner@v2` README가 `ubuntu-latest` + KVM 권한 설정 단계를 권한다. 기기가 없어도 ML Kit 인식(모델 내려받기 포함)·녹음 상태 전이·권한 흐름을 `integration_test`로 자동 확인할 수 있고 macOS의 1/10 비용이다. 에뮬레이터 마이크는 실제 소리가 없다. ML Kit이 Google Play 서비스를 요구하는지 확실하지 않으므로 `target: google_apis` 이미지로 시작한다. [문서(README) / 추측(ML Kit·마이크 동작)]

### 3.5 서명 — 고정 키 [확인(현재 상태) / 추측(방식)]

| 방식 | 내용 | 장점 | 단점 |
|---|---|---|---|
| A. 시크릿 (INFRA 6.14 선택안) | 컨테이너 `keytool`(OpenJDK 21)로 PKCS12 키 생성 → base64 → 시크릿 `ANDROID_KEYSTORE_BASE64`·`ANDROID_KEYSTORE_PASSWORD`·`ANDROID_KEY_ALIAS`·`ANDROID_KEY_PASSWORD` → CI가 `key.properties`·키 파일을 만들고 `build.gradle.kts`가 있을 때만 사용 | 키가 저장소에 없음, 이미 계획됨 | 사용자가 시크릿 4개 등록, 키 파일을 따로 보관해야 함(잃으면 다시 '지우고 설치') |
| B. 개발용 키 커밋 | 비밀번호가 알려진 개발 전용 키를 비공개 저장소에 커밋 | 사용자 작업 없음 | 저장소를 보는 누구나 같은 서명의 APK를 만들 수 있음. 스토어 배포 키로는 쓰지 않음 |

어느 쪽이든 이 키는 **사이드로드 시험용**이다. 나중에 Play에 올리면 Play 앱 서명 + 별도 업로드 키를 쓰게 되고, 서명이 달라 시험용 설치본은 그때 한 번 지우고 다시 설치해야 한다. 앱 ID(INFRA Q12)도 이 전에 확정해야 한다. [추측]

### 3.6 사이드로드 정책 변화 [2차]

Google의 '안드로이드 개발자 인증'이 2026-09-30부터 브라질·인도네시아·싱가포르·태국의 인증 기기에서 시행 중이고, 2027년에 전 세계로 넓힌다고 한다. 인증되지 않은 앱도 ADB 설치와 새 '고급 설치 흐름'으로는 설치할 수 있고, 학생·취미 개발자용 가벼운 계정 경로가 있다고 한다. 한국은 아직 대상이 아니다. 2027년 전에 시험 APK 설치 방법(취미 개발자 등록 또는 ADB)을 다시 확인해야 한다. 출처: Android Authority(13절).

### 3.7 이 컨테이너에서 검증할 수 있는 범위 [확인]

| 할 수 있음 | 방법 |
|---|---|
| 워크플로 YAML 구조·명령 | INFRA `tool/test/workflows_test.dart` 방식(파싱, `bash -n`, `ws` 인자 해석) |
| 매니페스트·Info.plist·pbxproj·gradle·Podfile 값 | XML/plist 파싱(`package:xml`은 이미 간접 의존)·정규식 시험 — 예: `INTERNET`·FGS 선언 존재, `UIBackgroundModes`에 `audio`, `IPHONEOS_DEPLOYMENT_TARGET` 3곳 모두 ≥ 15.5, `ITSAppUsesNonExemptEncryption = false`, Podfile `platform :ios, '15.5'` |
| 플러그인 요구 사항 | `package_config.json` → 각 플러그인의 podspec(`s.platform`·`ios.deployment_target`)·`Package.swift`(`.iOS("x")`)·`android/build.gradle*`(`minSdk`·`compileSdk`) 읽기 → 앱 값과 비교, **CocoaPods 전용 플러그인 목록** 출력. 파이썬 시제품 23행으로 3.2 표를 만들었다(최종은 `tool/` 아래 Dart로) |
| Dart 분석·웹 빌드·Chrome 실행 | 기존 `ws analyze`·`flutter build web`·`--platform chrome` |
| 서버 함수 | 6절 — 단위 시험·에뮬레이터 시험 모두 가능 |

| 할 수 없음 | 이유 |
|---|---|
| `flutter build apk`·`appbundle`·`--config-only`, Gradle 동기화 | Android SDK 없음, `dl.google.com` 차단(maven.google.com 산출물도 그리로 301) |
| `flutter build ios`·`ipa`, `pod install` | 리눅스 Flutter에 하위 명령 없음(`Could not find a subcommand named "ios"`), Xcode 없음 |
| 안드로이드 에뮬레이터 | `/dev/kvm` 없음, 시스템 이미지는 `dl.google.com` |

---

## 4. iOS

### 4.1 macOS 러너와 Apple 요구 사항

| 항목 | 값 | 근거 |
|---|---|---|
| `macos-latest` | **macOS 26 arm64**(`macos-26`과 같음). Intel은 `macos-26-intel`/`-large`. macOS 14 이미지는 2026-11-02 은퇴 | [확인 — runner-images README 31–41행] |
| Xcode | 26.6(기본, 17F113), 26.5, 26.4.1, 26.3, 26.2, 26.1.1, 26.0.1 | [확인 — `macos-26-arm64-Readme.md`, 이미지 20261026.0455.2] |
| 도구 | CocoaPods 1.17.0, fastlane 2.241.2, Ruby 3.4.12, Node 24.22.1 | [확인 — 같은 문서] |
| Flutter 요구 | Xcode ≥ 15(권장 16), CocoaPods ≥ 1.10.0(권장 1.16.2) | [확인 — `xcode.dart` 24·28, `cocoapods.dart` 86–87] |
| Apple 업로드 요구 | 2026-04-28부터 "Xcode 26 or later using an SDK for iOS 26, iPadOS 26 …", 2026-09-09부터 "must target iOS 13 or later" | [문서 — https://developer.apple.com/news/upcoming-requirements/ (WebFetch로 원문 확인)] |

### 4.2 계정 없이 할 수 있는 것 — `flutter build ios --no-codesign`

- 하는 일: Dart AOT(arm64), SwiftPM 해석·CocoaPods `pod install`, 모든 플러그인 Swift/ObjC 컴파일, 링크까지 한다. 서명·프로비저닝·엔타이틀먼트·실행 시 권한은 확인하지 않는다. [문서 — Flutter 명령 설명 / 추측 — 단계 구성]
- 잡아낼 수 있는 문제: ML Kit pod와 앱 배포 대상 불일치, SwiftPM·CocoaPods 혼합의 중복 심볼(4.4), 직접 만들 Pencil 플러그인(02-audio 9.3)의 Swift 컴파일 오류, `UIScene` 수명주기와 플러그인 충돌로 생기는 컴파일 경고.
- 시뮬레이터 빌드는 쓰지 않는다: ML Kit pod가 `EXCLUDED_ARCHS[sdk=iphonesimulator*] = arm64`라 arm64 러너의 시뮬레이터 빌드가 막힌다(플러그인 0.15.0이 iOS 26+ Apple Silicon 시뮬레이터를 켰다고 하나 pod 설정은 그대로다). [확인(podspec) / 추측(실제 결과)]
- `flutter build ipa --no-codesign`은 서명 안 된 `.xcarchive`를 만든다. 이것으로 `Payload/Runner.app`을 zip해 `.ipa`를 만들면 4.7의 무료 Apple ID 사이드로드에 쓸 수 있다. [추측]
- 시간·비용: 캐시 없는 첫 실행은 Flutter 설치 + `pod install`(ML Kit 프레임워크 내려받기) + (M4 뒤) firebase-ios-sdk SwiftPM 해석까지 15~25분, 캐시(`~/Library/Caches/CocoaPods`, `app/ios/Pods`, SwiftPM 캐시) 뒤 8~12분으로 추정한다. 10배 계산이면 1회 80~250분이다. [추측 — 측정 전]

### 4.3 최소 iOS 버전 [확인]

| 요구 주체 | 최소 | 근거 |
|---|---|---|
| ML Kit(플러그인 podspec, `GoogleMLKit 9.0.0`·`MLKitCommon 14.0.0`·`MLKitVision 10.0.0`·`MLKitDigitalInkRecognition 8.0.0` 사양) | **15.5** | podspec `s.platform`, CocoaPods 사양 JSON `platforms.ios`(raw.githubusercontent.com/CocoaPods/Specs) |
| FlutterFire(`firebase_core` 5.1.0 등) | 15.0 | podspec·`Package.swift` |
| `image_picker_ios`, `pdfium_flutter` | 15.0 | 같음 |
| Flutter 템플릿 기본 | 15.0 | `templates/app/ios.tmpl/Runner.xcodeproj/project.pbxproj.tmpl` 383·513·565 |
| Apple Pencil 스퀴즈(Pencil Pro) | 17.5(API 가용성 검사로 처리) | 02-audio 9.1 [문서] |

ML Kit README는 Podfile에 `platform :ios, '15.5'`와 `post_install`에서 Pods 프로젝트의 `IPHONEOS_DEPLOYMENT_TARGET`을 15.5 이상으로 올리는 줄, armv7 제외를 넣으라고 한다. 앱 pbxproj의 3개 구성도 15.5로 올려야 한다. 사용자의 iPad Pro 13"(M4 이상)은 iPadOS 26을 돌리므로 기기 쪽 제약은 없다. [확인(README) / 추측(기기 OS)]

### 4.4 SwiftPM·CocoaPods 혼합 모드

Flutter 3.47.9의 동작 [확인 — 소스]:

- `darwin_dependency_management.dart` 87–100: SwiftPM이 켜진 프로젝트에서 `useCocoapods = swiftPackageCount < totalCount`. 즉 **SwiftPM을 지원하지 않는 플러그인이 하나라도 있으면 Podfile을 만들고 CocoaPods를 함께 쓴다.**
- `podhelper.rb` 327–334: SwiftPM이 켜져 있고 `Package.swift`가 있는 플러그인은 pod 설치에서 **건너뛴다.** 따라서 혼합 모드에서는 ML Kit 두 플러그인만 pod, 나머지(FlutterFire 포함)는 SwiftPM이다.
- 같은 파일 286–295: CocoaPods 전용 플러그인마다 "This will become an error in a future version of Flutter" 경고.
- 앱 단위로 SwiftPM을 끄는 설정: `app/pubspec.yaml`의 `flutter: config: enable-swift-package-manager: false`(`flutter_manifest.dart` 603–613, `features.dart` 233–240).
- 리눅스에서 `pub get`은 `ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift`를 의존 없이(`platforms: .iOS("15.0")`만) 만들고 Podfile은 만들지 않는다. Podfile은 macOS 빌드 때 생기거나 손으로 만들어 커밋해야 한다(템플릿 `templates/cocoapods/Podfile-ios`).

의존성 겹침 [확인 — CocoaPods 사양 JSON]:

| 하위 라이브러리 | ML Kit(`MLKitCommon 14.0.0`, pod) | Firebase 12.19.x(pod, 마지막 CocoaPods 판) | Firebase 13.1.1(SwiftPM) |
|---|---|---|---|
| `GTMSessionFetcher/Core` | `>= 3.3.2, < 4.0` | `>= 3.4, < 6.0` | SwiftPM 패키지 |
| `GoogleUtilities` | `~> 8.0`(Logger·UserDefaults) | `~> 8.1` | SwiftPM 패키지 |
| `GoogleDataTransport` | `~> 10.0` | (Firebase 일부가 사용) | SwiftPM 패키지 |

- **전부 CocoaPods**(SwiftPM 끔): 위 범위의 교집합(`GTMSessionFetcher 3.4~3.x`, `GoogleUtilities 8.1.x`)이 있어 해석될 것이다. 대신 Firebase iOS가 CocoaPods 마지막 판(12.19.3)에 고정된다. [확인(범위) / 추측(해석 결과)]
- **혼합**(지금 기본): Firebase가 SwiftPM으로 같은 이름 라이브러리를 또 넣는다. Stack Overflow에 "Firebase는 SPM, ML Kit는 CocoaPods로 넣었더니 GoogleUtilities·FBLPromises가 두 벌이 되어 어느 쪽이 쓰일지 모른다"는 보고가 있다. [2차 / 추측(우리 빌드)]
- **이번 라운드 영향**: 앱이 `sync_engine`에 의존하지 않으므로(계약 7.1) 앱 iOS 빌드에 Firebase가 없다. 서버 함수 호출을 `cloud_functions`로 하거나 M4 로그인을 넣으면 그때부터 문제다.
- **시간 축**: CocoaPods trunk는 2026-12-02 읽기 전용이 된다(11-01~07 시험 운영)[2차]. `firebase_core 5.1.0`의 `ios/firebase_sdk_version.rb`는 "New releases stop publishing in October 2026"이라 적고 12.19.3에 고정한다[확인]. CocoaPods CDN의 `FirebaseCore` 마지막 판도 12.19.3이다[확인]. ML Kit iOS의 공식 SwiftPM 배포는 찾지 못했다(실험적 제3자 래퍼 `d-date/google-mlkit-swiftpm`만 있음)[2차].

### 4.5 Info.plist 키 (이번 범위 기능 기준)

| 키 | 값(예) | 필요한 기능 | 근거 |
|---|---|---|---|
| `NSMicrophoneUsageDescription` | "노트에 녹음을 붙이려면 마이크가 필요합니다." | M6 녹음 | `record` README [문서], 02-audio 4.1 |
| `UIBackgroundModes` | `[audio]` | 백그라운드 녹음 | `record` 백그라운드 문서 [문서] |
| `NSPhotoLibraryUsageDescription` | "사진을 노트에 넣습니다." | M5 이미지 삽입 | `image_picker` README: `requestFullMetadata: false`면 묻지 않지만 "App Store policy requires including the plist entry" [확인(README)] |
| `NSCameraUsageDescription` | "사진을 찍어 노트에 넣습니다." | 카메라로 바로 넣기를 할 때만 | 같은 README |
| `ITSAppUsesNonExemptEncryption` | `false` | TestFlight 업로드마다 수출 규정 질문을 건너뜀(HTTPS만 씀) | [추측 — Apple 규정 기억, 원문 미확인] |
| `LSSupportsOpeningDocumentsInPlace`·문서 유형 | — | M3 '다른 앱에서 PDF 열기'(이번 범위 밖) | — |

`permission_handler_apple`를 넣으면 SwiftPM 매니페스트가 위 `NS*UsageDescription` 키를 보고 권한 코드만 컴파일한다(5절). 넣지 않으면 신경 쓸 것이 없다. Apple Pencil 더블탭·스퀴즈(`UIPencilInteraction`)는 키가 필요 없다. 앱 개인정보 매니페스트(`PrivacyInfo.xcprivacy`)는 플러그인이 각자 갖고 있고, 업로드 뒤 ITMS-91053 같은 경고 메일이 오면 앱 수준 파일을 더한다. [추측]

### 4.6 TestFlight (계정 가입 뒤)

사용자가 할 일(웹에서, Mac 불필요) [문서 — PLAN 10장, INFRA 안내서 06 / 일부 추측]:

1. Apple Developer Program 가입(연 99달러, 개인).
2. Certificates, Identifiers & Profiles → Identifiers → 명시적 App ID 등록(번들 ID = 확정한 앱 ID). 백그라운드 오디오는 App ID 기능 등록이 필요 없다(엔타이틀먼트가 아니라 Info.plist 키). [추측]
3. App Store Connect → 앱 → 새 앱(이름은 스토어 전체에서 유일해야 함, 번들 ID 선택, SKU).
4. 사용자 및 액세스 → 통합 → App Store Connect API → 팀 키 생성 → `.p8`(한 번만 내려받음)·Key ID·Issuer ID.
5. TestFlight → 내부 테스트 그룹에 본인 추가 → iPad에 TestFlight 앱 설치. 내부 테스트는 베타 심사가 없고 빌드는 90일 유효하다. [추측 — 기억]

서명 방식 비교:

| 방식 | CI가 하는 일 | 시크릿 | 위험·주의 |
|---|---|---|---|
| A. 클라우드 자동 서명(현재 초안) | `xcodebuild archive/-exportArchive -allowProvisioningUpdates -authenticationKey*` → Xcode가 배포 인증서·프로파일을 Apple 클라우드에서 만들고 씀 | `ASC_KEY_ID`·`ASC_ISSUER_ID`·`ASC_PRIVATE_KEY`·`APPLE_TEAM_ID` | **App Manager 키로는 'Cloud signing permission error'가 나고 Admin 키여야 됐다는 보고**가 여럿 있다(키 역할은 만든 뒤 못 바꿈) [2차]. Admin 키는 팀 전체 권한이라 유출 위험이 크다 |
| B. 수동 인증서 + 프로파일 | CSR을 **컨테이너의 openssl로 만들어** 개발자 사이트에서 Apple Distribution 인증서 발급 → `.cer`+개인키를 `.p12`로 묶음 → App Store 프로비저닝 프로파일 발급 → CI가 임시 키체인에 넣고 수동 서명으로 export → API 키(App Manager)로 업로드 | 위 4개 + `IOS_DIST_P12_BASE64`·`IOS_DIST_P12_PASSWORD`·`IOS_PROFILE_BASE64` | 사용자 웹 작업이 늘고 인증서(1년)·프로파일 만료 관리 필요. 키 권한은 좁다 [추측] |
| C. fastlane `match`/`pilot` | 인증서 저장소(비공개 git) + `upload_to_testflight` | match 저장소 접근 키 등 | 1인 개발에는 과함. 러너에 fastlane 2.241.2가 있어 업로드만 `pilot`으로 쓰는 것은 가능 [확인(설치) / 추측(적합성)] |

빌드 번호는 `--build-number=$GITHUB_RUN_NUMBER`로 계속 커진다(초안 그대로). 1024px 앱 아이콘에 알파 채널이 있으면 업로드가 거절되므로 INFRA 아이콘 생성기가 iOS 아이콘도 만든다면 알파를 빼야 한다. [추측 — 기억]

### 4.7 계정 전 대안 — 무료 Apple ID 사이드로드 [2차 · 선택]

Sideloadly(Windows·macOS)는 서명 안 된 `.ipa`를 사용자의 **무료 Apple ID**로 서명해 USB(또는 Wi-Fi)로 설치한다. 무료 계정은 **7일마다 다시 서명**해야 하고 기기당 3개 앱 제한이 있다(공식 FAQ). 우리 경로로는: macOS 러너가 `flutter build ipa --no-codesign` → `.ipa` 아티팩트 → 사용자 PC의 Sideloadly → iPad. 네이티브 필기감·Pencil 더블탭·백그라운드 녹음·ML Kit을 유료 계정 전에 볼 수 있다. 대신 ① Windows/Mac PC와 케이블이 필요하고(PLAN 11장 '사용자 PC 개발 환경 없음'과 충돌할 수 있음) ② Apple ID 비밀번호를 제3자 도구에 넣어야 하며 ③ 무료 프로비저닝에서 막히는 기능이 있을 수 있다(이번 범위 기능은 엔타이틀먼트가 필요 없어 될 것으로 본다 [추측]). 사용자 판단 사항이다(10절 Q4).

### 4.8 Actions 사용 시간 [2차 / 추측]

| 항목 | 값 |
|---|---|
| 비공개 저장소 무료 시간(개인 Free) | 월 2,000분, 리눅스 1배·macOS 10배(2026-01 단가 인하 뒤에도 배수 동일하다는 보고) [2차] |
| 공개 저장소 | 표준 러너 무료·무제한 [2차] |
| INFRA 기존 예산(6.13) | ci 960 + android 160 + web-experiment 24 + iOS 450 = 1,594분 [문서] |
| 이번 라운드 추가 후보 | iOS 컴파일 확인 1회 80~250분(4.2), 안드로이드 에뮬레이터 시험 1회 10~20분, 서버 함수 시험 1~2분 [추측] |

---

## 5. 권한 처리 패키지

| 패키지 | 버전(게시일) | 상태 | 근거 |
|---|---|---|---|
| `permission_handler` | 13.0.2 (2026-09-04) | 웹 구현(`permission_handler_html 0.1.4+1`) 있음 — 헤드리스 Chrome에서 `Permission.microphone.status` = `denied` | [확인 — 7.1 실행] |
| `permission_handler_android` | 14.1.1 (2026-10-28) | **compileSdk 37**, minSdk 24, AGP 9.0.1 buildscript | [확인 — `build.gradle.kts` 12·31·48] |
| `permission_handler_apple` | 9.6.5 (2026-11-02) | SwiftPM 지원. SwiftPM에서는 Info.plist의 `NS*UsageDescription` 키로 `PERMISSION_*` 매크로를 자동 결정(CocoaPods에서는 Podfile `GCC_PREPROCESSOR_DEFINITIONS`). 키를 바꾸면 DerivedData를 지워야 반영 | [확인 — README 13–60] |

이번 범위에서 필요한 권한과 처리 수단:

| 권한 | 처리 수단 | `permission_handler` 필요? |
|---|---|---|
| 마이크 | `AudioRecorder.hasPermission(request: true)`(record) | 아니오 |
| 알림(안드로이드 13+, 포그라운드 서비스) | `FlutterForegroundTask.requestNotificationPermission()` | 아니오 |
| 사진 | iOS PHPicker·안드로이드 사진 선택기(권한 대화상자 없음) | 아니오 |
| 영구 거부 뒤 '설정 열기' | `permission_handler.openAppSettings()` 또는 안내 문구 | 이것만 해당 |

결론: **이번 라운드에는 넣지 않는다**(02-audio 12.1과 같음). compileSdk 37 경고·3일 된 iOS 구현 판·권한 매크로 설정 부담을 피한다. 나중에 넣는다면 그때 게시 2주 이상 된 판으로 고정하고 앱 compileSdk를 37로 올리는 것을 함께 검토한다. [추측]

---

## 6. 서버 함수 (Firebase Functions)

### 6.1 필요 여부는 수식 엔진 선택에 달렸다

| 엔진(03-recognition 6절) | 키 보호 방법 | Functions 필요 | Blaze 필요 |
|---|---|---|---|
| Mathpix | 서버가 대리 호출하거나 단기 `app_token` 발급 | 예 | 예 |
| 멀티모달 AI — Claude | 서버 대리 호출(Secret Manager) | 예 | 예 |
| 멀티모달 AI — Gemini(Firebase AI Logic) | Firebase가 대리(앱에 키 없음, App Check 권장) | **아니오** | **아니오**(`gemini-developer-api`) [확인 — firebase-tools `gcp/ailogic.js` 316–335] |
| MyScript iink(기기 안) | 앱 안 인증서 | 아니오(Cloud REST면 예) | 아니오 |
| ML Kit 손글씨(텍스트) | 키 없음 | 아니오 | 아니오 |

### 6.2 요금제 [확인 + 2차 + 추측]

- 배포: firebase-tools 15.34.2 `lib/deploy/functions/ensure.js` 39행 — Cloud Build API를 켤 때 결제 오류면 "Cloud Functions deployment requires the pay-as-you-go (Blaze) billing plan." [확인]
- 비용 성격: 호출·컴퓨팅·전송 무료 사용량이 있고 배포 컨테이너 이미지 저장(Artifact Registry)에 소액이 든다는 것이 Firebase 할당량 문서의 설명이다. firebase-tools에는 이미지 정리기(`containerCleaner.js`)가 있다. [2차 / 확인(정리기 존재)]
- Secret Manager: 무료 활성 버전 수·접근 횟수 한도가 있다는 2차 자료만 봤다. 비밀값 1~2개면 무시할 수준으로 본다. [2차·추측]
- 예산 알림: INFRA 안내서 03이 'Blaze로 바꿀 때 즉시' 설정으로 이미 준비돼 있다. 알림은 과금을 멈추지 않는다. [문서]

### 6.3 지역

- `asia-northeast3`(서울)은 `firebase-functions 7.4.0`의 2세대 `SupportedRegion`과 1세대 `SUPPORTED_REGIONS`에 모두 있다. [확인 — `lib/v2/options.d.ts` 8, `lib/v1/function-configuration.d.ts` 8]
- Firestore 위치 권장도 `asia-northeast3`(INFRA 안내서 01)이라 함수가 Firestore를 쓸 때 같은 지역이 맞다.
- 지역별 가격 등급과 무료 사용량 적용 범위는 원문(docs.cloud.google.com)을 열지 못해 확인하지 못했다. 개인 사용량(하루 수십 건)이면 어느 쪽이든 비용 차이는 작다. [추측]

### 6.4 골격 — 실제로 만들어 에뮬레이터에서 돌린 것 [확인]

배치(제안): 저장소 루트 `functions/`(app·packages와 나란히, Dart 워크스페이스 멤버 아님), `app/firebase.json`이 `"functions": [{"source": "../functions", ...}]`로 참조. 이 상대 경로가 에뮬레이터에서 동작함을 확인했다(INFRA 6.12가 rules 파일에 대해 미확인으로 남긴 '`../` 경로를 읽는지' 질문의 Functions 쪽 답).

```text
functions/
  package.json        # engines.node "22"; firebase-admin 14.5.0, firebase-functions 7.4.0;
                      # dev: typescript 6.0.3, @types/node 22.20.5 (모두 정확히 고정)
  tsconfig.json       # firebase init 템플릿 기준(NodeNext, strict, outDir lib, rootDir src) + target es2022
  .env.local          # MATH_ENGINE=fake          (에뮬레이터 전용, 커밋 안 함)
  .secret.local       # MATH_API_KEY=emulator-dummy (에뮬레이터 전용, 커밋 안 함)
  src/index.ts        # onCall 함수
  src/recognizer.ts   # 엔진 포트 + 가짜 엔진 + 입력 검사(순수 함수)
  src/test/recognizer.test.ts  # node:test
```

```ts
// src/index.ts (요지)
setGlobalOptions({region: "asia-northeast3", maxInstances: 2});
const mathApiKey = defineSecret("MATH_API_KEY");
const mathEngine = defineString("MATH_ENGINE", {default: "fake"});
export const recognizeMath = onCall(
  {secrets: [mathApiKey], timeoutSeconds: 30, memory: "256MiB", enforceAppCheck: false},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "sign-in required");
    const parsed = validateRequest(request.data);           // pngBase64 필수·base64·≤2MB
    if (typeof parsed === "string") throw new HttpsError("invalid-argument", parsed);
    return recognizerFor(mathEngine.value(), mathApiKey.value()).recognize(parsed.pngBase64);
  });
```

결과:

| 시험 | 명령 | 결과 |
|---|---|---|
| 설치 | `npm install` | 246개, 8초, `node_modules` 114 MB |
| 단위 시험 | `npm test`(= `tsc && node --test lib/test/*.test.js`) | 2/2 통과(입력 검사 5경우, 가짜 엔진) |
| 에뮬레이터 | `firebase emulators:exec --only functions,auth --project demo-noteapp scripts/call_fn.sh` | 시작 약 3초, "Using node@22 from host", `.env.local` 읽음, `asia-northeast3-recognizeMath` 초기화 |
| 로그인 없이 호출 | `POST http://127.0.0.1:5001/demo-noteapp/asia-northeast3/recognizeMath` `{"data":{...}}` | `{"error":{"message":"sign-in required","status":"UNAUTHENTICATED"}}` |
| Auth 에뮬레이터 익명 가입 → ID 토큰(431자) → 잘못된 입력 | 같은 주소 + `Authorization: Bearer` | `INVALID_ARGUMENT` "pngBase64 is not base64", 검증 로그 `auth: VALID, app: MISSING` |
| 정상 호출 | 같음 | `{"result":{"latex":"\\frac{8}{2}","confidence":1,"engine":"fake"}}`, 로그 `keyPresent: true`(`.secret.local` 반영) |
| Dart에서 호출(VM) | `dart run dartclient/bin/call.dart`(에뮬레이터 안에서) — `package:http` 1.6.0으로 callable 규약(`{"data":…}` + Bearer) 구현 | `anon: {error: {… UNAUTHENTICATED}}`, `auth: {result: {latex: \frac{4}{2}, …}}` |

경고(무해): `::1` 포트 확인 실패(IPv6 없음), MOTD·메타데이터 조회 403. 에뮬레이터에 쓸 호스트를 `127.0.0.1`로 명시하면 된다. [확인]

### 6.5 Firebase 프로젝트가 없을 때 개발·시험하는 방법 [확인]

- **`demo-` 접두어 프로젝트 ID**를 쓰면 에뮬레이터가 "emulated services will use a demo configuration and attempts to access non-emulated services for this project will fail"로 동작한다. 로그인·실제 프로젝트·결제가 필요 없다.
- Functions·Auth 에뮬레이터는 Node만으로 돈다(Java 불필요). **Firestore 에뮬레이터**는 Java가 필요하고 첫 실행에 `cloud-firestore-emulator-v1.22.0.jar`를 storage.googleapis.com에서 내려받는다 — 이 컨테이너에서 내려받기·시작·REST 문서 쓰기까지 됐다. SYNC 규칙 시험(07-sync 55행 '선택 작업')을 에뮬레이터로 할 수 있다는 뜻이다.
- 앱 쪽: 웹 `firebase_core_web`은 Firebase JS SDK를 `https://www.gstatic.com/firebasejs/<버전>/…`에서 받는다(`firebase_core_web.dart` 236–242). 이 컨테이너에서는 gstatic이 막혀 **`cloud_functions`·`firebase_auth`의 웹 경로는 컨테이너 Chrome에서 시험할 수 없다.** 사용자 기기·CI에서는 된다. 그래서 컨테이너 시험은 ① 서버 함수 단위 시험 ② 에뮬레이터 + Dart HTTP 클라이언트(VM) ③ 앱은 엔진 포트의 가짜 구현으로 한다.
- 실제 프로젝트 연결 뒤: `firebase deploy --only functions`는 CI(서비스 계정) 또는 컨테이너에서 할 수 있다(`*.googleapis.com` API 호스트는 이 컨테이너에서 열려 있음). 서비스 계정에는 Functions 배포·Secret Manager·Cloud Build·Artifact Registry 관련 역할이 더 필요하다(INFRA 안내서 02의 역할 4개로는 부족). [확인(접속) / 추측(역할 목록)]

### 6.6 앱 쪽 호출 방법

| 방법 | 장점 | 단점 |
|---|---|---|
| `cloud_functions` 7.0.1 (`firebase_core` 5.1.0과 해석됨 [확인 — 워크스페이스 해석]) | App Check·인증 토큰을 SDK가 붙임, 지역·에뮬레이터 설정(`useFunctionsEmulator`) 내장 | 네이티브 Firebase SDK가 앱에 들어옴 → iOS SwiftPM 혼합 위험(4.4)이 이번 라운드에 생김. 컨테이너에서 웹 경로 시험 불가 |
| `package:http` 1.6.0 + callable 규약 직접 구현 | 순수 Dart, 컨테이너 VM에서 에뮬레이터 상대로 시험됨(6.4), 네이티브 SDK 없음 | ID 토큰은 결국 `firebase_auth`(M4)에서 받아야 함. App Check 헤더(`X-Firebase-AppCheck`)를 직접 붙여야 함 |

함수 보호 [추측 — 설계 제안]: ① `request.auth` 필수 ② 소유자 UID 허용 목록(`defineString("OWNER_UIDS")`) — 개인 앱이면 이것만으로 남용을 막는다 ③ `maxInstances` 작게 ④ 하루 호출 수 상한(Firestore 카운터). App Check는 웹(reCAPTCHA)·iOS(App Attest — 유료 계정 필요)·안드로이드(Play Integrity — **사이드로드 APK는 Play가 모르는 앱이라 통과하지 못할 가능성**)의 사정이 달라 지금은 `enforceAppCheck: false`로 두고 디버그 공급자로 시험하는 것이 현실적이다.

**로그인과의 결합**: callable 함수를 안전하게 열려면 로그인이 필요하다. M4 로그인을 이번 라운드에 넣지 않으면 실제 엔진 연결은 '에뮬레이터 + 가짜 엔진'까지만 되고, 실제 호출은 로그인과 함께 연다(10절 Q11).

---

## 7. 웹 빌드에 네이티브 전용 플러그인이 섞일 때

### 7.1 실험 [확인]

`webprobe`(독립 앱, `flutter create --platforms=web,android,ios`)에 `google_mlkit_digital_ink_recognition 0.16.1`·`image_picker 1.2.4`·`firebase_core 5.1.0`·`cloud_functions 7.0.1`·`record 7.1.2`·`flutter_foreground_task 11.0.3`·`permission_handler 13.0.2`·`http 1.6.0`을 넣고, `main()`에서 **가드 없이** 각 API를 부르는 `probeAll()`을 실행했다.

| 단계 | 결과 |
|---|---|
| `flutter analyze` | 처음엔 오류: ML Kit의 `Ink`가 Flutter `Ink` 위젯과 겹침("The name 'Ink' is defined in the libraries …"). `as mlkit` 접두어로 해결. **`material_ui` 1.10.0도 `Ink`를 export**(`lib/src/ink_decoration.dart`)하므로 우리 코드에서도 같다 |
| `flutter build web --release`(wasm dry run 포함) | 통과(48~75초). "Wasm dry run succeeded" — `google_mlkit_commons`의 `dart:io` import가 dart2js·dart2wasm 모두에서 컴파일됨 |
| 빌드한 앱을 헤드리스 Chrome에서 실행(Playwright로 콘솔 수집, `--no-web-resources-cdn`) | `mlkit.isModelDownloaded` → `MissingPluginException(No implementation found for method vision#manageInkModels …)`, `mlkit.recognize` → 같은 예외(`vision#startDigitalInkRecognizer`), `FlutterForegroundTask.isRunningService` → `MissingPluginException`, `Permission.microphone.status` → `denied`(웹 구현), `ImagePicker().supportsImageSource(gallery)` → `true`, `FirebaseFunctions.instance`(초기화 전) → "Null check operator used on a null value"(축소된 오류) |
| `main.dart.js` 크기 | API 호출 있음 1,755,155 B / 없음 1,740,762 B → 차이 약 14 KB(웹 플러그인 등록 코드는 양쪽 모두 포함) |

참고: 03-recognition 요약 7은 `flutter test --platform chrome`에서 ML Kit 호출이 5초 안에 응답하지 않았다고 적는다. 빌드한 실제 앱에서는 즉시 `MissingPluginException`이 난다. 시험 바인딩과 실제 앱의 채널 처리 차이로 보인다. [확인(이번 실행) / 추측(원인)]

### 7.2 결론

- **컴파일 때문에 조건부 import가 꼭 필요하지는 않다.** 플러그인의 `dart:io` import는 웹 컴파일러가 받아들이고, 크기 영향도 작다.
- **그래도 경계는 필요하다.** 웹에서 부르면 런타임 예외(또는 시험 환경에서 무응답)이므로 ① 기능 포트(인터페이스) + provider 기본값 '지원 안 함' 구현 ② 네이티브 구현 파일을 `*_native.dart`로 두고 계약 7.4.3의 조건부 import로만 불러오는 방식이 안전하다.
- INFRA 규칙 R4②의 `native_only_imports`는 지금 `package:ffi/`·`package:pdfium_dart/`·`package:drift/native.dart`뿐이다(01-infra 2140행). M5~M7 네이티브 전용 플러그인(`package:google_mlkit_`, `package:flutter_foreground_task/`, 직접 만들 Pencil 플러그인)을 이 목록에 더하면 '`*_native.dart` 밖에서 import 금지'가 기계적으로 지켜진다.
- 웹에 구현이 있는 플러그인(`record`, `image_picker`, `permission_handler`, `cloud_functions`)은 일반 파일에서 써도 되지만, `cloud_functions`·Firebase는 `Firebase.initializeApp` 전에 부르면 안 된다.

---

## 8. 실기기 테스트 경로 종합 — 기능별로 어디서 확인하나

| 기능 | iPad Safari(웹, 지금) | 안드로이드 APK(실기기) | 안드로이드 에뮬레이터(CI) | iOS 컴파일만(macOS CI, 계정 불필요) | 무료 Apple ID 사이드로드 | TestFlight(계정 뒤) |
|---|---|---|---|---|---|---|
| 올가미 회전·색·잘라내기, 텍스트 상자, 도형, 추가 펜 | ✔ | ✔ | (위젯 시험으로 충분) | — | ✔ | ✔ |
| 이미지 삽입·이미지 페이지 | ✔(파일 선택) | ✔(사진 선택기) | △ | 컴파일 | ✔ | ✔(PHPicker) |
| 제스처 사용자 지정 | ✔ | ✔ | — | — | ✔ | ✔ |
| S펜 버튼 | — | ✔(S펜 기기) | ✘ | — | — | — |
| Pencil 더블탭·스퀴즈 | ✘(웹 API 없음 — 02-audio 8) | — | — | 컴파일 | ✔ | ✔ |
| 녹음·재생 바·필기 연동 | ✔(앞에 있을 때) | ✔ | △(가상 마이크) | 컴파일 | ✔ | ✔ |
| 백그라운드 녹음 | ✘ | ✔ | △ | 컴파일 | ✔ | ✔ |
| 손글씨→텍스트(ML Kit) | ✘ | ✔ | ✔(모델 내려받기 포함, 추측) | 컴파일 | ✔ | ✔ |
| 수식 인식(서버 함수) | ✔(로그인 뒤) | ✔ | ✔(에뮬레이터 연결) | — | ✔ | ✔ |
| 필기감 최종 판정 | 참고만 | ✔(안드로이드) | ✘ | — | ✔ | ✔ |

✔ 확인 가능, △ 일부, ✘ 불가, — 해당 없음. 표의 판단은 2~7절 사실을 근거로 한 [추측]이다.

---

## 9. 권장안 (조사자 의견 — 설계에서 채택 여부 결정)

1. **이번 라운드 실기기 경로**: iPad는 웹(홈 화면 앱) 유지 + 네이티브는 'macOS CI 컴파일 확인'까지. 안드로이드는 **고정 키로 서명한 release APK**로 실기기 시험(사용자에게 안드로이드 태블릿이 있을 때). 기기가 없으면 에뮬레이터 통합 시험 잡(3.4)으로 ML Kit·녹음 흐름을 자동 확인한다.
2. **`android.yml` 개정(INFRA)**: ① 고정 서명(3.5 방식 A — 시크릿 4개, 없으면 지금처럼 debug 서명) ② `main` 매니페스트에 `INTERNET`, 라벨 `필기노트` ③ 녹음 권한·포그라운드 서비스 선언(02-audio 4.2) ④ 첫 실행에서 NDK 28.2 내려받기 시간을 재서 9.2 실측표에 기록 ⑤ 영역 브랜치는 수동 실행만. 앱 셸의 `nativeDatabasePath` 연결(01-hooks)이 같은 묶음의 선행 작업이다.
3. **새 워크플로 `ios-compile.yml`(INFRA, 계정 불필요)**: `workflow_dispatch` + 입력 `confirm`(10배 과금 확인), `macos-26`(라벨 고정 — `-latest`는 1~2개월에 걸쳐 바뀜), `timeout-minutes: 45`, `flutter build ios --release --no-codesign`, CocoaPods·SwiftPM 캐시. 실행 시점은 ML Kit·녹음·Pencil 플러그인이 앱에 처음 연결된 통합 단계 1회 + 라운드 마감 1회(월 2회 이하). 성공하면 `flutter build ipa --no-codesign` 산출물을 아티팩트로 남겨 4.7 선택지에 쓸 수 있게 한다.
4. **iOS 설정(INFRA)**: `IPHONEOS_DEPLOYMENT_TARGET` 3곳을 15.5로, Flutter 템플릿(`templates/cocoapods/Podfile-ios`)에서 `app/ios/Podfile`을 만들어 `platform :ios, '15.5'`와 ML Kit README의 `post_install` 줄을 넣어 커밋, Info.plist에 4.5 표의 키(`NSMicrophoneUsageDescription`, `UIBackgroundModes: audio`, `NSPhotoLibraryUsageDescription`, `ITSAppUsesNonExemptEncryption=false`). 카메라 키는 카메라 기능을 넣을 때만.
5. **SwiftPM 혼합 모드**: 이번 라운드(앱에 Firebase 네이티브 없음)는 기본값(SwiftPM + ML Kit만 pod)을 유지한다. M4 연결(또는 `cloud_functions`·`firebase_auth`를 앱에 넣는 시점)에 `ios-compile`을 한 번 돌려 중복 심볼·실행 시 경고를 확인하고, 문제가 있으면 ⓐ `enable-swift-package-manager: false`(Firebase iOS 12.19.3 고정) ⓑ iOS 손글씨 엔진 교체 중에서 고른다. ML Kit iOS의 CocoaPods 의존은 리스크 표에 올리고 인식 엔진은 교체 가능한 포트 뒤에 둔다(PLAN F-14 원칙과 같음).
6. **네이티브 전용 경계**: ML Kit·포그라운드 서비스·Pencil 플러그인은 각 패키지의 `*_native.dart`에서만 import하고 조건부 import로 연결, 웹 기본 구현은 '지원 안 함'. INFRA R4 `native_only_imports`에 `package:google_mlkit_`·`package:flutter_foreground_task/`·Pencil 플러그인 패키지를 추가한다. ML Kit은 `as mlkit` 접두어로 import한다.
7. **컨테이너 정적 검사(INFRA `tool/`)**: ① `native_config_test.dart` — 매니페스트(권한·서비스·라벨), Info.plist 키, pbxproj 배포 대상 3곳, Podfile 플랫폼 줄, `build.gradle.kts` 서명 분기를 파싱해 시험 ② `ws native-reqs` — `package_config.json`의 플러그인 podspec·`Package.swift`·gradle을 읽어 앱 minSdk·compileSdk·iOS 대상과 비교하고 CocoaPods 전용 플러그인을 나열(3.7 시제품). 플러그인을 추가하는 영역이 컨테이너에서 바로 위반을 알 수 있다.
8. **서버 함수 골격(6.4 그대로)**: 저장소 루트 `functions/`(TypeScript, Node 22, `firebase-functions 7.4.0`·`firebase-admin 14.5.0`·`typescript 6.0.3`·`@types/node 22.20.5` 정확히 고정, `package-lock.json` 커밋, `npm ci`), 지역 `asia-northeast3`, `onCall` + 로그인 필수 + 소유자 UID 허용 목록 + `maxInstances: 2` + `defineSecret`, 엔진 포트 + 가짜 엔진. CI는 `ubuntu-latest`에서 `npm ci && npm test` + `firebase emulators:exec --only functions,auth --project demo-noteapp`(firebase-tools 15.34.2 — INFRA 고정값과 같음)로 1~2분. **수식 엔진이 Gemini(AI Logic)로 정해지면 이 골격은 만들지 않는다.**
9. **앱 쪽 호출**: EDITOR/인식 모듈은 `MathRecognitionGateway` 같은 포트만 알고, 구현은 앱 셸이 주입한다. M4 로그인 전에는 가짜 구현 + (개발자용) 에뮬레이터 HTTP 구현까지만 둔다. 실제 연결 때 `cloud_functions`(편의) vs HTTP 구현(네이티브 SDK 회피)을 5번의 iOS 결과를 보고 고른다.
10. **TestFlight 준비 갱신(INFRA 안내서 06)**: 클라우드 서명은 Admin 키가 필요할 수 있음을 밝히고, ⓐ Admin 키(간단, 권한 큼) ⓑ App Manager 키 + 수동 인증서(.p12는 컨테이너 openssl로 CSR부터 만들 수 있음) 두 경로를 적는다. `ios-testflight.yml` 초안은 ⓑ로 바꿀 수 있게 서명 단계를 분리해 둔다. 첫 업로드는 계정 가입 뒤 실제 화면 기준으로 다시 검증한다.
11. **`permission_handler`는 넣지 않는다**(5절). 영구 거부 때는 '설정 → 필기노트 → 마이크'를 안내하는 문구로 처리한다.
12. **예산**: macOS는 수동·게이트·월 2회 이하, 캐시 필수. 안드로이드 에뮬레이터 잡도 수동. 저장소 공개 여부를 정하면(공개면 Actions 무료) iOS 시험 횟수 제한을 풀 수 있다.
13. **감시 항목(리스크 표에 추가)**: CocoaPods trunk 읽기 전용(2026-12-02) 이후 ML Kit iOS 배포 방식, Flutter의 CocoaPods 전용 플러그인 오류 전환 시점, 안드로이드 개발자 인증의 국내 시행(2027 예정), Apple 다음 SDK 요구(현재 페이지에는 Xcode 27 요구 없음).

---

## 10. 열린 질문 (사용자 또는 총괄이 정할 것)

| # | 질문 | 왜 필요한가 | 대상 |
|---|---|---|---|
| Q1 | 안드로이드 태블릿(S펜 지원)이 있는가, 모델은? | 실기기 APK 시험·S펜 버튼·백그라운드 녹음 완료 판정 가능 여부. 없으면 에뮬레이터 잡(3.4) 도입 여부를 같이 정함 | 사용자 |
| Q2 | 안드로이드 고정 서명 키: 시크릿 등록(A) vs 개발용 키 커밋(B), 도입 시점 | 덮어 설치·노트 보존(3.5) | 사용자·총괄 |
| Q3 | 최종 앱 ID(`dev.noteapp.noteapp` 유지 여부) | 고정 키·App ID·TestFlight 앱 등록 전에 확정해야 함(바꾸면 다른 앱) — INFRA Q12 | 사용자 |
| Q4 | Apple 개발자 계정 가입 시점. 그 전에 무료 Apple ID + Sideloadly(Windows/Mac PC·케이블 필요, 7일마다 재설치)를 쓸 의향이 있는가 | 네이티브 Pencil·녹음·ML Kit을 언제 처음 손으로 확인하는지(4.7) | 사용자 |
| Q5 | 수식 엔진(Mathpix / Claude / Gemini AI Logic / MyScript) | 서버 함수·Blaze 필요 여부가 여기서 갈림(6.1). 03-recognition과 함께 결정 | 사용자·총괄 |
| Q6 | Blaze 전환 시점과 예산 한도 | Functions 배포 전제(6.2), Storage(M4)와 같은 시점일 수 있음 | 사용자 |
| Q7 | 함수 지역 `asia-northeast3` vs `us-central1` | 지연 vs 무료 사용량 조건(원문 미확인) — Firestore 위치와 함께 | 총괄 |
| Q8 | `functions/`의 소유 영역(INFRA / 인식 영역 / 새 SERVER 영역)과 CI 잡 위치 | 한 패키지 = 한 영역 원칙, `ws check` 규칙이 루트의 Node 디렉터리를 어떻게 볼지 | 총괄 |
| Q9 | M4 로그인(앱 연결·로그인 화면)을 이번 라운드에 넣는가 | 서버 함수 실제 호출은 로그인과 묶임(6.6). 넣으면 iOS SwiftPM 혼합 문제(4.4)도 이번 라운드에 확인해야 함 | 총괄 |
| Q10 | macOS 러너 월 허용 횟수, 저장소 공개 여부 | 4.8 예산 | 사용자 |
| Q11 | iOS 최소 버전 15.5(ML Kit 최소) vs 16 이상 | 대안 엔진(예: Apple Vision의 한국어 텍스트 인식 — 지원 버전 미확인)을 iOS에 둘 가능성 | 총괄 |
| Q12 | iOS 의존 관리: 기본(SwiftPM+pod 혼합) 유지 vs 전부 CocoaPods | Firebase iOS 업데이트(13.x)와 ML Kit 공존 문제(4.4) — M4 때 실험 결과로 결정 | 총괄 |

---

## 11. 확인한 버전

| 패키지·도구 | 버전(게시일) | 확인 방법 |
|---|---|---|
| Flutter / Dart | 3.47.9 (`c197ca5`, 2026-10-29) / 3.13.7 | `flutter --version` |
| Flutter 안드로이드 기본값 | compileSdk 36, targetSdk 36, minSdk 24, NDK 28.2.13676358 | `FlutterExtension.kt` 23–42 |
| 앱 안드로이드 도구 | AGP 9.1.0, Gradle 9.3.1, Kotlin 2.4.0, Java 17 대상 | `app/android/*.kts`, `gradle-wrapper.properties` |
| `google_mlkit_digital_ink_recognition` | 0.16.1 (2026-08-17) | pub.dev API + 워크스페이스 해석 + 웹 빌드 + podspec |
| `google_mlkit_commons` | 0.13.0 (2026-08-17) | 같음 |
| `GoogleMLKit` / `MLKitCommon` / `MLKitDigitalInkRecognition` / `MLKitVision` (pod) | 9.0.0 / 14.0.0 / 8.0.0 / 10.0.0, 모두 iOS 15.5 | cdn.cocoapods.org 버전 목록 + CocoaPods/Specs 사양 JSON |
| `com.google.mlkit:digital-ink-recognition` | 19.0.0 | 플러그인 `build.gradle` 49 (AAR은 dl.google.com 차단으로 못 받음) |
| `permission_handler` / `_android` / `_apple` | 13.0.2 (2026-09-04) / 14.1.1 (2026-10-28) / 9.6.5 (2026-11-02) | pub.dev API + 해석 + Chrome 실행 + gradle·README |
| `image_picker` / `_ios` / `_android` / `_for_web` | 1.2.4 (2026-10-06) / 0.8.13+14 (2026-10-29) / 0.8.13+25 (2026-10-02) / 3.1.1 | pub.dev API + 해석 + Chrome 실행 |
| `firebase_core` / `cloud_functions` / `cloud_functions_web` | 5.1.0 / 7.0.1 (2026-10-23) / 5.1.15 | pub.dev API + 워크스페이스 해석(기존 잠금 변화 없음) |
| Firebase iOS SDK | SwiftPM 13.1.1, CocoaPods 12.19.3(마지막) | `firebase_core/ios/firebase_core/Package.swift` 11, `ios/firebase_sdk_version.rb`, CocoaPods CDN 목록 |
| Firebase Android BoM | 35.1.0 | `firebase_core/android/gradle.properties` |
| `firebase_ai` | 5.1.0 (2026-10-23) | pub.dev API(해석은 안 함) |
| `record` / `flutter_foreground_task` / `just_audio` | 7.1.2 / 11.0.3 / 0.10.6 | 02-audio와 같은 버전으로 해석·웹 빌드 |
| `http` | 1.6.0 (2025-11-10) | Dart VM에서 에뮬레이터 호출 |
| `flutter_math_fork` | 0.7.4 — 넣으면 `xml` 7.1.0 → **7.0.1로 내려감**(`vector_graphics_compiler 1.3.4`가 `xml <=7.0.1`) | 워크스페이스 해석 잠금 비교 |
| firebase-tools | 15.34.2 (2026-10-28, INFRA 고정값), 최신 15.35.0 (2026-11-04) | npm + 설치·실행 |
| firebase-functions / firebase-admin | 7.4.0 (2026-09-15) / 14.5.0 (2026-09-23, `node >=22`) | npm + 설치 + 에뮬레이터 실행 |
| typescript / @types/node | 6.0.3 (2026-04-16, firebase init 템플릿 `^6.0.0`) / 22.20.5 (2026-10-01) — 최신 TS는 7.0.2 | npm + `tsc` 빌드 |
| Firestore 에뮬레이터 | 1.22.0 jar | `firebase emulators:exec --only firestore` |
| GitHub 러너 이미지 | Ubuntu 24.04 20261026.354.1 / macOS 26 arm64 20261026.0455.2(Xcode 26.6) | runner-images README(raw.githubusercontent.com) |
| `reactivecircus/android-emulator-runner` | `@v2`(README 예시) | raw.githubusercontent.com README |

1차 잠금 대비 해석 결과(`ws/` — `native_probe`에 ML Kit·image_picker·firebase_core·cloud_functions·flutter_math_fork·record·just_audio·audio_session·flutter_foreground_task·permission_handler): **기존 잠금 변화는 `xml 7.1.0 → 7.0.1` 한 건**(원인 `flutter_math_fork` → `flutter_svg 2.3.2` → `vector_graphics_compiler 1.3.4`), 추가 53개. 나머지 후보만 넣으면 기존 변화 없음(02-audio 2.2와 같음). [확인]

---

## 12. 확인 명령 기록 (재현용)

모든 명령 앞: `export PATH=/opt/flutter/bin:$PATH CHROME_EXECUTABLE=/usr/local/bin/chrome-nosandbox`

```bash
# 2절 현재 상태
cat /home/user/noteapp/app/android/{settings.gradle.kts,gradle.properties} /home/user/noteapp/app/android/app/build.gradle.kts
grep -n "IPHONEOS_DEPLOYMENT_TARGET\|PRODUCT_BUNDLE_IDENTIFIER" /home/user/wt/infra/app/ios/Runner.xcodeproj/project.pbxproj
cat /home/user/wt/infra/.github/workflows/{android,ios-testflight}.yml /home/user/wt/infra/app/ios/{ExportOptions.plist,Runner/Info.plist}
grep -i permission /home/user/wt/infra/app/android/app/src/{main,debug}/AndroidManifest.xml

# 3.1 Flutter Gradle 기준
grep -n "Version(\|MinSdkVersion" /opt/flutter/packages/flutter_tools/gradle/src/main/kotlin/DependencyVersionChecker.kt
grep -n "val .*Version\|ndkVersion" /opt/flutter/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt
sed -n 565,600p /opt/flutter/packages/flutter_tools/gradle/src/main/kotlin/FlutterPluginUtils.kt

# 3.2 / 3.7 플러그인 요구 스캐너 (시제품)
python3 -I /tmp/claude-0/plan57-scratch/native/scripts/plugin_reqs.py /tmp/claude-0/plan57-scratch/native/ws

# 3.7 컨테이너 한계
curl -s -o /dev/null -w '%{http_code}\n' https://dl.google.com/android/repository/repository2-3.xml   # 000 (connect_rejected)
curl -sI https://maven.google.com/com/google/mlkit/digital-ink-recognition/19.0.0/digital-ink-recognition-19.0.0.pom | grep location  # → dl.google.com
cd /tmp/claude-0/plan57-scratch/native/webprobe && flutter build apk --config-only    # No Android SDK found
flutter build ios                                                                      # Could not find a subcommand named "ios"

# 4.3 / 4.4 CocoaPods 사양
pod=GoogleMLKit; h=$(printf %s $pod | md5sum | cut -c1-3)
curl -s "https://cdn.cocoapods.org/all_pods_versions_${h:0:1}_${h:1:1}_${h:2:1}.txt" | grep "^$pod/"
curl -sL "https://raw.githubusercontent.com/CocoaPods/Specs/master/Specs/${h:0:1}/${h:1:1}/${h:2:1}/$pod/9.0.0/$pod.podspec.json"
#   같은 방법으로 MLKitCommon 14.0.0, MLKitDigitalInkRecognition 8.0.0, MLKitVision 10.0.0, Firebase{Core,Auth,Functions,Storage} 12.19.0
sed -n 60,100p /opt/flutter/packages/flutter_tools/lib/src/macos/darwin_dependency_management.dart
sed -n 320,336p /opt/flutter/packages/flutter_tools/bin/podhelper.rb
cat /root/.pub-cache/hosted/pub.dev/firebase_core-5.1.0/ios/firebase_sdk_version.rb

# 4.1 러너 이미지
curl -s https://raw.githubusercontent.com/actions/runner-images/main/README.md
curl -s https://raw.githubusercontent.com/actions/runner-images/main/images/macos/macos-26-arm64-Readme.md
curl -s https://raw.githubusercontent.com/actions/runner-images/main/images/ubuntu/Ubuntu2404-Readme.md

# 11절 워크스페이스 해석 (noteapp pubspec·lock 복사 + packages/native_probe)
cd /tmp/claude-0/plan57-scratch/native/ws && flutter pub get     # Changed 54 dependencies (xml 하향 1 + 추가 53)

# 7절 웹 빌드·실행
cd /tmp/claude-0/plan57-scratch/native/webprobe
flutter analyze
flutter build web --release                                         # Wasm dry run succeeded
flutter build web --release --no-wasm-dry-run --no-web-resources-cdn
(cd build/web && python3 -I -m http.server 8791 --bind 127.0.0.1 &)
node /tmp/claude-0/plan57-scratch/native/scripts/console.mjs http://127.0.0.1:8791/   # Playwright, 콘솔 수집

# 6절 서버 함수
cd /tmp/claude-0/plan57-scratch/native/fbtools && npm install firebase-tools@15.34.2
cd /tmp/claude-0/plan57-scratch/native/fnrepo/functions && npm install && npm test   # 2/2
export PATH=/tmp/claude-0/plan57-scratch/native/fbtools/node_modules/.bin:$PATH
cd /tmp/claude-0/plan57-scratch/native/fnrepo/app
firebase emulators:exec --only functions,auth --project demo-noteapp /tmp/claude-0/plan57-scratch/native/scripts/call_fn.sh
firebase emulators:exec --only functions,auth --project demo-noteapp "dart run /tmp/claude-0/plan57-scratch/native/dartclient/bin/call.dart"
firebase emulators:exec --only firestore --project demo-noteapp /tmp/claude-0/plan57-scratch/native/scripts/fs_write.sh
grep -n "Blaze" node_modules/firebase-tools/lib/deploy/functions/ensure.js     # (fbtools 아래)
sed -n 300,340p node_modules/firebase-tools/lib/gcp/ailogic.js
grep -n "SupportedRegion" /tmp/claude-0/plan57-scratch/native/fnrepo/functions/node_modules/firebase-functions/lib/v2/options.d.ts
```

---

## 13. 출처

로컬 소스(읽기 전용)

- Flutter 3.47.9: `/opt/flutter/packages/flutter_tools/gradle/src/main/kotlin/{DependencyVersionChecker,FlutterExtension,FlutterPluginUtils}.kt`, `.../tasks/ValidateCompileSdkVersionTask.kt`, `/opt/flutter/packages/flutter_tools/lib/src/macos/{darwin_dependency_management,cocoapod_utils,cocoapods,xcode}.dart`, `/opt/flutter/packages/flutter_tools/lib/src/{flutter_manifest,features}.dart`, `/opt/flutter/packages/flutter_tools/bin/podhelper.rb`, `/opt/flutter/packages/flutter_tools/templates/{app/ios.tmpl,cocoapods,app/android.tmpl}`, `/opt/flutter/packages/flutter_tools/lib/src/isolated/native_assets/android/native_assets.dart`
- pub 캐시: `/root/.pub-cache/hosted/pub.dev/{google_mlkit_digital_ink_recognition-0.16.1, google_mlkit_commons-0.13.0, permission_handler_android-14.1.1, permission_handler_apple-9.6.5, image_picker-1.2.4, image_picker_android-0.8.13+25, record_android-2.2.0, flutter_foreground_task-11.0.3, firebase_core-5.1.0, firebase_core_web-4.1.0, cloud_functions-7.0.1, pdfium_dart-0.4.1, material_ui-1.10.0}`
- firebase-tools 15.34.2: `lib/deploy/functions/ensure.js`, `lib/deploy/functions/runtimes/supported/types.js`, `lib/gcp/ailogic.js`, `lib/experiments.js`, `templates/init/functions/typescript/`
- firebase-functions 7.4.0: `lib/v2/options.d.ts`, `lib/v1/function-configuration.d.ts`
- 저장소: `/home/user/noteapp`(`ec8366a`), `/home/user/wt/infra`(`1a62fba`) — `.github/workflows/`, `app/android/`, `app/ios/`, `docs/guides/05-android-apk.md`·`06-ios-testflight.md`, `docs/plans/progress/infra.md`

원격(직접 받음)

- pub.dev API `https://pub.dev/api/packages/<이름>`(2026-11-05 조회), npm 레지스트리(`npm view`)
- GitHub runner-images: https://github.com/actions/runner-images (README, `images/ubuntu/Ubuntu2404-Readme.md`, `images/macos/macos-26-arm64-Readme.md`)
- CocoaPods: https://cdn.cocoapods.org/ (버전 목록), https://github.com/CocoaPods/Specs (사양 JSON)
- android-emulator-runner: https://github.com/ReactiveCircus/android-emulator-runner (README)
- Apple 요구 사항: https://developer.apple.com/news/upcoming-requirements/ (WebFetch)

검색 요약으로만 본 것([2차])

- GitHub Actions 요금·배수: https://dev.to/shubhamoriginx/github-actions-changed-pricing-in-2026-heres-exactly-what-youre-paying-now-51db · https://bitrise.io/blog/post/best-github-actions-runners-in-2026-and-hidden-pricing-traps-to-avoid · https://dev.to/ace2932/your-github-actions-bill-is-mostly-macos-minutes-heres-how-to-tell-56fk (원문 docs.github.com은 접근 불가)
- 클라우드 서명 Admin 키: https://developer.apple.com/forums/thread/698117 · https://rxliuli.com/blog/two-pitfalls-of-safari-cloud-signing-in-github-actions · https://docs.devin.ai/onboard-devin/environment/testflight.md
- CocoaPods trunk 읽기 전용: https://blog.cocoapods.org/CocoaPods-Specs-Repo/ (검색 요약) · https://dev.to/subraatakumar/the-cocoapods-sunset-what-dec-2-2026-means-for-your-react-native-app-4g4i · https://www.bluefrontier.co.uk/blog/cocoapods-trunk-read-only-plan-what-ios-developers-need-to-know
- ML Kit SwiftPM·혼합 중복: https://developers.google.com/ml-kit/migration/ios · https://github.com/d-date/google-mlkit-swiftpm · https://kiwix.lema.org/stackoverflow.com_en_all_2023-11/questions/70855053/swift-package-manager-spm-and-cocoapod-dependency-conflict · https://github.com/bharat-biradar/Google-Ml-Kit-plugin/issues/357
- 안드로이드 개발자 인증: https://androidauthority.com/android-sideloading-developer-verification-first-wave-rollout-3717921 · https://www.androidauthority.com/android-sideloading-changes-timeline-3679204/
- Sideloadly: https://sideloadly.io/faq
- Firebase 요금·할당량: https://firebase.google.com/pricing · https://firebase.google.com/docs/functions/quotas (원문 접근 불가)
