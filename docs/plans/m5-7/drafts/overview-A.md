# 2차 라운드(M5·M6·M7) 동시 개발 개요 — 초안 A: 기존 패키지 중심

> 상태: **설계 초안 A** (2026-11-05, 2차 라운드 설계자 A) · 기준: 1차 [00-overview.md](../../00-overview.md) 7장 통합 계약 v1.4, [00-review.md](../../00-review.md) · 마스터 기획서: [PLAN.md](../../../PLAN.md) F-03·F-10·F-11·F-12·F-13·F-14·F-16, 5장, 10장 M5~M7 · 조사: [research/01-hooks.md](../research/01-hooks.md), [02-audio-stylus.md](../research/02-audio-stylus.md), [03-recognition.md](../research/03-recognition.md), [04-native.md](../research/04-native.md)
>
> **관점 A — 기존 패키지 중심.** 1차의 7개 영역(INFRA·CORE·INK·EDITOR·LIBRARY·PDF·SYNC)과 7개 패키지를 그대로 두고, 각 소유 영역이 자기 패키지를 확장한다. 플랫폼 전용 기능(오디오, 인식 엔진, 스타일러스 플러그인)만 새 패키지 3개(`media_io`, `ink_recognition`, `pencil_bridge`)로 두고, 새 영역은 만들지 않는다 — 새 패키지와 서버 함수 디렉터리(`functions/`)는 짐이 가벼운 기존 영역이 맡는다. 영역 수(7)를 늘리지 않고 1차 계획서·코드·작업 트리와의 연속성을 우선한다.

## 0. 이 초안을 읽는 법

- 이 문서는 1차 `00-overview.md`의 구성을 본뜬다. 확정되면 1장~3장은 2차 개요의 1장~5장, **4장(통합 계약 v2.0 초안)은 2차 개요 7장**, 5장은 7.6~7.7, 6장은 리스크·질문, 7장은 이 초안에만 있는 자체 평가다.
- 1차 계약 v1.4는 **그대로 유효하다.** 4장은 그 위에 덮어쓰는 변경분만 적는다. 4장과 1차 계약이 다르면 4장이 우선한다.
- 4장 각 항목의 '계약' 분류는 조사 01과 같다.

| 분류 | 뜻 |
|---|---|
| 추가 | 공개 진입점에 새 타입·멤버·선택 인자를 더한다. 기존 호출은 그대로 컴파일된다 |
| 깨짐 | 기존 공개 시그니처·의미가 바뀌거나, sealed/enum 값 추가로 **다른 패키지의** exhaustive switch가 컴파일되지 않는다 |
| 규칙 | Dart 시그니처는 같고 계약 문장(소유표·예산·동작 보장)만 바뀐다 |

- 코드 블록은 시그니처 계약이다(본문 생략). `// v1.4` 표시는 1차 계약 그대로라는 뜻이다.
- 문서 안의 [확인]·[추측] 표기는 조사 문서의 표기를 따른다. 표기가 없는 판단은 설계 결정(이 초안의 제안)이다.

---

## 1. 목적과 범위

### 1.1 목적과 진행 순서

`docs/PLAN.md` 10장의 **M5 편집 강화 · M6 녹음 · M7 인식**을 여러 영역으로 나눠 동시에 개발한다. 1차 7.8에서 미룬 항목 중 M5와 맞닿은 것(올가미 회전·색 변경 UI, 제스처 동작 변경, 이미지 페이지)과 M7과 같은 색인으로 갈 수 있는 것(라이브러리 전역 PDF 텍스트 검색)도 넣는다.

진행 순서는 1차와 같다.

1. **전제**: 1차 통합(1차 7.7 V1~V7)이 끝나 `main`이 1차 결과 전체를 담고 있어야 한다. 2차 작업 트리는 그 `main`에서 만든다(5.1).
2. 영역마다 상세 계획서 `docs/plans/m5-7/NN-<id>.md` 작성(1차 6장 공통 목차 그대로).
3. 총괄이 검토하고 이 문서 4장을 '통합 계약 v2.0'으로 확정한다.
4. 기반 단계(5.2): 새 패키지 골격·계약 코드·자리표시를 먼저 `main`에 넣는다.
5. 영역별 작업 트리에서 동시 개발(브랜치 `area2/<id>`).
6. 통합(5.3) → 컨테이너 검증(5.4) → 실기기 확인(5.5).

### 1.2 기능별 범위

표의 '웹'은 iPad Safari(홈 화면 앱 포함), 'APK'는 안드로이드 release APK, 'TF'는 Apple 유료 계정 가입 뒤 TestFlight다. '실기기 확인'은 그 기능의 완료 판정을 사람 손으로 하는 첫 시점이다.

| # | 기능 (PLAN) | 이번 범위 | 웹 | 네이티브 전용 부분 | 실기기 확인 | 이후로 미룸 |
|---|---|---|---|---|---|---|
| M5-1 | 올가미 고급: 회전 핸들(15° 맞춤), 색 변경, 잘라내기, 붙여넣기, 획과 객체를 함께 선택 (5.1) | 전부 | ✔ | — | 웹(통합 직후) | — |
| M5-2 | 텍스트 상자: 키보드 입력, 글자 크기·색·굵게·정렬, 이동·크기·회전 (5.1) | 전부(서식은 상자 단위, 글자 단위 서식 없음) | ✔ (한글 IME 조합은 실기기 확인 항목) | — | 웹 | 글자 단위 서식, 목록·표 |
| M5-3 | 이미지 삽입: 사진·카메라·파일·(웹) 클립보드 붙여넣기, 이동·크기·회전 (5.1) | 전부 | ✔ (`navigator.clipboard.read` 지원 시 붙여넣기) | 네이티브 클립보드 이미지 붙여넣기는 이후 | 웹, APK | 자르기(crop), 네이티브 클립보드 |
| M5-4 | 이미지 페이지 (F-13, 1차 7.8 이후 항목) | 전부: 페이지 추가 시트 '이미지', 화면·썸네일·PDF 내보내기 | ✔ | — | 웹 | — |
| M5-5 | 도형 도구: 직선·화살표·사각형·원/타원·삼각형·다각형·별, 테두리 색·굵기·선 스타일·채우기, 크기·회전·꼭짓점 편집 (F-11) | 전부 | ✔ | — | 웹 | 그리드 스냅·자(F-11 P1) |
| M5-6 | 자동 도형 보정: 그리다 펜을 멈추면(500 ms) 반듯한 도형으로 (F-11) | 직선·원·타원·삼각형·사각형·다각형 | ✔ | — | 웹(문턱값을 실제 획으로 다시 맞춤) | 별·화살표 자동 보정 |
| M5-7 | 제스처 사용자 지정: 두·세 손가락 탭, 손가락 길게 누르기, 펜 버튼, Pencil 더블탭·스퀴즈의 동작 변경·끄기 (F-12) | 전부(드래그·핀치·펜 전용 모드 스크롤은 고정) | ✔ | Pencil 항목은 네이티브에서만 보임 | 웹 | — |
| M5-8 | S펜 측면 버튼 — 누른 채 쓰면 임시 지우개 (F-12) | 전부 | △ 안드로이드 Chrome(접촉 비트 판정) | 플러그인 불필요(Flutter가 버튼 비트를 줌) | APK(S펜 기기가 있을 때) | — |
| M5-9 | Apple Pencil 더블탭·스퀴즈·배럴 롤·호버 높이 (F-12, F-03) | Dart 쪽 동작 매핑·설정 + iOS 플러그인(Swift) 작성 + macOS CI 컴파일 확인 | ✘ (웹 API 없음 — 항목 숨김) | 전부 | **TF 뒤** | — |
| M5-10 | 붓펜·캘리그래피·점선 (F-03 P1) | 전부 | ✔ (웹 캘리그래피는 고정 펜촉 각 — 웹은 방위각이 항상 0) | 배럴 롤로 펜촉 각 돌리기 | 웹, TF 뒤(롤) | — |
| M5-11 | 레이저 포인터 — 잠시 뒤 사라짐, 저장 안 함 (F-03, E-3) | 전부 | ✔ | — | 웹 | 외부 모니터 발표 모드(5.2) |
| M5-12 | 암기 테이프 — 가렸다가 탭하면 보임 (F-03, 5.2) | 전부(드러냄 상태는 저장 안 함) | ✔ | — | 웹 | 드러냄 상태 저장·학습 기록 |
| M6-1 | 녹음 시작·일시정지·정지, 노트당 여러 녹음, 이름·삭제, 녹음 동의 안내 (F-16) | 전부 | ✔ 앞에 있을 때(Safari는 AAC/mp4) | — | 웹 | — |
| M6-2 | 백그라운드 녹음 (F-16) | 네이티브 코드·설정 전부(안드로이드 포그라운드 서비스, iOS `UIBackgroundModes: audio`) + 웹 대체 동작(가려지면 자동 일시정지·화면 꺼짐 방지) | ✘ (대체 동작만) | 전부 | APK, **TF 뒤**(iOS) | — |
| M6-3 | 재생 바: 0.5~2배속, 10초 앞뒤, 탐색, 녹음 목록, 용량 표시 (F-16) | 전부 | ✔ | — | 웹 | 잠금 화면 재생 제어 |
| M6-4 | 획별 녹음 시점 → 재생 시 필기 강조, 필기 탭 → 그 시점부터 재생 (F-16) | 전부 | ✔ | — | 웹, APK(시계 오차 측정) | 시계 보정 필드(실측 뒤 판단) |
| M6-5 | 녹음 끊김 대비 — 녹음 중 조각을 임시 저장해 탭이 닫혀도 복구 | 저장소 API(CORE) 전부, 웹 조각 저장 녹음기는 P-B(1.5) | ✔ | — | 웹 | — |
| M6-6 | 녹음 동기화 (F-16 '압축 후 동기화') | 에셋·`Recording` 동기화 경로는 1차에 있음 — 실연결 뒤 동작 | — | — | 실연결 뒤 | 실연결(1.4) |
| M7-1 | 손글씨 → 텍스트: 올가미 선택 → 후보·직접 편집 → 텍스트 상자로 바꾸기 / 복사 (F-10) | 엔진 교체 구조 + ML Kit 어댑터 + 변환 UI 전부 | ✘ (메뉴는 보이되 '이 기기에서는 쓸 수 없음' 안내) | ML Kit 인식 | **APK가 첫 판정**, iPad는 TF 뒤 | 웹 인식(서버 경유 OCR) |
| M7-2 | 손글씨 검색 색인 (5.2) | 색인 테이블·질의·결과 UI·색인기 전부 | 검색 ✔ / 손글씨 색인 생성 ✘ (동기화된 인식 결과로만 — 실연결 뒤) | 손글씨 인식 | APK | — |
| M7-3 | 라이브러리 전역 PDF 텍스트 검색 (1차 7.8 이후 항목) | 전부(M7-2와 같은 테이블) | ✔ | — | 웹 | — |
| M7-4 | 텍스트 상자·수식 내용 검색 | 전부(같은 테이블) | ✔ | — | 웹 | — |
| M7-5 | 수식 객체: LaTeX 직접 입력·편집, 렌더, 이동·크기·색, LaTeX 복사, PDF 출력 (F-14) | 전부(PDF는 래스터 300 dpi) | ✔ | — | 웹 | PDF 벡터 수식 |
| M7-6 | 수식 인식 엔진 비교 구조 + 손글씨 수식 → LaTeX (F-14) | 앱 쪽 엔진 포트·가짜·서버 호출 클라이언트, 서버 함수 코드(에뮬레이터 시험까지), 수식 입력 패드(멈춤 1초 뒤 미리보기), 엔진 비교 도구 | ✔ (엔진 연결 뒤) | — | **Firebase(Blaze)·로그인·엔진 계정 생긴 뒤** | 실제 엔진 호출·비교 실험 실행 |
| 공통-1 | 네이티브 저장(파일 DB·파일 에셋 블롭) — APK·네이티브 실사용의 선행 조건 | 전부 | — | 전부 | APK | — |
| 공통-2 | 동기화 실연결(M4 앱 연결·로그인 화면) | **넣지 않는다**(1.4). SYNC 사전 정비(새 엔티티 종류·모르는 종류 보류)는 넣는다 | — | — | 실연결 미니 라운드 | 실연결 |

### 1.3 1차 7.8에서 미룬 항목

| 1차 7.8 항목 | 1차 결정 | 2차 처리 |
|---|---|---|
| 올가미 회전·색 변경 계산 | INK API만, UI는 M5 | **이번**: EDITOR 회전 핸들·색 변경·잘라내기, 객체까지 함께 선택(M5-1) |
| 제스처 켜기/끄기 | 탭 3종 켜기/끄기만 | **이번**: 동작 매핑(M5-7). 1차 bool 키는 읽기 호환으로 남긴다(4.11) |
| 다른 노트 페이지 복사, 이미지 페이지 (F-13) | 이후 | 이미지 페이지는 **이번**(M5-4). 다른 노트 페이지 복사는 **이후**(노트·페이지 고르기 UI가 필요하고 M5와 무관). 단, `PageDraft`가 객체까지 복사하므로(4.4) 나중에 UI만 더하면 된다 |
| 라이브러리 전역 PDF 텍스트 검색·색인 | 이후 | **이번**: 손글씨 색인과 같은 `search_units` + FTS5 테이블(M7-3, 4.6) |
| 동기화 실연결 | M4(Firebase 프로젝트 생성 후) | **이후**(1.4). 새 엔티티 종류는 실연결 **전에** 코덱·병합에 넣는다 |
| 다중 탭 리더 선출, tombstone 정리, 고아 에셋 GC | 이후 | **이후** 유지. '녹음만 따로 삭제'는 소프트 삭제까지(바이트 회수는 GC와 함께 — 6.2 U13) |
| 백업 내보내기 | 1차 권장 작업 | 새 엔티티(페이지 객체·손글씨 결과·녹음 이름)를 백업 JSON에 포함한다(CORE). 색인·녹음 초안은 넣지 않는다 |

### 1.4 동기화 실연결(M4)을 이번 라운드에 넣지 않는다

판단 근거:

1. Firebase 프로젝트가 없어 실연결을 **검증할 수 없다**. 컨테이너에서는 gstatic이 막혀 `firebase_core_web` 경로도 Chrome에서 시험할 수 없다(조사 04 6.5).
2. 앱에 `sync_engine`(Firebase 네이티브 SDK, SwiftPM)을 넣는 순간 ML Kit(CocoaPods 전용)과의 **iOS 혼합 모드 중복 의존 위험**이 이번 라운드로 들어온다(조사 04 요약 9). 2차는 ML Kit만 pod로 들어가는 상태에서 iOS 컴파일을 먼저 확인하는 편이 원인 분리가 쉽다.
3. 대신 **실연결 전에 해야 싼 일**은 이번에 한다: 새 엔티티 종류(`pageObject`, `handwriting`)를 코덱·병합·게이트에 넣고, 모르는 종류 기록을 청크째 버리지 않고 그 기록만 보류하도록 바꾼다(조사 01 R2, 4.9). 배포된 옛 앱이 없을 때 바꾸면 형식 전환 규칙이 필요 없다.
4. 서버 함수(수식 인식 키 보호)도 코드 + 에뮬레이터 시험까지만 하고 배포는 Firebase·Blaze 뒤로 둔다.

**실연결 미니 라운드**: 사용자가 Firebase 프로젝트를 만들면 2차 통합이 끝난 뒤 INFRA·SYNC 두 영역만으로 짧게 한다(1차 7.3.3 M4 행 + 로그인 화면 + `cloud_functions`/`firebase_auth` 연결 + iOS 혼합 모드 컴파일 확인). 2차 도중 프로젝트가 생겨도 2차 범위에 끼워 넣지 않는다(범위 팽창 방지). 사용자 질문 U3.

### 1.5 우선순위 등급 — 범위를 줄여야 할 때

동시 개발 중 일정이 밀리면 아래 순서로 자른다. 각 영역 계획서의 작업 분해도 이 등급을 표시한다.

| 등급 | 뜻 | 포함 |
|---|---|---|
| P-A | 2차 완료 조건 | M5-1~5, M5-7, M5-8, M5-10~12, M6-1, M6-3, M6-4, M7-2(색인·질의·결과 UI), M7-3, M7-4, M7-5, 공통-1, SYNC 사전 정비 |
| P-B | 해야 하지만 미뤄도 2차 완료 | M5-6 자동 도형 보정, M5-9 Pencil 플러그인, M6-2 백그라운드(네이티브), M6-5 웹 조각 저장 녹음기, M7-1 ML Kit 어댑터·변환 UI, M7-6 수식 엔진 포트·패드·서버 함수 |
| P-C | 여유가 있으면 | iOS 컴파일 확인 실행, 안드로이드 에뮬레이터 CI 잡, 별·화살표 꼭짓점 편집, 수식 엔진 비교 도구 |

---

## 2. 영역 지도

### 2.1 영역 표

| ID | 영역 | 계획서 | 소유 경로 (겹침 없음) | 이번 범위 (맡는 기능) | 1차와의 관계 |
|---|---|---|---|---|---|
| INFRA | 기반 · 빌드 · 배포 · 플랫폼 설정 | `/home/user/wt/plan57/docs/plans/m5-7/01-infra.md` | 루트 `pubspec.yaml`·`pubspec.lock`·`analysis_options.yaml`·`.gitignore`·`.gitattributes`, `app/`, `.github/`, `tool/`, `docs/guides/`, **`packages/pencil_bridge/`(새)** | 새 연결(모듈·override·라우팅), 네이티브 저장 경로, 안드로이드 매니페스트·고정 서명·`android.yml`, iOS 15.5·Podfile·Info.plist·`ios-compile.yml`, `ws` 규칙·네이티브 설정 정적 시험·플러그인 요구 검사, 웹 예산, **Apple Pencil 플러그인**(M5-9), 실기기 안내서 | 1차 INFRA 그대로 + 플랫폼 플러그인 하나. 네이티브 설정(Info.plist·매니페스트)과 iOS CI를 이미 소유하므로 iOS 전용 플러그인도 같은 손에 둔다 |
| CORE | 문서 모델 · 저장 · 되돌리기 · 색인 | `/home/user/wt/plan57/docs/plans/m5-7/02-core.md` | `packages/note_core/` | 페이지 객체 4종 모델·JSON·DB v2·명령, 녹음 저장소·초안 저장소·오디오 포트, 손글씨 인식 결과 엔티티, 검색 색인(FTS5), 이미지 가져오기 타입, 네이티브 저장(파일 DB·파일 블롭) | 1차 CORE 그대로. `PageElement` sealed 계층·DB·명령 해석기를 만든 손이 확장한다 |
| INK | 필기 엔진 · 페이지 렌더 | `/home/user/wt/plan57/docs/plans/m5-7/03-ink.md` | `packages/ink_engine/`(새 `assets/fonts/` 포함) | 추가 펜 5종 렌더, 페이지 객체 렌더·적중·선택·변형, 자동 도형 보정 발동·미리보기(판정은 포트), 이미지 배경 빌더·이미지 캐시, 썸네일·벡터 내보내기 v2, 수식 렌더(`flutter_math_fork`), 텍스트 글꼴, 재생 강조·테이프·레이저 | 1차 INK 그대로. '화면·썸네일·PDF가 같은 렌더 경로'를 한 영역이 계속 지킨다 |
| EDITOR | 에디터 화면 | `/home/user/wt/plan57/docs/plans/m5-7/04-editor.md` | `packages/feature_editor/` | 올가미 고급 UI·클립보드, 텍스트 도구(IME), 도형 도구·핸들, 이미지 삽입·이미지 페이지 흐름, 제스처 매핑·설정·펜 버튼·Pencil 이벤트 소비, 새 펜 선택기·고급 설정, 녹음 연동(펜 다운 시점·재생 강조·탭 재생), 확장 자리(선택 메뉴·삽입 메뉴·녹음 패널·이미지 가져오기) | 1차 EDITOR 그대로. 무거운 UI 흐름 두 개(녹음 패널, 인식 변환 창)는 자리만 두고 새 패키지 소유 영역에 넘긴다(2.3) |
| LIBRARY | 라이브러리 화면 · **인식** | `/home/user/wt/plan57/docs/plans/m5-7/05-library.md` | `packages/feature_library/`, **`packages/ink_recognition/`(새)** | 검색 결과 묶음(손글씨·PDF·텍스트 상자·수식)·페이지 위치로 열기, **인식 패키지 전부**: 손글씨 엔진 포트·ML Kit 어댑터·줄 나누기·색인기, 수식 엔진 포트·서버 호출 클라이언트, 변환 UI(텍스트 변환 창·수식 입력 패드·LaTeX 편집), 도형 판정기, 인식 설정 화면 | 1차 LIBRARY + 인식. 1차에서 검색 화면을 만든 영역이 M7의 첫 소비자(손글씨 검색)이고, 1차 짐이 가장 가벼웠다 |
| PDF | PDF · **미디어** 입출력 | `/home/user/wt/plan57/docs/plans/m5-7/06-pdf.md` | `packages/pdf_io/`, **`packages/media_io/`(새)** | PDF 합성에 이미지·텍스트 객체, 페이지 객체·이미지 페이지 내보내기, 한글 글꼴 넣기, 수식 래스터, 라이브러리 전역 PDF 텍스트 색인기 / **미디어 패키지 전부**: 녹음·재생 서비스, 녹음 시계, 웹 녹음 대체 동작·조각 저장, 안드로이드 포그라운드 서비스·오디오 세션, 이미지 가져오기·정규화, 녹음 패널 UI | 1차 PDF + 미디어. '파일(에셋)을 들여오고 내보내는' 일, 웹 JS 상호운용·네이티브 조건부 import 경험이 그대로 쓰인다 |
| SYNC | 동기화 · **서버 함수** | `/home/user/wt/plan57/docs/plans/m5-7/07-sync.md` | `packages/sync_engine/`, **`functions/`(새, 루트, Node — 워크스페이스 멤버 아님)** | 새 엔티티 종류 매핑(필드 단위·범위·게이트·영구 삭제 보호·페이지 되살림), 모르는 종류 기록 보류, 시나리오 시험, **서버 함수**(수식 인식 `recognizeMath`·키 보호·에뮬레이터 시험), 수식 엔진 비교 도구 | 1차 SYNC + Firebase 백엔드 코드. 이미 `packages/sync_engine/firebase/`(규칙 파일)·에뮬레이터를 다루는 영역이다 |

- 총괄은 1차와 같이 `docs/plans/`(개요·검토·계획서 승인)와 통합 병합을 맡는다. 각 영역은 자기 작업 트리의 `docs/plans/progress/<id>.md`에 진행 기록을 남긴다(1차와 같음).
- 소유 경로 밖 파일이 필요하면(예: SYNC가 `app/firebase.json`의 `functions` 항목, `.github/workflows/functions.yml`) 1차처럼 '변경 요청'으로 INFRA에 남긴다. 기반 단계에서 INFRA가 미리 넣어 둔다(5.2 R2-B1).

### 2.2 새 패키지를 기존 영역에 두는 기준

1. **한 패키지 = 한 영역.** 새 패키지는 하나의 기존 영역이 통째로 소유한다. 한 영역이 패키지 둘을 가질 수 있다(1차 INFRA가 `app/`·`tool/`·`.github/`를 함께 가진 것과 같다).
2. **주제가 가깝고 짐이 가벼운 영역.** 1차 계획서 크기와 2차 추정 작업량(2.3)으로 고른다.
   - `ink_recognition` → LIBRARY: M7의 첫 소비자가 라이브러리 검색이고, 인식 결과를 화면에 보이는 흐름(후보 고르기·직접 편집)이 LIBRARY가 1차에 만든 검색·목록 UI와 성격이 같다.
   - `media_io` → PDF: 에셋 바이트를 들여오고(PDF 가져오기) 내보내는(PDF 내보내기) 영역이고, `*_browser.dart`(JS 확장)·`*_native.dart`(FFI) 분리와 웹 정적 자산을 이미 다뤘다. 이미지 정규화(JPEG/PNG)는 PDF 이미지 객체 입력과 같은 형식이라 한 손에 두면 맞추기 쉽다.
   - `pencil_bridge` → INFRA: iOS 전용 Swift 코드이고 확인 수단이 INFRA의 macOS CI뿐이다. Info.plist·배포 대상도 INFRA 소유다.
   - `functions/` → SYNC: Firebase 백엔드(규칙·에뮬레이터)를 이미 소유하고, 2차 SYNC 본업(사전 정비)이 가장 가볍다.
3. **피처 패키지는 플러그인 패키지에 의존하지 않는다.** EDITOR·LIBRARY는 `media_io`·`ink_recognition`·`pencil_bridge`를 import하지 않는다. 연결은 1차 7.1 규칙 1 그대로 ① CORE에 둔 인터페이스(오디오 포트, 4.5) 또는 ② 소비하는 쪽 자리 + 앱 셸 override(선택 메뉴·삽입 메뉴·녹음 패널·이미지 가져오기, 4.11)로만 한다. 그래서 EDITOR 위젯 시험은 웹·VM 모두 플러그인 없이 돈다.

### 2.3 작업량 균형

단위는 '1차 계획서 기준 작업 하나(T) ≈ 1'의 상대 추정이다. 각 영역 계획서가 8장 작업 분해로 다시 잰다.

| 영역 | 주요 작업 (추정 단위) | 합계 | 조정 내역 |
|---|---|---|---|
| CORE | 객체 모델·JSON·불변식 2, DB v2·마이그레이션·행 변환·outbox 힌트 3, 명령·해석기·세션·초안 2, 복사·휴지통·백업·가짜 저장소 2, 녹음 저장소·초안 저장소·오디오 포트·가짜 2.5, 손글씨 결과 엔티티·저장소 1, 검색 색인(FTS5 바이그램·작성기·질의·정규화 통합) 3, 네이티브 저장 1.5 | **17** | 오디오·인식 **구현**은 넘기고 계약 타입·저장만 맡는다 |
| INK | 추가 펜 5종 4, 객체 렌더·캐시·층 3, 객체 적중·올가미·선택·숨김 2, 도형 보정 발동·미리보기 1, 이미지 배경·이미지 캐시·썸네일 2, 벡터 내보내기 v2·글꼴·수식 래스터 2.5, 재생 강조·테이프·레이저 상태 1 | **15.5** | 도형 **판정 알고리즘**(시제품 279줄 기반, 합성 1,400개 시험)은 포트(`InkShapeFitter`)로 떼어 LIBRARY(`ink_recognition`)로 넘긴다 |
| EDITOR | 올가미 고급·클립보드 2.5, 텍스트 도구·IME 3, 도형 도구·핸들·꼭짓점 3, 이미지 삽입·이미지 페이지 1.5, 제스처 매핑·설정·펜 버튼·Pencil 이벤트 3, 새 펜 선택기·테이프·레이저 상호작용 1.5, 녹음 연동(펜 다운 시점·강조·탭 재생) 2, 확장 자리·위치로 열기 0.5 | **17** | 녹음 패널 UI(→ PDF `media_io`), 인식 변환 창·수식 입력 패드(→ LIBRARY `ink_recognition`)를 자리로 넘겨 약 5.5를 덜었다 |
| LIBRARY | 검색 묶음·위치로 열기·설정 연결 2.5, 인식 포트·가짜·줄 나누기 2, ML Kit 어댑터·모델 관리 2, 색인기 2, 변환 UI 3, 도형 판정기 1.5, 서버 수식 클라이언트·인식 설정 화면 1 | **14** | |
| PDF | 합성 이미지·텍스트 명령(웹 JS + FFI) 3, 객체 벡터화·층·점선 1.5, 이미지 페이지·수식 래스터 1, 한글 글꼴 넣기 1, 전역 PDF 텍스트 색인기 1.5 / 녹음 서비스 3, 재생 서비스·녹음 시계 1.5, 포그라운드 서비스·오디오 세션 1, 이미지 가져오기·정규화·웹 클립보드 1.5, 녹음 패널 UI 1.5 | **16.5** | |
| SYNC | 새 종류 매핑 3, 모르는 종류 보류 2, 시나리오·계약 시험 2, 서버 함수 골격·엔진 포트·보호·에뮬레이터 시험 3, 수식 엔진 비교 도구 1 | **11** | 실연결 미니 라운드(1.4)의 주 담당이 될 여유를 남긴다 |
| INFRA | 앱 연결 2, 네이티브 저장 경로 0.5, 안드로이드 설정·서명·워크플로 1.5, iOS 설정·`ios-compile.yml` 2, `ws` 규칙·정적 시험·요구 검사 2, 웹 예산 0.5, `pencil_bridge` 2.5, 안내서·체크리스트 1.5 | **12.5** | |

- 범위: 11~17. 1차처럼 CORE·INK·EDITOR가 크지만, 셋 다 2차 작업의 절반 이상이 '자기 1차 코드를 넓히는 일'이라 처음 보는 코드가 적다.
- 세 큰 영역이 임계 경로(3.4)에 있으므로, 기반 단계에서 계약 타입과 **단순하지만 동작하는 구현**을 먼저 넣어 나머지 영역이 기다리지 않게 한다(5.2).

---

## 3. 의존 그래프와 동시 개발

### 3.1 패키지 의존 방향 (v2.0)

```mermaid
flowchart LR
  core[note_core<br/>순수 Dart]
  ink[ink_engine<br/>+ flutter_math_fork] --> core
  editor[feature_editor] --> ink
  editor --> core
  library[feature_library] --> core
  pdf[pdf_io] --> core
  pdf --> ink
  media[media_io<br/>새 · PDF 소유] --> core
  recog[ink_recognition<br/>새 · LIBRARY 소유] --> core
  recog --> ink
  pencil[pencil_bridge<br/>새 · INFRA 소유<br/>형제 의존 없음]
  sync[sync_engine] --> core
  app[app 셸] --> editor & library & pdf & media & recog & pencil & ink & core
  app -.->|실연결 미니 라운드| sync
  fn[functions/<br/>Node · SYNC 소유] -. HTTP callable 형식 4.14 .- recog
```

규칙(1차 7.1 규칙에 더함):

1. `media_io`·`ink_recognition`·`pencil_bridge`는 **서비스 패키지**다. 피처 패키지(`feature_editor`, `feature_library`, `pdf_io`, `sync_engine`)를 import하지 않고, 피처 패키지도 이들을 import하지 않는다. `media_io`↔`ink_recognition`도 서로 import하지 않는다.
2. 서비스 패키지와 피처 패키지의 연결은 앱 셸(INFRA)만 한다(4.17 표). 서비스 패키지가 다른 패키지의 provider를 덮어쓰는 것은 자기 `*Overrides()` 함수를 통해서만 한다(1차 `pdfIoOverrides()`와 같은 방식).
3. 앱은 이번 라운드에도 `sync_engine`에 의존하지 않는다(1.4).

### 3.2 기능 흐름별 의존

| 흐름 | 순서 (→ = 호출·데이터 방향) |
|---|---|
| 텍스트 상자·도형·이미지 객체 | EDITOR 도구 → CORE `AddObjects`/`UpdateObjects` → 세션 N-1 → INK `updateContent`(렌더) → PDF 벡터화(내보내기) → SYNC 코덱(실연결 뒤) |
| 이미지 삽입 | EDITOR 삽입 메뉴 → (자리) `editorImageImporterProvider` = `media_io.importImageForNote` → CORE `AssetStore.put` → EDITOR `AddObjects(ImageObject)` / `InsertPages(ImageBackground)` |
| 자동 도형 보정 | INK 획 세션(멈춤 감지) → (포트) `inkShapeFitterProvider` = `ink_recognition.GeometricShapeFitter` → INK 미리보기 → `InkEdit(addShape)` → EDITOR 실행 |
| 녹음 | EDITOR 녹음 패널 자리 = `media_io.RecordingPanel` → (CORE 포트) `AudioRecorderService` = `media_io` 구현 → CORE `RecordingDraftStore`(조각) → 정지 시 `AssetStore.put(audio)` + `RecordingRepository.createRecording` |
| 펜 다운 녹음 시점 | EDITOR 펜 다운 → CORE 포트 `offsetNowMs()` → INK `beginStroke(meta: InkStrokeMeta)` → CORE `Stroke.recordingId/OffsetMs` |
| 재생 강조·탭 재생 | EDITOR(Ticker) → CORE 포트 `AudioPlaybackService.positionMs()` → INK `setPlaybackFocus` / `hitTestRecorded` → 포트 `seekMs` |
| 손글씨 → 텍스트 | EDITOR 선택 메뉴 자리 = `ink_recognition` 동작 → 엔진(`HandwritingRecognizer`) → 변환 창 → `EditorSelectionContext.execute(Composite[RemoveElements, AddObjects(TextBox)])` |
| 손글씨 색인 | CORE `NoteStore.changes` → `ink_recognition.HandwritingIndexer` → 엔진 → CORE `HandwritingRepository.put` → CORE 내부 색인(`search_units`) |
| PDF 텍스트 전역 색인 | CORE `NoteStore.changes`(PDF 에셋) → `pdf_io.PdfSearchIndexer` → CORE `SearchIndexWriter` |
| 검색 | LIBRARY 검색 화면 → CORE `searchLibrary`(제목 + `pages`) → 결과 누름 → `onOpenNoteAt(noteId, pageId, rect)` → INFRA 경로 → EDITOR `initialPageId`·`initialFocusRectPt` |
| 수식 | EDITOR 삽입·선택 메뉴 자리 = `ink_recognition` 수식 패드 → (엔진 있으면) `MathRecognizer` → 서버 함수 → LaTeX → INK `InkMathRenderer.validate` → `AddObjects(MathObject)` |
| 펜 버튼·Pencil | S펜: Flutter `PointerEvent.buttons` → EDITOR `InputRouter`. Pencil: `pencil_bridge` → INFRA 어댑터 → EDITOR `stylusExtrasProvider` |

### 3.3 동시 개발 — 누가 누구의 가짜로 개발하는가

| 영역 | 의존 대상 | 개발 중 쓰는 것 | 실제와 맞춰 보는 시점 |
|---|---|---|---|
| CORE | (없음) | 자기 실제 구현. SYNC 쪽 동작은 1차 `SyncStore` 계약 시험 그대로 | — |
| INK | CORE | `createFakeNoteStore()`(v2: 객체·에셋), CORE 값 타입 실제 | 통합 2단계(INK 골든·불변식) |
| EDITOR | CORE, INK, (자리) media·recog·pencil | CORE 가짜 저장소 + `FakeAudioRecorder`·`FakeAudioPlayback`(CORE `testing.dart`), INK 실제(기반 단계 단순 구현 → 개발 중 INK 진행분은 통합 때), 자리는 테스트용 `EditorSelectionMenuItem`·가짜 `EditorImageImporter`·가짜 `StylusExtrasSource` | 통합 태그 E-2x(실제 INK + 실제 CORE) |
| LIBRARY | CORE, INK(recog만) | CORE 가짜 저장소(v2: `searchLibrary`가 가짜 색인으로 `pages`를 채움), `FakeHandwritingRecognizer`·`FakeMathRecognizer`(자기 `testing.dart`), INK 실제(`InkShapeFitter` 포트·`MathPreview`) | 통합 태그 L2x(실제 CORE 색인) |
| PDF | CORE, INK | CORE 가짜 저장소, INK 벡터 v2(기반 단계에서 객체 항목을 '단순 동작'으로 냄), `record`·`just_audio` 플랫폼 인터페이스 가짜(media_io 내부), Chrome 가짜 마이크 | 통합 태그 `integration`(PDF 객체 내보내기), `media`(실제 CORE 에셋 + Chrome 녹음) |
| SYNC | CORE | 1차와 같이 자기 `fake_sync_store`(v2 종류 지원)·`FakeSyncServer`. 실제 CORE v2는 `openTestNoteStore` — CORE의 DB v2가 들어오는 대로(개발 중 CORE 커밋을 읽기만) | 통합 태그 T16-v2(실제 CORE 2개, 객체·손글씨 시나리오) |
| INFRA | 전부 | 기반 단계 자리표시 구현, `pencil_bridge`는 가짜 `EventChannel` | 통합 7단계(실제 모듈 연결, V5 스모크) |

### 3.4 임계 경로

```
R2-B2 CORE 계약 타입 ─┬→ R2-B3 INK 공개 표면 ─┬→ EDITOR (객체 도구·녹음 연동)
                      │                        ├→ PDF (객체 벡터화)
                      │                        └→ LIBRARY/recog (패드·도형 판정기)
                      ├→ R2-B7 SYNC 컴파일 패치(EntityKind 값 추가는 SYNC switch를 깸)
                      └→ PDF/media_io (오디오 포트·이미지 타입)
통합: CORE → INK → SYNC → PDF(+media) → LIBRARY(+recog) → EDITOR → INFRA
```

- 가장 긴 사슬은 **CORE 객체 모델 → INK 객체 렌더·선택 → EDITOR 객체 도구**다. 기반 단계에서 INK가 객체를 '경계 상자 + 단순 그리기'로라도 그려 두면 EDITOR는 개발 첫날부터 실제 화면으로 상호작용을 만들 수 있다.
- 오디오·인식은 CORE 포트 타입만 있으면 독립적으로 진행된다(가짜로 EDITOR가, 실제로 media/recog가 각자).

---

## 4. 통합 계약 v2.0 초안

> **계약 v2.0 초안** — 1차 v1.4 위에 덮어쓴다. 확정 시 2차 개요 7장이 된다. 절 번호 옆 괄호는 1차 7장의 해당 절이다.

### 4.0 변경 분류와 원칙

- **공유 데이터 타입은 CORE**(1차 4장 원칙 1). 2차의 새 공유 타입 — 페이지 객체, 녹음 저장소·오디오 포트, 손글씨 인식 결과, 검색 색인, 이미지 가져오기 결과 — 은 모두 `note_core`(순수 Dart)가 정의한다. Flutter 타입(`BuildContext`, `Widget`, `Rect`)이 필요한 자리만 소비하는 패키지(EDITOR·LIBRARY)가 정의한다.
- **렌더는 INK 한 곳**. 화면·썸네일·PDF 벡터가 모두 INK를 거친다(1차 원칙 유지). 새 객체·새 펜의 그리기 의미는 INK가 정하고 CORE가 저장한다(1차 7.2.4 원칙 확장).
- 새 이름은 6+3개 패키지 공개 진입점에서 서로 겹치지 않는다(1차 7.2.0, R14). 특히 Flutter·`material_ui`와 겹치는 이름을 피했다: `TextBox`(dart:ui)·`Ink`(material_ui) 대신 `TextBoxObject`·`HandwritingTrace`를 쓴다.
- 깨짐 변경 요약: CORE `EntityKind` 값 2개 추가(→ SYNC·CORE switch), CORE `NoteStore` 멤버 추가(→ CORE 구현만), EDITOR `StylusExtrasSource` 멤버 추가·`StylusExtraEvent` 하위 타입 추가(→ 구독자 없음), INK `InkEditKind`·`InkRenderMethod`·`InkLayer`·`InkRenderLayer` 값 추가(→ 다른 패키지에 exhaustive switch 없음 — `grep` 확인). 나머지는 '추가'·'규칙'이다.

### 4.1 패키지 구조와 의존 방향 (7.1)

| 패키지 | 소유 | 종류 | 허용 의존(형제) | 공개 진입점 |
|---|---|---|---|---|
| `note_core` | CORE | 순수 Dart | — | v1.4 그대로(`note_core.dart`·`testing.dart`·`testing_vm.dart`·`dev_tools.dart`) |
| `ink_engine` | INK | Flutter 패키지 | `note_core` | v1.4 그대로. 패키지 에셋 `assets/fonts/` 추가 |
| `feature_editor` | EDITOR | Flutter 패키지 | `note_core`, `ink_engine` | v1.4 그대로 |
| `feature_library` | LIBRARY | Flutter 패키지 | `note_core` | v1.4 그대로 |
| `pdf_io` | PDF | Flutter 패키지 | `note_core`, `ink_engine` | v1.4 그대로 |
| `sync_engine` | SYNC | v1.4 그대로 | `note_core` | v1.4 그대로 |
| **`media_io`** (새) | PDF | Flutter 패키지(플러그인 사용) | `note_core` | `media_io.dart`, `testing.dart`(테스트 전용) |
| **`ink_recognition`** (새) | LIBRARY | Flutter 패키지(플러그인 사용) | `note_core`, `ink_engine` | `ink_recognition.dart`, `testing.dart`(테스트 전용) |
| **`pencil_bridge`** (새) | INFRA | Flutter 플러그인(iOS만 구현, 그 밖은 지원 안 함) | — | `pencil_bridge.dart`(웹 안전) |
| `noteapp` (`app/`) | INFRA | Flutter 앱 | 위 전부(`sync_engine` 제외 — 1.4) | — |
| `functions/` | SYNC | Node 22 + TypeScript (워크스페이스 멤버 아님) | — | Firebase callable 함수(4.14) |

`tool/workspace_rules.yaml` `allowed_dependencies`(R8)에 새 세 패키지와 `noteapp: [..., media_io, ink_recognition, pencil_bridge]`를 더한다. `ws check`는 `functions/`를 검사 대상에서 뺀다(R1~R15는 Dart 멤버만).

### 4.2 소유표 추가분 (7.2.1)

| 타입 · 인터페이스 | 소유 | 사용 영역 | 정의 |
|---|---|---|---|
| `PagePoint`, `ElementFrame` | note_core | 전 영역 | 4.3 |
| `PageObject`(sealed) · `ShapeObject` · `TextBoxObject` · `ImageObject` · `MathObject` · `UnknownObject`, `ShapeKind`·`ShapeGeometry`(`PolylineGeometry`·`EllipseGeometry`)·`ShapeStyle`·`LineDash`·`ArrowHeads`, `TextBoxStyle`·`TextAlignKind`, `MathStyle`, `PageObjectLimits` | note_core | INK, EDITOR, PDF, SYNC, recog | 4.3 |
| `AddObjects`, `UpdateObjects`, `RemoveElements`, `ClearPage.includeObjects`, `PageContent.objects`, `PageDraft.objects` | note_core | EDITOR, INK, PDF, recog | 4.4 |
| `Recording.title`, `RecordingRepository`, `RecordingDraftStore`·`RecordingDraft`, `AudioRecorderService`·`RecorderStatus`·`RecorderPhase`, `AudioPlaybackService`·`PlaybackStatus`·`PlaybackPhase`, `AudioSupport`, 오디오 provider | note_core | EDITOR, media | 4.5 |
| `HandwritingText`·`HandwritingLine`, `HandwritingRepository`, `SearchIndex`·`SearchIndexWriter`·`SearchSource`·`SearchUnitDraft`·`PageSearchHit`·`SearchIndexStatus`, `SearchText`, `LibrarySearchResult.pages` | note_core | LIBRARY, recog, PDF, SYNC | 4.6 |
| `ImageImportSource`, `ImportedImage`, `ImageImportLimits`, `AssetStorageUsage.bytesByType`, `NoteStoreConfig.nativeAssetDirectoryPath` | note_core | EDITOR, media, INFRA | 4.7 |
| 펜 extras 키, 렌더 층, 객체 렌더·선택·적중 API, `InkShapeFitter`, `InkPlaybackFocus`, 테이프·레이저, `ImageBackgroundLayerBuilder`·`InkImageCache`, 벡터 내보내기 v2, `InkMathRenderer`·`MathPreview`, `InkFonts`·`InkTextLayout` | ink_engine | EDITOR, PDF, recog, INFRA | 4.10 |
| `EditorExtensions` v2 · 선택/삽입 메뉴 자리 · 녹음 패널 자리 · `EditorImageImporter`, `EditorGesture`·`EditorAction`·`GestureSettings` v2, `StylusExtras` v2, `EditorScreen.initialFocusRectPt` | feature_editor | INFRA | 4.11 |
| `LibraryScreen.onOpenNoteAt` | feature_library | INFRA | 4.12 |
| 인식 엔진 포트·가짜·`recognitionOverrides`·`RecognitionAction`·`HandwritingIndexer`·`GeometricShapeFitter`·`RecognitionSettingsSection` | ink_recognition | INFRA | 4.12 |
| `pdfIoOverrides` v2, `PdfSearchIndexer` | pdf_io | INFRA | 4.13 |
| `initializeMediaIo`·`mediaIoOverrides`·`importImageForNote`·`supportedImageSources`·`RecordingPanel`·`mediaDevOverlayLinesProvider` | media_io | INFRA | 4.13 |
| `PencilBridge`·`PencilEvent` 계열·`PencilCapabilities` | pencil_bridge | INFRA | 4.14 |
| `recognizeMath` callable 형식 | functions/ | recog | 4.14 |

### 4.3 페이지 객체 (note_core)

결정 (조사 01 R1·R3 채택, 변형 포함):

- 획이 아닌 페이지 요소는 **`EntityKind` 하나(`pageObject`)와 테이블 하나(`page_objects`)**로 넣고, 종류는 JSON `type`(`shape`·`text`·`image`·`math`)으로 나눈다. 종류마다 `EntityKind`를 두면 SYNC·CORE switch와 매핑이 네 배가 된다.
- 모르는 `type`은 원본 JSON을 보존하는 `UnknownObject`로 읽고, `frame` 자리에 자리표시를 그리고, 그대로 동기화한다(다음 라운드에 종류가 늘어도 옛 앱이 기록을 잃지 않음).
- 모든 객체는 회전 가능한 상자 `ElementFrame`을 가진다. 도형만 꼭짓점 기하(`ShapeGeometry`)가 원본이고 `frame`은 거기서 계산한다.
- z 순서는 1차 `Stroke.compareOrder`(createdAt → id) 그대로다. '맨 앞/뒤로'는 이번에 하지 않는다(6.3 D2). 층(어느 묶음이 위에 그려지는가)은 INK가 종류로 정한다(4.10 L-1).

```dart
// lib/src/common/geometry.dart — (v2.0) added
@immutable
final class PagePoint {
  const PagePoint(this.x, this.y);               // pt, page coordinates, y down
  final double x, y;
  PagePoint transformed(Affine2 m);
}

/// (v2.0) Rotated box in page pt. [rect] is the UNROTATED box; [rotation] (rad, clockwise
/// on screen because y is down) turns it about rect's center.
@immutable
final class ElementFrame {
  const ElementFrame(this.rect, {this.rotation = 0});
  final PageRect rect;                           // width, height in [0, 14400] (a straight line's frame may be flat)
  final double rotation;                         // normalized to (-pi, pi]
  PagePoint get center;
  List<PagePoint> get corners;                   // tl, tr, br, bl after rotation
  PageRect get bounds;                           // AABB of corners
  /// Similarity transforms (move / uniform scale / rotate) are exact: center' = m(center),
  /// width·s, height·s, rotation + m.rotation, s = m.uniformScale. Other transforms are
  /// approximated the same way (EDITOR sends non-uniform resizes as UpdateObjects).
  ElementFrame transformed(Affine2 m);
  bool contains(PagePoint p, {double tolerance = 0});
  List<double> toJson();                         // [left, top, right, bottom, rotation]
  factory ElementFrame.fromJson(List<Object?> json);   // FormatException on bad input
}
```

```dart
// lib/src/model/stroke.dart — PageElement stays sealed; the new subtypes are `part` files
// of this library (page_object.dart, shape_object.dart, …).
sealed class PageElement implements SyncEntity { /* v1.4: id, pageId, bounds, createdAt, updatedAt */ }
final class Stroke extends PageElement { /* v1.4 */ }

/// (v2.0) Every page element that is not a Stroke: EntityKind.pageObject, table
/// `page_objects`, subtype chosen by JSON `type`.
sealed class PageObject extends PageElement {
  const PageObject();
  @override EntityKind get kind => EntityKind.pageObject;
  String get type;                               // 'shape' | 'text' | 'image' | 'math' | unknown
  ElementFrame get frame;
  @override EpochMillis? get deletedAt;
  @override Hlc? get version;
  /// Assets this object references (ImageObject: {assetId}); others empty.
  Set<AssetId> get referencedAssets;
  /// TransformElements. UnknownObject returns itself unchanged.
  PageObject transformed(Affine2 m);
  /// Paste / duplicate / page copy: new id, page and createdAt; version and deletedAt cleared.
  PageObject copyTo({required ElementId id, required PageId pageId, required EpochMillis createdAt});
  PageObject copyWithMeta({EpochMillis? updatedAt, EpochMillis? deletedAt,
      bool clearDeletedAt = false, Hlc? version});
  @override Map<String, Object?> toJson();
  /// Dispatches on `type`; an unknown type → UnknownObject (never throws for that reason).
  factory PageObject.fromJson(Map<String, Object?> json);
}

abstract final class PageObjectLimits {
  static const int maxObjectsPerPage = 2000;
  static const int maxTextLength = 10000;        // TextBoxObject.text, String.length
  static const int maxLatexLength = 4000;
  static const int maxPolylinePoints = 64;
}
```

```dart
// --- shapes ---
enum ShapeKind { line, arrow, rectangle, ellipse, triangle, polygon, star }
enum LineDash { solid, dashed, dotted }          // INK renders; dash lengths in multiples of strokeWidth
enum ArrowHeads { none, end, both }

@immutable
final class ShapeStyle {
  const ShapeStyle({required this.strokeColorArgb, this.strokeWidth = 2.0, this.strokeOpacity = 1.0,
      this.dash = LineDash.solid, this.fillColorArgb, this.fillOpacity = 1.0,
      this.arrowHeads = ArrowHeads.none});
  static const double minWidth = 0.1, maxWidth = 30.0;   // = StrokeStyle range
  final int strokeColorArgb;                     // alpha forced to 0xFF by normalized() (1차 K-5와 같음)
  final double strokeWidth;                      // pt
  final double strokeOpacity;                    // [0.05, 1]
  final LineDash dash;
  final int? fillColorArgb;                      // null = no fill
  final double fillOpacity;                      // [0, 1]
  final ArrowHeads arrowHeads;                   // line / arrow only; others ignore it
  /// Arrowhead length in pt: max(6, 3 * strokeWidth). Part of the bounds rule below.
  double get arrowHeadLength;
  ShapeStyle normalized();
  ShapeStyle copyWith({int? strokeColorArgb, double? strokeWidth, double? strokeOpacity,
      LineDash? dash, int? fillColorArgb, bool clearFill = false, double? fillOpacity,
      ArrowHeads? arrowHeads});
  Map<String, Object?> toJson();
  factory ShapeStyle.fromJson(Map<String, Object?> json);
}

/// Shape geometry in ABSOLUTE page pt. Vertex editing moves PolylineGeometry.points.
sealed class ShapeGeometry {
  const ShapeGeometry();
  ShapeGeometry transformed(Affine2 m);
  ElementFrame get frame;                        // polyline: AABB of points (rotation 0); ellipse: its frame
  Object toJson();                               // {"poly":[x0,y0,…],"closed":bool} | {"ellipse":[l,t,r,b,rot]}
  factory ShapeGeometry.fromJson(Object? json);
  // Templates (pure geometry, used by EDITOR's shape tool and the shape fitter):
  static PolylineGeometry line(PagePoint a, PagePoint b);
  static PolylineGeometry rectangle(PageRect r, {double rotation = 0});         // 4 points, clockwise from top-left
  static EllipseGeometry ellipse(PageRect r, {double rotation = 0});
  static PolylineGeometry triangle(PageRect r);                                 // isosceles, apex up
  static PolylineGeometry regularPolygon(PageRect r, int sides, {double rotation = 0});   // 3..12
  static PolylineGeometry star(PageRect r, {int points = 5, double innerRatio = 0.5});    // 2·points vertices
}
final class PolylineGeometry extends ShapeGeometry {
  const PolylineGeometry(this.points, {required this.closed});
  final List<PagePoint> points;                  // 2..PageObjectLimits.maxPolylinePoints
  final bool closed;
}
final class EllipseGeometry extends ShapeGeometry {
  const EllipseGeometry(this.ellipseFrame);
  final ElementFrame ellipseFrame;               // bounding box before rotation
}

final class ShapeObject extends PageObject {
  ShapeObject({required this.id, required this.pageId, required this.shapeKind,
      required this.geometry, required this.style, required this.createdAt, int? updatedAt,
      this.deletedAt, this.version});
  @override String get type => 'shape';
  final ShapeKind shapeKind;                     // UI meaning only; geometry is the truth
  final ShapeGeometry geometry;
  final ShapeStyle style;
  @override ElementFrame get frame => geometry.frame;
  /// Derived, identical on every device (K-6):
  ///   geometry.frame.bounds.inflate(style.strokeWidth * 0.75
  ///       + (arrowHeads != none && shapeKind is line|arrow ? style.arrowHeadLength : 0))
  @override PageRect get bounds;
  ShapeObject copyWith({ShapeKind? shapeKind, ShapeGeometry? geometry, ShapeStyle? style,
      EpochMillis? updatedAt});
  // id, pageId, createdAt, updatedAt, deletedAt, version — as Stroke
}
```

```dart
// --- text boxes, images, math ---
enum TextAlignKind { start, center, end }

@immutable
final class TextBoxStyle {
  const TextBoxStyle({this.fontSizePt = 16, this.colorArgb = 0xFF1A1A1A, this.bold = false,
      this.align = TextAlignKind.start, this.lineHeight = 1.4, this.backgroundArgb});
  static const double minFontSize = 6, maxFontSize = 144;
  final double fontSizePt;
  final int colorArgb;                           // alpha 0xFF
  final bool bold;
  final TextAlignKind align;
  final double lineHeight;                       // [1.0, 3.0], multiple of fontSizePt
  final int? backgroundArgb;                     // null = transparent
  TextBoxStyle normalized();
  TextBoxStyle copyWith({double? fontSizePt, int? colorArgb, bool? bold, TextAlignKind? align,
      double? lineHeight, int? backgroundArgb, bool clearBackground = false});
  Map<String, Object?> toJson();
  factory TextBoxStyle.fromJson(Map<String, Object?> json);
}

final class TextBoxObject extends PageObject {
  TextBoxObject({required this.id, required this.pageId, required this.frame, required this.text,
      required this.style, required this.createdAt, int? updatedAt, this.deletedAt, this.version});
  @override String get type => 'text';
  /// frame.rect.width = wrap width; height = laid-out height written by EDITOR with
  /// INK InkTextLayout.measure (4.10). INK clips the text to the frame (K-6).
  @override final ElementFrame frame;
  final String text;                             // plain text, '\n' = line break, ≤ maxTextLength
  final TextBoxStyle style;
  @override PageRect get bounds => frame.bounds;
  TextBoxObject copyWith({ElementFrame? frame, String? text, TextBoxStyle? style, EpochMillis? updatedAt});
}

final class ImageObject extends PageObject {
  ImageObject({required this.id, required this.pageId, required this.frame, required this.assetId,
      required this.pixelWidth, required this.pixelHeight, required this.createdAt, int? updatedAt,
      this.deletedAt, this.version});
  @override String get type => 'image';
  @override final ElementFrame frame;            // aspect = pixel aspect unless the user unlocks it
  final AssetId assetId;                         // AssetType.image, mime image/jpeg | image/png (4.7)
  final int pixelWidth, pixelHeight;             // intrinsic size of the stored bytes
  @override PageRect get bounds => frame.bounds;
  @override Set<AssetId> get referencedAssets => {assetId};
  ImageObject copyWith({ElementFrame? frame, EpochMillis? updatedAt});
}

@immutable
final class MathStyle {
  const MathStyle({this.colorArgb = 0xFF1A1A1A, this.fontSizePt = 18});
  final int colorArgb;
  final double fontSizePt;                       // [6, 144]; scaled by TransformElements
  Map<String, Object?> toJson();
  factory MathStyle.fromJson(Map<String, Object?> json);
}

final class MathObject extends PageObject {
  MathObject({required this.id, required this.pageId, required this.frame, required this.latex,
      required this.style, this.engineId, required this.createdAt, int? updatedAt, this.deletedAt,
      this.version});
  @override String get type => 'math';
  /// Laid out by INK InkMathRenderer at style.fontSizePt when inserted / edited; INK draws the
  /// formula contain-fitted into the frame (K-6), so devices with other metrics stay inside.
  @override final ElementFrame frame;
  final String latex;                            // ≤ maxLatexLength; INK validate() == null before insert
  final MathStyle style;
  final String? engineId;                        // provenance: 'manual', 'mathpix/…', 'claude/…'
  @override PageRect get bounds => frame.bounds;
  MathObject copyWith({ElementFrame? frame, String? latex, MathStyle? style, String? engineId,
      EpochMillis? updatedAt});
}

/// Object written by a newer app. It can be selected, deleted and copied as a whole and is
/// synced unchanged; it cannot be transformed or edited. JSON round-trips key-for-key (C-12).
final class UnknownObject extends PageObject {
  @override final String type;
  final Map<String, Object?> rawJson;
  /// From rawJson['frame'] when decodable, else ElementFrame(PageRect(0, 0, 1, 1)).
  @override final ElementFrame frame;
  @override PageRect get bounds => frame.bounds;
}
```

- `EntityKind`(깨짐): `enum EntityKind { folder, note, page, stroke, penPreset, asset, recording, setting, pageObject, handwriting }` — 뒤에 둘을 더한다. 이름(wire)은 enum 이름 그대로다.
- `Stroke.compareOrder(PageElement a, PageElement b)`는 그대로 객체에도 쓴다(createdAt → id).
- 붙여넣기·복제된 객체는 `copyTo`로 새 `createdAt`(= 붙여넣은 시각 + i, 1차 획 클립보드 규칙과 같음)을 받는다.

### 4.4 페이지 내용 · 초안 · 편집 명령 (7.2.7, 7.2.8 — note_core)

```dart
final class PageContent {                                         // 추가
  PageContent({required this.page, required List<Stroke> strokes,
      List<PageObject> objects = const [], required this.revision});
  final List<PageObject> objects;              // active only, Stroke.compareOrder
  PageObject? objectById(ElementId id);
  PageElement? elementById(ElementId id);       // stroke or object
  int get objectCount;
  // page, strokes, revision, strokeById, strokeCount — v1.4
}
// PageContentChange.added/removed/updated: element ids (strokes AND objects) — v1.4 type, wider meaning

final class PageDraft {                                           // 추가
  const PageDraft({this.id, required this.size, required this.background,
      this.strokes = const [], this.objects = const []});
  final List<PageObject> objects;              // copied with new ids by InsertPages / DuplicatePages
  factory PageDraft.copyOf(PageContent content); // strokes AND objects
}
```

```dart
// (v2.0) new commands — 추가 (EditCommand is sealed; the only exhaustive switch is CORE's resolver)
/// objects: new ids, version == null, pageId == this.pageId. ≤ PageObjectLimits.maxObjectsPerPage.
final class AddObjects extends EditCommand { AddObjects(this.pageId, this.objects); final PageId pageId; final List<PageObject> objects; }
/// Replace by id (same id, same type). UnknownObject or a missing id → ArgumentError before any
/// change. Only JSON keys whose value changed get a new field version (7.2.10, C-11).
final class UpdateObjects extends EditCommand { UpdateObjects(this.pageId, this.objects); final PageId pageId; final List<PageObject> objects; }
/// Removes strokes AND objects by id; unknown / already deleted ids ignored (like RemoveStrokes).
final class RemoveElements extends EditCommand { RemoveElements(this.pageId, this.elementIds); final PageId pageId; final Set<ElementId> elementIds; }

// (v2.0) changed meaning — 규칙
// TransformElements(pageId, elementIds, transform, scaleStrokeWidth): strokes as v1.4 AND
//   PageObject.transformed(transform) (ShapeObject: geometry; MathObject: also fontSizePt ×
//   uniformScale; UnknownObject skipped). scaleStrokeWidth also scales ShapeStyle.strokeWidth.
// ClearPage(pageId, filter = StrokeFilter.all, {bool includeObjects = false}) — 추가:
//   includeObjects removes every PageObject too (filter applies to strokes only).
// InsertPages / DuplicatePages: PageDraft.objects copied with new ids.
// DeletePages / page purge / note copy / backup: objects follow strokes (CORE 동작 계약).
```

EDITOR 명령 매핑(04-editor 5.1 표에 더할 것):

| 사용자 동작 | 명령 (한 번 = 되돌리기 1단계) |
|---|---|
| 도형 그리기 완료, 자동 보정 확정 | `AddObjects([ShapeObject])` (자동 보정 때 원래 획은 저장되지 않음) |
| 텍스트 상자 만들기 → 입력 → 포커스 해제 | 새 상자: `AddObjects`, 기존 상자: `UpdateObjects` (편집 세션 1회 = 1단계, E-6) |
| 핸들로 비율 무시 크기 조절, 꼭짓점 이동, 스타일 변경 | `UpdateObjects` |
| 선택 이동·비율 유지 크기·회전 | `TransformElements` (획 + 객체) |
| 선택 색 변경 | `CompositeCommand([RestyleStrokes, UpdateObjects])` (빈 쪽은 뺌) |
| 잘라내기 | 클립보드 복사 + `RemoveElements` 한 번 |
| 붙여넣기 | `CompositeCommand([AddStrokes, AddObjects])` |
| 손글씨 → 텍스트 상자 | `CompositeCommand([RemoveElements(획), AddObjects([TextBoxObject])])` (recog가 `execute`로) |
| 이미지 삽입 | `AddObjects([ImageObject])`, 이미지 페이지: `InsertPages([PageDraft(background: ImageBackground)])` |

### 4.5 녹음 (note_core) — 엔티티 · 저장소 · 오디오 포트 · 획 연결 규칙

```dart
// Recording (v1.4 CORE 4.2) — 추가: title
final class Recording implements SyncEntity {
  const Recording({/* v1.4 fields */, this.title});
  final String? title;                           // trimmed 1..100 chars; null → UI shows '녹음 N' by startedAt order
  Recording copyWith({/* v1.4 */, String? title, bool clearTitle = false});
  // JSON: 'title' (absent = null). Old apps ignore it (no deployed old app before 실연결).
}

/// (v2.0) Local create / list API (v1.4 had only the remote-apply path).
abstract interface class RecordingRepository {
  Stream<List<Recording>> watchRecordings(NoteId noteId);   // active, startedAt asc
  Future<List<Recording>> recordingsOf(NoteId noteId);
  Future<Recording?> getRecording(RecordingId id);           // also deleted ones
  /// Called by media_io AFTER AssetStore.put(audio) returned (M-1). [id] was chosen at
  /// record start so strokes could link to it immediately.
  Future<Recording> createRecording({required RecordingId id, required NoteId noteId,
      required AssetId assetId, required int durationMs, required EpochMillis startedAt, String? title});
  Future<void> renameRecording(RecordingId id, String? title);
  /// Soft delete; no restore UI this round. Strokes keep recordingId (R-7). Asset bytes stay
  /// until asset GC (later, 1.3).
  Future<void> deleteRecording(RecordingId id);
  /// Σ Asset.size of the note's active recordings (재생 바 '용량').
  Future<int> audioBytesOf(NoteId noteId);
}

/// (v2.0) Crash-safe staging of an in-progress recording. Device-local: never synced, never in
/// backups, not in outbox. Chunks live in the asset blob store under a private prefix.
abstract interface class RecordingDraftStore {
  Future<RecordingDraft> begin({required RecordingId recordingId, required NoteId noteId,
      required String mimeType, required EpochMillis startedAt});
  /// Ordered append; each chunk ≤ 4 MiB; completes after the chunk is durable (write-Future rule).
  Future<void> append(String draftId, Uint8List chunk, {required int activeMs});
  Future<List<RecordingDraft>> listDrafts();     // leftovers after a crash / closed tab
  Future<Uint8List> readAll(String draftId);
  Future<void> discard(String draftId);
}
@immutable
final class RecordingDraft {
  const RecordingDraft({required this.draftId, required this.recordingId, required this.noteId,
      required this.mimeType, required this.startedAt, required this.chunkCount, required this.bytes,
      required this.activeMs, required this.updatedAt});
  final String draftId; final RecordingId recordingId; final NoteId noteId; final String mimeType;
  final EpochMillis startedAt; final int chunkCount, bytes, activeMs; final EpochMillis updatedAt;
}
```

```dart
// lib/src/media/audio_ports.dart — (v2.0) pure Dart ports. Implemented by media_io, consumed
// by EDITOR (and media_io's own panel). One recorder and one player per app.
enum AudioSupport { supported, unsupported, permissionDenied, permissionPermanentlyDenied }
enum RecorderPhase { idle, starting, recording, paused, finishing }

@immutable
final class RecorderStatus {
  const RecorderStatus({this.phase = RecorderPhase.idle, this.recordingId, this.noteId,
      this.activeMs = 0, this.backgroundCapable = false, this.interrupted = false,
      this.mimeType, this.crossPlatformPlayable = true, this.error});
  final RecorderPhase phase;
  final RecordingId? recordingId;
  final NoteId? noteId;                          // the note the recording belongs to
  final int activeMs;                            // audio-timeline length so far (pauses excluded)
  final bool backgroundCapable;                  // native FGS / UIBackgroundModes; false on web
  final bool interrupted;                        // paused by the system / hidden tab, not the user
  final String? mimeType;                        // what is actually being written
  final bool crossPlatformPlayable;              // false for webm/opus (iOS native can't play it)
  final Object? error;
  bool get isActive;                             // recording || paused
  // ==, hashCode (7.4.4)
}

abstract interface class AudioRecorderService {
  RecorderStatus get status;
  Stream<RecorderStatus> get statusStream;       // emits current value on listen
  Future<AudioSupport> checkSupport({bool requestPermission = false});
  /// [recordingId] is generated by the caller (core.idGeneratorProvider) BEFORE start so the
  /// first stroke can link to it. Throws StateError when another recording is active.
  Future<void> start({required RecordingId recordingId, required NoteId noteId});
  Future<void> pause();
  Future<void> resume();
  /// Finishes the file, stores Asset(audio) then Recording (M-1). null when nothing was recorded.
  Future<Recording?> stop();
  Future<void> cancel();                         // discards the draft; no Recording row
  /// Audio-timeline ms now (pauses excluded); null unless phase == recording. Synchronous and
  /// cheap — EDITOR calls it at pen down (R-1, R-2).
  int? offsetNowMs();
  Future<List<RecordingDraft>> pendingDrafts();
  Future<Recording?> recoverDraft(String draftId);
}

enum PlaybackPhase { idle, loading, ready, playing, paused, completed, failed }
@immutable
final class PlaybackStatus {
  const PlaybackStatus({this.phase = PlaybackPhase.idle, this.recordingId, this.durationMs = 0,
      this.speed = 1.0, this.unsupportedFormat = false, this.error});
  final PlaybackPhase phase; final RecordingId? recordingId; final int durationMs;
  final double speed;                            // [0.5, 2.0]
  final bool unsupportedFormat;                  // e.g. webm on iOS native
  final Object? error;
}
abstract interface class AudioPlaybackService {
  PlaybackStatus get status;
  Stream<PlaybackStatus> get statusStream;
  /// Bytes via AssetStore; when missing locally and remoteAssetFetcherProvider is set,
  /// ensureLocal first (P-2 pattern). Closes any open recording.
  Future<void> open(Recording recording);
  Future<void> play();
  Future<void> pause();
  Future<void> seekMs(int positionMs);           // clamped to [0, durationMs]
  Future<void> setSpeed(double speed);           // clamped to [0.5, 2.0]
  /// Extrapolated position (no platform call). Call every frame.
  int positionMs();
  Future<void> close();
}

// Defaults: web/VM without media_io → unsupported (no throw on read).
final audioRecorderServiceProvider = Provider<AudioRecorderService>(
    (ref) => const UnsupportedAudioRecorder(), name: 'audioRecorderServiceProvider');
final audioPlaybackServiceProvider = Provider<AudioPlaybackService>(
    (ref) => const UnsupportedAudioPlayback(), name: 'audioPlaybackServiceProvider');
final recordingRepositoryProvider = Provider<RecordingRepository>(/* store.recordings */);
final noteRecordingsProvider =
    StreamProvider.autoDispose.family<List<Recording>, NoteId>(/* watchRecordings */);
// testing.dart: FakeAudioRecorder (controllable clock, phases, interruptions),
//               FakeAudioPlayback (manual position, speed) — 7.4.8 공용 가짜
```

획 ↔ 녹음 연결 규칙(계약 문장, 조사 02 6·12.4 채택):

| # | 규칙 |
|---|---|
| R-1 | 펜 다운 순간 `recorder.status.phase == recording` **그리고** `status.noteId == 지금 노트`일 때만 `InkStrokeMeta(recordingId, offsetNowMs())`를 넘긴다. 일시정지 중·다른 노트에서 녹음 중에 쓴 획은 연결하지 않는다(사용자 질문 U12 기본값) |
| R-2 | `recordingOffsetMs`는 **오디오 타임라인 위치**(일시정지 제외)다. 벽시계 차(`createdAt − startedAt`)를 쓰지 않는다. media_io는 단조 `Stopwatch`를 녹음기 상태 이벤트에 맞춰 멈추고 이어 간다 |
| R-3 | `Recording.durationMs` = 저장된 파일을 디코더가 읽은 길이. 시계 활성 시간과의 차이는 개발자 표시에만 보인다(보정 필드는 실측 뒤 판단 — D9 체크리스트) |
| R-4 | 재생 위치 p에서 획은 `recordingOffsetMs + t_last ≤ p`이면 '쓴 획', `offset ≤ p < offset + t_last`이면 '쓰는 중'이다(INK 4.10 재생 강조) |
| R-5 | 필기 탭 재생은 `seekMs(max(0, offset − preRollMs))` 후 재생, `preRollMs` 기본 1500(설정 `editor.playback.preRollMs`, synced) |
| R-6 | 부분 지우개 조각·붙여넣기·복제는 `recordingId/OffsetMs`를 유지한다(v1.4 그대로). **노트 복사**는 녹음 행도 새 id로 복사하고(에셋은 같은 해시), 복사된 획의 `recordingId`를 새 id로 바꾼다(CORE `copyNote` 동작 계약) |
| R-7 | `recordingId`가 가리키는 녹음 행이 없거나 삭제됐으면 '연결 없음'으로 다룬다(오류 아님). 녹음이 취소(`cancel`)되면 이미 쓴 획의 `recordingId`는 그대로 남고 연결 없음이 된다 |
| R-8 | 녹음 시작·정지·이름·삭제는 되돌리기 히스토리 밖이다(삭제는 확인 창) |

### 4.6 손글씨 인식 결과 · 검색 색인 (note_core)

결정(조사 01 R7, 03 R3·R8 채택):

- 손글씨 인식 결과는 **동기화되는 엔티티**(`EntityKind.handwriting`)로 페이지마다 하나 둔다. 웹(ML Kit 불가)은 네이티브가 만든 결과를 받아 검색만 한다(실연결 뒤).
- id는 결정적이다: `HandwritingText.idFor(pageId) = 'hw_' + pageId`(1차 7.4.6 ID 규칙의 예외에 추가 — 두 기기가 같은 페이지를 인식해도 같은 엔티티가 된다).
- 검색 색인(`search_units` + FTS5)은 **기기 로컬 파생 데이터**다. 동기화·백업하지 않고 언제든 다시 만든다.
- 한국어 토큰화는 '음절 바이그램을 Dart에서 만들어 `unicode61` 내용 없는 테이블에 넣는' 방식(조사 03 9.2 실험)으로 한다. 정규화 함수는 제목·PDF·손글씨·텍스트 상자가 **하나**(`SearchText.normalize`)를 쓴다.

```dart
@immutable
final class HandwritingLine {
  const HandwritingLine({required this.text, this.alternatives = const [], required this.rect,
      required this.strokeIds, this.languageTag = 'ko', this.userConfirmed = false});
  final String text;                             // best, user-chosen or user-edited text
  final List<String> alternatives;               // ≤ 5, engine order
  final PageRect rect;                           // union of the line strokes' pointBounds, page pt
  final List<ElementId> strokeIds;
  final String languageTag;                      // BCP-47 of the model that produced [text]
  final bool userConfirmed;                      // set by the conversion UI; auto re-recognition keeps it
  Map<String, Object?> toJson();
  factory HandwritingLine.fromJson(Map<String, Object?> json);
}

final class HandwritingText implements SyncEntity {
  HandwritingText({required this.noteId, required this.pageId, required this.engineId,
      required this.sourceRev, required this.lines, required this.createdAt, int? updatedAt,
      this.deletedAt, this.version}) : id = idFor(pageId);
  static String idFor(PageId pageId) => 'hw_$pageId';
  /// Input strokes = active strokes of the page whose tool is not highlighter / tape / laser.
  /// sourceRev = first 16 hex chars of sha256 over "id:updatedAt;" of those strokes sorted by id.
  static String sourceRevOf(Iterable<Stroke> inputStrokes);
  static bool isRecognitionInput(Stroke s);
  @override final String id;
  final NoteId noteId; final PageId pageId;
  final String engineId;                         // 'mlkit-digital-ink/19.0.0:ko'
  final String sourceRev;
  final List<HandwritingLine> lines;             // reading order
  @override EntityKind get kind => EntityKind.handwriting;
  // createdAt, updatedAt, deletedAt, version, isDeleted, toJson / fromJson, ==
}

abstract interface class HandwritingRepository {
  Future<HandwritingText?> forPage(PageId pageId);
  Stream<HandwritingText?> watchPage(PageId pageId);
  /// Upsert (recognizer, conversion UI). Also re-indexes the page's ink units (same transaction
  /// when possible; an index failure never fails the write — C-13).
  Future<void> put(HandwritingText value);
  Future<void> removeForPage(PageId pageId);
  /// Active pages of [noteId] whose input strokes' sourceRevOf differs from the stored value
  /// (or that have none and at least one input stroke). Cheap: uses DB columns, no point decode.
  Future<List<PageId>> stalePages(NoteId noteId);
}
final handwritingRepositoryProvider = Provider<HandwritingRepository>(/* store.handwriting */);
```

```dart
enum SearchSource { ink, pdf, text, math }

@immutable
final class SearchUnitDraft {
  const SearchUnitDraft({required this.body, this.rects = const []});
  final String body;                             // original text (CORE normalizes)
  final List<PageRect> rects;                    // source pdf: fractions [0,1] of the PDF page
}

/// For pdf_io (source pdf only). ink / text / math are indexed by CORE itself from
/// HandwritingText and PageObject rows (no other package writes them).
abstract interface class SearchIndexWriter {
  /// ownerKey for pdf: '<assetId>#<pdfPageIndex>' (one entry per PDF page, shared by every note
  /// that uses the asset). sourceRev for pdf: '<assetId>:<SearchText.normalizerVersion>'.
  Future<String?> sourceRevOf(SearchSource source, String ownerKey);
  Future<void> replaceUnits(SearchSource source, String ownerKey, List<SearchUnitDraft> units,
      {required String sourceRev});
  Future<void> removeOwner(SearchSource source, String ownerKey);
}

@immutable
final class PageSearchHit {
  const PageSearchHit({required this.noteId, required this.pageId, required this.source,
      required this.snippet, required this.matchRange, this.rects = const [], required this.score});
  final NoteId noteId; final PageId pageId; final SearchSource source;
  final String snippet;                          // ≤ 80 chars of original text around the match
  final (int, int) matchRange;                   // [start, end) in snippet
  final List<PageRect> rects;                    // page pt of the note's Page.size (pdf converted)
  final double score;                            // higher = better; for ordering only
}

@immutable
final class SearchIndexStatus {
  const SearchIndexStatus({this.pendingOwners = 0, this.rebuilding = false, this.lastRebuildAt});
  final int pendingOwners; final bool rebuilding; final EpochMillis? lastRebuildAt;
}

abstract interface class SearchIndex implements SearchIndexWriter {
  /// normalize → bigram phrase query (FTS5) or LIKE fallback for 1-char queries; trashed notes
  /// excluded; results grouped by page, best score first.
  Future<List<PageSearchHit>> searchPages(String query, {int limit = 100, NoteId? withinNote});
  Stream<SearchIndexStatus> get status;
  /// Drops and rebuilds derived rows (also run when normalizerVersion changes).
  Future<void> rebuild({Set<SearchSource>? sources});
}
final searchIndexProvider = Provider<SearchIndex>(/* store.search */);

abstract final class SearchText {
  static const int normalizerVersion = 1;
  /// Hangul jamo composition → lowercase → whitespace folding. THE normalizer for titles
  /// (searchLibrary), PDF text, handwriting and text boxes (replaces common/text_normalize.dart's
  /// private copy and must equal pdf_io PdfTextNormalizer on the same input — test in PDF).
  static String normalize(String text);
  static String indexTerms(String normalized);  // syllable bigrams for Hangul words, words otherwise
  static String? matchQuery(String normalized); // FTS5 MATCH text; null → use LIKE fallback
}

// LibrarySearchResult (7.2.9) — 추가
final class LibrarySearchResult {
  const LibrarySearchResult({required this.query, required this.folders, required this.notes,
      this.pages = const [], this.pagesTruncated = false});
  final List<PageSearchHit> pages;               // content hits (ink, pdf, text, math)
  final bool pagesTruncated;
}
// LibraryRepository.searchLibrary(query, {limit = 50}) now also fills pages (≤ 100).
```

### 4.7 이미지 가져오기 · 에셋 · 저장소 묶음 (7.2.11, 7.2.12 — note_core)

```dart
enum ImageImportSource { photos, camera, files, clipboard }

@immutable
final class ImportedImage {
  const ImportedImage({required this.asset, required this.pixelWidth, required this.pixelHeight});
  final Asset asset;                             // AssetType.image, already in AssetStore
  final int pixelWidth, pixelHeight;
}

abstract final class ImageImportLimits {
  static const int maxLongSidePx = 2048;         // larger photos are downscaled (media_io)
  static const int maxBytes = 8 * 1024 * 1024;   // after re-encoding
  static const Set<String> storedMimeTypes = {'image/jpeg', 'image/png'};   // HEIC/WebP/GIF converted
}

// AssetStorageUsage — 추가
final class AssetStorageUsage { /* v1.4 */ final Map<AssetType, int> bytesByType; }

// NoteStoreConfig — 추가
final class NoteStoreConfig { /* v1.4 */ final String? nativeAssetDirectoryPath; }   // file BlobStore root (native)

// NoteStore — 깨짐(CORE 구현만): new getters
abstract interface class NoteStore {
  /* v1.4 */
  RecordingRepository get recordings;
  RecordingDraftStore get recordingDrafts;
  HandwritingRepository get handwriting;
  SearchIndex get search;
}
```

- 네이티브 저장(공통-1): `nativeDatabasePath`와 `nativeAssetDirectoryPath`가 모두 있으면 CORE는 파일 DB + 파일 블롭 저장소(`*_native.dart`, 청크 4 MiB 파일)를 쓴다. 둘 중 하나라도 없으면 1차처럼 `storageUnavailable`. 앱 셸이 `path_provider`의 앱 지원 디렉터리로 두 경로를 넘긴다(INFRA).
- 이미지 에셋은 `ImageImportLimits.storedMimeTypes`만 저장한다(PDF 이미지 객체 입력 형식과 같게 — JPEG는 `FPDFImageObj_LoadJpegFileInline`, PNG는 비트맵).

### 4.8 저장 형식 — JSON 키, DB 스키마 v2, 마이그레이션 (7.4.6, CORE 6.3·6.15)

페이지 객체 JSON(동기화·백업 공통, camelCase, 모르는 키 무시 — 1차 규칙 그대로):

| `type` | 공통 키 | 종류별 키 |
|---|---|---|
| (모두) | `id`, `pageId`, `type`, `frame`(`[l,t,r,b,rot]` — **모든 종류가 쓴다**: 옛 앱이 모르는 종류를 자리표시로 그릴 수 있게. 도형은 기하에서 계산한 값을 쓰고 읽을 때는 무시), `createdAt`, `updatedAt`, `deletedAt`, `version` | |
| `shape` | | `shape`(`ShapeKind` 이름), `geometry`(`{"poly":[x0,y0,…],"closed":true}` 또는 `{"ellipse":[l,t,r,b,rot]}`), `style`(`ShapeStyle.toJson`) |
| `text` | | `text`, `style`(`TextBoxStyle.toJson`) |
| `image` | | `assetId`, `px`(`[w,h]`) |
| `math` | | `latex`, `style`(`MathStyle.toJson`), `engine`(선택) |

손글씨 결과 JSON: `id`, `noteId`, `pageId`, `engineId`, `sourceRev`, `lines`(배열), `createdAt`, `updatedAt`, `deletedAt`, `version`. 녹음 JSON: v1.4 + `title`.

DB 스키마 v2(`kDatabaseSchemaVersion = 2`, 규칙 — CORE 내부, 이름은 CORE가 바꿀 수 있음):

| 테이블 | 열 | 비고 |
|---|---|---|
| `page_objects` | `id` PK, `page_id`, `note_id`(비정규화 — 영구 삭제·복사), `type`, `min_x`·`min_y`·`max_x`·`max_y`(= `bounds`), `data_json`(종류별 키 + `frame`), `asset_id`(이미지만, 참조·GC용), `created_at`, `updated_at`, `deleted_at`, `version`, `field_versions` | 색인 `(page_id, deleted_at)`, `note_id`, `asset_id` |
| `handwriting` | `id` PK(`hw_<pageId>`), `page_id`, `note_id`, `engine_id`, `source_rev`, `lines_json`, 시간 열, `version`, `field_versions` | |
| `recordings` | + `title` (NULL 허용) | `ALTER TABLE ADD COLUMN` |
| `recording_drafts` | `draft_id` PK, `recording_id`, `note_id`, `mime_type`, `started_at`, `chunk_count`, `bytes`, `active_ms`, `updated_at` | 기기 로컬, outbox·백업 제외 |
| `search_units` | `id` INTEGER PK, `source`, `owner_key`, `note_id`, `page_id`(pdf는 NULL), `body`, `rects`(BLOB), `source_rev`, UNIQUE(`source`,`owner_key`) | 파생, 기기 로컬 |
| `search_fts` | FTS5 `(g, content='', tokenize='unicode61')`, rowid = `search_units.id` | 마이그레이션 단계의 `customStatement`로 만든다(drift `.drift` 파일·`sqlite_modules` 옵션은 쓰지 않아도 됨 — CORE 선택) |
| `strokes` | (변경 없음) | `stalePages`용으로 `(page_id, tool, updated_at)` 조회가 색인 범위 안인지 CORE가 확인 |

- `kNoteSchemaVersion`은 **1 그대로**다(조사 01 Q3 기본안). 객체가 든 노트도 옛 앱에서 읽기 전용이 되지 않는다. 배포된 옛 앱이 없고(실연결 전) 사용자 한 명이 모든 기기를 함께 갱신하기 때문이다.
- 마이그레이션 v1 → v2는 한 트랜잭션(1차 `runSchemaUpgrade`)이고, `dart run drift_dev make-migrations`가 만든 `schema_versions.dart`와 생성 시험을 커밋한다. **1차 v1 DB 고정 자료**(실제 1차 코드로 만든 노트·획·PDF 에셋)를 v2로 여는 시험을 VM과 Chrome 둘 다 둔다(V7). iPad에는 1차 웹으로 쓴 실제 노트가 있기 때문이다.
- 옛 앱이 v2 DB를 열면 `NewerSchemaError` → 앱 전체가 열리지 않는다(1차 동작). 웹 배포를 되돌릴 때 주의(위험 6.1 #9).
- 검색 색인 채우기: 마이그레이션 직후 텍스트 상자는 없고, PDF는 `PdfSearchIndexer`가 백그라운드로 채운다(4.13). `search_state`(정규화 판·재구축 표시)는 CORE 메타 KV에 둔다.

### 4.9 동기화 문서 매핑 (7.2.10 — sync_engine)

원격 구조(Firestore `users/{uid}/changes/{chunkId}` + 코덱 v1 이진 페이로드)는 바뀌지 않는다. 문서 필드에 엔티티 종류가 없으므로 Firestore·Storage 규칙도 바뀌지 않는다(조사 01 3.11). 코덱 형식 `fmt`는 **1 그대로** 둔다 — 배포된 옛 앱이 없고, 이번에 '모르는 종류 보류'가 들어가므로 이후 종류 추가에도 `fmt`를 올릴 필요가 없다.

| `EntityKind` | 청크 범위 | outbox 힌트 (CORE, 7.2.10 규칙 확장) | 병합 단위(필드 묶음) | 하위 기록·게이트 |
|---|---|---|---|---|
| `stroke` | 노트 | v1.4 | v1.4 (`{recordingId, recordingOffsetMs}`) | v1.4 |
| `pageObject` | 노트 | `noteId` 항상, `pageId` 항상 | **객체 단위 하나**: `{type, frame, shape, geometry, style, text, assetId, px, latex}` + 따로 `{engine}`. 같은 객체를 두 기기가 동시에 고치면 나중 것이 이긴다(삭제 규칙은 v1.4 그대로) | 페이지·노트 영구 삭제 때 함께(`purge_guard`·`record_gate`에 추가). 삭제된 페이지에 상대가 모르는 객체가 있으면 페이지를 되살림(`page_resurrection` — 획과 같은 근거) |
| `handwriting` | 노트 | `noteId` 항상, `pageId` 항상 | 하나: `{engineId, sourceRev, lines}` | 페이지 영구 삭제 때 함께. 되살림 근거가 **아니다**(파생 데이터) |
| `recording` | 노트 | v1.4 | v1.4 + `{title}` 따로 | v1.4 |
| (모르는 종류) | — | — | — | **보류**(아래) |

- 정렬(`chunk_packer.kindOrder`): `folder, note, page, penPreset, setting, asset, recording, stroke, pageObject, handwriting`.
- 이진 필드(`blobKeys`): 새 종류에는 없다(객체 JSON에 점 배열을 넣지 않는다).
- **모르는 종류 보류(S-13)**: `ChunkCodec`은 모르는 `kind` 기록을 실패시키지 않고 `UnknownKindRecord(kind, rawJson)`로 디코드한다. 다운로드 파이프라인은 같은 청크의 나머지 기록을 적용하고, 모르는 기록만 메타 KV(`sync.heldRecords`)에 보관한 뒤 `SyncIssueCode.needsAppUpdate`를 한 번 낸다. 앱이 갱신되어 그 종류를 알게 되면 시작 시 보관분을 순서대로 다시 적용한다. 커서는 정상 진행한다(청크를 버리지 않는다).
- 모르는 `type`의 `pageObject`는 CORE가 `UnknownObject`로 받아 저장·동기화하므로 SYNC 입장에서는 일반 기록이다(C-12).
- 에셋: 이미지·오디오는 1차 에셋 파이프라인 그대로(업로드 상한 300 MiB — 64 kbps 3시간 녹음 86 MB에 여유). `recording_drafts`·`search_units`·`search_fts`는 기기 로컬이라 동기화 대상이 아니다.
- SYNC T16 'JSON 키 대조'(1차)를 새 두 종류에도 돌린다: CORE `toJson` 키 집합 = SYNC `FieldUnits.keysOf(kind)`.

### 4.10 펜 스타일 · 렌더 층 · 페이지 객체 렌더 (7.2.4, 7.2.15, 7.2.16 — ink_engine)

```dart
// --- style extras keys (INK owns; CORE stores in StrokeStyle.extras) — 추가 ---
abstract final class InkStyleExtras {
  static const String highlighterStraightening = 'hlStraight';   // v1.4
  static const String nibAngleDeg = 'nibAngleDeg';     // calligraphy, [0, 180), default 45
  static const String nibAspect = 'nibAspect';         // calligraphy, minor/major (0.1..1], default 0.25
  static const String followBarrelRoll = 'rollNib';    // calligraphy, bool, default true (native Pencil Pro)
  static const String dash = 'dash';                   // dashed, [on, off, …] × width, default [4, 3]
  static const String laserFadeMs = 'laserFadeMs';     // laser, [300, 5000], default 1500
  static const String tapeStyle = 'tapeStyle';         // tape, 'solid' | 'striped', default 'solid'
}
enum InkTapeStyle { solid, striped }
extension StrokeStyleInk on core.StrokeStyle {
  /* v1.4: profile, previewRadius, highlighterStraightening, withHighlighterStraightening */
  double get nibAngleDeg; double get nibAspect; bool get followBarrelRoll;
  List<double> get dashPattern; int get laserFadeMs; InkTapeStyle get tapeStyle;
  core.StrokeStyle withInkExtras({double? nibAngleDeg, double? nibAspect, bool? followBarrelRoll,
      List<double>? dashPattern, int? laserFadeMs, InkTapeStyle? tapeStyle});
}
// PenProfile.of (v2.0): brush → filledOutline (high pressure gain, long taper);
// calligraphy → nibOutline; dashed → dashedPolyline (round caps); laser → transientTrail;
// tape → filledOutline, square cap, layer cover.
enum InkRenderMethod { filledOutline, strokedPolyline, nibOutline, dashedPolyline, transientTrail }  // 깨짐(값 추가)
enum InkLayer { highlighter, ink, cover }                                                             // 깨짐(값 추가)
enum InkRenderLayer { background, underlay, highlighterBase, highlighterActive, inkBase, inkActive,
  annotation, cover, overlay }                                                                        // 깨짐(값 추가)
```

`StrokeStyle.defaultsFor`(CORE)의 P1 5종 값은 v1.4 값을 유지하고 extras 기본값만 위 표로 채운다(색·굵기 조정은 INK가 렌더를 확정한 뒤 CORE에 변경 요청). 모든 새 펜은 1차 K-1(`Stroke.bounds` 공식)을 지킨다: 캘리그래피 펜촉 반길이 = `width·f/2` = `2·width·widthQ`, 테이프 사각 캡 0.7071·w ≤ 0.75·w, 점선 원형 캡.

**층 규칙 L-1** (아래에서 위로, 조사 01 R3 + PLAN 7.3):

| 순서 | 층 | 내용 | 층 안의 순서 |
|---|---|---|---|
| 1 | background | 종이·속지·PDF·이미지 배경 | — |
| 2 | underlay | `ImageObject` | `compareOrder` |
| 3 | highlighter | 형광펜 획 | `compareOrder` (v1.4) |
| 4 | ink | 일반 획 + `ShapeObject` | `compareOrder` — 도형과 획이 섞인다 |
| 5 | annotation | `TextBoxObject`, `MathObject`, `UnknownObject` 자리표시 | `compareOrder` |
| 6 | cover | 암기 테이프 획(드러낸 것은 테두리만) | `compareOrder` |
| 7 | overlay | 선택 표시, 올가미, 레이저 자취, 재생 강조, 도형 보정 미리보기 | — |

```dart
// --- content: 추가 ---
final class InkPageContent {
  factory InkPageContent.fromCore({required core.Page page, required List<core.Stroke> strokes,
      List<core.PageObject> objects = const [], required int revision});
  List<core.PageObject> get objects;
}

// --- page controller: 추가 ---
final class InkPageController extends ChangeNotifier {
  /* v1.4 */
  /// ids may mix strokes and objects; unknown ids ignored.
  InkSelection select(Set<String> elementIds);
  /// Topmost object at the point (annotation → ink → underlay); UnknownObject included.
  core.PageObject? hitTestObject(Offset pagePoint, {double tolerance = 4.0});
  /// Not drawn (e.g. the text box under EDITOR's EditableText). Selection still sees them.
  void setHiddenObjectIds(Set<String> ids);
  // playback (M6)
  void setPlaybackFocus(InkPlaybackFocus? focus);           // null = off (K-7)
  InkStroke? hitTestRecorded(Offset pagePoint, {String? recordingId, double tolerance = 8.0});
  // memorization tape (state per controller, never stored — U10)
  InkStroke? hitTestTape(Offset pagePoint);
  bool isTapeRevealed(String strokeId);
  void toggleTape(String strokeId);
  void setAllTapesRevealed(bool revealed);
}
@immutable
final class InkPlaybackFocus {
  const InkPlaybackFocus({required this.recordingId, required this.positionMs,
      this.style = InkPlaybackStyle.dimUnwritten});
  final String recordingId; final int positionMs; final InkPlaybackStyle style;
}
enum InkPlaybackStyle { dimUnwritten, highlightRecent }

// beginStroke (v1.4) + shapeAssist — 추가
StrokeSession beginStroke(InkSample first, {required core.StrokeStyle style,
    required double viewScale, InkStrokeMeta meta = const InkStrokeMeta(),
    ShapeAssist shapeAssist = ShapeAssist.off});
enum ShapeAssist { off, holdToSnap }
// StrokeSession — 추가: after the pen holds still ≥ InkTuning.shapeHoldMs (500) within
// InkTuning.shapeHoldRadiusPx (8 logical px) the session asks inkShapeFitterProvider; a fit
// shows in overlay; moving again cancels it; end() then yields InkEdit(addShape).
abstract class StrokeSession { /* v1.4 */ ValueListenable<InkShapeFit?> get shapePreview; }
// laser: StrokeSession.end() returns null (no InkEdit, E-3); the trail fades over laserFadeMs.

/// (v2.0) Shape recognition port. INK detects the hold; the fitter decides.
abstract interface class InkShapeFitter {
  /// Centerline points of the stroke so far (page pt). null = not a shape (keep the stroke).
  InkShapeFit? fit(List<Offset> points, {required double viewScale});
}
@immutable
final class InkShapeFit {
  const InkShapeFit({required this.kind, required this.geometry, required this.score});
  final core.ShapeKind kind; final core.ShapeGeometry geometry; final double score;   // score [0,1]
}
final class NoShapeFitter implements InkShapeFitter { const NoShapeFitter(); }
/// Overridden ONLY through ink_recognition's recognitionOverrides() (4.17).
final inkShapeFitterProvider = Provider<InkShapeFitter>((ref) => const NoShapeFitter(),
    name: 'inkShapeFitterProvider');

// --- selection / lasso / eraser / edit: 추가 ---
final class InkSelection {
  /* v1.4: strokeIds, strokes, bounds, previewTransform, setPreviewTransform, commitTransform,
     delete, duplicate, recolor — now also cover objects (recolor: shape stroke color, text and
     math color; images unchanged) */
  Set<String> get objectIds;
  Set<String> get allIds;
  List<core.PageObject> get objects;
}
final class LassoOptions { /* v1.4 */ final bool includeObjects; }   // default true: object center inside → selected
final class EraserSpec { /* v1.4 */ final bool eraseShapes; }        // default true: touching a shape removes it whole
enum InkEditKind { addStroke, eraseStrokes, splitStrokes, transformStrokes, recolorStrokes,
  deleteStrokes, duplicateStrokes, addShape }                          // 깨짐(값 추가)
final class InkEdit {
  /* v1.4 */
  final List<core.PageObject> addedObjects;     // addShape, duplicateStrokes
  final List<core.PageObject> updatedObjects;   // recolorStrokes on objects
}
```

| `InkEditKind` | `toCommand()` (v2.0) |
|---|---|
| `addShape` | `core.AddObjects(pageId, addedObjects)` |
| `eraseStrokes`, `deleteStrokes` | `removedIds`가 획뿐이면 `core.RemoveStrokes`(v1.4), 객체가 섞이면 `core.RemoveElements` |
| `transformStrokes` | `core.TransformElements`(획 + 객체 — 이름은 v1.4 유지) |
| `recolorStrokes` | `core.CompositeCommand([RestyleStrokes, UpdateObjects])`(빈 쪽은 뺌) |
| `duplicateStrokes` | `core.CompositeCommand([AddStrokes, AddObjects])`(빈 쪽은 뺌) |
| 그 밖 | v1.4 |

```dart
// --- backgrounds: 추가 / 규칙 ---
final class InkBackgroundSpec { /* v1.4 */ final core.ImageFit? imageFit; }   // kind == image
final class ImageBackgroundLayerBuilder
    implements PageBackgroundLayerBuilder, PageBackgroundStillRenderer {
  const ImageBackgroundLayerBuilder({required this.assets, required this.images});
  final core.AssetStore assets; final InkImageCache images;
}
/// Decoded image cache shared by image objects, image backgrounds and thumbnails.
/// Budget (7.4.10): web 48 MB, native 128 MB; decodes at the display bucket (no full-res decode).
final class InkImageCache { /* INK */ }
final inkImageCacheProvider = Provider<InkImageCache>(/* reads core.assetStoreProvider */);
/// The default list INK uses AND the list pdf_io must keep after its own builder.
List<PageBackgroundLayerBuilder> defaultPageBackgroundBuilders(Ref ref);   // [image, template]
// pageBackgroundBuildersProvider default (v2.0) = defaultPageBackgroundBuilders(ref).
// Rule kept: overridden ONLY through pdfIoOverrides() — which now returns
// [pdfBuilder, ...ink.defaultPageBackgroundBuilders(ref)].

// --- vector export v2 (paint order = L-1): 추가 ---
final class InkPageVectors {
  /* v1.4: highlighterGroups, inkShapes (now also ShapeObject outlines/fills and dashed strokes
     pre-split into dash segments — PDF needs no dash operator), bounds */
  final List<InkImageVector> underlay;          // image objects
  final List<InkAnnotationVector> annotations;  // text boxes, math (z order)
  final List<InkFillShape> cover;               // tape strokes (always covered in exports)
}
@immutable final class InkImageVector { final String assetId; final core.ElementFrame frame;
  final int pixelWidth, pixelHeight; }
sealed class InkAnnotationVector { core.ElementFrame get frame; }
final class InkTextVector extends InkAnnotationVector {
  final core.TextBoxObject object;
  final List<InkTextLine> lines;                // laid out with InkFonts.noteSans, frame-local pt
}
@immutable final class InkTextLine { final String text; final double x, baselineY, width; }
final class InkMathVector extends InkAnnotationVector { final core.MathObject object; }

// --- math, fonts, text layout: 추가 ---
abstract final class InkMathRenderer {
  /// null = renderable; else a short English error (unknown command …) for the LaTeX editor.
  static String? validate(String latex);
  static InkMathLayout? layout(String latex, {required double fontSizePt});   // size in pt
  /// Offscreen raster (thumbnails, PDF at 300 dpi, screen cache buckets). Web (CanvasKit) safe.
  static Future<ui.Image?> rasterize(String latex, {required int colorArgb,
      required double fontSizePt, required double pixelsPerPt});
}
@immutable final class InkMathLayout { final Size sizePt; final double baselinePt; }
/// flutter_math_fork Math.tex with explicit textStyle (fontSize, color) — never SelectableMath.
class MathPreview extends StatelessWidget {
  const MathPreview({super.key, required this.latex, required this.fontSize, required this.color,
      this.onError});
}
abstract final class InkFonts {
  static const String noteSans = 'NoteSans';    // text boxes; packages/ink_engine/assets/fonts/
  static Future<void> ensureLoaded();           // lazy FontLoader — not in FontManifest (no startup download)
  static Future<Uint8List> noteSansBytes({bool bold = false});   // PDF embedding
  static bool covers(String text);              // every char in the bundled subset?
}
abstract final class InkTextLayout {
  /// Height EDITOR writes into TextBoxObject.frame for the given width (same metrics INK paints with).
  static Future<Size> measure(String text, core.TextBoxStyle style, {required double widthPt});
}
```

- 썸네일(`InkPageThumbnailRenderer`): 이미지 배경·객체를 합성한다. 이미지·글꼴·수식이 2초 안에 준비되지 않으면 `null`(1차 규칙: 호출자는 캐시하지 않고 다시 시도).
- 웹 캘리그래피: 방위각이 항상 0이므로 `nibAngleDeg` 고정 각만 쓴다. 네이티브 iPad에서 `followBarrelRoll`이 켜져 있고 Pencil Pro 롤(4.11 `StylusBarrelRoll`)이 오면, EDITOR가 **펜 다운 순간의 롤 값**을 그 획 스타일의 `nibAngleDeg`에 더해 넘긴다. 획마다 고정 각이 되어 다시 열어도 같은 모양으로 그려지고, 점 코덱 v1(점별 롤 채널 없음)을 바꾸지 않는다(조사 02 9.3 '최근 롤 값 근사').

### 4.11 에디터 확장 지점 · 제스처 · 펜 버튼 (7.2.17 — feature_editor)

```dart
// --- extension points: 추가 ---
@immutable
class EditorExtensions {
  const EditorExtensions({this.moreMenuItems = const [], this.addPageSources = const [],
      this.appBarTrailing, this.selectionMenuItems = const [], this.insertMenuItems = const [],
      this.recordingPanel});
  /* v1.4: moreMenuItems, addPageSources, appBarTrailing (still reserved) */
  final List<EditorSelectionMenuItem> selectionMenuItems;   // recog: toText, copyText, toMath, editMath
  final List<EditorInsertMenuItem> insertMenuItems;         // recog: mathPad
  final EditorPanelBuilder? recordingPanel;                 // media_io RecordingPanel; null → mic button hidden
}

@immutable
class EditorSelectionContext {
  const EditorSelectionContext({required this.noteId, required this.pageId, required this.pageSize,
      required this.strokes, required this.objects, required this.boundsPt, required this.execute,
      required this.clearSelection});
  final String noteId, pageId;
  final core.PageSize pageSize;
  final List<core.Stroke> strokes;               // selected, z order
  final List<core.PageObject> objects;           // selected, z order
  final Rect boundsPt;                           // page pt
  /// Runs ONE command on the note session (one undo step). Throws like NoteSession.execute
  /// (ReadOnlyNoteException …); the caller shows the message.
  final void Function(core.EditCommand command) execute;
  final VoidCallback clearSelection;
}
@immutable
class EditorSelectionMenuItem {
  const EditorSelectionMenuItem({required this.id, required this.label, required this.icon,
      required this.onSelected, this.isVisible});
  final String id; final String label; final IconData icon;
  final Future<void> Function(BuildContext context, EditorSelectionContext selection) onSelected;
  final bool Function(EditorSelectionContext selection)? isVisible;
}
@immutable
class EditorInsertContext {
  const EditorInsertContext({required this.noteId, required this.pageId, required this.pageSize,
      required this.visibleRectPt, required this.execute, required this.selectObject});
  final String noteId, pageId; final core.PageSize pageSize;
  final Rect visibleRectPt;                      // insert near its center
  final void Function(core.EditCommand command) execute;
  final void Function(String objectId) selectObject;   // select what was just inserted
}
@immutable
class EditorInsertMenuItem {
  const EditorInsertMenuItem({required this.id, required this.label, required this.icon,
      required this.onSelected});
  final String id; final String label; final IconData icon;
  final Future<void> Function(BuildContext context, EditorInsertContext insert) onSelected;
}
typedef EditorPanelBuilder = Widget Function(BuildContext context, EditorPanelContext panel);
@immutable
class EditorPanelContext {
  const EditorPanelContext({required this.noteId, required this.tapToSeek,
      required this.setTapToSeek, required this.close});
  final String noteId;
  final ValueListenable<bool> tapToSeek;         // EDITOR owns the flag (finger tap on a recorded stroke → seek)
  final ValueChanged<bool> setTapToSeek;
  final VoidCallback close;
}

/// Image picking + normalization lives in media_io; EDITOR only calls this slot.
@immutable
class EditorImageImporter {
  const EditorImageImporter({required this.sources, required this.pick});
  final Set<core.ImageImportSource> sources;
  final Future<core.ImportedImage?> Function(BuildContext context, core.ImageImportSource source) pick;
}
final editorImageImporterProvider = Provider<EditorImageImporter?>((ref) => null,
    name: 'editorImageImporterProvider');      // null → image insert / image page hidden

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({/* v1.4 */, this.initialFocusRectPt});
  /// With initialPageId: bring this page rect (pt) into view and flash it (search hits).
  final Rect? initialFocusRectPt;
}
```

```dart
// --- gestures: 추가 (v1.4 bool keys kept for reading / writing compatibility) ---
enum EditorGesture { twoFingerTap, threeFingerTap, fingerLongPress, penButton, invertedStylus,
  pencilDoubleTap, pencilSqueeze }
enum EditorAction { none, undo, redo, contextMenu, eraserWhileHeld, lassoWhileHeld, toggleEraser,
  previousTool, toolPalette, colorPalette, followSystem }

@immutable
class GestureSettings {
  const GestureSettings({this.twoFingerTapUndo = true, this.threeFingerTapRedo = true,
      this.longPressMenu = true, this.actions = const {}});
  /* v1.4 bools */
  final Map<EditorGesture, EditorAction> actions;          // missing key → defaultFor
  EditorAction actionFor(EditorGesture gesture);
  static EditorAction defaultFor(EditorGesture gesture);   // table below
  static Set<EditorAction> allowedFor(EditorGesture gesture);
  /// JSON: v1.4 keys + "actions": {"twoFingerTap": "undo", …}. Read: actions[k] wins, else the
  /// v1.4 bool (false → none), else default; unknown names ignored. Write: both (bool = action != none).
  Map<String, Object?> toJson();
  factory GestureSettings.fromJson(Map<String, Object?> json);
}
```

| `EditorGesture` | 기본 | 고를 수 있는 동작 |
|---|---|---|
| `twoFingerTap` | `undo` | none, undo, redo, toggleEraser |
| `threeFingerTap` | `redo` | none, undo, redo, toggleEraser |
| `fingerLongPress` | `contextMenu` | none, contextMenu |
| `penButton` (S펜 측면 버튼을 누른 채 쓰기) | `eraserWhileHeld` | none, eraserWhileHeld, lassoWhileHeld |
| `invertedStylus` (지우개 끝) | `eraserWhileHeld` | none, eraserWhileHeld |
| `pencilDoubleTap` | `followSystem` | none, followSystem, toggleEraser, previousTool, colorPalette, toolPalette, undo |
| `pencilSqueeze` | `followSystem` | none, followSystem, toolPalette, colorPalette, toggleEraser |

- `followSystem`: `StylusPreferredAction`을 따른다 — switchEraser → toggleEraser, switchPrevious → previousTool, showColorPalette → colorPalette, showInkAttributes·showContextualPalette → toolPalette(스퀴즈는 `hoverPosition`에 띄움), ignore·runSystemShortcut·unknown → none.
- Pencil 항목은 `stylusExtrasProvider.capabilities`가 지원할 때만 설정 화면에 보인다.

```dart
// --- stylus extras: 깨짐(구독자 없음) / 추가 ---
enum StylusPreferredAction { ignore, switchEraser, switchPrevious, showColorPalette,
  showInkAttributes, showContextualPalette, runSystemShortcut, unknown }
enum StylusSqueezePhase { began, changed, ended, cancelled }
final class StylusDoubleTap extends StylusExtraEvent {
  const StylusDoubleTap({this.preferredAction = StylusPreferredAction.unknown, this.hoverPosition});
  final StylusPreferredAction preferredAction; final Offset? hoverPosition;   // global logical px
}
final class StylusSqueeze extends StylusExtraEvent {
  const StylusSqueeze({this.phase = StylusSqueezePhase.ended,
      this.preferredAction = StylusPreferredAction.unknown, this.hoverPosition});
  final StylusSqueezePhase phase; final StylusPreferredAction preferredAction; final Offset? hoverPosition;
}
final class StylusBarrelRoll extends StylusExtraEvent { const StylusBarrelRoll(this.angle); final double angle; }  // v1.4
final class StylusHoverPose extends StylusExtraEvent {
  const StylusHoverPose({required this.position, this.height, this.altitude, this.azimuth, this.roll});
  final Offset position;                         // global logical px
  final double? height;                          // 0..1 (UIKit zOffset)
  final double? altitude, azimuth, roll;         // rad
}
@immutable
class StylusCapabilities {
  const StylusCapabilities({this.doubleTap = false, this.squeeze = false, this.barrelRoll = false,
      this.hoverPose = false, this.prefersPencilOnlyDrawing = false});
  final bool doubleTap, squeeze, barrelRoll, hoverPose, prefersPencilOnlyDrawing;
  static const StylusCapabilities none = StylusCapabilities();
}
abstract interface class StylusExtrasSource {
  bool get isSupported;                          // v1.4
  StylusCapabilities get capabilities;           // (v2.0)
  Stream<StylusExtraEvent> get events;           // v1.4
}
```

입력 규칙(E-4, 조사 02 8·10·12.5): **네이티브**에서는 `PointerDownEvent` 자체가 '닿음'이고, **웹**에서는 `buttons & kStylusContact(0x01) != 0`일 때만 닿음이다(웹은 버튼을 누른 채 띄우면 닿기 전에 `down(0x02)`가 온다). 닿는 순간 `buttons & kPrimaryStylusButton != 0`이면 `penButton` 동작, `kind == invertedStylus`이면 `invertedStylus` 동작으로 그 제스처를 시작한다. 띄운 채 버튼만 눌렀다 떼는 토글은 쓰지 않는다(삼성 Air command·엔진이 `ACTION_BUTTON_PRESS`를 넘기지 않음).

### 4.12 라이브러리 · 인식 (7.2.18 — feature_library, ink_recognition)

```dart
// feature_library — 추가
typedef LibraryOpenNoteAt = void Function(String noteId, String pageId, Rect? focusRectPt);
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({/* v1.4 */, this.onOpenNoteAt});
  /// Content search hit → page + rect (page pt). null → onOpenNote(noteId) (page ignored).
  final LibraryOpenNoteAt? onOpenNoteAt;
}
// Search results view: groups '폴더' · '노트' (v1.4) + '노트 내용' (PageSearchHit, source badge
// 손글씨 / PDF / 텍스트 / 수식). Grouped by note, then page. Uses CORE results as-is (L-1).
```

```dart
// package:ink_recognition/ink_recognition.dart — web-safe entry (ML Kit only behind *_native.dart)

// --- inputs / outputs (pure Dart) ---
final class HandwritingTrace {                   // one stroke; page pt; absolute ms
  const HandwritingTrace({required this.xs, required this.ys, required this.ts, this.strokeId});
  factory HandwritingTrace.fromStroke(core.Stroke stroke);   // ts = createdAt + t(i)
  final Float32List xs, ys;
  final Float64List ts;                          // Float64List, NOT Int64List (dart2js, 7.4.3 웹 안전 수치)
  final String? strokeId;
}
final class HandwritingLineInput {
  const HandwritingLineInput(this.traces, {this.preContext = '', this.writingAreaPt});
  final List<HandwritingTrace> traces; final String preContext; final Size? writingAreaPt;
}
@immutable final class TextCandidate {
  const TextCandidate(this.text, {this.score, required this.languageTag});
  final String text; final double? score;        // engine-specific; never compared across engines
  final String languageTag;
}
enum RecognitionModelState { notDownloaded, downloading, ready, unsupported }
sealed class RecognitionFailure implements Exception {}
final class RecognizerUnsupported extends RecognitionFailure {}          // web + ML Kit, manual-only math
final class ModelNotReady extends RecognitionFailure { ModelNotReady(this.languageTag); final String languageTag; }
final class RecognizerOffline extends RecognitionFailure {}
final class RecognizerQuotaExceeded extends RecognitionFailure {}
final class RecognizerCancelled extends RecognitionFailure {}
final class RecognizerEngineError extends RecognitionFailure {
  RecognizerEngineError(this.code, this.message); final String code, message; }

abstract interface class HandwritingRecognizer {
  String get engineId;                           // 'mlkit-digital-ink/19.0.0', 'fake'
  bool get isAvailable;                          // false on web
  Future<RecognitionModelState> modelState(String languageTag);
  Future<void> ensureModel(String languageTag, {bool wifiOnly = true});   // iOS: app checks connectivity itself
  Future<List<TextCandidate>> recognizeLine(HandwritingLineInput line, {required String languageTag});
  Future<void> dispose();
}
final class MathInput {
  const MathInput({required this.traces, this.png, this.pngPxPerPt});
  final List<HandwritingTrace> traces; final Uint8List? png; final double? pngPxPerPt;
}
@immutable final class MathResult {
  const MathResult({required this.latex, this.confidence, this.alternatives = const [],
      required this.engineId, required this.latency});
  final String latex; final double? confidence; final List<String> alternatives;
  final String engineId; final Duration latency;
}
abstract interface class MathRecognizer {
  String get engineId;
  bool get isAvailable;                          // ManualOnlyMathRecognizer: false (LaTeX typing only)
  Future<MathResult> recognize(MathInput input, {Future<void>? cancel});
}
/// Pure Dart line grouping (search indexing AND lasso conversion use the same function).
List<List<HandwritingTrace>> groupIntoLines(List<HandwritingTrace> traces, {double gapFactor = 1.2});
/// Geometric fitter (03-recognition 4.3 prototype) — implements INK's port.
final class GeometricShapeFitter implements ink.InkShapeFitter { const GeometricShapeFitter({this.tuning = const ShapeFitTuning()}); }
@immutable final class ShapeFitTuning { /* every threshold in one place (03-recognition R4) */ }

// --- providers: overridden ONLY through recognitionOverrides() ---
final handwritingRecognizerProvider = Provider<HandwritingRecognizer>(
    (ref) => const UnsupportedHandwritingRecognizer(), name: 'handwritingRecognizerProvider');
final mathRecognizerProvider = Provider<MathRecognizer>(
    (ref) => const ManualOnlyMathRecognizer(), name: 'mathRecognizerProvider');
@immutable final class RecognitionConfig {
  const RecognitionConfig({this.mathEndpoint, this.idTokenProvider});
  final Uri? mathEndpoint;                       // callable URL (emulator in dev); null → manual only
  final Future<String?> Function()? idTokenProvider;   // M4 auth later; null → no Authorization header
}
/// web: unsupported handwriting; native: ML Kit (*_native.dart); math: CallableMathRecognizer
/// (package:http, callable protocol) when mathEndpoint != null. Also overrides
/// ink.inkShapeFitterProvider with GeometricShapeFitter on every platform.
List<Override> recognitionOverrides({RecognitionConfig config = const RecognitionConfig()});

// --- editor actions (INFRA wraps into EditorSelectionMenuItem / EditorInsertMenuItem) ---
@immutable final class RecognitionTarget {        // same fields as EditorSelectionContext / EditorInsertContext
  const RecognitionTarget({required this.noteId, required this.pageId, required this.pageSize,
      this.strokes = const [], this.objects = const [], required this.areaPt, required this.execute,
      required this.done});
  final String noteId, pageId; final core.PageSize pageSize;
  final List<core.Stroke> strokes; final List<core.PageObject> objects;
  final Rect areaPt;                             // selection bounds or visible rect
  final void Function(core.EditCommand command) execute;
  final VoidCallback done;                       // clearSelection / selectObject wrapper
}
@immutable final class RecognitionAction {
  const RecognitionAction({required this.id, required this.label, required this.icon,
      required this.run, this.isVisible});
  final String id; final String label; final IconData icon;
  final Future<void> Function(BuildContext context, RecognitionTarget target) run;
  final bool Function(RecognitionTarget target)? isVisible;
}
List<RecognitionAction> recognitionSelectionActions();   // recog.toText, recog.copyText, recog.toMath, recog.editMath
List<RecognitionAction> recognitionInsertActions();      // recog.mathPad

// --- background indexing ---
final class HandwritingIndexer {
  HandwritingIndexer({required core.NoteStore store, required HandwritingRecognizer recognizer,
      required ValueListenable<bool> enabled});
  /// Watches NoteStore.changes (stroke → pageId), waits for idle (≥ 3 s no input on that page),
  /// recognizes stalePages line by line, writes HandwritingRepository.put. Never runs on web.
  void start();
  Future<void> dispose();
  ValueListenable<HandwritingIndexerStatus> get status;
}
final handwritingIndexerProvider = Provider<HandwritingIndexer?>(/* null unless recognizer available */);
class RecognitionSettingsSection extends ConsumerWidget { const RecognitionSettingsSection({super.key}); }
// testing.dart: FakeHandwritingRecognizer, FakeMathRecognizer, SyntheticHandwriting (lines/words generator)
```

- 변환 UI(텍스트 변환 창, 수식 입력 패드, LaTeX 편집 창)는 `ink_recognition` 안의 위젯이고 `RecognitionAction.run`이 띄운다. 수식 입력 패드는 INK `InkPageView`를 저장하지 않는 임시 `core.Page`로 쓰고(1차 `InkPageContent.fromCore` 미리보기 방식), 멈춤 1초 뒤 `MathRecognizer`를 부르며 미리보기는 INK `MathPreview`로 그린다. 엔진이 없으면 LaTeX 직접 입력 + 미리보기만 보인다.
- 혼용 전략: 실기기 실험(5.5 A-4) 전까지 `ko` 단독 + 변환 창 언어 바꾸기(한국어/영어)를 기본으로 하고, 인터페이스는 두 모델 결과 선택(조사 03 3.4 B)을 넣을 수 있게 둔다.
- ML Kit은 `import 'package:google_mlkit_digital_ink_recognition/…' as mlkit;`로만 가져온다(`Ink`가 `material_ui`와, `StrokePoint`가 CORE와 겹친다).

### 4.13 PDF · 미디어 (7.2.19 — pdf_io, media_io)

```dart
// pdf_io — 규칙 / 추가
/// The ONLY override of ink.pageBackgroundBuildersProvider (v1.4 rule kept):
///   [pdfBackgroundLayerBuilder, ...ink.defaultPageBackgroundBuilders(ref)] (+ pdfIoConfigProvider).
List<Override> pdfIoOverrides({PdfIoConfig? config});
/// Library-wide PDF text index (1차 7.8 이후 항목): watches PDF assets / PdfBackground pages,
/// extracts with PdfTextService, writes core.SearchIndexWriter (source pdf, rects as page
/// fractions). Skips owners whose sourceRev is current. Idle-time, one PDF page per slice.
final class PdfSearchIndexer {
  PdfSearchIndexer(core.NoteStore store);
  void start();
  Future<void> dispose();
}
final pdfSearchIndexerProvider = Provider<PdfSearchIndexer>(/* started by INFRA PdfModule */);
// Export (06-pdf 6.11 확장, 내부): order = InkPageVectors L-1; ImageObject / image background →
// PDF image object (JPEG inline, PNG via bitmap); TextBoxObject → text object with embedded
// InkFonts.noteSans (searchable; falls back to raster when InkFonts.covers(text) is false or
// font loading fails); MathObject → raster 300 dpi (U17); tape → covered; laser → none.
```

```dart
// package:media_io/media_io.dart — web-safe entry
Future<void> initializeMediaIo({MediaIoConfig config = const MediaIoConfig()});   // idempotent
@immutable
final class MediaIoConfig {
  const MediaIoConfig({this.bitRate = 64000, this.sampleRate = 44100, this.allowNonAacOnWeb = true,
      this.webDraftChunkMs = 5000, this.androidForegroundService = true});
  final int bitRate;                             // AAC-LC mono (U8)
  final int sampleRate;
  final bool allowNonAacOnWeb;                   // Chrome: opus/webm with a warning (crossPlatformPlayable false)
  final int webDraftChunkMs;                     // web: MediaRecorder chunks flushed to RecordingDraftStore
  final bool androidForegroundService;           // microphone FGS while recording (M6-2)
}
/// Overrides core.audioRecorderServiceProvider and core.audioPlaybackServiceProvider.
List<Override> mediaIoOverrides({MediaIoConfig? config});

/// EditorImageImporter parts (INFRA wraps them).
Set<core.ImageImportSource> supportedImageSources();          // web: photos, camera, files (+ clipboard when navigator.clipboard.read exists)
/// Pick → decode → downscale to ImageImportLimits → re-encode (JPEG for photos, PNG when alpha)
/// → AssetStore.put(type: image). null = cancelled (or a handled error shown as a message).
Future<core.ImportedImage?> importImageForNote(BuildContext context, core.ImageImportSource source);

/// Recording + playback panel for EditorExtensions.recordingPanel (INFRA adapts EditorPanelContext).
/// Record / pause / stop, recordings list (rename, delete, size), play / pause, ±10 s, speed
/// 0.5–2.0, scrubber, tap-to-seek toggle, consent notice on first record (F-16), web hidden-tab notice,
/// leftover-draft recovery prompt.
class RecordingPanel extends ConsumerWidget {
  const RecordingPanel({super.key, required this.noteId, required this.tapToSeek,
      required this.onTapToSeekChanged, required this.onClose});
  final String noteId; final ValueListenable<bool> tapToSeek;
  final ValueChanged<bool> onTapToSeekChanged; final VoidCallback onClose;
}
/// Developer overlay lines: encoder support table, last recording MIME / duration / clock error (R-3).
final mediaDevOverlayLinesProvider = Provider<ValueListenable<List<String>>>(/* … */);
// testing.dart: FakeRecordPlatform, FakeJustAudioPlatform hooks, registerMediaWebPlugins() for Chrome tests
```

media_io 내부 결정(계약 아님, PDF 계획서에서 상세): 네이티브는 `record`(AAC-LC/m4a, 모노, `manageAudioSession(false)`) + `audio_session`으로 세션을 혼자 관리, 안드로이드는 `flutter_foreground_task`의 microphone 서비스(`*_native.dart`), 재생은 `just_audio`(네이티브 `setFilePath` — 에셋을 캐시 파일로, 웹 `setUrl(blob:)`). 웹 녹음은 P-A에서 `record_web`을 쓰고, P-B에서 MediaRecorder 조각을 `RecordingDraftStore`에 5초마다 쓰는 자체 녹음기(`*_browser.dart`, `isTypeSupported`로 MIME 선택 — Safari AAC/mp4 우선, Chrome opus/webm + WebM 길이 보정)로 바꾼다. 웹에서 `visibilitychange`로 가려지면 먼저 `pause()`하고 `interrupted = true`, 녹음 중에는 Screen Wake Lock을 건다.

### 4.14 펜슬 플러그인 (pencil_bridge) · 서버 함수 (functions/)

```dart
// package:pencil_bridge/pencil_bridge.dart — web-safe: no dart:io; isSupported =
// !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS. Other platforms: empty stream.
abstract final class PencilBridge {
  static bool get isSupported;
  static Future<PencilCapabilities> capabilities();
  /// Broadcast. Attaches UIPencilInteraction + hover / roll recognizers on first listen
  /// (key window may not exist at plugin registration under UIScene), detaches on last cancel.
  static Stream<PencilEvent> get events;
}
sealed class PencilEvent { const PencilEvent(this.timestamp); final Duration timestamp; }
final class PencilTap extends PencilEvent { final String preferredAction; final Offset? position; final double? z; }
final class PencilSqueeze extends PencilEvent { final String phase, preferredAction; final Offset? position;
  final double? z, roll; }
final class PencilHover extends PencilEvent { final Offset position; final double? z, altitude, azimuth, roll; }
final class PencilRoll extends PencilEvent { final double angle; }   // while drawing, throttled ≤ 60 Hz
@immutable final class PencilCapabilities { final String os; final bool squeeze, hover, roll,
  prefersPencilOnlyDrawing; final String preferredTapAction, preferredSqueezeAction; }
// Swift: ios/pencil_bridge/Sources/pencil_bridge/PencilBridgePlugin.swift (SwiftPM + podspec),
// channels 'dev.noteapp/pencil/events' (EventChannel) and 'dev.noteapp/pencil/methods'.
// INFRA app adapter: PencilStylusExtrasSource implements StylusExtrasSource (string → enum mapping).
```

```text
functions/ (SYNC) — Node 22, TypeScript, firebase-functions 7.4.0, firebase-admin 14.5.0
callable recognizeMath  (region asia-northeast3, maxInstances 2, timeout 30 s, memory 256 MiB)
  auth   : request.auth required; uid ∈ OWNER_UIDS (defineString) else permission-denied
  secrets: MATH_API_KEY (+ engine-specific) via defineSecret — never in the app or the repo
  in     : { v: 1, engine?: 'auto' | 'mathpix' | 'claude' | 'gemini' | 'fake',
             strokes?: { x: number[][], y: number[][], t?: number[][] },   // page pt, ≤ 512 KB
             pngBase64?: string (≤ 2 MB), locale?: 'ko' | 'en' }
  out    : { latex: string, confidence?: number, alternatives?: string[],
             engine: string, engineVersion: string, ms: number }
  errors : unauthenticated | permission-denied | invalid-argument | resource-exhausted
           (daily cap per uid, Firestore counter) | unavailable | internal
  App Check: enforceAppCheck false this round (sideloaded APK cannot pass Play Integrity).
tool   : functions/tool/math_eval.ts — reads fixtures (stroke JSON + expected LaTeX), calls each
         engine with keys from developer env vars, writes the 03-recognition 6.6 score table.
```

앱 쪽 `CallableMathRecognizer`(ink_recognition)는 `package:http`로 callable 규약(`{"data": …}` + `Authorization: Bearer`)을 직접 구현한다 — `cloud_functions`(Firebase 네이티브 SDK)를 이번에 넣지 않아 iOS 혼합 모드 위험을 피한다(1.4). 실연결 미니 라운드에서 `cloud_functions 7.0.1`로 바꿀지 다시 정한다.

### 4.15 영역 간 인터페이스 목록 (7.3.1 — X1~X17은 v1.4 그대로, 추가분)

| # | 제공 | 소비 | 인터페이스 | 핵심 규칙 |
|---|---|---|---|---|
| X18 | CORE | EDITOR | `PageObject` 계열, `AddObjects`·`UpdateObjects`·`RemoveElements`·`ClearPage.includeObjects`, `PageContent.objects` | 4.4 명령 매핑, C-11 |
| X19 | CORE | EDITOR, media | 오디오 포트(`audioRecorderServiceProvider`·`audioPlaybackServiceProvider`), `RecordingRepository`, `noteRecordingsProvider` | R-1~R-8, M-1·M-2 |
| X20 | CORE | media | `AssetStore.put(audio/image)`, `RecordingRepository.createRecording`, `RecordingDraftStore`, `ImageImportLimits` | 에셋 먼저, 녹음 행은 그 뒤(M-1) |
| X21 | CORE | LIBRARY | `LibrarySearchResult.pages`, `PageSearchHit` | 결과를 그대로 표시(1차 L-1) |
| X22 | CORE | recog | `HandwritingRepository`(`stalePages`·`put`), `HandwritingText.sourceRevOf`·`isRecognitionInput`, `NoteStore.changes` | 웹에서는 쓰기 없음 |
| X23 | CORE | PDF | `SearchIndexWriter`(source pdf), `PageContent.objects`, 이미지 에셋 | 사각형은 PDF 페이지 비율 좌표 |
| X24 | CORE | SYNC | `EntityKind.pageObject`·`handwriting`, JSON(4.8), outbox 힌트, `UnknownObject` | 4.9 매핑, S-13 |
| X25 | INK | EDITOR | 객체 렌더·`select`·`hitTestObject`·`setHiddenObjectIds`, `ShapeAssist`·`shapePreview`, `InkEdit` v2, `setPlaybackFocus`·`hitTestRecorded`, 테이프 API, `InkTextLayout`, `MathPreview`, `InkFonts` | K-6~K-9 |
| X26 | INK | PDF | `InkPageVectors` v2, `InkMathRenderer.rasterize`, `InkFonts.noteSansBytes`, `defaultPageBackgroundBuilders` | L-1 순서로 그린다 |
| X27 | INK | recog | `InkShapeFitter`(구현), `MathPreview`, `InkPageView`(수식 패드), `InkMathRenderer.validate` | |
| X28 | media | INFRA → CORE | `mediaIoOverrides()` | 오디오 provider의 유일한 override |
| X29 | media | INFRA → EDITOR | `supportedImageSources`·`importImageForNote` → `editorImageImporterProvider`; `RecordingPanel` → `EditorExtensions.recordingPanel`; `mediaDevOverlayLinesProvider` → `DevOverlaySection` | INFRA가 감싼다(1차 X14와 같은 방식) |
| X30 | recog | INFRA → EDITOR | `recognitionSelectionActions`·`recognitionInsertActions` → `EditorSelectionMenuItem`·`EditorInsertMenuItem` | `RecognitionTarget` ↔ 에디터 문맥 1:1 변환 |
| X31 | recog | INFRA → INK | `recognitionOverrides()` 안의 `inkShapeFitterProvider` override | `inkShapeFitterProvider`의 유일한 override |
| X32 | recog | INFRA | `recognitionOverrides`, `handwritingIndexerProvider`(시작·종료), `RecognitionSettingsSection` | 설정 화면 '인식' 섹션 |
| X33 | PDF | INFRA | `pdfSearchIndexerProvider`(시작·종료), `pdfIoOverrides` v2 | |
| X34 | LIBRARY | INFRA | `LibraryScreen.onOpenNoteAt` → `AppRoutes.note(noteId, pageId: , focus: )` → `EditorScreen.initialFocusRectPt` | 주소 `?page=<id>&focus=l,t,r,b` |
| X35 | pencil_bridge | INFRA → EDITOR | `PencilBridge.events`·`capabilities` → `PencilStylusExtrasSource` → `stylusExtrasProvider` | 웹·안드로이드는 `NoStylusExtras` 그대로 |
| X36 | functions/ (SYNC) | recog | `recognizeMath` callable 형식(4.14) | 형식 바꿀 때 7.4.12 절차 |

### 4.16 동작 보장 추가 (7.3.2)

| # | 주체 | 보장 |
|---|---|---|
| K-6 | INK | 모든 `PageObject`의 렌더 외곽 ⊆ CORE `bounds`. 텍스트는 frame으로 자르고, 수식은 frame 안에 contain으로 맞추고, 도형은 둥근 이음·캡으로 `strokeWidth·0.75` 안에 그린다. 새 펜 5종도 1차 K-1을 지킨다(불변식 시험에 추가) |
| K-7 | INK | `setPlaybackFocus`가 바뀌어도 기본 래스터 타일을 다시 만들지 않는다. 다시 그리는 비용은 '쓴/안 쓴' 경계를 넘은 획 수에 비례한다(재생 중 매 프레임 호출해도 됨) |
| K-8 | INK | 그리기 순서 = L-1. 화면·썸네일·벡터 내보내기가 같은 순서다 |
| K-9 | INK | 레이저 획은 `InkEdit`을 만들지 않는다(1차 E-3 보장의 INK 쪽). 테이프 드러냄 상태는 저장하지 않고, 썸네일·벡터 내보내기는 항상 가린 상태다 |
| C-11 | CORE | `TransformElements`는 획과 객체를 한 커밋으로 바꾼다. `UpdateObjects`는 값이 바뀐 JSON 키만 새 필드 버전을 받는다 |
| C-12 | CORE | `UnknownObject`는 읽은 JSON을 키 하나 빠짐없이 그대로 쓴다(동기화·백업 왕복 시험) |
| C-13 | CORE | 검색 색인은 파생 데이터다: `rebuild()`는 멱등이고, 색인이 비어 있어도 원천 데이터로 다시 만든다. 색인 실패는 원천 쓰기를 실패시키지 않는다(같은 커밋에서 색인 쓰기만 다음 유휴 시간으로 미룸) |
| C-14 | CORE | 마이그레이션 v1 → v2는 1차 데이터(노트·페이지·획·에셋·설정·outbox)를 바꾸지 않는다(V7) |
| E-4 | EDITOR | 펜 접촉·버튼 판정 규칙(4.11). 웹에서 공중 `down(0x02)`로 획·지우기가 시작되지 않는다 |
| E-5 | EDITOR | 펜 다운 시 R-1 규칙으로만 `InkStrokeMeta`를 채운다. `offsetNowMs()`는 펜 다운 이벤트 처리 안에서 동기적으로 읽는다 |
| E-6 | EDITOR | 텍스트 상자 편집 세션(포커스 들어옴 → 나감) 1회 = 명령 1회 = 되돌리기 1단계. 편집 중에는 INK에서 그 상자를 숨긴다(`setHiddenObjectIds`) |
| E-7 | EDITOR | 자리(선택 메뉴·삽입 메뉴·녹음 패널·이미지 가져오기)가 비어 있으면 해당 UI를 숨긴다(자리표시 안내 없음). 자리 콜백의 예외는 `FlutterError.reportError` 후 사용자 문구로 보인다 |
| M-1 | media | `stop()`은 에셋(`AssetStore.put`)을 먼저 쓰고 그다음 `createRecording`을 부른다. `offsetNowMs()`는 한 녹음 안에서 단조 증가하고 일시정지 구간을 빼며, `durationMs`는 디코더 길이다(R-2·R-3) |
| M-2 | media | 웹에서 탭이 가려진 동안 녹음하지 않는다: 가려지는 즉시 `pause()`(`interrupted = true`), 돌아와도 자동 재개하지 않는다. 녹음 중 Screen Wake Lock |
| M-3 | media | 이미지 에셋은 `ImageImportLimits`를 지킨다(긴 변 2048 px, 8 MiB, JPEG/PNG만) |
| G-1 | recog | 웹에서 ML Kit을 부르지 않는다(조건부 import + `RecognizerUnsupported`). 인식 실패는 EDITOR로 예외를 던지지 않고 recog 자기 창에서 문구로 보인다 |
| G-2 | recog | 색인기는 사용자가 쓰는 페이지를 방해하지 않는다: 마지막 입력 3초 뒤, 한 번에 한 줄, 앱이 뒤로 가면 멈춘다 |
| S-13 | SYNC | 모르는 `kind` 기록은 그 기록만 보류하고 같은 청크의 나머지는 적용한다. 보류분은 앱 갱신 뒤 다시 적용된다 |
| F-1 | SYNC(functions) | 외부 API 키는 Secret Manager(에뮬레이터는 `.secret.local`)에만 있고 앱·저장소에 없다. 로그인 + 소유자 UID 목록 밖 호출은 거절한다 |

### 4.17 앱 셸 연결(override) 추가 행 (7.3.3)

| provider (정의) | override 주체 (INFRA 모듈) | 값 | 시점 |
|---|---|---|---|
| `audioRecorderServiceProvider`, `audioPlaybackServiceProvider` (CORE) | `MediaModule` → `mediaIoOverrides()` | media_io 구현. 시작 실패 시 override 없음(기본 = 지원 안 함 → 녹음 패널은 '이 기기에서 녹음할 수 없어요') | 이번 |
| `ink.pageBackgroundBuildersProvider` (INK) | `PdfModule` → `pdfIoOverrides()` (v1.4 행 그대로) | `[pdf, image, template]`. PDF 시작 실패 시 override 없음 → 기본 `[image, template]` | 이번 |
| `handwritingRecognizerProvider`, `mathRecognizerProvider` (recog), `ink.inkShapeFitterProvider` (INK) | `RecognitionModule` → `recognitionOverrides(config)` | 웹: 손글씨 지원 안 함, 네이티브: ML Kit, 수식: `mathEndpoint`가 있을 때만 서버, 도형: `GeometricShapeFitter` | 이번 |
| `editorExtensionsProvider` (EDITOR) | `FeatureWiringModule` (v1.4 행 확장) | + `selectionMenuItems`·`insertMenuItems`(recog 동작 변환), `recordingPanel`(media `RecordingPanel` 감쌈) | 이번 |
| `editorImageImporterProvider` (EDITOR) | `FeatureWiringModule` | `EditorImageImporter(sources: supportedImageSources(), pick: importImageForNote)` | 이번 |
| `devOverlaySectionsProvider` (EDITOR) | `FeatureWiringModule` (v1.4 행 확장) | + 미디어 섹션(`mediaDevOverlayLinesProvider`), 인식 색인기 상태 섹션 | 이번 |
| `stylusExtrasProvider` (EDITOR) | `FeatureWiringModule` | `PencilBridge.isSupported`면 `PencilStylusExtrasSource`, 아니면 override 없음 | 이번 |
| `core.recordingRepositoryProvider` 등 CORE 새 provider | — | `noteStoreProvider`에서 파생(override 없음) | — |

override가 아닌 연결: `PdfModule`이 `pdfSearchIndexerProvider`를, `RecognitionModule`이 `handwritingIndexerProvider`를 앱 시작 뒤 유휴 시간에 `start()`하고 종료 때 `dispose()`한다. 라우터는 `LibraryScreen.onOpenNoteAt`을 `AppRoutes.note(noteId, pageId:, focus:)`로 잇는다.

모듈 순서(v2.0): `core` → `pdf`(비필수) → `media`(비필수) → `recognition`(비필수) → `featureWiring` → (실연결) `sync`. '비필수' 모듈이 시작에 실패하면 그 기능만 꺼지고 앱은 뜬다(1차 PDF 규칙과 같음).

### 4.18 공통 규칙 추가 (7.4)

#### 4.18.1 네이티브 플러그인 · 플랫폼 분기 (7.4.3 확장)

- **네이티브 전용 플러그인**은 `*_native.dart`에서만 import하고 조건부 import로 고른다. `workspace_rules.yaml` `native_only_imports`에 더한다: `package:google_mlkit_digital_ink_recognition/`, `package:google_mlkit_commons/`, `package:flutter_foreground_task/`, `package:path_provider/`. (조사 04 7절: 이 플러그인들은 웹으로 **컴파일은 되지만** 부르면 `MissingPluginException`이므로 경계는 컴파일러가 아니라 규칙으로 지킨다.)
- **웹 구현이 있는 플러그인**(`record`, `just_audio`, `audio_session`, `image_picker`)은 일반 파일에서 써도 되지만, 서비스 패키지(`media_io`) 밖으로 나가지 않는다. 피처 패키지의 pubspec에 플러그인을 넣지 않는다(새 규칙 R16: `feature_*`·`pdf_io`·`sync_engine`의 의존에 플러그인 목록 `plugin_packages`가 없음 — 1차 `pdf_io`의 `file_picker`·`pdfium_dart`, `sync_engine`의 Firebase는 기존 예외로 둔다).
- 플랫폼 판정은 `kIsWeb` + `defaultTargetPlatform`만 쓴다. `dart:io` `Platform`은 `*_native.dart` 안에서도 쓰지 않는다(조사 02: `apple_pencil_double_tap`의 `Platform.isIOS`가 웹에서 예외). UI는 플랫폼을 직접 묻지 않고 서비스의 능력(`checkSupport()`, `isAvailable`, `capabilities`, `supportedImageSources()`)을 묻는다.
- 이름 충돌: ML Kit은 `as mlkit` 접두어 필수(`Ink`↔`material_ui`, `StrokePoint`↔CORE). `rendering.dart`의 `SelectionGeometry` 규칙(v1.4 C14-01)은 그대로.

#### 4.18.2 웹 대체 동작 (iPad Safari)

| 기능 | 웹에서의 동작 |
|---|---|
| 백그라운드 녹음 | 가려지면 자동 일시정지 + 돌아오면 '녹음이 멈췄어요. 이어서 녹음할까요?' 안내(M-2). 녹음 중 화면 꺼짐 방지 |
| AAC를 못 내는 브라우저(데스크톱 Chrome) | opus/webm으로 저장하고 녹음 목록에 '아이패드 앱에서는 재생되지 않을 수 있어요' 표시(`crossPlatformPlayable = false`) |
| 손글씨 인식 | 선택 메뉴 '텍스트로 변환'은 보이되 누르면 '이 기기(웹)에서는 손글씨 인식을 쓸 수 없어요. 안드로이드 앱에서 쓸 수 있어요.' 손글씨 색인은 만들지 않는다(텍스트 상자·PDF·수식 검색은 됨) |
| 수식 인식 | 엔진이 없으면 LaTeX 직접 입력 + 미리보기만 |
| Pencil 더블탭·스퀴즈·롤·호버 높이 | 설정 항목 숨김, 캘리그래피는 고정 각 |
| S펜 버튼(안드로이드 Chrome) | 접촉 비트 판정으로 동작(E-4) |
| 이미지 붙여넣기 | `navigator.clipboard.read`가 있을 때만 메뉴. 카메라는 file input `capture` |

#### 4.18.3 권한

- `permission_handler`는 넣지 않는다(조사 02 7.2, 04 5절). 마이크는 `record.hasPermission(request: true)`, 안드로이드 13+ 알림(포그라운드 서비스)은 `flutter_foreground_task`, 사진은 시스템 선택기(권한 대화상자 없음)로 받는다.
- 거절·영구 거절은 해요체 문구 + '설정 → 필기노트 → 마이크' 안내로 처리한다(설정 앱 열기 버튼 없음).
- Info.plist·매니페스트 키는 INFRA 소유다. 플러그인을 쓰는 영역은 필요한 키를 계획서 7절에 적고 INFRA가 기반 단계에서 넣는다: iOS `NSMicrophoneUsageDescription`, `UIBackgroundModes: [audio]`, `NSPhotoLibraryUsageDescription`, `NSCameraUsageDescription`, `ITSAppUsesNonExemptEncryption = false`, 배포 대상 15.5(3곳) + `Podfile`(`platform :ios, '15.5'`, ML Kit `post_install`). 안드로이드 `main` 매니페스트 `INTERNET`(지금 debug·profile에만 있음), `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MICROPHONE`, `POST_NOTIFICATIONS`, microphone 서비스 선언, 라벨 `필기노트`, 부팅 수신기 제거(`tools:node="remove"`).

#### 4.18.4 ID · 설정 키 · 문구 (7.4.6, 7.4.5)

- ID 규칙 예외 추가: `HandwritingText.idFor(pageId) = 'hw_' + pageId`(결정적 id). 녹음 id는 녹음 시작 전에 `idGeneratorProvider`로 만든다.
- 설정 키 접두사 추가: `media.*`(PDF 영역), `recog.*`(LIBRARY 영역). scope: 녹음 비트레이트·인식 언어·인식 켜기는 `synced`, 녹음 동의 안내 본 여부·모델 Wi-Fi 전용·자동 색인·탭 재생 기본값은 `device`. 제스처 동작 매핑은 1차 `editor.settings.synced`의 `gestures` 안(`synced`).
- 녹음 동의 안내 문구(F-16, 고정): "다른 사람의 목소리를 녹음할 때는 미리 동의를 받아 주세요." — 바꿀 때 7.4.12 절차.

#### 4.18.5 글꼴 · 웹 예산 · 메모리 (7.4.9, 7.4.10)

- 텍스트 상자 글꼴 `NoteSans`는 INK 패키지 에셋(한글 KS X 1001 2,350자 + 라틴 부분 집합, 보통·굵게 — 사용자 질문 U7)이고, `FontManifest`에 넣지 않아 **웹 첫 로드에 내려받지 않는다**(텍스트 상자를 처음 그릴 때 `InkFonts.ensureLoaded`). 라이선스(OFL) 고지는 INFRA 앱 정보 화면.
- KaTeX 글꼴(`flutter_math_fork`, 20개, gzip 371 KB)은 패키지가 `fonts:`로 선언해 웹 시작 때 모두 내려받는다. 이번에는 받아들이고 예산표에 올린다(U15). 초과하면 포크해 지연 적재.
- 웹 예산표(INFRA 6.13)에 추가 측정: `main.dart.js` 증가분, 시작 때 받는 글꼴 바이트, `record_web` 워크릿 JS.
- 메모리 예산(7.4.10) 추가: INK 이미지 디코드 캐시 웹 48 MB / 네이티브 128 MB, 수식 래스터 캐시 8 MB, PDF 내보내기 중 이미지 객체 임시 16 MB, 웹 녹음 메모리 조각 ≤ 8 MB(그 이상은 초안 저장소로). 합계 ≤ 300 MB(1차) 유지.

#### 4.18.6 테스트 (7.4.8 확장)

| 항목 | 규칙 |
|---|---|
| 태그 `media` | Chrome 가짜 마이크 시험. `tool/chrome-fakemedia`(INFRA — `--use-fake-device-for-media-stream --use-fake-ui-for-media-stream --autoplay-policy=no-user-gesture-required`)를 `CHROME_EXECUTABLE`로 쓴다. 패키지 `dart_test.yaml`에 선언·기본 skip, CI의 별도 단계에서 실행. 시험 파일이 `RecordPluginWeb.registerWith`·`JustAudioPlugin.registerWith`를 직접 부른다 |
| 태그 `emulator` | `functions/` 에뮬레이터 + Dart HTTP 클라이언트(VM) 시험. 기본 skip, CI `functions` 잡에서만 |
| 플러그인 가짜 | EDITOR·LIBRARY 시험은 CORE `FakeAudioRecorder`·`FakeAudioPlayback`, recog `FakeHandwritingRecognizer`·`FakeMathRecognizer`, 가짜 `EditorImageImporter`·`StylusExtrasSource`만 쓴다(플러그인 채널을 건드리지 않음) |
| 글자 골든 | 1차 규칙 그대로(Ahem만). `NoteSans`·수식 렌더는 픽셀 단언(경계 안·비어 있지 않음)과 실기기로 확인 |
| 합성 자료 | 도형 판정·줄 나누기는 고정 시드 합성 획(조사 03 4.2·7.4). 실기기 표본은 사용자 동의 뒤 `test/fixtures/real/`(U18) |
| 네이티브 설정 정적 시험 | INFRA `tool/test/native_config_test.dart`(매니페스트·Info.plist·pbxproj·Podfile·gradle 파싱) + `ws native-reqs`(플러그인 podspec·`Package.swift`·gradle 요구 vs 앱 값, CocoaPods 전용 목록) |

#### 4.18.7 서버 함수 (functions/)

- 저장소 루트 `functions/`(SYNC). npm 의존은 **정확한 버전** + `package-lock.json` 커밋 + `npm ci`. `.env.local`·`.secret.local`·`node_modules/`·`lib/`는 `.gitignore`(INFRA가 기반 단계에서 넣음).
- `app/firebase.json`에 `"functions": [{"source": "../functions"}]`(INFRA, 에뮬레이터에서 동작 확인됨 — 조사 04 6.4).
- CI `functions` 잡(INFRA 소유 워크플로, SYNC 스크립트 호출): `ubuntu-latest`, Node 22, `npm ci && npm test && npm run test:emulator`(`firebase emulators:exec --only functions,auth --project demo-noteapp`, firebase-tools 15.34.2). 경로 필터 `functions/**`.
- 배포(`firebase deploy --only functions`)는 Firebase 프로젝트 + Blaze 뒤(1.4, U3·U6).

### 4.19 외부 패키지 버전 고정표 추가분 (7.5)

확인: 2026-11-05 pub.dev, 1차 잠금 파일 복사본 + 아래 배치로 `flutter pub get` 해석 성공(`/tmp/claude-0/plan57-scratch/designA/ws` — `media_io`·`ink_recognition`·`pencil_bridge` 시험 멤버, `ink_engine`에 `flutter_math_fork`, 앱에 `path_provider`). **기존 잠금 변화는 `xml 7.1.0 → 7.0.1` 한 건**(원인: `flutter_math_fork` → `flutter_svg` → `vector_graphics_compiler 1.3.x`의 `xml <=7.0.1` — 1.3.0~1.3.4 모두 같아 피할 수 없음), 추가 44개.

| 패키지 | 버전 | 쓰는 멤버 | 비고 |
|---|---|---|---|
| `record` | 7.1.2 | media_io | 연합 플러그인(`record_web 2.1.3`, `record_android 2.2.0`, `record_ios 2.1.1` …). 7.0부터 안드로이드 백그라운드 서비스 없음 |
| `just_audio` | 0.10.6 | media_io | `just_audio_web 0.4.16` |
| `audio_session` | 0.2.4 | media_io | |
| `flutter_foreground_task` | 11.0.3 | media_io (`*_native.dart`) | `shared_preferences 2.5.6` 끌어옴 |
| `image_picker` | 1.2.4 | media_io | `image_picker_for_web 3.1.1`, `image_picker_android 0.8.13+25` |
| `image_picker_ios` | 0.8.13+13 | media_io (간접 고정) | 0.8.13+14는 2026-10-29 게시(7일)라 채택하지 않음. +13은 2026-10-22 |
| `path_provider` | 2.1.6 | media_io (`*_native.dart`), app (`*_native.dart`) | 1차 잠금에 이미 간접으로 있음 |
| `image` | 4.12.0 | media_io | 1차 루트 dev와 같은 버전(JPEG 재인코딩) |
| `google_mlkit_digital_ink_recognition` | 0.16.1 | ink_recognition (`*_native.dart`, `as mlkit`) | `google_mlkit_commons 0.13.0`. 안드로이드 `digital-ink-recognition:19.0.0`, iOS pod 15.5 |
| `http` | 1.6.0 | ink_recognition | callable 클라이언트 |
| `flutter_math_fork` | 0.7.4 | ink_engine | 2025-05 이후 갱신 없음 — 깨지면 포크(위험 #6) |
| `flutter_svg` | 2.3.0 | ink_engine (간접 고정) | 최신 2.3.2(2026-10-28)는 2주 미만. 2.3.0은 2026-05-08 |
| `vector_graphics` | 1.2.3 | ink_engine (간접 고정) | 최신 1.2.6(2026-11-02) 대신 |
| `vector_graphics_compiler` | 1.3.0 | ink_engine (간접 고정) | 최신 1.3.4(2026-10-29) 대신 |
| `flutter_riverpod` / `material_ui` / `meta` / `collection` / `web` | v1.4 값 | + media_io, ink_recognition (`web`은 media_io `*_browser.dart`) | |
| (npm) `firebase-functions` / `firebase-admin` / `typescript` / `@types/node` | 7.4.0 / 14.5.0 / 6.0.3 / 22.20.5 | functions/ | 조사 04 6.4에서 설치·에뮬레이터 실행 확인 |
| (도구) `firebase-tools` | 15.34.2 | CI | v1.4 INFRA 고정값 |

넣지 않음: `permission_handler`(권한은 4.18.3), `cloud_functions`·`firebase_auth`(실연결 미니 라운드), `apple_pencil_double_tap`·`stylet`(참고 구현만 — 직접 만든 `pencil_bridge`), `one_dollar_unistroke_recognizer`(도형 판정 정확도·전역 상태 — 조사 03 4.2), `super_clipboard`, `audioplayers`, `flutter_sound`/`taudio`.

간접 고정(이번에 처음 생긴 방식): 2주가 안 된 간접 의존이 해석되면 그 의존을 끌어오는 패키지의 pubspec에 정확한 버전으로 적어 내린다(주석 `# 간접 고정`). `ws check` R9 `pinned_external`에도 올린다.

---

## 5. 기반 단계 · 통합 순서 · 검증

### 5.1 전제

- 1차 통합(1차 7.7 1~6단계, V1~V7)이 끝나고 `main`에 병합되어 있다. 1차 iPad 확인 결과(PLAN 체크리스트 갱신)가 나와 있다.
- 2차 작업 트리: `/home/user/wt2/<id>`, 브랜치 `area2/<id>`(1차 `area/<id>`와 섞이지 않게). 계획 작업 트리 `plan57`의 계획서는 승인 뒤 `main`의 `docs/plans/m5-7/`로 들어간다.
- 계약 변경 절차는 1차 7.4.12 그대로(변경 요청 → 총괄 승인 → 4장 수정 + `v2.x`).

### 5.2 기반 단계 (동시 개발 시작 전 `main`에 커밋)

각 단계 뒤 `ws check`·`flutter analyze --fatal-infos`·`ws test`(VM·Chrome)·`dart test tool/test`가 통과해야 다음 단계로 간다(1차 7.6 규칙). **예외 하나**: R2-B2(CORE `EntityKind` 값 추가)는 SYNC switch를 깨므로 R2-B7과 **한 묶음으로 병합**한다(총괄이 두 브랜치를 함께 병합한 뒤 검사).

| 단계 | 담당 | 경로 | 내용 | 완료 조건 |
|---|---|---|---|---|
| R2-B1 | INFRA | 루트 `pubspec.yaml`·`pubspec.lock`·`.gitignore`, `packages/{media_io,ink_recognition,pencil_bridge}/pubspec.yaml`·`README.md`·빈 진입점·스모크 시험, `tool/workspace_rules.yaml`(R8 v2.0, `native_only_imports`·`pinned_external`·R16 `plugin_packages`), `tool/chrome-fakemedia`, `app/firebase.json`(`functions`), `.github/workflows/functions.yml` 골격 | 4.19의 **모든** 새 의존을 각 pubspec에 미리 넣고 lock을 만든다(간접 고정 포함). `pencil_bridge`는 iOS `pluginClass`만 있는 빈 플러그인 | `flutter pub get --enforce-lockfile`, `ws check`, `ws test`, `dart test tool/test` |
| R2-B2 | CORE | `packages/note_core/lib/**`, `test/**` | 4.3~4.8의 계약 파일 **전부 + 동작 구현**: `PagePoint`·`ElementFrame`·객체 4종 + `UnknownObject`·JSON·`bounds`, `ShapeGeometry` 템플릿, `EntityKind` 2값, `PageContent.objects`·`PageDraft.objects`, 명령 3종 + 해석기(가짜 저장소에서 동작), `Recording.title`, 녹음·초안·손글씨·검색 인터페이스와 provider, 오디오 포트 + `Unsupported*` 기본값, `SearchText`(정규화·바이그램 — 순수 함수라 B2에서 완성), 이미지 타입. `testing.dart`: `createFakeNoteStore()` v2(객체·녹음·초안·손글씨·검색 — 검색은 메모리 `LIKE`), `FakeAudioRecorder`·`FakeAudioPlayback`, `ObjectFixtures`. DB v2·마이그레이션·FTS5·파일 저장은 동시 개발에서(`openTestNoteStore`는 v1 DB로 계속 동작) | CORE 계약 시험 + `api_surface_test` v2 |
| R2-B7 | SYNC | `packages/sync_engine/lib/**`, `functions/` | (R2-B2와 한 묶음) `EntityKind` switch에 새 두 값을 '노트 범위 일반 기록'으로 넣어 컴파일·기존 시험 통과. `functions/` 골격(`package.json` 정확한 고정, `tsconfig.json`, 가짜 엔진, 단위 시험 1개) | SYNC 기존 시험 전부, `npm ci && npm test` |
| R2-B3 | INK | `packages/ink_engine/lib/**`, `assets/fonts/`, `test/**` | 4.10 공개 표면 전부를 **단순하지만 동작하는 구현**으로: 객체는 L-1 층에 경계 상자 + 기본 그리기(도형 폴리라인·타원, 텍스트는 시스템 글꼴 `Paragraph`, 이미지는 회색 상자, 수식은 `MathPreview` 래스터 없이 상자), `select`·`hitTestObject`·`setHiddenObjectIds` 동작, P1 펜은 볼펜 프로필(v1.4), `ShapeAssist`는 받기만, `NoShapeFitter`, 재생·테이프 API는 상태만, `ImageBackgroundLayerBuilder`는 종이 색, `defaultPageBackgroundBuilders`, 벡터 v2 필드는 빈 목록, `InkMathRenderer.validate`는 `flutter_math_fork` 해석기로 실제 동작, `InkFonts`·`InkTextLayout` 동작(글꼴 파일 포함) | 스모크 + 다른 영역이 컴파일·기본 동작 가능 |
| R2-B4 | PDF | `packages/pdf_io/lib/**`, `packages/media_io/lib/**`, 각 `test/**` | `pdfIoOverrides()` v2 목록(`defaultPageBackgroundBuilders` 사용), `PdfSearchIndexer`(`start()` 아무것도 안 함). media_io: `initializeMediaIo`·`mediaIoOverrides()`(B4에서는 빈 목록 → CORE 기본 '지원 안 함'), `supportedImageSources()` = 빈 집합, `importImageForNote` = `null`, `RecordingPanel` 자리표시(제목 + 닫기), `mediaDevOverlayLinesProvider` 빈 목록 | `api_surface_test`, `pdfIoOverrides()`만 넣은 컨테이너에서 provider read 예외 없음 |
| R2-B5 | EDITOR | `packages/feature_editor/lib/**` | 4.11 공개 표면: `EditorExtensions` v2 + 문맥·메뉴 항목 타입, `editorImageImporterProvider`, `EditorScreen.initialFocusRectPt`(받기만), `EditorGesture`·`EditorAction`·`GestureSettings` v2(JSON 왕복 동작), Stylus v2 타입 + `NoStylusExtras.capabilities` | 스모크 위젯 시험, `GestureSettings` JSON 시험(v1.4 JSON 읽기 포함) |
| R2-B6 | LIBRARY | `packages/feature_library/lib/**`, `packages/ink_recognition/lib/**` | `LibraryScreen.onOpenNoteAt`(받기만). recog: 4.12 공개 표면 — 포트·실패 타입·`HandwritingTrace.fromStroke`(동작), `Unsupported*`·`ManualOnlyMathRecognizer`, `recognitionOverrides()`(B6: 도형 판정기만 `NoShapeFitter`로), 동작 목록 빈 목록, `HandwritingIndexer`(`start()` 아무것도 안 함), `RecognitionSettingsSection` 자리표시, `testing.dart` 가짜 엔진 | `api_surface_test`, 스모크 |
| R2-B8 | INFRA | `app/lib/**`, `app/test/**`, `packages/pencil_bridge/**` | `MediaModule`·`RecognitionModule` 추가, 4.17 표의 override를 기반 단계 구현으로 연결, 라우팅 `?page=&focus=`, `PencilStylusExtrasSource`(가짜 채널 시험), `pencil_bridge` Dart 표면(이벤트 디코딩) + Swift 파일 골격 | 전체: `ws check` 0, analyze 0, `ws test`(VM·Chrome), `dart test tool/test`, `cd app && flutter build web --release`. **`main.dart.js` 크기·시작 글꼴 바이트를 기록**해 웹 예산표 갱신 |

- 순서: R2-B1 → (R2-B2 + R2-B7 묶음) → R2-B3 → (R2-B4, R2-B5, R2-B6 병렬 — INK 타입을 쓰므로 B3 뒤) → R2-B8. 각 영역은 CORE 계약 타입 커밋 뒤 자기 작업 트리에서 코드 작성을 시작해도 되지만 `main` 커밋은 위 순서다(1차 v1.2 풀이와 같음).
- 기반 단계가 끝나면 각 계획서 5절 '가정' 블록을 실제 타입으로 바꾸고 동시 개발을 시작한다.

### 5.3 통합 순서

1. **CORE** 병합 → lock 재생성 → 검사 + **마이그레이션 시험(V7)**
2. **INK** 병합 → 검사 + INK 골든·불변식(K-1·K-6)
3. **SYNC** 병합 → 검사 + T16-v2(실제 CORE 2개: 객체 동시 편집·삭제 대 수정·모르는 `type` 왕복·모르는 `kind` 보류·손글씨 결과) + `functions` 시험
4. **PDF**(`pdf_io` + `media_io`) → 검사 + `integration`(객체 내보내기) + `media`(Chrome 녹음 → 실제 CORE 에셋·녹음 행 → 재생)
5. **LIBRARY**(`feature_library` + `ink_recognition`) → 검사 + 실제 CORE 색인 시험(L2x) + 도형 판정 합성 시험
6. **EDITOR** → 검사 + E-2x(실제 INK + 실제 CORE: 객체 도구·올가미 혼합 선택·녹음 연동(가짜 오디오 포트))
7. **INFRA** → 실제 모듈 연결, `pencil_bridge`, 네이티브 설정 정적 시험, 스모크 V5·V6
8. 통합 태그 시험 전체(`ws test --run-skipped -t integration`, `-t media`, `-t emulator`)
9. 미리보기 배포 → 사용자 iPad 웹 확인(5.5 B) / `android.yml` APK → 안드로이드 확인(5.5 A, 기기가 있을 때) / (선택) `ios-compile.yml` 1회 → PLAN.md 체크리스트 갱신(총괄)

3~6은 1차처럼 순서를 바꿔도 된다(서로 import하지 않음). 위 순서는 '데이터 → 렌더 → 소비자' 순으로 실패 원인을 좁히기 위한 권장이다.

### 5.4 컨테이너 검증 기준 (전부 통과해야 '2차 통합 완료')

| # | 기준 |
|---|---|
| V1 | `flutter pub get --enforce-lockfile`, `ws check`(R1~R16) 위반 0 |
| V2 | 루트 `flutter analyze --fatal-infos` 0건, `dart format` 변경 없음 |
| V3 | `ws test`(VM, 골든 포함)·`ws test --platform chrome`·`dart test tool/test`·통합 태그(`integration`) 전부 통과 |
| V4 | `cd app && flutter build web --release` 성공, `web-assets verify` 통과, 웹 예산표 갱신(`main.dart.js` 증가분, 시작 글꼴 바이트) |
| V5 | INFRA 스모크(1차 V5 확장, 메모리 CORE + 실제 모듈): 새 노트 → 획 1개 → 텍스트 상자 입력 → 사각형 도형 → 가짜 가져오기로 이미지 1개 → 올가미로 셋 다 선택 → 회전 → 닫기·다시 열기 → 모두 유지 → 되돌리기 2회 → 회전 전 상태. 4.17의 override가 모두 실제 구현이고 중복이 없음 |
| V6 | 같은 스모크를 Chrome에서(웹 런타임에 `dart:io`·네이티브 전용 플러그인 호출 없음 확인) |
| V7 | **마이그레이션**: 1차 코드로 만든 v1 DB 고정 자료(노트 3개·페이지 20장·획 2,000개·PDF 에셋 1개·설정·outbox 미전송 기록)를 v2로 열기 — VM(파일 DB)과 Chrome(웹 워커) 둘 다, 모든 행·필드 버전·outbox 유지, drift 생성 마이그레이션 시험 통과 |
| V8 | `media` 태그(Chrome 가짜 마이크): 2초 녹음(가운데 1초 일시정지) → 정지 → 에셋 + `Recording` 행 → 재생·2배속·탐색, `offsetNowMs` 누적 vs 파일 길이 차 ≤ 50 ms(조사 02 실측 −3~+7 ms) |
| V9 | 인식: `groupIntoLines` 합성 자료 정확도 ≥ 95%, 도형 판정 합성 1,400개(조사 03 4.2 조건) — 원 ≥ 98%, 직선·사각형·타원 ≥ 85%, 삼각형 ≥ 80%, 낙서 거부 ≥ 90%, 잘못 바꿈(다른 도형으로) ≤ 10%. 색인기 낡음 판정 시험(가짜 엔진), 웹 경로 `RecognizerUnsupported` |
| V10 | 검색: 조사 03 9.2의 질의(2·3글자, 낱말 중간, 영문 접두사, 여러 낱말 AND, 1글자 LIKE 대체)를 VM·Chrome에서 같은 결과로. 5,000쪽 합성 색인 질의 중앙값 ≤ 5 ms(VM). PDF 출처 결과의 사각형이 노트 페이지 pt로 맞음 |
| V11 | PDF 내보내기(실제 PDFium VM·Chrome): 객체 4종 + 이미지 페이지 + 테이프 + 점선이 든 노트 → 내보낸 PDF를 pdfrx로 다시 열어 텍스트 상자 한글이 텍스트로 추출되고, 이미지 객체 수·수식 래스터·점선 조각이 맞음 |
| V12 | 네이티브 설정 정적 시험(매니페스트 `INTERNET`·서비스·권한·라벨, Info.plist 키, 배포 대상 15.5 × 3, Podfile 줄, release 서명 분기) + `ws native-reqs` 위반 0, CocoaPods 전용 플러그인 = ML Kit 둘뿐 |
| V13 | `functions/`: `npm ci && npm test`, 에뮬레이터 시험(로그인 없이 → `unauthenticated`, 목록 밖 UID → `permission-denied`, 잘못된 입력 → `invalid-argument`, 가짜 엔진 정상), Dart HTTP 클라이언트(`CallableMathRecognizer`) VM 시험(`emulator` 태그) |
| V14 | CI에서 `android.yml` release APK가 고정 서명(시크릿이 없으면 debug 서명)으로 만들어져 아티팩트로 남음(통합 때 1회). (선택, 사용자 승인) `ios-compile.yml` 1회 성공 |

### 5.5 실기기 체크리스트

A. **안드로이드 APK** (안드로이드 태블릿이 있을 때 — U2. 없으면 '코드만, 확인은 이후'로 표시)

| # | 확인 | 근거 |
|---|---|---|
| A-1 | 고정 서명 APK 덮어 설치 → 1차·2차 노트가 남아 있음(파일 DB·파일 에셋) | 공통-1 |
| A-2 | S펜: 닿은 채 측면 버튼 누르고 쓰기 → 지우기, 버튼 떼면 펜. Air command 켬/끔 각각 | M5-8, 조사 02 D6 |
| A-3 | 녹음 → 홈으로 나감·화면 끔 5분 → 돌아와 정지 → 길이·재생 정상, 알림 표시 | M6-2 |
| A-4 | ML Kit `ko` 모델 받기(크기 기록), 한국어 문장·혼용 문장 30줄 문자 오류율(`ko` 단독 vs `ko`+`en`), 줄당 인식 시간 | M7-1, 조사 03 R1 |
| A-5 | 녹음 시계 오차 10회(파일 길이 − 시계) → 150 ms 넘게 일정하면 보정 필드 검토 | R-3, 조사 02 D9 |
| A-6 | 가로·세로·분할 화면에서 에디터·녹음 패널 | 조사 04 3.3 |

B. **iPad 웹(Safari, 홈 화면 앱)** — 통합 미리보기 배포 직후

| # | 확인 | 근거 |
|---|---|---|
| B-1 | 1차에서 쓴 실제 노트가 2차 첫 실행 뒤 그대로 열림(DB v2 마이그레이션) | V7 실사용 |
| B-2 | 텍스트 상자 한글 입력: 조합 중 글자·자동 완성·받침 이동·줄바꿈, 확대 상태에서 입력 | M5-2 |
| B-3 | 사진 보관함·카메라로 이미지 삽입(HEIC 사진 포함), 이미지 페이지 | M5-3·4 |
| B-4 | 도형 도구 7종, 자동 도형 보정(멈춤 500 ms)의 오인식 체감, 꼭짓점 편집 | M5-5·6 |
| B-5 | 올가미 회전 15° 맞춤·색 변경·잘라내기·붙여넣기(획 + 객체) | M5-1 |
| B-6 | 붓펜·캘리그래피·점선 필기감, 레이저 사라짐, 테이프 가림·탭 드러냄 | M5-10~12 |
| B-7 | 제스처 동작 바꾸기(두 손가락 탭 → 다시 실행 등) | M5-7 |
| B-8 | 녹음 30분(앞에 둔 채) → 재생 강조·필기 탭 재생·배속, `isEncoderSupported`·MIME(개발자 표시) | M6, 조사 02 D1·D2 |
| B-9 | 녹음 중 앱 전환·화면 잠금 → 자동 일시정지·안내, Screen Wake Lock | M-2, 조사 02 D3·D4 |
| B-10 | 검색: 텍스트 상자·PDF 텍스트·수식으로 찾기 → 결과 누르면 그 페이지·위치로 | M7-2~4 |
| B-11 | 수식: LaTeX 입력 → 렌더, 크기·색, LaTeX 복사, PDF 내보내기 | M7-5 |
| B-12 | Pencil 호버가 `kind: stylus` 호버로 오는가(개발자 표시) | 조사 02 D8 |
| B-13 | 1차 7.7 V7 복합 항목 재확인(PDF 500쪽 + 객체 많은 페이지에서 캐시 합계 ≤ 300 MB) | 4.18.5 |

C. **TestFlight 뒤(Apple 유료 계정 가입 후)** — 2차 완료 조건이 아니다

| # | 확인 |
|---|---|
| C-1 | Pencil 더블탭·스퀴즈(시스템 설정 따르기·앱 설정), 배럴 롤 캘리그래피, 호버 높이 |
| C-2 | 백그라운드 녹음(앱 전환·잠금), 녹음 → 재생 전환 때 세션·스피커, 다른 앱 음악 재개(조사 02 D5) |
| C-3 | ML Kit iOS 인식(A-4와 같은 목록), 모델 받기가 셀룰러를 막는지 |
| C-4 | 네이티브 필기 지연(PLAN 5.4 20 ms) — 1차부터 미뤄진 판정 |

---

## 6. 위험과 물을 것

### 6.1 위험

| # | 위험 | 영향 | 대응 |
|---|---|---|---|
| 1 | CORE·INK·EDITOR가 각 15~17 단위로 크고 객체 사슬(CORE → INK → EDITOR)의 임계 경로에 있다 | 2차 일정 지연 | 기반 단계에서 '단순하지만 동작하는 구현'까지 넣어 사슬을 끊는다(R2-B2·B3). 무거운 UI 둘(녹음 패널·변환 창)을 다른 영역으로 넘겼다(2.3). 일정이 밀리면 1.5의 P-B·P-C부터 자른다 |
| 2 | 사용자의 주 기기(iPad 웹)에서 손글씨 인식이 이번 라운드에 **동작하지 않는다**(ML Kit 웹 불가, 실연결 전이라 동기화된 결과도 없음) | M7-1·M7-2(손글씨 부분)의 체감 가치가 TestFlight 또는 실연결 뒤로 밀림 | 안드로이드 APK로 첫 판정(U2). 웹 인식은 서버 경유 OCR 어댑터 하나로 더할 수 있게 포트를 둔다(U5). 텍스트 상자·PDF·수식 검색은 웹에서 이번에 된다 |
| 3 | ML Kit 한국어 태그·품질·혼용 인식 미확인(외부 문서 접근 불가) | 인식률 불만족 | A-4 실기기 실험을 M7 첫 작업으로. 후보 고르기·직접 편집 UI. 엔진 포트 뒤라 상용 엔진으로 바꿀 수 있음 |
| 4 | iPad Safari의 Flutter 웹 텍스트 입력(한글 IME 조합) 품질 | 텍스트 상자 사용성 | EDITOR 첫 작업을 IME 시제품 + 미리보기 배포로(B-2 조기 확인). 문제가 크면 웹에서는 시트 안의 일반 입력란으로 받고 상자에 반영하는 대체 UI |
| 5 | 한글 글꼴 크기(부분 집합이라도 수백 KB~1 MB)와 부분 집합 밖 글자 | 첫 텍스트 상자 지연, 드문 글자 대체 글꼴(온라인) | 지연 적재(`InkFonts.ensureLoaded`), `covers()`가 거짓이면 PDF는 래스터로, 화면은 대체 글꼴. 크기는 R2-B8에서 측정 |
| 6 | `flutter_math_fork`는 1년 반 갱신이 없고, 끌어오는 `flutter_svg` 계열은 최신판이 2주 미만, `xml` 하향(7.1.0 → 7.0.1) | 빌드 깨짐·회귀 | 간접 고정(4.19), 순수 Dart라 깨지면 포크. 1차 코드는 `package:xml`을 직접 쓰지 않는다(작업 트리 7개 `grep` 확인) — 간접 사용처(빌드 도구 등)는 R2-B1 전체 시험으로 확인 |
| 7 | 웹 녹음은 탭이 닫히면 메모리 조각이 사라진다(`record_web`) | 강의 녹음 손실 | CORE 초안 저장소 API를 B2에 넣고, media_io P-B 자체 녹음기가 5초마다 조각을 저장. P-B가 늦으면 패널에 '녹음 중에는 탭을 닫지 마세요' 안내 |
| 8 | 네이티브 녹음 시계 오차 미측정 | 재생 강조가 어긋남 | 강조 허용 폭 + 탭 재생 1.5초 앞당김(R-5). A-5 실측 뒤 `Recording` 보정 필드(계약 변경) 판단 |
| 9 | DB 스키마 v2: 옛 앱(되돌린 웹 배포)이 v2 DB를 열지 못함, 1차 실제 노트의 마이그레이션 실패 | iPad 노트 접근 불가·손실 | V7 고정 자료 시험(VM·Chrome), 미리보기 채널은 출처가 달라 데이터가 따로(1차 7.4.9). live 배포 전에 '백업 내보내기'를 안내서에 넣는다. 웹 배포 되돌리기는 v2 이후 금지(안내서) |
| 10 | 페이지 객체가 많은 페이지(이미지 여러 장 + 텍스트)에서 iPad Safari 메모리·타일 재생성 | 탭 재로드 | 이미지 디코드를 표시 버킷 크기로, 캐시 예산(4.18.5), `PageObjectLimits`, B-13 확인 |
| 11 | ML Kit iOS는 CocoaPods 전용이고 CocoaPods trunk가 2026-12-02 읽기 전용. 실연결 때 Firebase(SwiftPM)와 혼합 모드 중복 | iOS 빌드 실패 | 이번에는 Firebase 네이티브를 앱에 넣지 않는다(1.4). `ios-compile.yml` 1회로 ML Kit 단독 상태 확인(P-C). 인식 엔진은 포트 뒤 |
| 12 | 서버 함수 코드를 배포 없이 오래 두면 낡음(firebase-functions 판, Node 런타임 2027-04-30 지원 중단 예정) | 실연결 때 재작업 | CI 에뮬레이터 시험을 계속 돌리고, 실연결 미니 라운드에서 판을 다시 확인 |
| 13 | 영역 주제가 어색한 배치(PDF가 오디오, LIBRARY가 인식, SYNC가 서버 함수) | 그 영역의 학습 비용 | 조사 02·03·04가 패키지 구조·코드 뼈대까지 적어 둠. 7장 평가 참고 |
| 14 | 앱 셸 연결 코드(자리 변환)가 늘어남 | INFRA 통합 단계 부담, 변환 실수 | 변환을 `RecognitionTarget` ↔ 에디터 문맥 1:1로 단순하게 두고, V5 스모크가 자리 각각을 한 번씩 누른다 |
| 15 | 안드로이드 개발자 인증(2027 전 세계 시행 예정)·사이드로드 정책 | 시험 APK 설치 방법 변화 | 안내서에 감시 항목으로(조사 04 3.6) |

### 6.2 사용자에게 물을 것 (기본값으로 진행하고, 답이 오면 바꾼다)

| # | 질문 | 왜 필요한가 | 기본값 |
|---|---|---|---|
| U1 | Apple Pencil 종류(Pro / USB-C / 2세대)와 iPad 정확한 모델명 | USB-C 펜슬이면 필압·더블탭·스퀴즈·롤이 없어 M5-9를 쓸 수 없다(PLAN 11장 1번) | Pro 기능까지 코드로 만들고 설정에서 능력에 따라 숨김 |
| U2 | S펜이 되는 안드로이드 태블릿이 있는가, 모델은? | A 체크리스트(S펜 버튼·백그라운드 녹음·ML Kit)의 완료 판정 | 없다고 보고 '코드만, 확인은 이후'. (P-C) 안드로이드 에뮬레이터 CI 잡으로 ML Kit 흐름만 자동 확인 |
| U3 | Firebase 프로젝트를 언제 만들 것인가 | 실연결·서버 함수 배포 시점 | 2차 통합 뒤 '실연결 미니 라운드'(1.4). 2차 도중 만들어도 2차에 끼우지 않음 |
| U4 | Apple 유료 계정 가입 시점, 그 전에 무료 Apple ID + Sideloadly(PC·케이블 필요, 7일마다 재설치)를 쓸 의향 | C 체크리스트 시점 | 쓰지 않음. TestFlight 뒤 확인 |
| U5 | iPad 웹에서 '손글씨 → 텍스트'가 꼭 필요한가 | 필요하면 서버 경유 OCR(Firebase Blaze + 외부 API 비용, 필기 이미지를 외부로 보냄) | 이번엔 불필요(검색은 텍스트 상자·PDF·수식으로) |
| U6 | 수식 엔진 비교용 유료 계정(Mathpix 설정비 $19.99, Anthropic API 등)과 필기 이미지·획을 외부 서비스로 보내는 데 동의하는가 | 실제 엔진 호출·비교 실험(M7-6) | 계정 생길 때까지 LaTeX 직접 입력 + 가짜 엔진. 보낼 때는 수식 영역만, 설정에 명시 |
| U7 | 텍스트 상자 글꼴: Noto Sans KR 부분 집합(KS X 1001 2,350자 + 라틴, 보통·굵게) | 크기·라이선스·드문 글자 | 그대로(지연 적재). 다른 글꼴(예: Pretendard)을 원하면 교체 |
| U8 | 녹음 음질 기본값(AAC 64 kbps 모노 — 1시간 약 29 MB)과 데스크톱 Chrome 녹음 허용(재생 제한 경고) | 용량·동기화 비용 | 64 kbps, 허용 + 경고 |
| U9 | S펜 버튼 = '누른 채 쓰는 동안 지우개', Pencil 더블탭 = 'iPadOS 설정 따르기' | 기본 동작 | 그대로 |
| U10 | 암기 테이프 드러냄 상태는 저장하지 않고(다시 열면 모두 가림), 썸네일·PDF는 가린 채 | 학습 흐름 | 그대로 |
| U11 | 레이저 포인터 1.5초 뒤 사라짐 | | 그대로(설정에서 0.3~5초) |
| U12 | 녹음 일시정지 중에 쓴 필기는 녹음에 연결하지 않음 | 재생 강조 규칙(R-1) | 그대로 |
| U13 | '녹음 삭제'는 목록에서만 지우고 파일 용량은 나중(에셋 정리 기능)에 회수 | 저장 공간 | 그대로 |
| U14 | 자동 도형 보정: 펜을 0.5초 멈추면 발동, 대상 직선·원·타원·삼각형·사각형·다각형(별·화살표는 도형 도구로만) | 오인식 체감 | 그대로, 설정에서 끌 수 있음 |
| U15 | 웹 첫 로드에 수식 글꼴 약 371 KB(gzip) 추가 | 첫 화면 시간 | 받아들임(측정 뒤 초과면 지연 적재로) |
| U16 | 손글씨 자동 인식(검색 색인용)은 설정에서 켜야 동작(기본 꺼짐), 모델(약 20 MB/언어)은 Wi-Fi에서 | 배터리·저장 공간 | 그대로 |
| U17 | PDF로 내보낼 때 수식은 300 dpi 이미지(벡터 아님) | F-15 '벡터 출력'은 필기 기준 | 그대로 |
| U18 | 실기기 도형·수식 획 표본을 시험 자료로 저장소에 넣어도 되는가(손글씨 문장은 넣지 않음) | 문턱값 회귀 시험 | 도형·수식만 넣음 |
| U19 | macOS 러너(10배 과금)로 iOS 컴파일 확인을 2차에 1~2회 해도 되는가, 저장소 공개 여부 | Actions 무료 시간 | 1회(통합 뒤), 비공개 유지 |
| U20 | 안드로이드 고정 서명 키: 시크릿 등록(키 파일 따로 보관) | 덮어 설치·노트 보존 | 시크릿 방식(조사 04 3.5 A). 등록 전에는 debug 서명 |
| U21 | 최종 앱 ID(`dev.noteapp.noteapp` 유지?) | 고정 키·App ID 등록 전에 확정해야 함 | 유지 |

### 6.3 총괄이 정할 것 (이 초안의 기본값)

| # | 질문 | 이 초안의 기본값 |
|---|---|---|
| D1 | 새 패키지 3개·`functions/`의 소유 영역 | 2.1(media → PDF, recog → LIBRARY, pencil → INFRA, functions → SYNC). 새 영역 없음 |
| D2 | 페이지 객체를 `EntityKind` 하나로, 층 규칙 L-1, '맨 앞/뒤로' 없음 | 그대로 |
| D3 | 객체 병합 단위 = 객체 단위 LWW(엔진 정보만 따로) | 그대로(단일 사용자 — 동시 편집 드묾, 텍스트 높이·내용 어긋남 방지) |
| D4 | `kNoteSchemaVersion` 유지(객체가 든 노트도 옛 앱에서 읽기 전용 아님) | 유지 |
| D5 | SYNC '모르는 종류 보류'를 실연결 전에 | 이번에 |
| D6 | M4 실연결을 2차에 넣지 않음 | 넣지 않음, 미니 라운드 |
| D7 | 손글씨 인식 결과 = 페이지당 동기화 엔티티(결정적 id `hw_<pageId>`), 색인은 기기 로컬 | 그대로 |
| D8 | 노트 복사 때 녹음 행도 새 id로 복사하고 획 연결을 옮김 | 그대로(R-6) |
| D9 | 오디오 포트를 CORE에 둠(피처 사이 연결 ① 방식) vs EDITOR 자리 + 어댑터 | CORE(같은 개념을 두 패키지가 정의하지 않게) |
| D10 | 앱 쪽 수식 서버 호출을 `package:http` 직접 구현으로(이번), `cloud_functions`는 실연결 때 | 그대로 |
| D11 | 우선순위 등급(1.5) | 그대로 |
| D12 | 간접 의존 '2주 규칙'을 pubspec 간접 고정으로 지킴 | 그대로(R9에 포함) |

---

## 7. 이 관점(기존 패키지 중심)의 자체 평가

### 7.1 장점

1. **연속성.** 7개 영역의 소유자가 그대로라, 2차 작업의 대부분이 '자기가 1차에 만든 코드를 넓히는 일'이다. CORE는 자기 sealed 계층·DB·해석기를, INK는 자기 렌더 캐시·적중 판정·벡터 내보내기를, EDITOR는 자기 입력 라우터·선택 메뉴를 고친다. 1차 계획서 3,000줄씩의 맥락을 새로 넘길 필요가 없다.
2. **렌더 경로가 하나.** 새 객체·새 펜이 모두 INK를 지나므로 화면·썸네일·PDF가 같은 층 규칙(L-1)·같은 외곽 불변식(K-1·K-6)을 지킨다. 객체마다 다른 영역이 그리면 생길 '화면과 PDF가 다름' 문제가 구조적으로 없다.
3. **계약 경계 수가 적다.** 새 공유 타입은 거의 모두 CORE 한 곳(4.2)이고, 영역 사이 새 인터페이스(X18~X36)는 1차 패턴(CORE 인터페이스, 소비자 자리 + 앱 셸 override, `*Overrides()` 함수) 세 가지만 쓴다. 새 연결 방식을 발명하지 않는다.
4. **플러그인 격리.** 플랫폼 전용 코드는 서비스 패키지 3개에만 있고 피처 패키지는 플러그인을 모른다. EDITOR·LIBRARY 위젯 시험은 1차처럼 웹·VM에서 가짜로 돈다. `native_only_imports`·R16으로 기계적으로 지킨다.
5. **작업 트리·병합 운영이 1차와 같다.** 영역 수 7, 통합 순서·검증 기준이 1차의 확장이라 총괄 운영 비용이 늘지 않는다.
6. **실연결 전에 데이터 형식을 굳힌다.** 새 종류를 SYNC에 먼저 넣고 '모르는 종류 보류'를 만들어, 실연결 미니 라운드가 형식 변경 없이 연결 작업만 하게 된다.

### 7.2 단점

1. **큰 세 영역이 임계 경로에 몰린다.** 객체 기능 하나(텍스트 상자)가 CORE → INK → EDITOR → PDF 네 영역을 거친다. 기능 단위로 영역을 나누는 관점(예: '객체'·'녹음'·'인식' 영역)보다 한 기능이 끝나기까지 손이 많이 바뀌고, 기반 단계 계약이 틀리면 여러 영역이 같이 고쳐야 한다.
2. **주제가 어색한 배치.** PDF 영역이 오디오를, LIBRARY 영역이 손글씨·수식 인식과 그 UI를, SYNC 영역이 서버 함수를 맡는다. 짐 균형과 '파일 입출력', '첫 소비자', 'Firebase 백엔드'라는 연결 고리로 정했지만, 그 영역에 새 지식(오디오 세션·ML Kit·TypeScript)이 필요하다.
3. **UX가 영역 경계에서 갈린다.** 에디터 안에서 보이는 녹음 패널(media)과 변환 창·수식 패드(recog)를 EDITOR가 아닌 영역이 만든다. 1차 PDF 흐름(가져오기·내보내기 창)과 같은 방식이지만, 에디터 화면과 시각·상호작용이 어긋날 위험이 있고 앱 셸 변환 코드가 늘어난다.
4. **CORE가 '공유 타입 허브'로 커진다.** 문서 모델 패키지에 오디오 포트·이미지 가져오기 타입까지 들어간다. 순수 Dart라 규칙 위반은 아니지만 응집도가 낮아진다.
5. **INK 의존이 무거워진다.** 수식 렌더 때문에 `ink_engine`이 `flutter_math_fork`(갱신 멈춤)와 그 간접 의존(`flutter_svg` 계열, `xml` 하향)을 진다. INK를 쓰는 모든 패키지·시험이 그 무게를 함께 진다.
6. **M6·M7이 EDITOR 일정에 묶인다.** 녹음·인식 서비스는 독립적으로 만들어지지만, 사용자가 볼 수 있는 흐름(펜 다운 시점 기록, 선택 메뉴 연결, 재생 강조)은 EDITOR 작업이 끝나야 완성된다.

### 7.3 완화

- (단점 1) 기반 단계에서 객체 사슬 전체를 '단순 동작'으로 먼저 이어 둔다(R2-B2·B3). 통합 순서를 데이터 → 렌더 → 소비자로 둬 실패 원인을 좁힌다(5.3). P-A/P-B 등급으로 자를 곳을 미리 정한다(1.5).
- (단점 2) 조사 02·03·04가 패키지 구조·코드 뼈대·버전·실험까지 적어 두었고, 맡는 영역은 1차에서 짐이 가장 가벼웠던 곳들이다(2.3).
- (단점 3) 자리 콜백에 에디터 문맥을 그대로 넘기고(`execute`, `clearSelection`, `selectObject`), 변환 창·패널은 `Theme.of(context).colorScheme`만 쓴다(1차 7.4.11). V5 스모크가 자리마다 한 번씩 연다. B 체크리스트 B-8·B-10·B-11에서 일관성을 사람이 본다.
- (단점 4) 오디오 포트는 `lib/src/media/` 한 디렉터리에 모으고 저장·모델 코드와 섞지 않는다. 다음 라운드에 공유 포트가 더 늘면 `note_ports` 같은 순수 Dart 패키지로 떼는 것을 검토한다.
- (단점 5) 간접 고정 + 포크 준비. 수식 렌더를 INK 밖(예: recog)으로 빼면 INK가 수식을 그릴 수 없어 렌더 경로가 둘이 되므로 받아들인다.
- (단점 6) EDITOR 작업 순서에서 녹음 연동(펜 다운 메타·강조)과 자리 연결을 앞쪽에 둔다(작업량 2.5, 자리만 열면 media·recog가 자기 화면을 붙일 수 있음).

### 7.4 이 관점이 맞는 경우 / 다른 관점과 비교할 지표

- 맞는 경우: 1차 코드 품질이 좋고 영역 소유자가 그대로 이어서 일하는 경우, 화면·PDF 일관성을 가장 중요하게 볼 때, 총괄의 운영 부담을 늘리고 싶지 않을 때.
- 맞지 않는 경우: M6·M7을 M5와 독립적으로 빨리 실사용하고 싶을 때(기능 중심 영역이 유리), 큰 세 영역의 일정 위험을 받아들이기 어려울 때.
- 비교 지표(총괄이 초안 B와 나란히 볼 것): ① 영역 수·작업 트리 수 ② 기반 단계 계약 파일 수와 '깨짐' 변경 수 ③ 임계 경로 길이(객체 기능이 지나는 영역 수) ④ 가장 큰 영역의 작업량 ⑤ 피처 패키지가 플러그인을 직접 의존하는지 ⑥ 앱 셸 변환 코드 양 ⑦ 1차 계획서·코드 재사용 정도.

---

## 부록 A. 조사 권장안 반영표

| 조사 | 권장 | 이 초안 |
|---|---|---|
| 01 R1 | 요소는 `EntityKind` 하나 + 테이블 하나, 모르는 `type` 보존 | 채택(`pageObject`, `UnknownObject`) |
| 01 R2 | 실연결 전에 SYNC '모르는 종류 보류' | 채택(S-13) |
| 01 R3 | INK가 모든 요소 렌더·적중·선택, 층(이미지 아래 등), 정렬 기능 없음 | 채택 + 층 표 확정(L-1: 텍스트·수식은 잉크 위 annotation 층, 테이프는 cover 층) |
| 01 R4 | 재생 강조는 overlay 층 API | 채택(`setPlaybackFocus`, K-7) |
| 01 R5 | 녹음 시점 = 녹음기 위치, 녹음 행은 정지 뒤, 녹음 중 임시 저장(CORE 자리), 복제 획은 연결 유지 | 채택(R-1~R-7, `RecordingDraftStore`) |
| 01 R6 | 오디오·인식 플러그인은 새 패키지, 소비자 쪽 자리로 연결 | 채택. 단, 오디오 포트는 소비자 자리가 아니라 **CORE 인터페이스**(D9) |
| 01 R7 | 인식 결과는 동기화 엔티티, 색인은 기기별 FTS5 | 채택(바이그램은 조사 03 방식으로 변경) |
| 01 R8 | S펜은 이번 구현·확인, Pencil은 매핑·가짜까지 | 채택 + Swift 플러그인 작성·컴파일 확인(P-B·P-C) |
| 01 R9 | `GestureSettings`는 bool 유지 + 동작 매핑 추가 | 채택 |
| 01 R10 | 네이티브 저장을 선행 작업으로 | 채택(공통-1) |
| 01 R11 | 한글 글꼴 1종 번들, PDF 텍스트 객체 + 래스터 대체, 수식은 래스터 | 채택(지연 적재로 웹 첫 로드에서 뺌) |
| 01 R12 | 이미지 배경 빌더는 INK 기본 목록, `pdfIoOverrides`가 앞에 PDF | 채택(`defaultPageBackgroundBuilders`) |
| 02 12.1 | `record`·`just_audio`·`audio_session`·`flutter_foreground_task`, `permission_handler` 제외 | 채택 |
| 02 12.2 | 오디오 모듈 새 패키지, EDITOR는 포트만 | 채택(`media_io`, 포트는 CORE) |
| 02 12.3~12.4 | AAC-LC 모노 64 kbps, 웹은 지원 MIME 선택, 녹음 시계·보정 안 함·pre-roll 1.5초 | 채택 |
| 02 12.5 | Stylus 이벤트 확장(선호 동작·스퀴즈 단계·호버 자세·능력) | 채택 |
| 02 12.6 | 웹 조각 IndexedDB 저장은 선택 | P-B로 채택(iPad 웹이 주 기기라 중요도 올림) |
| 02 9.3 | 작은 iOS 플러그인 직접 작성, 앱 셸이 어댑터 | 채택(`pencil_bridge`, INFRA) |
| 03 R1·R2 | ML Kit 0.16.1, 첫 작업은 APK 실기기 판정, `ko` 단독 + 언어 바꾸기 | 채택(A-4) |
| 03 R3 | 인식 단위 = 줄, 줄 나누기·낡음·위치는 순수 Dart | 채택(`groupIntoLines`, `sourceRevOf`) |
| 03 R4 | 자동 도형 보정은 INK 순수 Dart 기하 판정 | **변형**: 발동·미리보기는 INK, 판정 알고리즘은 포트(`InkShapeFitter`) 뒤 recog — INK 짐 덜기 + 교체 가능 |
| 03 R5 | 웹은 인식하지 않고 결과로 검색 | 채택 |
| 03 R6·R7 | 수식 엔진은 서버 함수 뒤 교체형, 이번엔 어댑터·가짜·객체·렌더·직접 편집·함수 코드까지 | 채택 |
| 03 R8 | `search_units` + FTS5 바이그램, PDF 전역 색인 함께, 정규화 하나 | 채택(`SearchText`) |
| 03 R9 | `flutter_math_fork` `Math.tex`만, `textStyle` 명시, KaTeX 글꼴 예산 | 채택(INK `MathPreview`) |
| 04 1~7 | APK 고정 서명·`INTERNET`, `ios-compile.yml`, iOS 15.5·Podfile·Info.plist, 혼합 모드는 실연결 때, 네이티브 전용 경계, 정적 시험·요구 검사 | 채택(INFRA) |
| 04 8~9 | 서버 함수 골격(`asia-northeast3`, 로그인·소유자 목록·`defineSecret`), 앱은 포트만 | 채택(SYNC `functions/`, 앱은 `package:http`) |
| 04 11 | `permission_handler` 넣지 않음 | 채택 |
