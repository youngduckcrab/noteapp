# 2차 라운드 기술 조사 02 — 오디오 녹음·재생과 스타일러스 버튼

> 상태: 조사 완료(2026-11-05) · 담당: 2차 라운드 기술 조사(오디오·스타일러스) · 기준 계약: [00-overview.md 7장 v1.4](../../00-overview.md#7-통합-계약) · 마스터 기획서: [PLAN.md](../../../PLAN.md) F-12(펜 버튼), F-16(녹음), 6.2(세부 스택), 10장 M5·M6 · 함께 볼 문서: [01-hooks.md](01-hooks.md) 3.5(시간 정보)·3.7(입력)·3.9(에셋)
>
> M6 녹음(녹음·백그라운드 녹음·재생 바·획별 녹음 시점·필기 탭 재생)과 M5 펜 버튼(S펜 측면 버튼, Apple Pencil 더블탭·스퀴즈, Pencil Pro 배럴 롤·호버)에 쓸 기술을 조사한다. 패키지 후보마다 Flutter 3.47.9 / Dart 3.13.7에서 실제로 의존성을 해석하고 웹 빌드·Chrome 실행까지 확인했다. 설계 결정은 하지 않는다. 조사자 의견은 12절 '권장안', 정해야 할 것은 13절 '열린 질문'으로 분리한다.

표기

| 표시 | 뜻 |
|---|---|
| **[확인]** | 이 컨테이너에서 명령을 실행하거나 소스(패키지·Flutter 엔진)를 읽어 직접 확인한 사실. 명령·경로를 함께 적는다 |
| **[문서]** | 공식 문서·패키지 문서·계획서에 적힌 내용(이번에 실행으로는 확인하지 않음). 출처 URL을 함께 적는다 |
| **[추측]** | 확인하지 않은 판단. 근거를 함께 적고, 설계 전 또는 실기기에서 확인이 필요하다 |

---

## 0. 요약 — 핵심 사실

1. **녹음 = `record` 7.1.2, 재생 = `just_audio` 0.10.6, 세션 = `audio_session` 0.2.4가 Flutter 3.47.9 워크스페이스에서 그대로 해석된다.** 1차 잠금 파일(`pubspec.lock`)의 기존 패키지 버전은 하나도 바뀌지 않고 새 패키지만 추가된다(`rxdart 0.28.0`·`path_provider 2.1.6`·`synchronized 3.5.0`·`uuid 4.6.0`·`crypto 3.0.8`은 이미 잠겨 있던 버전을 같이 씀). `flutter build web`도 통과한다(약 20초). [확인]
2. **웹(Chrome)에서 녹음 → 재생 전 과정이 헤드리스로 실제 동작한다.** 가짜 마이크(`--use-fake-device-for-media-stream`)로 `record`가 2초 녹음(중간 1초 일시정지)한 webm/opus를 `just_audio`가 열어 길이 2,009 ms(일시정지 구간 제외), 2배속 재생 시 벽시계 대비 위치 기울기 ≈ 1.99, `seek(700 ms)` 뒤 위치 704~712 ms를 냈다. 녹음 상태 이벤트(`record@30ms, pause@1034ms, record@2038ms, stop@3050ms`)로 잰 활성 시간과 파일 길이 차는 10 ms 안이었다. [확인]
3. **크롬(리눅스)은 AAC로 녹음하지 못한다.** `MediaRecorder.isTypeSupported('audio/mp4;codecs=mp4a.40.2') = false`, `audio/webm;codecs=opus = true`라 `record`의 `aacLc`가 `isEncoderSupported = false`다. iPad Safari는 `audio/mp4`(AAC)로 녹음한다는 것이 패키지 문서의 시험 결과다. **크롬에서 녹음한 webm/opus는 iOS 네이티브(AVPlayer)에서 재생할 수 없으므로**, 여러 기기에서 들을 녹음은 AAC-LC/m4a로 통일하는 것이 맞다. [확인(크롬) / 문서(Safari·AVPlayer)]
4. **백그라운드 녹음은 네이티브에서만 된다.** iOS는 `UIBackgroundModes: audio` + 활성 오디오 세션이면 되고, 안드로이드는 `record` 7.0이 자체 서비스를 없앴으므로 **포그라운드 서비스(type `microphone`)를 앱이 띄워야 한다**(record 문서 권장 `flutter_foreground_task` 11.0.3, 해석 확인). 안드로이드 14+는 `FOREGROUND_SERVICE_MICROPHONE` 권한과 `RECORD_AUDIO` 허가가 있어야 하고 **앱이 앞에 있을 때만** 이 서비스를 시작할 수 있다. 웹(iPad Safari)은 탭이 뒤로 가면 마이크가 멈추거나 소리가 비며, 페이지에서 되살릴 방법이 없다는 WebKit 보고가 있다. [문서]
5. **재생 위치는 `just_audio`가 Dart 안에서 외삽한다.** `position = updatePosition + (now − updateTime) × speed`라 매 프레임 읽어도 플랫폼 호출이 없다. iOS는 0 허용 오차로 탐색하고, 재생 속도는 iOS `AVAudioTimePitchAlgorithmTimeDomain`(음성용), 안드로이드 ExoPlayer `PlaybackParameters`, 웹 `playbackRate`로 0.5~2배를 낸다. [확인(소스)]
6. **획 시각은 '녹음기 위치'로 정해야 한다.** 계약상 `recordingOffsetMs`는 녹음 시작부터 펜 다운까지 ms이고 INK는 펜 다운 때 `beginStroke(meta: InkStrokeMeta(...))`로 받는다. 일시정지를 빼려면 벽시계 차가 아니라 **단조 시계(Stopwatch)를 녹음 상태 이벤트에 맞춰 멈추고 이어 가는 '녹음 시계'**로 재야 한다(6절). [확인(계약·코드) / 추측(설계)]
7. **S펜 측면 버튼은 Flutter가 이미 준다.** 안드로이드 엔진이 `getButtonState() >> 4`로 `BUTTON_STYLUS_PRIMARY`를 `kPrimaryStylusButton`(0x02)으로 바꾼다. 웹 엔진은 DOM `buttons`를 그대로 넘긴다. **웹에서는 버튼을 누른 채 펜을 띄워 두면 닿기 전에 `PointerDownEvent(buttons: 0x02)`가 오고 닿는 순간은 `PointerMoveEvent(buttons: 0x03)`이다**(CDP로 펜 이벤트를 흉내 내 확인). 네이티브 안드로이드는 닿은 채 버튼이면 `PointerDownEvent(buttons: 0x02)`(접촉 비트 없음)다. 플랫폼마다 '접촉' 판정이 다르다. [확인]
8. **Apple Pencil 더블탭·스퀴즈·배럴 롤은 Flutter에 없다.** Flutter iOS 엔진에 `UIPencilInteraction`이 없고, Pencil 호버는 `UIHoverGestureRecognizer`를 거쳐 **`kind: mouse`** 호버로 오며 높이(`zOffset`)·롤이 없다. 웹에는 더블탭·스퀴즈 API가 없고(이 부분만 [추측] — 표준 Pointer Events에 해당 이벤트가 없고 Apple 포럼 질문에 답이 없음), Flutter 웹 엔진은 `twist`(롤)를 읽지 않는다. 플러그인 후보는 `apple_pencil_double_tap` 2.0.0(MIT, iOS 전용, 더블탭·스퀴즈만, Swift 약 170줄)과 `stylet` 0.1.4(MIT, 전 플랫폼, 배럴 롤·호버 포함, 2026-08 첫 공개)가 있다. 둘 다 해석·웹 빌드는 되지만 **`apple_pencil_double_tap`은 `dart:io` `Platform.isIOS`를 불러 웹에서 그대로 부르면 안 된다**. [확인]
9. **iOS 네이티브 기능은 지금 실기기 검증 수단이 없다.** Mac·유료 Apple 계정이 없으므로 할 수 있는 것은 GitHub Actions macOS에서 `flutter build ios --no-codesign`(컴파일 확인)까지다. Pencil 이벤트 동작 확인은 계정 가입·TestFlight 뒤다. [문서(01-infra 워크플로) / 추측(일정)]

---

## 1. 조사 범위와 방법

### 1.1 질문

| # | 질문 | 답한 절 |
|---|---|---|
| A1 | 녹음·재생 패키지 후보의 정확한 최신 버전, 지원 플랫폼, Flutter 3.47.9 해석 여부 | 2 |
| A2 | 코덱(AAC/m4a, Opus), 웹 Safari·Chrome MediaRecorder가 내는 형식, 교차 재생 | 3 |
| A3 | 백그라운드 녹음 조건(iOS·안드로이드·웹) | 4 |
| A4 | 재생 위치 정밀도, 속도 0.5~2배, 탐색 | 5 |
| A5 | 녹음 중 일시정지, 녹음 시작 시각과 획 시각 맞추기(시계 기준·지연 보정) | 6 |
| A6 | 오디오 세션·권한 | 7 |
| S1 | Flutter `PointerEvent`가 주는 스타일러스 정보(버튼 비트·호버·기울기)의 플랫폼별 실제 값 | 8 |
| S2 | Apple Pencil 더블탭·스퀴즈·배럴 롤·호버를 받는 방법(플러그인 유무, 직접 만들 때 구조) | 9 |
| S3 | S펜 측면 버튼 | 10 |
| W1 | 웹 우선 테스트 관점에서 되는 것/안 되는 것 | 11 |

### 1.2 확인 환경

- Flutter 3.47.9 stable / Dart 3.13.7(`/opt/flutter`), Linux 컨테이너, 헤드리스 Chrome for Testing 153.0.8010.12(`/opt/pw-browsers/chromium-1243`), Node 22 + Playwright 1.63.0(전역 설치본).
- pub.dev 조회 시각: 2026-11-05(`https://pub.dev/api/packages/<name>`, 점수는 `/score`).
- 임시 작업 위치(모두 `/tmp/claude-0/plan57-scratch/` 아래): `audio_ws/`(1차 워크스페이스 pubspec 복사본 + 시험 멤버), `audio_probe/`(독립 Flutter 앱, 웹 빌드·Chrome 시험), `cdp/`(Playwright CDP 펜 시험), `chrome/`(MediaRecorder MIME 시험), `src/`(플러그인 소스 압축 해제본), `audio/`(pub.dev 응답).
- 확인한 명령 전체는 14절에 둔다.

---

## 2. 녹음·재생 패키지 후보

### 2.1 버전 · 플랫폼 · 상태

| 패키지 | 최신 버전(게시일) | 요구 SDK | 플랫폼(pub 태그) | 라이선스 | 점수·좋아요 | 비고 |
|---|---|---|---|---|---|---|
| `record` | **7.1.2** (2026-10-09) | Dart ^3.12, Flutter ≥ 3.44 | android, ios, web, windows, macos, linux · wasm-ready · swiftpm | BSD-3 | 160/160 · 899 | 연합 플러그인: `record_android 2.2.0`, `record_ios 2.1.1`, `record_web 2.1.3`, `record_platform_interface 2.1.0` 등. 7.0에서 안드로이드 백그라운드 서비스 제거 [확인] |
| `just_audio` | **0.10.6** (2026-06-29) | Dart ^3.6, Flutter ≥ 3.27 | android, ios, macos, web · swiftpm · **Flutter Favorite** | Apache-2.0 / MIT | 150/160 · 4,151 | `just_audio_web 0.4.16`, `just_audio_platform_interface 4.6.0`. wasm-ready 태그 없음(우리 웹 빌드는 dart2js라 무관 — 01-infra D6) [확인] |
| `audio_session` | **0.2.4** (2026-06-29) | Dart ^3.6, Flutter ≥ 3.27 | android, ios, macos, web · swiftpm | MIT | 150/160 · 366 | `just_audio`가 의존(>=0.1.24 <0.3.0). 웹 구현은 설정값만 보관하는 자리(소스 `audio_session_web.dart`) [확인] |
| `audioplayers` | 6.8.1 (2026-06-27) | Dart ^3.6, Flutter ≥ 3.44 | android, ios, windows, linux, macos, web · swiftpm | MIT | 150/160 · 3,449 | 재생 전용(녹음 없음). 위치는 타이머 갱신(`TimerPositionUpdater`) 또는 프레임마다 플랫폼 호출(`FramePositionUpdater`) [확인] |
| `flutter_sound` | 9.30.0 (2025-11-27) | Dart ^3.7.2 | 6개 플랫폼 · **darwin-legacy-native-build**(SwiftPM 아님) | **MPL-2.0** | 140/160 · 1,641 | 10.x는 `taudio` 10.3.8(2025-07-17)로 이름이 바뀜. 웹은 실행 중 `./assets/packages/flutter_sound_web/src/*.js`를 불러 씀 [확인] |
| `flutter_foreground_task` | **11.0.3** (2026-09-07) | Dart ^3.12, Flutter ≥ 3.44 | android, ios · swiftpm | MIT | 150/160 · 583 | 안드로이드 포그라운드 서비스. `record` 문서가 백그라운드 녹음에 권장 [확인/문서] |
| `permission_handler` | 13.0.2 (2026-09-04) | Dart ^3.6 | android, ios, windows, web | MIT | 160/160 · 6,017 | 필요 없을 가능성이 큼(7.2) [확인] |

보조로 본 것: `just_audio_background` 0.0.1-beta.17(잠금 화면 재생 제어, 베타), `audio_service` 0.18.19(백그라운드 재생 서비스). 녹음 화면에는 필요하지 않다. [확인]

### 2.2 워크스페이스 해석 확인 [확인]

1차 `/home/user/noteapp`의 루트·멤버 `pubspec.yaml`과 `pubspec.lock`을 그대로 복사하고(영역 작업 트리 7개의 잠금 파일이 noteapp과 같음을 먼저 비교함), 시험 멤버 `packages/media_probe`를 넣어 해석했다.

```yaml
# /tmp/claude-0/plan57-scratch/audio_ws/packages/media_probe/pubspec.yaml
dependencies:
  flutter: {sdk: flutter}
  record: 7.1.2
  just_audio: 0.10.6
  audio_session: 0.2.4
  apple_pencil_double_tap: 2.0.0
  stylet: 0.1.4
  permission_handler: 13.0.2
  flutter_foreground_task: 11.0.3
```

결과(`flutter pub get`, 6초; 다시 `--offline`으로 재확인):

- 기존 잠금 버전 변화: **없음**(잠긴 175개 중 0개).
- 추가 28개: 위 7개 + `just_audio_platform_interface 4.6.0`, `just_audio_web 0.4.16`, `record_android 2.2.0`, `record_ios 2.1.1`, `record_linux 2.1.3`, `record_macos 2.1.1`, `record_platform_interface 2.1.0`, `record_web 2.1.3`, `record_windows 2.3.0`, `permission_handler_*` 5개, `shared_preferences 2.5.6`과 그 플랫폼 구현 6개(`flutter_foreground_task`가 끌어옴).
- 이미 잠겨 있던 것을 같이 씀: `rxdart 0.28.0`, `path_provider 2.1.6`, `synchronized 3.5.0`, `uuid 4.6.0`, `crypto 3.0.8`, `web 1.1.2`, `plugin_platform_interface 2.1.8`, `async 2.13.1`.
- 대안 해석(따로): `audioplayers 6.8.1` → 7개 추가, 기존 변화 없음. `flutter_sound 9.30.0` → 3개 추가(`flutter_sound_platform_interface`·`flutter_sound_web` 9.30.0, 10.3.8은 `taudio` 쪽), 기존 변화 없음.

### 2.3 웹 빌드 확인 [확인]

독립 앱 `audio_probe`(`flutter create --platforms=web,android,ios`)에 `record`·`just_audio`·`audio_session`·`apple_pencil_double_tap`·`stylet`·`web 1.1.2`를 정확한 버전으로 넣고, 네 패키지의 주요 API(`AudioRecorder.start/pause/resume/stop`, `RecordConfig`, `AudioSession.configure`, `AudioPlayer.setSpeed/positionStream`, `ApplePencilDoubleTap.listen`, `StyletListener`, `kPrimaryStylusButton`)를 부르는 코드를 썼다.

- `flutter analyze`: 코드 문제 없음(템플릿의 `flutter_lints` include 경고 1건만).
- `flutter build web --release --no-wasm-dry-run`: 통과, 20.3초, `main.dart.js` 1.1 MB.
- 빌드 결과에 `assets/packages/record_web/assets/js/record.worklet.js`가 들어간다. `record_web`은 이 파일을 `audioWorklet.addModule('assets/packages/record_web/assets/js/record.worklet.js')`(상대 주소 → 브라우저가 `document.baseURI` 기준으로 해석)로 부른다. **wav·pcm16 인코더에서만** 쓰고 aac·opus(MediaRecorder 경로)는 쓰지 않는다. 계약 7.4.3의 '정적 파일 주소는 `document.baseURI` 기준' 규칙과 맞는다. INFRA의 웹 정적 파일 목록(`tool/web_assets.yaml`)과는 별개로 Flutter가 패키지 에셋으로 함께 넣는다.

### 2.4 후보 비교

| 기준 | record + just_audio (+ audio_session) | audioplayers (재생) | flutter_sound / taudio |
|---|---|---|---|
| 녹음 | ✔ 파일·스트림, 일시정지, 진폭, 인코더 지원 질의(`isEncoderSupported`), 실제 적용 설정 콜백(`setOnConfigChanged`, 7.1.0) | ✘ | ✔ |
| 재생 위치 | Dart 외삽(`position` getter, 5.1) — 프레임마다 읽어도 비용 없음 | 200 ms 타이머 또는 프레임마다 비동기 플랫폼 호출 | 구독 주기 설정 |
| 속도 0.5~2배 | ✔(iOS TimeDomain 음높이 보존, 안드로이드 ExoPlayer, 웹 `playbackRate`) | ✔ `setPlaybackRate` | ✔ |
| 웹 | ✔ 헤드리스 Chrome에서 녹음→재생 실측(5.2) | ✔(이번에 실행하지 않음) | 실행 중 JS 파일을 불러 씀 |
| iOS 빌드 | SwiftPM 지원 | SwiftPM 지원 | SwiftPM 미지원(CocoaPods 강제) |
| 라이선스 | BSD-3 / Apache-2.0·MIT / MIT | MIT | MPL-2.0 |
| 유지 상태 | 2026-06~10 게시 | 2026-06 | 9.x 마지막 2025-11, 10.x는 다른 이름 |
| PLAN 6.2 | "녹음 / 재생: record / just_audio"와 같음 | — | — |

탈락 이유: `audioplayers`는 녹음이 없어 결국 패키지가 둘이 되고, 위치 갱신이 획 강조(프레임 단위)에 덜 맞는다. `flutter_sound`는 MPL-2.0, SwiftPM 미지원, 이름 변경(`taudio`)으로 유지 경로가 불분명하다. [확인(소스·pub 태그) / 추측(유지 판단)]

---

## 3. 코덱 · 파일 형식

### 3.1 `record`의 인코더 지원 (패키지 README 표) [문서]

| 인코더 | Android | iOS | 웹 | 비고 |
|---|---|---|---|---|
| `aacLc` | ✔ | ✔ | Safari ✔ (Chrome·Firefox ✘) | 컨테이너 MPEG-4, 권장 확장자 `m4a` |
| `aacHe` | ✔ | ✘ | ? | |
| `opus` | ✔ (API 29+, **OGG**) | ✔ (**CAF**, "iOS에서만 재생 가능") | Chrome·Firefox ✔ (**WebM**) | 플랫폼마다 컨테이너가 다름 |
| `wav` / `pcm16bits` | ✔(고급 녹음기) | ✔ | ✔(패키지가 직접 인코딩, AudioWorklet) | 무압축 |

출처: <https://pub.dev/packages/record> README "File" 표(`record-7.1.2/README.md`). 안드로이드 최소 SDK 23(Opus 29), iOS 12.0. 앱의 안드로이드 `minSdk`는 Flutter 기본 24(`flutter_tools/gradle/.../FlutterExtension.kt` `minSdkVersion: Int = 24`), `record_android`는 24 [확인].

### 3.2 Chrome의 MediaRecorder 실측 [확인]

`/tmp/claude-0/plan57-scratch/chrome/mime.html`을 헤드리스 Chrome 153(리눅스)에서 `--dump-dom`으로 실행.

| MIME | `MediaRecorder.isTypeSupported` | `<audio>.canPlayType` |
|---|---|---|
| `audio/mp4` | true(코덱 미지정 — opus를 mp4에 넣음) | maybe |
| `audio/mp4;codecs=mp4a` | false | "" |
| `audio/mp4;codecs=mp4a.40.2` (AAC-LC) | **false** | probably |
| `audio/mp4;codecs=opus` | true | probably |
| `audio/aac` | false | probably |
| `audio/webm;codecs=opus` | **true** | probably |
| `audio/ogg;codecs=opus` | false | probably |

같은 결과로 `record_web`의 `isEncoderSupported`: `aacLc·aacEld·aacHe·amrNb·amrWb·flac = false`, `opus·wav·pcm16bits = true`(5.2 시험 로그). `record_web`은 `aacLc`에 `audio/mp4;codecs=mp4a`, `audio/mp4;codecs=mp4a.40.2`, `audio/aac`만 시도하고 코덱 없는 `audio/mp4`는 시도하지 않는다(`record_web-2.1.3/lib/src/mime_types.dart`) [확인]. 다른 OS의 Chrome(Windows·macOS·Android)이 AAC 녹음을 지원하는지는 [추측 — 플랫폼 인코더에 따라 다르다고 알려져 있으나 확인 못 함].

### 3.3 iPad Safari

- Safari는 14.1부터 MediaRecorder를 지원하고 오디오는 `audio/mp4`(AAC)를 낸다(WebKit 블로그 <https://webkit.org/blog/11353/mediarecorder-api/>). [문서]
- `record` README의 브라우저 표: Safari에서 `aacLc` ✔, `opus` ✘. [문서]
- Safari 18.4부터 WebM/Opus 녹음이 된다는 2차 출처가 있다(<https://addpipe.com/media-recorder-api-demo/>). Ogg/Opus는 18.4에서도 실패한다는 보고가 있다(<https://frequal.com/java/OggOpusStillNotWorkingInSafari18_4.html>). 버전으로 가르지 말고 **실행 중 `isTypeSupported`로 고르라**는 것이 공통 권고다. [문서(2차 출처)]
- `record_web`은 `MediaRecorder.start(200)`(200 ms마다 조각)로 녹음한다. Safari가 이때 조각난(fragmented) MP4를 내고, 그 파일을 `just_audio`(웹 `<audio>`, iOS AVPlayer, 안드로이드 ExoPlayer)가 유한한 길이로 읽는지는 [추측 — 실기기 확인 항목 D2].

### 3.4 교차 재생 (어디서 녹음한 파일을 어디서 들을 수 있나)

| 녹음한 곳 → 형식 | iOS 네이티브(AVPlayer) | 안드로이드(ExoPlayer) | iPad Safari | Chrome |
|---|---|---|---|---|
| iOS 네이티브 `aacLc` → m4a | ✔ | ✔ | ✔ | ✔ |
| 안드로이드 `aacLc` → m4a | ✔ (`record` 7.1.0 변경 기록 "AAC encoding from Android now provides a stricter output. iOS should now be able to read those files") | ✔ | ✔ | ✔ |
| iPad Safari `aacLc` → mp4(AAC) | ✔ [추측 D2] | ✔ [추측] | ✔ | ✔ |
| Chrome `opus` → webm | **✘** (AVFoundation은 WebM 미지원) | ✔ | Safari 버전에 따라 [추측] | ✔ (실측 재생, 5.2) |

결론: **동기화해서 여러 기기에서 들을 녹음은 AAC-LC(MPEG-4)로 통일**한다. 크롬 데스크톱 녹음은 개발·시험용으로만 보고, 저장할 때 `Asset.mimeType`에 실제 MIME(`MediaRecorder.mimeType`)을 남겨 재생 가능 여부를 판단할 수 있게 한다(12.3). [추측 — 설계 판단]

### 3.5 용량 (AAC-LC 모노, 계산)

| 비트레이트 | 1시간 | 3시간 강의 |
|---|---|---|
| 32 kbps | 14.4 MB | 43 MB |
| 48 kbps | 21.6 MB | 65 MB |
| 64 kbps | 28.8 MB | 86 MB |

`record` 기본값은 `aacLc`, 128 kbps, 44.1 kHz, **2채널**이다(`record_config.dart`) [확인]. 음성에는 모노·48~64 kbps면 충분하다고 본다 [추측]. iOS AAC 인코더가 표본율·채널별로 허용하는 비트레이트 범위가 있으므로 실제 적용값은 `setOnConfigChanged`로 받아 기록한다(7.1.0 "Native platforms now eagerly clamp to device and codec capabilities") [문서]. SYNC 업로드 상한 300 MiB(01-hooks 3.9)에는 여유가 있다.

---

## 4. 백그라운드 녹음

### 4.1 iOS [문서 + 확인(소스)]

- `record` 문서(<https://github.com/llfbandit/record/blob/main/doc/bg_recording.md>): Info.plist에 `UIBackgroundModes`로 `audio`(+`fetch`)를 넣으면 된다. `AudioInterruptionMode.pauseResume`을 쓰려면 `mixWithOthers` 옵션이 필요하다.
- `NSMicrophoneUsageDescription` 필수(README).
- `record_ios`는 파일 녹음에 `AVAudioRecorder`를 쓰고, 시작 때 세션을 `.playAndRecord` + 옵션(기본 `defaultToSpeaker`·`allowBluetooth`·`allowBluetoothA2DP`)으로 정하고 `setActive(true, .notifyOthersOnDeactivation)`한다. **정지 때 세션을 비활성화하지 않는다**(`RecorderSessionExtension.swift` 11–20·44–56, `Recorder.swift` 115) [확인]. 다른 앱의 음악을 다시 틀게 하려면 앱이 정지 뒤 `setActive(false)`를 불러야 한다.
- 중단(전화·Siri·FaceTime): 기본 `AudioInterruptionMode.pause` → 녹음기가 일시정지 상태가 되고 상태 스트림에 `pause`가 온다. 자동 재개(`pauseResume`)는 시스템의 `shouldResume` 플래그를 따른다(7.0 변경 기록) [확인(소스)].
- 현재 앱 템플릿: `app/ios/Runner/Info.plist`에 `UIBackgroundModes`·`NSMicrophoneUsageDescription` 없음, 배포 대상 iOS 15.0, `SceneDelegate` 사용(UIScene 수명주기) [확인]. INFRA 소유 파일이다.

### 4.2 안드로이드 [문서 + 확인]

- `record` 7.0.0 변경 기록: "**Breaking change** Remove background recording service. See docs" → 앱이 포그라운드 서비스를 따로 띄워야 한다. 문서는 `flutter_foreground_task`와 예제(`flutter_foreground_task_example/record_service`)를 권한다 [확인(CHANGELOG)·문서].
- 안드로이드 14(API 34)+ 규칙(<https://developer.android.com/develop/background-work/services/fg-service-types#microphone>): 매니페스트 `android:foregroundServiceType="microphone"`, 권한 `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_MICROPHONE`, `startForeground()`에 `FOREGROUND_SERVICE_TYPE_MICROPHONE`, **`RECORD_AUDIO` 런타임 허가가 먼저 있어야 함**, "`RECORD_AUDIO`는 while-in-use 제한 대상이라 **앱이 백그라운드일 때 microphone 서비스를 만들 수 없고** `BOOT_COMPLETED`에서도 시작할 수 없다" [문서].
- 안드로이드 13+는 알림 표시에 `POST_NOTIFICATIONS` 런타임 허가가 필요하다(`flutter_foreground_task` README 4단계) [문서].
- 예제 앱 매니페스트(확인함): `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MICROPHONE`, `RECORD_AUDIO`, `<service android:name="com.pravera.flutter_foreground_task.service.ForegroundService" android:foregroundServiceType="microphone" android:exported="false"/>` [확인(원격 파일)].
- `flutter_foreground_task` 11.0.3의 라이브러리 매니페스트가 합쳐 넣는 것: `FOREGROUND_SERVICE`, `WAKE_LOCK`, `RECEIVE_BOOT_COMPLETED`, `POST_NOTIFICATIONS`, 부팅 수신기(`RebootReceiver`, `exported="true"`), `RestartReceiver` [확인(`android/src/main/AndroidManifest.xml`)]. 부팅 자동 시작을 쓰지 않으면 매니페스트 병합 `tools:node="remove"`로 뺄 수 있다 [추측 — 일반적인 Gradle 매니페스트 병합 방법].
- 빌드 도구: 앱은 AGP 9.1.0·Gradle 9.3.1·Kotlin 2.4.0(`app/android/settings.gradle.kts`), `record_android 2.2.0`의 자체 buildscript는 AGP 9.2.1·Kotlin 2.3.20, compileSdk 36, minSdk 24 [확인]. 컨테이너에 Android SDK가 없어 APK 빌드는 CI `android.yml`에서만 확인할 수 있다 [확인(INFRA 워크플로 주석)].

### 4.3 웹 (iPad Safari)

- 백그라운드 녹음은 웹에서 기대할 수 없다. WebKit 버그 보고들: 백그라운드에서 음소거된 캡처 탭은 되살릴 수 없고 탭을 닫았다 열어야 한다(<https://bugs.webkit.org/show_bug.cgi?id=173268>), iOS에서 `getUserMedia` 오디오 트랙이 음소거되면 페이지가 풀 방법이 없다(<https://bugs.webkit.org/show_bug.cgi?id=218815>), 통화 뒤 마이크가 조용해짐(<https://bugs.webkit.org/show_bug.cgi?id=208209>). 화면 잠금 때 MediaRecorder가 계속 도는지 밝힌 출처는 찾지 못했다 [문서(검색 요약) — bugs.webkit.org는 이 세션 네트워크에서 직접 열리지 않아 검색 결과 요약으로만 봄].
- 대응 [추측 — 설계 제안]: ① 녹음 중 `document.visibilityState == 'hidden'`이 되면 **앱이 먼저 `pause()`**하고 녹음 시계도 멈춘다(무음이 섞이거나 시각이 어긋나는 것을 막음). 돌아오면 '이어서 녹음' 안내. ② 녹음 중 **Screen Wake Lock**(`navigator.wakeLock.request('screen')`)으로 화면 꺼짐을 막는다 — 헤드리스 Chrome에 `navigator.wakeLock`이 있음 [확인], `package:web` 1.1.2에 바인딩 있음(`screen_wake_lock.dart`) [확인], Safari 지원은 [추측 — 16.4부터로 알려짐, 실기기 확인 D4]. ③ 오디오 트랙 `mute`/`ended` 이벤트를 감시해 녹음이 끊겼음을 알린다.
- 탭이 닫히거나 Safari가 페이지를 버리면 `record_web`이 메모리에 모은 조각(200 ms마다 `Blob`)은 사라진다(`media_recorder_delegate.dart` `_chunks`) [확인]. 끊김에 강하게 하려면 MediaRecorder 조각을 IndexedDB에 바로 쓰는 자체 웹 녹음기가 필요하다(12.6 선택안) [추측].

---

## 5. 재생 — 위치 정밀도 · 속도 · 탐색

### 5.1 `just_audio`의 위치 계산 [확인 — `just_audio-0.10.6/lib/just_audio.dart` 671–760]

```dart
Duration get position => _getPositionFor(playbackEvent);
// playing && ready:  updatePosition + (DateTime.now() - updateTime) * speed
```

- 플랫폼은 상태가 바뀔 때·주기적으로 `(updatePosition, updateTime)`을 보내고, Dart가 그 사이를 외삽한다. **매 프레임 `player.position`을 읽어도 플랫폼 호출이 없다.**
- `positionStream`은 16~200 ms 주기(곡 길이 / 800, 하한 16 ms·상한 200 ms), `createPositionStream(minPeriod, maxPeriod)`로 바꿀 수 있다. 획 강조는 `Ticker`에서 `position`을 직접 읽는 편이 낫다 [추측 — 설계 판단].
- iOS: `seekToTime:toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero`(정확 탐색, `UriAudioSource.m` 158). 재생 중 실제 위치가 기대값보다 100 ms 넘게 뒤처지면 버퍼링으로 보고 위치를 다시 보낸다(`AudioPlayer.m` 300–325) [확인].
- 속도: iOS `_player.rate = speed`, 항목마다 `audioTimePitchAlgorithm = AVAudioTimePitchAlgorithmTimeDomain`(음성에 맞는 음높이 보존, `UriAudioSource.m` 77). 안드로이드 `setPlaybackParameters(new PlaybackParameters(speed, pitch))`(media3). 웹 `audioElement.playbackRate`(`just_audio_web.dart` 334) [확인]. iOS 소스 주석: 1.0~2.0은 `canPlayFastForward`와 무관하게 허용(Apple QA1772 인용) [확인(주석)].

### 5.2 Chrome 실측 [확인]

시험: `/tmp/claude-0/plan57-scratch/audio_probe/test/web_audio_probe_test.dart`, 결과 로그 `audio_probe/web_audio_probe_result.log`. 가짜 마이크로 opus 녹음 1초 → 일시정지 1초 → 1초 더 녹음 → 정지 → blob URL을 `just_audio`로 열기.

| 항목 | 결과 |
|---|---|
| `hasPermission()` | true(가짜 UI 플래그로 자동 허가) |
| 상태 이벤트(스톱워치 기준) | `record@30ms, pause@1034ms, record@2038ms, stop@3050ms` (1회차는 40/1047/2057/3071) |
| `stop()` 반환 | `blob:http://localhost:…/…`(웹은 `path` 인자를 무시하고 객체 URL을 돌려줌) |
| 파일 | 12,406 B, 머리 `1a 45 df a3`(EBML = WebM) |
| `setUrl(blob)` 길이 | **2,009 ms**(1회차 2,024 ms) — 일시정지 1초 제외, `record_web`이 WebM Duration을 고쳐 넣음(`webm_duration_fixer.dart`) |
| 2배속 위치(벽시계 ms : 위치 증가 ms) | `50:72, 109:188, 159:290, 210:390, 260:492, 317:604, 367:706, 418:806` → 기울기 (806−72)/(418−50) ≈ **1.99** |
| `positionStream` 이벤트 | 약 0.5초에 29건(≈ 16 ms 주기) |
| `seek(700 ms)` 직후 위치 | 704 ms / 712 ms |
| 상태 이벤트 기준 활성 시간 vs 파일 길이 | (1034−30)+(3050−2038) = 2,016 vs 2,009 → **+7 ms**, 1회차 2,021 vs 2,024 → −3 ms |

주의: `flutter test --platform chrome`은 앱의 웹 플러그인 등록기를 돌리지 않아 시험에서 `RecordPluginWeb.registerWith(webPluginRegistrar)`·`JustAudioPlugin.registerWith(...)`를 직접 불러야 했다(안 부르면 `hasPermission()`이 끝나지 않음). 또 시험 서버는 패키지 에셋을 내주지 않아 `wav`(AudioWorklet) 녹음은 `record.worklet.js` 404로 실패한다 — 실제 빌드에는 파일이 있다(2.3) [확인].

### 5.3 음원 공급 방법 [확인(소스) + 추측(선택)]

| 방법 | 웹 | 네이티브 | 판단 |
|---|---|---|---|
| `setUrl(blobUrl)` | ✔ 실측. `AssetStore.readBytes` → `Blob` → `URL.createObjectURL` | — | 웹 권장. 다 쓰면 `revokeObjectURL` |
| `setFilePath(path)` | — | ✔ | 네이티브 권장. 에셋 바이트를 앱 캐시 파일로 한 번 쓰고 재사용 |
| `StreamAudioSource` | 바이트 전체를 **base64 `data:` URL**로 바꿈(`just_audio.dart` 3297–3316) — 30 MB 녹음이면 40 MB 문자열 | 로컬 HTTP 프록시(`localhost`) — 안드로이드 cleartext·iOS ATS 설정 필요(README) | 쓰지 않음 |

---

## 6. 녹음 중 일시정지와 시각 맞추기

### 6.1 계약과 현재 코드 [확인]

- `Stroke.createdAt` = 펜 다운 벽시계 ms(INK `InkCoreServices.nowMillis`), `StrokePoint.t` = `createdAt`부터 ms, `Stroke.recordingOffsetMs` = "ms from recording start to createdAt (point i: + t(i))"(02-core 683, CORE-2-16).
- INK `InkPageController.beginStroke(first, style:, viewScale:, meta: InkStrokeMeta(recordingId, recordingOffsetMs))` — 펜 다운 순간 동기적으로 받는다(`ink_page_controller.dart` 273–297). 500,000 ms 넘는 긴 획 분할 때 오프셋을 `offset + tb`로 이어 준다(`stroke_builder.dart` 312–316).
- `Recording(id, noteId, assetId, durationMs, startedAt, …)` — 보정값 필드는 없다.
- EDITOR는 아직 `meta`를 넘기지 않는다(01-hooks 3.5).

### 6.2 시계 기준 [추측 — 설계 제안, 근거는 5.2 실측]

- **오프셋은 '오디오 타임라인 위치'여야 한다.** 일시정지 동안 파일에는 아무것도 쌓이지 않으므로(5.2: 1초 일시정지 → 파일 길이에 포함 안 됨) 벽시계 차(`createdAt − Recording.startedAt`)를 쓰면 일시정지 뒤 획이 모두 늦게 강조된다.
- **녹음 시계(RecordingClock)**: 단조 시계 `Stopwatch`를 녹음기 상태 이벤트(`onStateChanged()`의 `record`/`pause`/`stop`)에 맞춰 시작·멈춤·재개하고 활성 구간을 누적한다. 펜 다운 때 `offsetNowMs()`를 읽어 `InkStrokeMeta`에 넣는다.
  - 근거: 5.2에서 상태 이벤트로 잰 활성 시간과 실제 파일 길이 차가 −3~+7 ms였다(Chrome).
  - 벽시계(`DateTime.now`, `package:clock`의 `clock.now()`)는 NTP 보정으로 뛸 수 있다. `package:clock` 1.1.3의 `clock.stopwatch()`는 `clock.now()` 차로 재는 `ClockStopwatch`라 **단조가 아니다**(`clock.dart` 177) [확인]. 따라서 제품 코드는 `Stopwatch()`를 쓰고, 시험은 시계 팩토리를 주입해 `fake_async`로 돌린다.
- 일시정지 중 쓴 획: 연결하지 않음(`recordingId = null`)과 일시정지 지점에 붙임 중 하나를 정해야 한다(13절 Q4).
- 시스템 중단(전화 등)으로 녹음기가 스스로 `pause`가 되면 상태 스트림을 따라 시계도 멈춘다. 이벤트가 늦게 오는 만큼(수 ms, EventChannel) 오차가 생긴다 [추측].

### 6.3 지연 보정 [추측]

- 남는 오차는 **녹음기 시작 지연**(start 호출 ~ 첫 표본)이다. iOS `AVAudioRecorder.record()`·안드로이드 `AudioRecord`·웹 MediaRecorder 모두 상태 이벤트가 첫 표본보다 앞설 수 있다. Chrome에서는 10 ms 안이었고 네이티브 값은 모른다.
- 제안: ① 정지 때 `오차 = 시계 활성 시간 − 실제 파일 길이`(`just_audio` `setFilePath`/`setUrl`이 돌려주는 길이)를 계산해 개발자 표시에 남긴다. `Recording.durationMs`는 **파일 길이**로 저장한다. ② v1은 보정하지 않고, 재생 강조에 허용 폭을 두고, '필기 탭 → 재생'은 **앞당겨 시작(pre-roll, 예: 1.5초)**한다. 실기기에서 오차가 일정하게 크면(예: 150 ms 이상) 그때 `Recording`에 보정 필드(예: `clockOffsetMs`)를 넣는 계약 변경을 검토한다. 획 수천 개의 `recordingOffsetMs`를 정지 때 고쳐 쓰는 방식은 동기화 변경이 많아 권하지 않는다.
- 펜 이벤트 전달 지연(이벤트 시각 ~ Dart 처리)은 한 프레임 안이다. 웹은 DOM `event.timeStamp`와 `performance.now()`가 같은 기준이라 보정이 가능하지만 네이티브는 기준이 달라 하지 않는다 [추측].

### 6.4 재생 강조 계산 [추측 — 설계 제안]

- 재생 중 매 프레임 `pos = player.position`(5.1 외삽) → 같은 `recordingId`의 획을 `recordingOffsetMs` 오름차순으로 정렬해 두고 이분 탐색으로 '이미 쓴 획'(`offset ≤ pos`)과 '지금 쓰는 획'(`offset ≤ pos < offset + t_last`)을 찾는다. 경계 인덱스가 바뀔 때만 다시 그린다(INK 강조 API는 01-hooks 3.5 '재생 강조' 행).
- 탭 → `seek(max(0, offset − preRoll))` 후 재생.
- 여러 녹음: 재생 바는 한 번에 한 `Recording`, 강조도 그 `recordingId`만.

### 6.5 컨테이너에서 할 수 있는 시험 [확인(가능성) / 추측(구성)]

| 시험 | 방식 | 근거 |
|---|---|---|
| 녹음 시계(시작·일시정지·재개·중단·정지 → 오프셋) | 순수 Dart VM 시험, 가짜 상태 스트림 + `fake_async` | 플랫폼 불필요 |
| 강조 인덱스 계산·탭 → 탐색 위치 | 순수 Dart VM 시험 | 〃 |
| 녹음 → 저장 → 재생 통합(웹) | `flutter test --platform chrome` + 가짜 마이크 Chrome 래퍼(14절) + 웹 플러그인 직접 등록 | 5.2에서 실제로 통과 |
| 펜 버튼 입력 분기 | 위젯 시험에서 `TestPointer(kind: stylus, buttons: kPrimaryStylusButton)`로 합성 | 프레임워크 입력만 씀 |
| 웹 펜 이벤트 경로(호버·버튼) | 빌드한 웹 앱 + Playwright CDP `Input.dispatchMouseEvent(pointerType: 'pen')` | 8.4에서 실제로 실행 |

---

## 7. 오디오 세션 · 권한

### 7.1 세션 [확인(소스) + 추측(권장)]

- `just_audio`는 `audio_session`으로 재생 때 세션을 켜고(`handleAudioSessionActivation: true`), 중단을 처리하고(`handleInterruptions`), 안드로이드 오디오 속성을 적용한다(`androidApplyAudioAttributes`) — 생성자 인자(`just_audio.dart` 214–257).
- `audio_session`의 `AudioSessionConfiguration.speech()`는 iOS `.playback` + `.spokenAudio`, 안드로이드 `contentType: speech, usage: media`(`core.dart` 561–571).
- `record`도 시작 때 세션을 `.playAndRecord`로 바꾼다(4.1). 세션 주인이 둘이면 녹음 → 재생 전환 때 범주가 엉킬 수 있다. `record`는 `AudioRecorder.ios?.manageAudioSession(false)`·`setAudioSessionActive`·`setAudioSessionCategory`를 준다(`record.dart` 185–260) [확인]. 권장: 우리 오디오 모듈이 `audio_session`으로 세션을 혼자 관리(녹음 전 `playAndRecord` + `defaultToSpeaker`·`allowBluetooth`, 정지 뒤 `setActive(false)`, 재생 전 `speech()`), `record`는 `manageAudioSession(false)` [추측 — 실기기 확인 D5].
- 웹: `audio_session`은 설정값만 보관하는 자리, `just_audio`·`record` 모두 브라우저에 맡긴다 [확인(소스)].

### 7.2 권한 [확인(소스) + 문서]

| 권한 | 받는 방법 | 비고 |
|---|---|---|
| 마이크(모든 플랫폼) | `AudioRecorder.hasPermission(request: true)` | iOS Info.plist `NSMicrophoneUsageDescription`, 안드로이드 `RECORD_AUDIO`, 웹 `getUserMedia`(HTTPS 필요 — Firebase Hosting은 HTTPS) |
| 알림(안드로이드 13+) | `FlutterForegroundTask.checkNotificationPermission()` / `requestNotificationPermission()` | 포그라운드 서비스 알림 |
| 영구 거부 → 설정 열기 | (`permission_handler.openAppSettings`) | `permission_handler`를 넣지 않으면 안내 문구로 대체 |

`permission_handler`는 iOS에서 권한마다 Podfile 전처리 매크로(`PERMISSION_MICROPHONE=1` 등)를 켜야 동작한다는 것이 이 패키지의 알려진 설정 요건이고, 앱에는 아직 Podfile이 없다(`app/ios`에 Podfile 없음 — SwiftPM 사용) [확인(Podfile 없음) / 추측(매크로 요건 — 이번에 문서를 다시 열어 보지 않음)]. 마이크·알림은 위 두 패키지로 충분하므로 넣지 않는 쪽을 권한다.

---

## 8. 스타일러스 — Flutter `PointerEvent`가 이미 주는 것

### 8.1 버튼 비트 상수 [확인 — `/opt/flutter/packages/flutter/lib/src/gestures/events.dart` 43–148]

| 상수 | 값 |
|---|---|
| `kPrimaryButton` = `kStylusContact` | 0x01 |
| `kSecondaryButton` = `kPrimaryStylusButton` = `kSecondaryMouseButton` | 0x02 |
| `kTertiaryButton` = `kSecondaryStylusButton` = `kMiddleMouseButton` | 0x04 |

프레임워크 변환기는 터치·스타일러스의 down/move에서 `buttons == 0`일 때만 `kPrimaryButton`을 채워 넣는다(`converter.dart` `_synthesiseDownButtons` 21–35). **버튼 비트가 이미 있으면 접촉 비트를 더하지 않는다.** EDITOR `InputRouter`의 마우스 보조 버튼 검사(`kind == mouse && buttons & kSecondaryMouseButton`)는 종류를 먼저 보므로 펜 버튼과 섞이지 않는다(`input_router.dart` 188) [확인].

### 8.2 안드로이드 엔진 [확인 — `engine/src/flutter/shell/platform/android/io/flutter/embedding/android/AndroidTouchProcessor.java`]

- 스타일러스: `buttons = (event.getButtonState() >> 4) & 0xF` (338–345) → `BUTTON_STYLUS_PRIMARY`(0x20) → 0x02, `BUTTON_STYLUS_SECONDARY`(0x40) → 0x04. 접촉 정보는 버튼 상태에 없으므로 **닿은 채 버튼 = `PointerDownEvent(buttons: 0x02)`**, 버튼 없이 닿음 = 0x01(프레임워크가 채움).
- `TOOL_TYPE_ERASER` → `invertedStylus`(572–576). S펜에는 지우개 끝이 없다 [추측].
- 호버: `onGenericMotionEvent`가 `ACTION_HOVER_MOVE`·`ACTION_SCROLL`만 처리(250–275) → `PointerHoverEvent(kind: stylus)`, `AXIS_DISTANCE` → `distance`(419), `AXIS_ORIENTATION`·`AXIS_TILT`(434–437). 호버 중 버튼 상태도 같은 식으로 `buttons`에 실린다. **`ACTION_BUTTON_PRESS`/`RELEASE`는 처리하지 않는다**(띄운 채 버튼만 눌렀다 떼면 이벤트가 따로 오지 않고 다음 호버 이벤트의 `buttons`로만 보인다).

### 8.3 iOS 엔진 [확인 — `shell/platform/darwin/ios/framework/Source/FlutterViewController.mm`]

- `UITouchTypeStylus`(Apple Pencil) → `kStylus`(1102), `tilt = π/2 − altitudeAngle`(1236), `orientation = azimuthAngleInView − π/2`(1256), `pressure = force`.
- 버튼: `event.buttonMask`의 주 버튼만(마우스·트랙패드용). Apple Pencil에는 버튼이 없다.
- **Pencil 호버**: 엔진의 `UIHoverGestureRecognizer`(758–761)가 받아 `hoverEvent:`에서 **`kind = kMouse`**로 보낸다(2118–2125). 위치만 있고 높이(`zOffset`)·기울기·롤은 없다(`updateMousePointerDataFrom:`). 따라서 네이티브 앱에서는 Pencil 호버와 트랙패드 포인터를 Flutter 이벤트만으로 가를 수 없다.
- `UIPencilInteraction`은 엔진에 없다(01-hooks 3.7과 같음). `rollAngle`도 읽지 않는다.

### 8.4 웹 엔진 + CDP 실측 [확인]

소스(`lib/web_ui/lib/src/engine/pointer_binding.dart`): `pointerType 'pen'` → `stylus`(1334–1341, **`invertedStylus`는 만들지 않음**), `buttons`는 DOM 값을 마스크만 해서 그대로(`_htmlButtonsToFlutterButtons` 917–922), `tilt = max(|tiltX|, |tiltY|)`를 라디안으로(1360–1361), `orientation`·`distance`는 0, `twist`는 읽지 않음, `getCoalescedEvents` 사용(1317).

실측: `audio_probe/lib/pointer_probe.dart`(모든 `PointerEvent`를 콘솔에 한 줄로) → `flutter build web --no-web-resources-cdn` → Playwright CDP `Input.dispatchMouseEvent(pointerType: 'pen', tiltX: 30, tiltY: 10, force: 0.6, buttons: …)`. 로그: `/tmp/claude-0/plan57-scratch/cdp/cdp_run_final.log`.

| 흉내 낸 동작(DOM에서 본 이벤트) | Flutter가 받은 것 |
|---|---|
| 펜 띄움(`pointermove buttons=0`) | `hover kind=stylus buttons=0x0` |
| 펜 닿음 → 이동 → 뗌(`pointerdown buttons=1` …) | `down 0x1 pressure 0.60 tilt 0.524`, `move 0x1`, `up 0x0`; `orientation 0` |
| **띄운 채 배럴 버튼 누름**(`pointerdown button=2 buttons=2`) | **`down kind=stylus buttons=0x2`** — 닿기 전에 down |
| 버튼 누른 채 닿음(`pointermove button=0 buttons=3`, 겹친 버튼이라 down이 아님) | `move buttons=0x3` |
| 닿음 뗌(버튼은 유지, `pointermove buttons=2`) → 버튼 뗌(`pointerup`) | `move 0x2` → `up 0x0` |
| 닿은 채 획 중간에 버튼 누름/뗌 | `move 0x1 → 0x3 → 0x1`, `up` |
| 버튼 상태로 `pointermove`만 보냄(down 없이 `buttons=2`) | `hover buttons=0x0` — 엔진이 '누른 적 없는 버튼'을 버림(`sanitizeMoveEvent` 947–955) |

정리: **웹에서 '닿음'은 `buttons & kStylusContact(0x01)`로 판정해야 하고, 네이티브 안드로이드는 down 자체가 닿음이다.** EDITOR가 지금처럼 `PointerDownEvent`에서 바로 획을 시작하면, 웹(안드로이드 Chrome + S펜 등)에서 버튼을 먼저 누른 사용자는 공중에서 획(또는 지우기)이 시작된다. iPad Safari의 Apple Pencil은 버튼이 없어 해당하지 않는다. CDP 흉내와 실제 기기 이벤트 순서가 같은지는 [추측 — 실기기 D7].

---

## 9. Apple Pencil — 더블탭 · 스퀴즈 · 배럴 롤 · 호버 (네이티브)

### 9.1 UIKit API [문서 + 확인(플러그인 소스에서 사용 확인)]

| 기능 | API | iOS | 출처 |
|---|---|---|---|
| 더블탭 | `UIPencilInteraction` + `UIPencilInteractionDelegate.pencilInteractionDidTap(_:)`(12.1+), 17.5+는 `pencilInteraction(_:didReceiveTap:)`(`UIPencilInteraction.Tap`: `timestamp`, `hoverPose`) | 12.1 / 17.5 | <https://developer.apple.com/documentation/uikit/uipencilinteraction> |
| 스퀴즈(Pencil Pro) | `pencilInteraction(_:didReceiveSqueeze:)`, `Squeeze.phase`(began·changed·ended·cancelled), `hoverPose` | 17.5 | <https://developer.apple.com/documentation/applepencil/handling-squeezes-from-apple-pencil> |
| 사용자 기본 동작 | `UIPencilInteraction.preferredTapAction` / `preferredSqueezeAction`(`ignore, switchEraser, switchPrevious, showColorPalette, showInkAttributes, showContextualPalette, runSystemShortcut`) | 12.1 / 17.5 | 같은 곳. Apple 예제는 `showContextualPalette`이고 단계가 `ended`일 때 `hoverPose.location`에 팔레트를 띄움 |
| 호버 자세 | `UIPencilHoverPose`: `location`, `zOffset`, `altitudeAngle`, `azimuthAngle`, `rollAngle`(롤 미지원 펜은 0) | 17.5 | <https://developer.apple.com/documentation/uikit/uipencilhoverpose> |
| 호버 추적 | `UIHoverGestureRecognizer`(`allowedTouchTypes = [.pencil]`): `zOffset`(16.1), `altitudeAngle`(16.4), `rollAngle`(17.5) | 16.1+ | <https://developer.apple.com/documentation/uikit/adopting-hover-support-for-apple-pencil> |
| 쓰는 중 배럴 롤 | `UITouch.rollAngle` | 17.5 | Apple Pencil 업데이트 문서(검색 요약) — 9.2 `stylet` 소스가 실제로 사용 |
| 펜 전용 그리기 설정 | `UIPencilInteraction.prefersPencilOnlyDrawing` | 14.0 | [추측 — 이번에 문서를 다시 열지 않음] |

`stylet` iOS 소스가 위 API를 `#available(iOS 16.1/16.4/17.5)`로 나눠 쓰는 것을 확인했다(`StyletPlugin.swift` 146–283·464–622) [확인].

### 9.2 기존 플러그인 [확인 — 소스를 내려받아 읽음]

| | `apple_pencil_double_tap` 2.0.0 | `flutter_apple_pencil` 1.0.0 | `stylet` 0.1.4 |
|---|---|---|---|
| 게시 | 2026-10-20, 7개 버전, 좋아요 12, 30일 359회 | 2025-10-03, 1개 버전 | 2026-10-08(첫 공개 2026-08-25), 좋아요 0, 30일 34회 |
| SDK | Dart ≥ 3.13, Flutter ≥ 3.47, iOS 15 | Dart ≥ 3.0 | Dart ≥ 3.13, Flutter ≥ 3.47, iOS 15 |
| 플랫폼 | iOS만(SwiftPM + CocoaPods) | iOS만 | android·ios·linux·macos·web·windows |
| 기능 | 더블탭(17.5+ `hoverPose`의 x·y·z 포함), 스퀴즈(단계·선호 동작·x·y·z) | 더블탭·스퀴즈 | 압력·기울기·배럴 롤·호버(높이)·측면 버튼·더블탭·스퀴즈·예측 표본·추정값 보정 |
| 구조 | Swift 약 170줄. 정적 델리게이트, `MethodChannel` 하나, 등록 때 키 윈도의 루트 VC 뷰에 `UIPencilInteraction`을 붙이고 없으면 `didBecomeKeyNotification`을 기다림 | — | Swift 625줄·Kotlin 675줄·웹 618줄. `EventChannel`, 수동 관찰 제스처 인식기(`cancelsTouchesInView = false`) + `UIHoverGestureRecognizer` + `UIPencilInteraction` |
| 웹 | Dart 진입점이 `dart:io`를 import하고 `Platform.isIOS`를 부름 → **웹에서 `listen()`을 부르면 예외**. `kIsWeb` 가드가 필요(probe 코드에 넣어 빌드 통과) | — | 첫 구독 때 DOM 포인터 리스너를 붙임(우리 INK 입력과 이중 처리) |
| 롤 | ✘ | ✘ | ✔ |
| 라이선스 | MIT | — | MIT |

판단 [추측]: `apple_pencil_double_tap`은 작고 읽기 쉬우나 배럴 롤·호버 높이가 없고 사용자가 적다. `stylet`은 기능이 가장 많지만 나온 지 두 달 남짓이고 사용자가 거의 없으며, 우리 INK가 이미 하는 입력 처리와 겹친다. **둘 다 참고 구현으로 삼고, 필요한 것만 담은 작은 iOS 플러그인을 직접 만드는 쪽**이 계약(`StylusExtrasSource`)과 웹 규칙에 맞추기 쉽다(12.5). 직접 만들기 전 임시로 `apple_pencil_double_tap`을 쓰는 것도 가능하다(해석·웹 빌드 확인됨).

### 9.3 직접 만들 플러그인 구조 [추측 — 설계 제안]

```
packages/pencil_bridge/                 # Flutter plugin, iOS only (others: no-op)
├─ pubspec.yaml                         # flutter.plugin.platforms.ios.pluginClass: PencilBridgePlugin
│                                       #   + swiftPackageManager path (SwiftPM) + podspec (CocoaPods)
├─ lib/pencil_bridge.dart               # PencilBridge.events, capabilities(); web-safe (no dart:io:
│                                       #   defaultTargetPlatform == TargetPlatform.iOS && !kIsWeb)
├─ lib/src/pencil_event.dart            # PencilDoubleTap / PencilSqueeze(phase) / PencilHover / PencilRoll,
│                                       #   preferredAction enum, positions in global logical px
├─ ios/pencil_bridge/Package.swift
├─ ios/pencil_bridge/Sources/pencil_bridge/PencilBridgePlugin.swift   (~200 lines)
├─ ios/pencil_bridge.podspec
└─ test/pencil_bridge_test.dart          # mock EventChannel → event decoding (VM, runs in container)
```

Swift 쪽 뼈대:

```swift
public final class PencilBridgePlugin: NSObject, FlutterPlugin, FlutterStreamHandler,
    UIPencilInteractionDelegate {
  // channels: "dev.noteapp/pencil/events" (EventChannel), "dev.noteapp/pencil/methods"
  public static func register(with registrar: FlutterPluginRegistrar) { /* set handlers only */ }
  // Attach on onListen (UIScene template: the key window may not exist at register time):
  //   UIPencilInteraction (delegate = self) + UIHoverGestureRecognizer(.pencil, iOS 16.1+)
  //   + passive UIGestureRecognizer (cancelsTouchesInView = false, delaysTouches* = false)
  //     reading UITouch.rollAngle (iOS 17.5+) while drawing. Detach on onCancel.
  // didReceiveTap (17.5+) / pencilInteractionDidTap (older) → {type: tap, action, x, y, z, t}
  // didReceiveSqueeze (17.5+) → {type: squeeze, phase, action, x, y, z, roll, t}
  // hover → {type: hover, x, y, z, altitude, azimuth, roll (17.5+)}; roll stream throttled
  // methods: capabilities → {os, squeeze: 17.5+, hover: 16.1+, prefersPencilOnlyDrawing,
  //          preferredTapAction, preferredSqueezeAction}
}
```

- 좌표: `FlutterViewController.view`가 전체 화면이면 UIKit pt = Flutter 논리 px(전역)이다. 계약 `StylusSqueeze.hoverPosition`이 "global logical px"이므로 그대로 맞는다 [추측].
- 롤과 획 점의 대응: 네이티브 `UITouch`와 Flutter `PointerEvent`를 표본 단위로 짝짓는 것은 어렵다(`stylet`은 식별자·시각·위치로 짝지음). 캘리그래피 각도는 천천히 변하므로 **가장 최근 롤 값을 획 점에 적용**하는 근사로 충분하다고 본다(계약 `StylusBarrelRoll(angle)`이 이 모양) [추측].
- 안드로이드 쪽 Kotlin은 필요 없다(10절). 안드로이드 포그라운드 서비스도 `flutter_foreground_task`를 쓰면 이 플러그인에 넣을 이유가 없다.
- 앱 셸 연결: 플러그인은 자체 이벤트 타입만 내고, INFRA가 `stylusExtrasProvider`를 이 플러그인을 감싼 어댑터로 override한다(플러그인이 `feature_editor`에 의존하지 않게 — 계약 7.1 규칙 1과 같은 방향) [추측].

### 9.4 검증 한계 [문서 + 추측]

- 사용자 기기 iPad Pro 13"은 [추측] M4 이후 모델이라 Apple Pencil Pro 또는 Apple Pencil(USB-C)만 쓴다. USB-C 펜슬이면 필압·더블탭·스퀴즈·배럴 롤이 없다(PLAN 11장 질문 1이 아직 열려 있음, 13절 Q1).
- Mac이 없어 Xcode 무료 서명 설치도 못 한다. 유료 계정 전에는 GitHub Actions macOS에서 `flutter build ios --no-codesign`으로 **컴파일만** 확인할 수 있다(INFRA `ios-testflight.yml`이 이 명령을 쓰는 초안, macOS 러너는 10배 과금) [확인(워크플로 파일)].
- 따라서 Swift 코드의 동작 확인(더블탭·스퀴즈·롤·호버 높이)은 계정 가입·TestFlight 이후다. 이번 라운드에서 할 수 있는 것은 Dart 쪽(이벤트 디코딩, 동작 매핑, 설정) 시험과 컴파일 확인이다.

---

## 10. S펜 측면 버튼 (안드로이드)

- Flutter만으로 받는다(8.2): 닿은 채 버튼 = `PointerDownEvent(kind: stylus, buttons: 0x02)`, 띄운 채 버튼 = `PointerHoverEvent(buttons: 0x02)`. 플러그인이 필요 없다 [확인(엔진 소스)].
- 일반 안드로이드 펜 API 설명(`getButtonState`가 `BUTTON_STYLUS_PRIMARY`·`SECONDARY` 비트를 줌): <https://learn.microsoft.com/en-us/dual-screen/android/platform/pen> [문서].
- **삼성 기기 주의** [문서(포럼) + 추측]: 펜을 띄운 채 버튼을 누르면 시스템 'Air command'가 뜬다(설정에서 끌 수 있음). Galaxy Tab S9 FE+에서 측면 버튼 눌림이 앱의 터치·호버 처리기 어디에도 오지 않았다는 개발자 보고가 있다(<https://forum.developer.samsung.com/t/galaxy-tab-s9-fe-cant-get-any-spen-specific-events/38112>). 삼성은 버튼 이벤트를 'S Pen Remote SDK'로 주는 길도 문서화한다(<https://developer.samsung.com/s-pen-sdk/sdk>, Flutter 래퍼 `spen_remote` 0.0.4). 반면 Squid 같은 노트 앱은 '버튼을 누른 채 쓰면 지우개'를 지원한다(<https://help.squidnotes.com/article/709-what-can-i-do-with-my-pen-side-button>). 기종·설정마다 다를 수 있으므로 실기기 확인(D6)이 필요하다.
- 권장 동작 모델: **버튼을 누른 채 쓰는 동안만 임시 지우개**(펜 다운 때 버튼 비트가 있으면 지우개 세션). 띄운 채 한 번 누르기(토글)는 Air command와 겹치고 엔진이 `ACTION_BUTTON_PRESS`를 넘기지 않으므로 기본값으로 쓰지 않는다 [추측].
- 웹(안드로이드 Chrome)에서는 8.4의 '공중 down' 때문에 접촉 비트로 판정해야 한다.

---

## 11. 웹 우선 테스트 관점 — 되는 것 / 안 되는 것

| 기능 | iPad Safari(웹) | 데스크톱 Chrome(웹) | 안드로이드 APK | iOS 네이티브 | 컨테이너 시험 |
|---|---|---|---|---|---|
| 녹음(앞에 있을 때) | ✔ AAC/mp4 [문서] | ✔ opus/webm(AAC ✘) [확인] | ✔ AAC/m4a [문서] | ✔ AAC/m4a [문서] | Chrome 가짜 마이크로 통합 시험 ✔ [확인] |
| 녹음 일시정지·재개 | ✔ [추측] | ✔ [확인] | ✔ [문서] | ✔ [문서] | ✔ |
| 백그라운드·화면 꺼짐 녹음 | ✘(멈추거나 무음, 되살릴 수 없음) [문서] | 탭 숨김 시 [추측] | ✔ 포그라운드 서비스 [문서] | ✔ `UIBackgroundModes audio` [문서] | ✘ |
| 재생·0.5~2배속·탐색 | ✔ `<audio>` [추측] | ✔ [확인] | ✔ [문서] | ✔ [문서] | ✔ Chrome |
| ms 단위 위치(외삽) | ✔ [추측] | ✔ [확인] | ✔ [확인(소스)] | ✔ [확인(소스)] | ✔ |
| 녹음 중 화면 꺼짐 방지 | Wake Lock [추측 D4] | ✔ API 있음 [확인] | 불필요 | 불필요 | — |
| Pencil 필압·기울기 | ✔ 기울기는 tiltX·tiltY 중 절댓값이 큰 쪽, 방위 0 [확인(엔진)] | (펜 없음) | — | ✔ 방위 포함 | 합성 이벤트 ✔ |
| Pencil 호버 위치 | ✔ `kind: stylus` 호버 [확인(CDP 흉내) / 추측(Safari가 pen 호버 `pointermove`를 보냄 — WebKit 담당자가 "we already dispatch hover events for Apple Pencil hover"라 했다는 검색 요약, <https://bugs.webkit.org/show_bug.cgi?id=296943>)] | — | — | △ `kind: mouse`, 높이 없음 [확인(엔진)] → 플러그인 | CDP ✔ |
| Pencil 호버 높이·기울기 | ✘(호버 중 기울기·롤 없음 — 같은 WebKit 보고 요약) | — | — | 플러그인 | — |
| 더블탭·스퀴즈 | ✘(웹 API 없음. Apple 포럼 질문에 답 없음 <https://developer.apple.com/forums/thread/760238>) [추측] | — | — | 플러그인 | Dart 디코딩만 |
| 배럴 롤 | ✘(Flutter 웹 엔진이 `twist`를 안 읽음) [확인] | ✘ | (S펜 없음) | 플러그인 | — |
| S펜 측면 버튼 | — | 펜 버튼 비트 ✔(공중 down 주의) [확인(CDP)] | ✔ 0x02 [확인(엔진)] | — | 위젯 시험 ✔ |

---

## 12. 권장안

### 12.1 패키지 · 버전 고정안

| 패키지 | 버전 | 쓰는 곳(제안) | 근거 |
|---|---|---|---|
| `record` | 7.1.2 | 오디오 모듈 | 2.2·2.3·5.2 |
| `just_audio` | 0.10.6 | 오디오 모듈 | 2.2·5.1·5.2 |
| `audio_session` | 0.2.4 | 오디오 모듈 | 7.1 (`just_audio`의 간접 의존이기도 함) |
| `flutter_foreground_task` | 11.0.3 | 오디오 모듈의 `*_native.dart`, 안드로이드에서만 호출 | 4.2 |
| (선택·임시) `apple_pencil_double_tap` | 2.0.0 | 직접 플러그인 전까지 | 9.2. `kIsWeb` 가드 필수 |
| 간접(잠금으로 고정) | `record_web 2.1.3`, `record_android 2.2.0`, `record_ios 2.1.1`, `record_platform_interface 2.1.0`, `just_audio_web 0.4.16`, `just_audio_platform_interface 4.6.0`, `shared_preferences 2.5.6` 외 | — | 2.2 |

넣지 않음: `audioplayers`, `flutter_sound`/`taudio`, `permission_handler`, `stylet`(참고만), `just_audio_background`.

`record 7.1.2`는 게시 27일, `apple_pencil_double_tap 2.0.0`은 16일이 지났다. 나머지는 2개월 이상이다.

### 12.2 패키지 구조 [추측 — 소유 영역은 총괄이 정함]

- **오디오 모듈**(예: `packages/note_audio`, Flutter 패키지, 의존 `note_core`): 녹음 서비스(`record`·세션·포그라운드 서비스·웹 가시성/Wake Lock), 재생 서비스(`just_audio`, 음원 공급 5.3), 녹음 시계(순수 Dart), 저장(`AssetStore.put(bytes, type: audio, mimeType)` + `Recording` 생성 — CORE API 추가 필요, 01-hooks 3.5). 플랫폼 분리는 계약 7.4.3대로 `*_browser.dart`(blob URL·`visibilitychange`·Wake Lock)와 `*_native.dart`(`path_provider` 임시 파일·`dart:io` 파일 읽기·`flutter_foreground_task`).
- EDITOR는 플러그인에 직접 의존하지 않고 **소비 쪽 포트**(녹음 제어·재생 제어 인터페이스 + provider 자리 + 가짜 구현)를 정의하고, 앱 셸이 오디오 모듈 구현으로 override한다(7.3.3 방식). 그래야 EDITOR 위젯 시험이 플러그인 없이 돈다.
- **펜 플러그인**(예: `packages/pencil_bridge`, iOS 전용 Flutter 플러그인): 9.3. 앱 셸이 `stylusExtrasProvider`를 어댑터로 override.
- 새 패키지는 INFRA `tool/workspace_rules.yaml` `allowed_dependencies`(R8)와 7.1 표에 추가해야 한다.

### 12.3 녹음 설정값 [추측]

```dart
// native (iOS / Android)
const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1, sampleRate: 44100,
    bitRate: 64000, audioInterruption: AudioInterruptionMode.pause)   // file: <tmp>/<recordingId>.m4a
// web: aacLc if isEncoderSupported(aacLc) (Safari) else opus (Chrome/Firefox, webm)
```

- 저장 `Asset.mimeType`: 네이티브 `audio/mp4`, 웹은 `MediaRecorder`가 실제로 쓴 값(`record_web`은 정지 결과를 blob URL로만 주므로 `fetch(url)` 응답의 `Blob.type` 또는 `Response` 헤더에서 얻음 [추측 — `Blob` 생성 때 `mimeType`을 넣는 것은 확인함, `media_recorder_delegate.dart` 197–200]).
- 웹에서 opus(webm)로 녹음하면 'iPad 앱에서 재생되지 않을 수 있음' 표시를 남긴다(13절 Q3).
- 비트레이트는 설정으로 32/48/64 kbps 중 고르고 기본 64. 실제 적용값은 `setOnConfigChanged`로 기록.

### 12.4 시각 맞추기 설계 [추측 — 6절 요약]

1. 녹음 시계: 단조 `Stopwatch`, 녹음기 상태 이벤트로 멈춤·재개, 활성 시간 누적. 시계 팩토리 주입(시험은 `fake_async`).
2. 펜 다운(녹음 중) → `InkStrokeMeta(recordingId, clock.offsetNowMs())`. 일시정지 중 획 처리는 Q4.
3. 정지 → 파일 길이를 `Recording.durationMs`로, `오차 = 시계 − 파일`을 개발자 표시에. v1은 보정하지 않음.
4. 재생 → `Ticker`에서 `player.position`, 정렬된 오프셋에 이분 탐색, 경계가 바뀔 때만 다시 그림.
5. 탭 → `seek(offset − preRoll)`(기본 1.5초, 설정 가능 여부는 Q5).

### 12.5 스타일러스 계약 확장 제안 [추측 — 계약 7.2.17 변경, EDITOR 소유]

현재: `StylusDoubleTap()`, `StylusSqueeze({hoverPosition})`, `StylusBarrelRoll(angle)`, `StylusExtrasSource(isSupported, events)`.

| 제안 | 이유 |
|---|---|
| `StylusDoubleTap({preferredAction, hoverPosition})` | 사용자의 시스템 설정 '더블탭 동작'을 따르는 것이 기본이어야 함(Apple 권고), 17.5+는 위치도 옴 |
| `StylusSqueeze({phase, preferredAction, hoverPosition})` | 스퀴즈는 단계가 있음. Apple 예제는 `ended`에서 팔레트를 띄움 |
| `StylusHoverPose({position, height, altitude, azimuth, roll})` (새 하위 타입) | 네이티브 iOS는 Flutter 호버가 `kind: mouse`이고 높이가 없음(8.3). PLAN '호버 미리보기'에 필요 |
| `enum StylusPreferredAction { ignore, switchEraser, switchPrevious, showColorPalette, showInkAttributes, showContextualPalette, runSystemShortcut, unknown }` | UIKit 값과 1:1 |
| `StylusExtrasSource`에 `capabilities`(squeeze·hover·roll 지원, `prefersPencilOnlyDrawing`) | 설정 화면에서 지원하지 않는 항목 숨김, '펜 전용 모드' 기본값 |

`StylusExtraEvent`가 sealed이므로 하위 타입 추가는 다른 패키지의 exhaustive switch를 깰 수 있다(01-hooks 표기로 '깨짐'). 지금 구독하는 곳이 없어 실제 영향은 없다 [확인(01-hooks 3.7)].

S펜·웹 펜 버튼은 이 인터페이스가 아니라 EDITOR `InputRouter` 안에서 처리한다(`PointerEvent.buttons`) — 계약 변경 없음. 판정 규칙: 네이티브는 down = 닿음, 웹은 `buttons & kStylusContact != 0` = 닿음, 버튼 = `buttons & kPrimaryStylusButton != 0`, `invertedStylus` = 지우개.

### 12.6 이번 라운드에 넣을 것 / 미룰 것 [추측]

| 항목 | 이번 라운드(웹·컨테이너에서 완료 판정 가능) | 미룸 |
|---|---|---|
| 녹음·재생·재생 바·획 강조·탭 재생 | ✔ 웹(iPad Safari 앞에 있을 때) + Chrome 통합 시험 | — |
| 녹음 시계·강조 계산 | ✔ VM 시험 | — |
| 백그라운드 녹음 | iOS Info.plist·안드로이드 매니페스트·포그라운드 서비스 코드까지(INFRA·오디오 모듈) | 동작 확인: 안드로이드 APK 실기기(기기 여부 Q2), iOS는 TestFlight 뒤 |
| 웹 녹음 끊김 대비(조각 IndexedDB 저장) | 선택(자체 웹 녹음기 ~300줄, `record_web` MediaRecorder 위임 코드 281줄을 참고) | 기본은 미룸 |
| S펜 버튼 → 임시 지우개 | ✔ 위젯 시험(합성 포인터) | 실기기 확인(Q2) |
| Pencil 더블탭·스퀴즈·롤·호버 높이 | Dart 쪽 디코딩·동작 매핑·설정 + Swift 플러그인 작성(컴파일은 macOS 러너, Q6) | 동작 확인은 TestFlight 뒤 |

### 12.7 시험 구성

- Chrome 가짜 마이크 래퍼(14절)는 INFRA `ws test`의 Chrome 실행 파일과 별개로 둔다(태그 예: `media`, 기본 실행에서 제외 여부는 INFRA 판단). GitHub Actions ubuntu 러너의 Chrome에도 같은 플래그가 통한다고 본다 [추측].
- 웹 시험에서는 `flutter test --platform chrome`이 플러그인 등록기를 돌리지 않으므로 시험 파일이 `RecordPluginWeb.registerWith(webPluginRegistrar)`·`JustAudioPlugin.registerWith(webPluginRegistrar)`를 직접 부른다 [확인].
- AAC 경로는 리눅스 Chrome에서 시험할 수 없다(3.2). AAC는 실기기(iPad Safari) 진단 화면으로 확인한다 — 개발자 메뉴에 `isEncoderSupported` 표, 마지막 녹음의 MIME·길이·시계 오차를 보이는 항목을 권한다.

---

## 13. 열린 질문 (사용자·총괄 결정)

| # | 질문 | 왜 필요한가 | 대상 |
|---|---|---|---|
| Q1 | 사용자의 Apple Pencil 종류(Pro / USB-C)와 iPad 정확한 모델명 | USB-C 펜슬이면 더블탭·스퀴즈·배럴 롤·필압이 모두 없어 M5 펜 버튼 기능을 사용자 기기에서 쓸 수 없다(PLAN 11장 질문 1) | 사용자 |
| Q2 | S펜이 되는 안드로이드 태블릿이 있는가 | S펜 버튼·안드로이드 백그라운드 녹음은 실기기 없이는 완료 판정 불가. 없으면 '코드만, 확인은 이후' | 사용자 |
| Q3 | 크롬 등 AAC를 못 내는 브라우저에서 녹음을 허용할지(opus/webm 저장 + 경고) 아니면 막을지 | webm은 iOS 네이티브에서 재생 불가(3.4). 나중에 서버 변환(Cloud Functions)을 둘 수도 있음 | 총괄 |
| Q4 | 녹음 일시정지 중 쓴 획을 녹음에 연결할지(연결 안 함 / 일시정지 지점에 붙임) | `recordingOffsetMs` 규칙 | 총괄(EDITOR·오디오) |
| Q5 | 필기 탭 재생의 앞당김(pre-roll) 기본값과 설정 노출 여부 | 6.3 오차 흡수 | 총괄 |
| Q6 | iOS 펜 플러그인을 이번 라운드에 작성할지, 작성한다면 macOS 러너 컴파일 확인(10배 과금)을 몇 번 허용할지 | 9.4 — 동작 확인은 어차피 TestFlight 뒤 | 사용자·총괄 |
| Q7 | 오디오 모듈·펜 플러그인의 소유 영역(새 영역 / EDITOR / INFRA)과 패키지 이름 | 12.2. 7.1 표·R8 규칙 변경 | 총괄 |
| Q8 | `Recording`에 시계 보정 필드(예: `clockOffsetMs`)를 미리 둘지, 실기기 측정 뒤로 미룰지 | 6.3. 넣으면 CORE·SYNC 계약 변경 | 총괄 |
| Q9 | 녹음 비트레이트 기본값(32/48/64 kbps)과 사용자 설정 노출 | 용량(3.5)·동기화 비용(PLAN 리스크 '클라우드 비용') | 사용자 |
| Q10 | 웹 녹음의 끊김 대비(조각을 IndexedDB에 바로 저장)를 이번에 할지 | 탭이 닫히면 녹음 전체 손실(4.3) | 총괄 |
| Q11 | Pencil 더블탭·스퀴즈 기본 동작: 시스템 설정 따르기 vs PLAN F-12 고정값(지우개 전환 / 도구 팔레트) | 12.5. Apple은 시스템 설정 존중을 권고 | 사용자 |
| Q12 | S펜 버튼 동작 모델: 누른 채 쓰는 동안 임시 지우개(권장) vs 토글 | 10절. Air command와의 충돌 | 사용자 |

실기기 확인 목록(설계 뒤 체크리스트로)

| # | 확인할 것 | 기기 |
|---|---|---|
| D1 | iPad Safari `isEncoderSupported`(aacLc·opus) 실제 값, 녹음 파일 MIME | iPad |
| D2 | Safari가 만든 mp4를 `just_audio`(웹·iOS·안드로이드)가 유한한 길이로 열고 정확히 탐색하는가 | iPad, (안드로이드) |
| D3 | iPad Safari에서 앱 전환·화면 잠금 때 녹음 상태(멈춤·무음·계속)와 돌아온 뒤 동작 | iPad |
| D4 | iPad Safari Screen Wake Lock 동작 | iPad |
| D5 | iOS 네이티브 녹음 → 재생 전환 때 세션 범주·스피커 출력, 정지 뒤 다른 앱 음악 재개 | TestFlight 뒤 |
| D6 | 삼성 태블릿에서 S펜 버튼이 `buttons 0x02`로 오는가(닿은 채·띄운 채), Air command 켬/끔 | 안드로이드 |
| D7 | 안드로이드 Chrome(웹)에서 S펜 버튼을 먼저 누르고 닿을 때 이벤트 순서(8.4) | 안드로이드 |
| D8 | iPad Safari에서 Pencil 호버가 `kind: stylus` 호버로 오는가 | iPad |
| D9 | 네이티브 녹음 시계 오차(6.3) — iOS·안드로이드 각각 10회 | 안드로이드, TestFlight 뒤 |

---

## 14. 확인 명령 기록 (재현용)

모든 명령 앞: `export PATH=/opt/flutter/bin:$PATH CHROME_EXECUTABLE=/usr/local/bin/chrome-nosandbox`

```bash
# pub.dev 최신 버전·의존·플랫폼·점수
curl -s https://pub.dev/api/packages/record          # latest.version, pubspec.environment
curl -s https://pub.dev/api/packages/record/score    # grantedPoints, likeCount, tags
curl -s "https://pub.dev/api/search?q=apple%20pencil"   # 플러그인 찾기 (stylus, pencil squeeze, spen 등)

# 플러그인 소스 내려받기 (archive_url) → /tmp/claude-0/plan57-scratch/src/<pkg>/

# 2.2 워크스페이스 해석: noteapp pubspec·lock 복사 + packages/media_probe 추가
cd /tmp/claude-0/plan57-scratch/audio_ws && flutter pub get   # 이후 lock 비교 스크립트(기존 변화 0, 추가 28)
#   대안: media_probe 의존을 audioplayers: 6.8.1 / flutter_sound: 9.30.0 로 바꿔 각각 해석

# 2.3 웹 빌드
cd /tmp/claude-0/plan57-scratch/audio_probe
flutter analyze
flutter build web --release --no-wasm-dry-run                 # ✓ 20.3s

# 3.2 Chrome MediaRecorder MIME
/usr/local/bin/chrome-nosandbox --headless=new --disable-gpu --dump-dom \
  file:///tmp/claude-0/plan57-scratch/chrome/mime.html

# 5.2 Chrome 녹음→재생 (가짜 마이크 래퍼)
cat /tmp/claude-0/plan57-scratch/bin/chrome-fakemedia
#   exec /usr/local/bin/chrome-nosandbox --use-fake-device-for-media-stream \
#        --use-fake-ui-for-media-stream --autoplay-policy=no-user-gesture-required "$@"
CHROME_EXECUTABLE=/tmp/claude-0/plan57-scratch/bin/chrome-fakemedia \
  flutter test --platform chrome test/web_audio_probe_test.dart   # +1: All tests passed (3s)

# 8.4 웹 펜 이벤트 (CDP)
flutter build web --release --no-wasm-dry-run --no-web-resources-cdn \
  -t lib/pointer_probe.dart -o build/pointer_web
cd build/pointer_web && python3 -I -m http.server 8765 --bind 127.0.0.1 &
node /tmp/claude-0/plan57-scratch/cdp/pen_cdp.mjs http://127.0.0.1:8765/   # Playwright 1.63, CDP Input.dispatchMouseEvent(pointerType: 'pen')

# 8장 엔진 소스 (Flutter 3.47.9)
grep -n 'kPrimaryStylusButton' /opt/flutter/packages/flutter/lib/src/gestures/events.dart
sed -n 320,350p /opt/flutter/engine/src/flutter/shell/platform/android/io/flutter/embedding/android/AndroidTouchProcessor.java
sed -n 2118,2130p /opt/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterViewController.mm
sed -n 1280,1380p /opt/flutter/engine/src/flutter/lib/web_ui/lib/src/engine/pointer_binding.dart
```

참고: CanvasKit을 CDN(`gstatic`)에서 받는 기본 빌드는 컨테이너의 헤드리스 Chrome에서 시작되지 않아 `--no-web-resources-cdn`으로 다시 빌드했다(프록시 설정 문제로 보임) [추측].

---

## 15. 출처

패키지(pub.dev, 2026-11-05 조회)

- record <https://pub.dev/packages/record> · 백그라운드 녹음 문서 <https://github.com/llfbandit/record/blob/main/doc/bg_recording.md> · 안드로이드 설정 <https://github.com/llfbandit/record/blob/main/record_android/README.md>
- just_audio <https://pub.dev/packages/just_audio> · audio_session <https://pub.dev/packages/audio_session>
- audioplayers <https://pub.dev/packages/audioplayers> · flutter_sound <https://pub.dev/packages/flutter_sound> · taudio <https://pub.dev/packages/taudio>
- flutter_foreground_task <https://pub.dev/packages/flutter_foreground_task> · 녹음 예제 <https://github.com/Dev-hwang/flutter_foreground_task_example/tree/main/record_service>
- permission_handler <https://pub.dev/packages/permission_handler>
- apple_pencil_double_tap <https://pub.dev/packages/apple_pencil_double_tap> (<https://github.com/Code-Growers/apple_pencil_double_tap>) · flutter_apple_pencil <https://pub.dev/packages/flutter_apple_pencil> · stylet <https://pub.dev/packages/stylet> (<https://github.com/focale-editor/stylet>) · spen_remote <https://pub.dev/packages/spen_remote>

플랫폼 문서

- Android 포그라운드 서비스 유형 microphone <https://developer.android.com/develop/background-work/services/fg-service-types#microphone>
- Apple `UIPencilInteraction` <https://developer.apple.com/documentation/uikit/uipencilinteraction> · 스퀴즈 처리 <https://developer.apple.com/documentation/applepencil/handling-squeezes-from-apple-pencil> · `UIPencilHoverPose` <https://developer.apple.com/documentation/uikit/uipencilhoverpose> · 호버 지원 <https://developer.apple.com/documentation/uikit/adopting-hover-support-for-apple-pencil> · Apple Pencil 업데이트 <https://developer.apple.com/documentation/updates/applepencil>
- WebKit MediaRecorder <https://webkit.org/blog/11353/mediarecorder-api/>
- 안드로이드 펜 버튼 상태 설명(Microsoft) <https://learn.microsoft.com/en-us/dual-screen/android/platform/pen>
- Samsung S Pen Remote SDK <https://developer.samsung.com/s-pen-sdk/sdk>

보고·2차 출처(검색 요약으로 봄 — 직접 열지 못한 곳은 표시)

- WebKit 버그: 백그라운드 음소거 캡처 <https://bugs.webkit.org/show_bug.cgi?id=173268>, iOS 음소거 트랙 <https://bugs.webkit.org/show_bug.cgi?id=218815>, 통화 뒤 무음 <https://bugs.webkit.org/show_bug.cgi?id=208209>, Pencil 호버 이벤트 <https://bugs.webkit.org/show_bug.cgi?id=296943> (bugs.webkit.org는 이 세션 네트워크 허용 목록 밖이라 직접 열지 못함)
- Apple 개발자 포럼: Mobile Safari의 Pencil Pro 이벤트 <https://developer.apple.com/forums/thread/760238>(답 없음), Safari Pencil Pro PointerEvent 표본율 <https://developer.apple.com/forums/thread/776468>
- Safari WebM/Opus 녹음 <https://addpipe.com/media-recorder-api-demo/> · Ogg/Opus 실패 보고 <https://frequal.com/java/OggOpusStillNotWorkingInSafari18_4.html>
- Samsung 포럼 S펜 이벤트 미수신 <https://forum.developer.samsung.com/t/galaxy-tab-s9-fe-cant-get-any-spen-specific-events/38112> · Squid 측면 버튼 <https://help.squidnotes.com/article/709-what-can-i-do-with-my-pen-side-button>

로컬 소스(읽기 전용)

- Flutter 3.47.9: `/opt/flutter/packages/flutter/lib/src/gestures/{events,converter}.dart`, `/opt/flutter/engine/src/flutter/shell/platform/android/.../AndroidTouchProcessor.java`, `/opt/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterViewController.mm`, `/opt/flutter/engine/src/flutter/lib/web_ui/lib/src/engine/pointer_binding.dart`
- pub 캐시: `/root/.pub-cache/hosted/pub.dev/{record-7.1.2, record_web-2.1.3, record_ios-2.1.1, record_platform_interface-2.1.0, just_audio-0.10.6, just_audio_web-0.4.16, audio_session-0.2.4, flutter_foreground_task-11.0.3, clock-1.1.3}`
- 영역 코드: `/home/user/wt/editor/packages/feature_editor/lib/src/{di/stylus_extras.dart, input/input_router.dart}`, `/home/user/wt/ink/packages/ink_engine/lib/src/{render/ink_page_controller.dart, stroke/stroke_builder.dart}`
