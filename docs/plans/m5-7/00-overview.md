# 2차 라운드(M5·M6·M7) 동시 개발 영역 개요

> 상태: **2차 통합 완료(컨테이너 V1~V16 통과 — V4는 INFRA `3cdfaf5`의 C27-01 반영 뒤 `ws web-budget check` 0), 실기기 확인 대기, 계약 v2.7** (2026-11-12 — 7.9 C23-01~07·C24-01~02·C25-01~04·C26-01~04·C27-01~07, 최종 승인 2026-11-05. 통합 결과는 [00-review.md '2차 통합 결과'](00-review.md#2차-통합-결과). V4 새 한도는 `tool/web_budget.yaml`에 반영됨(INFRA `3cdfaf5`, C27-01), V14 GitHub 실행 1회는 C27-07). 그 앞: 2차 기반 단계 → 동시 개발 → 통합 — 7개 영역 계획서 01~07 모두 승인([00-review.md](00-review.md) '최종 승인' 절에 승인 요약·개발 중 주의할 점·기반 단계와 통합 순서·사용자 질문). v2.1(C21-01~35) 뒤 최종 승인에서 바뀐 곳은 본문에 `(v2.2)`로 표시했고 [7.9 변경 이력](#79-계약-변경-이력)의 C22-01~C22-09에 모두 있다. v2.0 초안에서 v2.1로 바뀐 곳은 `(v2.1)`로 표시했고 C21-01~C21-35에 있다
>
> 기준: 1차 [00-overview.md](../00-overview.md) 7장 통합 계약 v1.5(1차 통합 반영 — v1.4 대비 시그니처 변경 없음) · [00-review.md](../00-review.md) · 마스터 기획서 [PLAN.md](../../PLAN.md) F-03·F-10~F-16, 5장, 7.6, 10장 M5~M7 · 조사 [01-hooks](research/01-hooks.md) · [02-audio-stylus](research/02-audio-stylus.md) · [03-recognition](research/03-recognition.md) · [04-native](research/04-native.md) · 설계 초안 [A(기존 패키지 중심 — 바탕)](drafts/overview-A.md) · [B(기능 모듈 중심)](drafts/overview-B.md) · 채점·판정 [judgement.md](drafts/judgement.md) (A 29점 / B 21점)

이 문서를 읽는 법

- 1차 계약(v1.5 — 1차 통합에서 문구만 바뀌었고 시그니처는 v1.4와 같다)은 **그대로 유효하다.** 이 문서 7장(통합 계약 v2.2)은 그 위에 덮어쓰는 변경분만 적는다. 7장과 1차 계약이 다르면 7장이 우선한다. 1차 계약과 달라지는 곳은 **7.0 '1차 계약 대비 변경' 표**에 모두 모았다.
- 절 번호: 이 문서의 `7.x`는 2차 계약이다. 1차 계약의 절은 언제나 **'1차 7.x'**로 적는다(예: 1차 7.2.17).
- 코드 블록은 시그니처 계약이다(본문 생략). `// v1.4`는 1차 계약 그대로(v1.5에서도 같음)라는 뜻이다. 영역 계획서 4·5절은 이 장의 Dart 정의를 **그대로 복사**해 쓰고, 다르게 적지 않는다.
- [확인]·[추측] 표기는 조사 문서의 표기를 따른다. 표기가 없는 판단은 총괄의 설계 결정이다.
- 계약 변경 분류:

| 분류 | 뜻 |
|---|---|
| 추가 | 공개 진입점에 새 타입·멤버·선택 인자를 더한다. 기존 호출은 그대로 컴파일된다 |
| 깨짐 | 기존 공개 시그니처·의미가 바뀌거나, sealed/enum 값 추가·인터페이스 멤버 추가로 **다른 패키지의** 코드(시험 포함)가 컴파일되지 않을 수 있다 |
| 규칙 | Dart 시그니처는 같고 계약 문장(소유표·예산·동작 보장·검사 규칙)만 바뀐다 |

## 1. 목적

`docs/PLAN.md` 10장의 **M5 편집 강화 · M6 녹음 · M7 인식**을 1차와 같은 방식으로 여러 영역에 나눠 **동시에** 개발한다. 1차 7.8에서 미룬 항목 중 M5와 맞닿은 것(올가미 회전·색 변경 UI, 제스처 동작 변경, 이미지 페이지)과, M7과 같은 색인으로 풀리는 '라이브러리 전역 PDF 텍스트 검색'도 넣는다. 동기화 실연결(M4 앱 연결·로그인 화면)은 넣지 않는다(3.3).

바탕은 초안 A(1차 7개 영역이 자기 패키지를 넓히고, 플랫폼 전용 기능만 새 서비스 패키지 3개로 둠)이고, 초안 B에서 11가지 요소(웹 녹음 조각 저장 필수, 기능 스위치, 외부 전송 동의 게이트, INK 미리보기 객체 등)를 옮겼다. 근거는 [judgement.md](drafts/judgement.md).

진행 순서(1차와 같음):

1. **전제**: 1차 통합(1차 7.7 V1~V6)이 끝나 `main`이 1차 결과 전체를 담고 있다. 2차 작업 트리는 그 `main`에서 만든다(2.5). (v2.1) 1차 V7(iPad 확인)은 Firebase Hosting이 생기면 2차와 병행한다(3.7, D21).
2. 영역마다 상세 계획서 `docs/plans/m5-7/NN-<id>.md` 작성(6장 목차).
3. 총괄이 모든 계획서를 읽고 피드백(`m5-7/00-review.md`) → 이 문서 7장을 '통합 계약 v2.1'로 확정(2026-11-05 완료) → 영역 수정 → 승인((v2.2) 최종 승인 2026-11-05 완료 — 계약 v2.2, 00-review '최종 승인').
4. 기반 단계(7.6): 새 패키지 골격·계약 코드·자리표시·'단순하지만 동작하는 구현'을 먼저 `main`에 넣는다.
5. 영역별 작업 트리에서 동시 개발(브랜치 `area2/<id>`).
6. 통합(7.7) → 컨테이너 검증(V1~V16) → 미리보기 배포 → 실기기 확인(7.8) → PLAN.md 체크리스트 갱신(총괄).

## 2. 영역 지도

### 2.1 영역 표

| ID | 영역 | 계획서 | 소유 경로 (겹침 없음) | 이번 범위 (맡는 기능) | 1차와의 관계 |
|---|---|---|---|---|---|
| INFRA | 기반 · 빌드 · 배포 · 플랫폼 설정 | `01-infra.md` | 루트 `pubspec.yaml`·`pubspec.lock`·`analysis_options.yaml`·`.gitignore`·`.gitattributes`, `app/`, `.github/`, `tool/`, `docs/guides/`, **`packages/pencil_bridge/`(새)** | 새 연결(모듈·override·라우팅), 네이티브 저장 경로, 안드로이드 매니페스트·고정 서명·`android.yml`, iOS 15.5·Podfile·Info.plist·`ios-compile.yml`, `ws` 규칙·네이티브 설정 정적 시험·플러그인 요구 검사, 웹 예산, **Apple Pencil 플러그인**(M5-9), 실기기 안내서 | 1차 INFRA 그대로 + 플랫폼 플러그인 하나. 네이티브 설정(Info.plist·매니페스트)과 iOS CI를 이미 소유하므로 iOS 전용 플러그인도 같은 손에 둔다 |
| CORE | 문서 모델 · 저장 · 되돌리기 · 색인 | `02-core.md` | `packages/note_core/` | 페이지 객체 4종 모델·JSON·DB v2·명령, 녹음 저장소·초안 저장소·오디오 포트, 손글씨 인식 결과 엔티티, 검색 색인(FTS5), 이미지 가져오기 타입, 네이티브 저장(파일 DB·파일 블롭) | 1차 CORE 그대로. `PageElement` sealed 계층·DB·명령 해석기를 만든 손이 확장한다 |
| INK | 필기 엔진 · 페이지 렌더 | `03-ink.md` | `packages/ink_engine/`(새 `assets/fonts/` 포함) | 추가 펜 5종 렌더, 페이지 객체 렌더·적중·선택·변형, 자동 도형 보정 발동·미리보기(판정은 포트), 이미지 배경 빌더·이미지 캐시, 썸네일·벡터 내보내기 v2, 수식 렌더(`flutter_math_fork`), 텍스트 글꼴, 재생 강조·테이프·레이저 | 1차 INK 그대로. '화면·썸네일·PDF가 같은 렌더 경로'를 한 영역이 계속 지킨다 |
| EDITOR | 에디터 화면 | `04-editor.md` | `packages/feature_editor/` | 올가미 고급 UI·클립보드, 텍스트 도구(IME), 도형 도구·핸들, 이미지 삽입·이미지 페이지 흐름, 제스처 매핑·설정·펜 버튼·Pencil 이벤트 소비, 새 펜 선택기·고급 설정, 녹음 연동(펜 다운 시점·재생 강조·탭 재생), 확장 자리(선택 메뉴·삽입 메뉴·녹음 패널·이미지 가져오기) | 1차 EDITOR 그대로. 무거운 UI 흐름 두 개(녹음 패널, 인식 변환 창)는 자리만 두고 새 패키지 소유 영역에 넘긴다(2.4) |
| LIBRARY | 라이브러리 화면 · **인식** | `05-library.md` | `packages/feature_library/`, **`packages/ink_recognition/`(새)** | 검색 결과 묶음(손글씨·PDF·텍스트 상자·수식)·페이지 위치로 열기, **인식 패키지 전부**: 손글씨 엔진 포트·ML Kit 어댑터·줄 나누기·색인기, 수식 엔진 포트·서버 호출 클라이언트, 변환 UI(텍스트 변환 창·수식 입력 패드·LaTeX 편집), 도형 판정기, 인식 설정 화면 | 1차 LIBRARY + 인식. 1차에서 검색 화면을 만든 영역이 M7의 첫 소비자(손글씨 검색)이고, 1차 짐이 가장 가벼웠다 |
| PDF | PDF · **미디어** 입출력 | `06-pdf.md` | `packages/pdf_io/`, **`packages/media_io/`(새)** | PDF 합성에 이미지·텍스트 객체, 페이지 객체·이미지 페이지 내보내기, 한글 글꼴 넣기, 수식 래스터, 라이브러리 전역 PDF 텍스트 색인기 / **미디어 패키지 전부**: 녹음·재생 서비스, 녹음 시계, 웹 녹음 대체 동작·조각 저장, 안드로이드 포그라운드 서비스·오디오 세션, 이미지 가져오기·정규화, 녹음 패널 UI | 1차 PDF + 미디어. '파일(에셋)을 들여오고 내보내는' 일, 웹 JS 상호운용·네이티브 조건부 import 경험이 그대로 쓰인다 |
| SYNC | 동기화 · **서버 함수** | `07-sync.md` | `packages/sync_engine/`, **`functions/`(새, 루트, Node — 워크스페이스 멤버 아님)** | 새 엔티티 종류 매핑(필드 단위·범위·게이트·영구 삭제 보호·페이지 되살림), 모르는 종류 기록 보류, 시나리오 시험, **서버 함수**(수식 인식 `recognizeMath`·키 보호·에뮬레이터 시험), 수식 엔진 비교 도구 | 1차 SYNC + Firebase 백엔드 코드. 이미 `packages/sync_engine/firebase/`(규칙 파일)·에뮬레이터를 다루는 영역이다 |

- 총괄은 1차와 같이 `docs/plans/`(개요·검토·계획서 승인)와 통합 병합을 맡는다. 각 영역은 자기 작업 트리의 `docs/plans/progress/<id>.md`에 진행 기록을 남긴다(1차와 같음).
- 소유 경로 밖 파일이 필요하면(예: SYNC가 `app/firebase.json`의 `functions` 항목, `.github/workflows/functions.yml`) 1차처럼 '변경 요청'으로 INFRA에 남긴다. 기반 단계에서 INFRA가 미리 넣어 둔다(7.6 R2-B1).

### 2.2 소유 경로 겹침 확인

저장소의 모든 경로는 아래 표의 **한 행에만** 속한다(한 패키지 = 한 영역, 한 영역이 패키지 둘을 가질 수 있음). 표의 경로 접두사는 서로 포함하지 않는다.

| 경로 | 소유 | 비고 |
|---|---|---|
| 루트 `pubspec.yaml`·`pubspec.lock`·`analysis_options.yaml`·`.gitignore`·`.gitattributes` | INFRA | lock은 생성 파일 — 병합 충돌 시 INFRA가 재생성(1차 7.4.1) |
| `app/`(`app/firebase.json` 포함), `.github/`(`functions` 잡 포함), `tool/`, `docs/guides/` | INFRA | SYNC의 `functions` 관련 설정은 '변경 요청'으로 INFRA가 넣는다(R2-B1) |
| `packages/pencil_bridge/` (새) | INFRA | iOS Swift 소스 포함 |
| `packages/note_core/` | CORE | |
| `packages/ink_engine/` (`assets/fonts/` 새로 포함) | INK | |
| `packages/feature_editor/` | EDITOR | |
| `packages/feature_library/`, `packages/ink_recognition/` (새) | LIBRARY | |
| `packages/pdf_io/`, `packages/media_io/` (새) | PDF | |
| `packages/sync_engine/`, `functions/` (새, 루트, Node — 워크스페이스 멤버 아님) | SYNC | `functions/`는 다른 경로 아래에 있지 않다(`app/` 밖) |
| `docs/plans/`(`m5-7/` 포함, `progress/` 제외), `docs/PLAN.md` | 총괄 | 계획서는 각 영역이 계획 단계에 쓰고 총괄이 승인 |
| `docs/plans/progress/<id>.md` | 각 영역(자기 파일만) | 2차 기록은 같은 파일에 '2차' 절을 이어 쓴다 |

확인 결과(2026-11-05): 새 경로 4개(`pencil_bridge`·`ink_recognition`·`media_io`·`functions/`)는 1차 소유 경로 어느 것의 하위도 아니고, 서로 하위도 아니다. 1차 작업 트리 7개에 이 이름의 경로가 없다 [확인 — `ls /home/user/wt/*/packages`, `ls /home/user/wt/*/functions`]. 공용 파일(`pubspec.lock`, `tool/workspace_rules.yaml`, `app/lib/` 연결 코드)은 1차처럼 INFRA만 고친다.

### 2.3 새 패키지를 기존 영역에 두는 기준

1. **한 패키지 = 한 영역.** 새 패키지는 하나의 기존 영역이 통째로 소유한다. 한 영역이 패키지 둘을 가질 수 있다(1차 INFRA가 `app/`·`tool/`·`.github/`를 함께 가진 것과 같다).
2. **주제가 가깝고 짐이 가벼운 영역.** 1차 계획서 크기와 2차 추정 작업량(2.4)으로 고른다.
   - `ink_recognition` → LIBRARY: M7의 첫 소비자가 라이브러리 검색이고, 인식 결과를 화면에 보이는 흐름(후보 고르기·직접 편집)이 LIBRARY가 1차에 만든 검색·목록 UI와 성격이 같다.
   - `media_io` → PDF: 에셋 바이트를 들여오고(PDF 가져오기) 내보내는(PDF 내보내기) 영역이고, `*_browser.dart`(JS 확장)·`*_native.dart`(FFI) 분리와 웹 정적 자산을 이미 다뤘다. 이미지 정규화(JPEG/PNG)는 PDF 이미지 객체 입력과 같은 형식이라 한 손에 두면 맞추기 쉽다.
   - `pencil_bridge` → INFRA: iOS 전용 Swift 코드이고 확인 수단이 INFRA의 macOS CI뿐이다. Info.plist·배포 대상도 INFRA 소유다.
   - `functions/` → SYNC: Firebase 백엔드(규칙·에뮬레이터)를 이미 소유하고, 2차 SYNC 본업(사전 정비)이 가장 가볍다.
3. **피처 패키지는 플러그인 패키지에 의존하지 않는다.** EDITOR·LIBRARY는 `media_io`·`ink_recognition`·`pencil_bridge`를 import하지 않는다. 연결은 1차 7.1 규칙 1 그대로 ① CORE에 둔 인터페이스(오디오 포트, 7.2.4) 또는 ② 소비하는 쪽 자리 + 앱 셸 override(선택 메뉴·삽입 메뉴·녹음 패널·이미지 가져오기, 7.2.10)로만 한다. 그래서 EDITOR 위젯 시험은 웹·VM 모두 플러그인 없이 돈다.

### 2.4 작업량 균형

단위는 '1차 계획서 기준 작업 하나(T) ≈ 1'의 상대 추정이다. 각 영역 계획서가 8장 작업 분해로 다시 잰다.

| 영역 | 주요 작업 (추정 단위) | 합계 | 조정 내역 |
|---|---|---|---|
| CORE | 객체 모델·JSON·불변식 2, DB v2·마이그레이션·행 변환·outbox 힌트 3, 명령·해석기·세션·초안 2, 복사·휴지통·백업·가짜 저장소 2, 녹음 저장소·초안 저장소·오디오 포트·가짜 2.5, 손글씨 결과 엔티티·저장소 1, 검색 색인(FTS5 바이그램·작성기·질의·정규화 통합) 3, 네이티브 저장 1.5 | **17** | 오디오·인식 **구현**은 넘기고 계약 타입·저장만 맡는다 |
| INK | 추가 펜 5종 4, 객체 렌더·캐시·층 3, 객체 적중·올가미·선택·숨김 2, 도형 보정 발동·미리보기 1, 이미지 배경·이미지 캐시·썸네일 2, 벡터 내보내기 v2·글꼴·수식 래스터 2.5, 재생 강조·테이프·레이저 상태 1 | **15.5** | 도형 **판정 알고리즘**(시제품 279줄 기반, 합성 1,400개 시험)은 포트(`InkShapeFitter`)로 떼어 LIBRARY(`ink_recognition`)로 넘긴다 |
| EDITOR | 올가미 고급·클립보드 2.5, 텍스트 도구·IME 3, 도형 도구·핸들·꼭짓점 3, 이미지 삽입·이미지 페이지 1.5, 제스처 매핑·설정·펜 버튼·Pencil 이벤트 3, 새 펜 선택기·테이프·레이저 상호작용 1.5, 녹음 연동(펜 다운 시점·강조·탭 재생) 2, 확장 자리·위치로 열기 0.5 | **17** | 녹음 패널 UI(→ PDF `media_io`), 인식 변환 창·수식 입력 패드(→ LIBRARY `ink_recognition`)를 자리로 넘겨 약 5.5를 덜었다 |
| LIBRARY | 검색 묶음·위치로 열기·설정 연결 2.5, 인식 포트·가짜·줄 나누기 2, ML Kit 어댑터·모델 관리 2, 색인기 2, 변환 UI 3, 도형 판정기 1.5, 서버 수식 클라이언트·인식 설정 화면 1 | **14** | |
| PDF | 합성 이미지·텍스트 명령(웹 JS + FFI) 3, 객체 벡터화·층·점선 1.5, 이미지 페이지·수식 래스터 1, 한글 글꼴 넣기 1, 전역 PDF 텍스트 색인기 1.5 / 녹음 서비스(웹 자체 녹음기·1초 조각 저장·복구 포함) 3.5, 재생 서비스·녹음 시계 1.5, 포그라운드 서비스·오디오 세션 1, 이미지 가져오기·정규화·웹 클립보드 1.5, 녹음 패널 UI 1.5 | **17** | 웹 자체 녹음기를 P-A로 올려 +0.5(D13) |
| SYNC | 새 종류 매핑 3, 모르는 종류 보류 2, 시나리오·계약 시험 2, 서버 함수 골격·엔진 포트·보호·에뮬레이터 시험 3, 수식 엔진 비교 도구 1 | **11** | 실연결 미니 라운드(1.4)의 주 담당이 될 여유를 남긴다 |
| INFRA | 앱 연결 2, 네이티브 저장 경로 0.5, 안드로이드 설정·서명·워크플로 1.5, iOS 설정·`ios-compile.yml` 2, `ws` 규칙·정적 시험·요구 검사 2, 웹 예산 0.5, `pencil_bridge` 2.5, 안내서·체크리스트 1.5, 기능 스위치 `AppFeatures` 0.5 | **13** | 기능 스위치(D14) +0.5 |

- 범위: 11~17. 1차처럼 CORE·INK·EDITOR가 크지만, 셋 다 2차 작업의 절반 이상이 '자기 1차 코드를 넓히는 일'이라 처음 보는 코드가 적다.
- 세 큰 영역이 임계 경로(4.4)에 있으므로, 기반 단계에서 계약 타입과 **단순하지만 동작하는 구현**을 먼저 넣어 나머지 영역이 기다리지 않게 한다(7.6).

### 2.5 작업 트리 · 브랜치 · 바탕 코드

| ID | 2차 작업 트리 (브랜치) | 바탕 코드 (계획서 작성 때 읽기 전용으로 볼 곳) | 이어받는 1차 계획서 |
|---|---|---|---|
| INFRA | `/home/user/wt2/infra` (`area2/infra`) | `/home/user/wt/infra` | `/home/user/wt/infra/docs/plans/01-infra.md` |
| CORE | `/home/user/wt2/core` (`area2/core`) | `/home/user/wt/core` | `/home/user/wt/core/docs/plans/02-core.md` |
| INK | `/home/user/wt2/ink` (`area2/ink`) | `/home/user/wt/ink` | `/home/user/wt/ink/docs/plans/03-ink.md` |
| EDITOR | `/home/user/wt2/editor` (`area2/editor`) | `/home/user/wt/editor` | `/home/user/wt/editor/docs/plans/04-editor.md` |
| LIBRARY | `/home/user/wt2/library` (`area2/library`) | `/home/user/wt/library` | `/home/user/wt/library/docs/plans/05-library.md` |
| PDF | `/home/user/wt2/pdf` (`area2/pdf`) | `/home/user/wt/pdf` | `/home/user/wt/pdf/docs/plans/06-pdf.md` |
| SYNC | `/home/user/wt2/sync` (`area2/sync`) | `/home/user/wt/sync` | `/home/user/wt/sync/docs/plans/07-sync.md` |

- 2차 작업 트리는 1차 통합 뒤의 `main`에서 만든다(1차 `area/<id>`와 섞이지 않게 `area2/<id>`). 계획서 작성 단계에는 1차 통합 전이므로 각 영역의 1차 작업 트리를 바탕 코드로 읽는다(읽기 전용). 계획서의 '파일 경로·줄 번호' 인용은 1차 작업 트리 기준으로 적고, 통합 뒤 달라진 곳은 기반 단계 시작 때 고친다.
- **(v2.1) 바탕 코드는 1차 통합 결과다** — `/home/user/noteapp`(브랜치 `claude/note-app-planning-bk29xb`, 2026-11-05 HEAD `18c5ae5`, 1차 계약 v1.5). (v2.2, C22-08) 최종 승인 때 HEAD는 **`b6c9d0a`**다 — `18c5ae5` 뒤 8커밋은 INK `lasso_polygon.dart`·`lasso_options.dart` 퇴화 판정 문구와 시험(`446518e` — 동작·API 같음), EDITOR·INK·INFRA 문서·진행 기록, INFRA CI의 기본 브랜치 비교·`FULL_RUN`(`bb1bc60` — 01-infra 3.0)이다. 계획서가 `18c5ae5`로 적은 바탕은 이 HEAD로 읽는다(INFRA·INK 밖 소유 경로의 코드 변화 없음). 위 표의 1차 작업 트리에는 통합 커밋이 없다: INFRA `52de08c`(lock 정책·ink lab 멤버·R14)·`d5938c6`(개발 브랜치 APK)·`5adf710`(`ws test` 시간 제한·재시도·신호)·`3cf0b84`(V5·V6·라우팅 수정), CORE `c4966ce`, INK `1689f7e`, PDF `9305235`(`integration/real_wiring_test.dart`), SYNC `22abbea`. 계획서가 '전체'라고 적은 설정 블록(루트 `pubspec.yaml`, `workspace_rules.yaml`), 시험 수, CI 시간·웹 크기 예산의 기준값은 **이번 계획서 수정에서** 통합 HEAD 기준으로 고친다. 나머지 줄 번호 인용은 기반 단계 시작 때 고친다.
- 계획 작업 트리는 `/home/user/wt/plan57`(`area/plan57`). 2차 계획서는 승인 뒤 `main`의 `docs/plans/m5-7/`로 들어간다.

## 3. 범위 결정

### 3.1 기능별 범위

표의 '웹'은 iPad Safari(홈 화면 앱 포함), 'APK'는 안드로이드 release APK, 'TF'는 Apple 유료 계정 가입 뒤 TestFlight다. '실기기 확인'은 그 기능의 완료 판정을 사람 손으로 하는 첫 시점이다.

| # | 기능 (PLAN) | 이번 범위 | 웹 | 네이티브 전용 부분 | 실기기 확인 | 이후로 미룸 |
|---|---|---|---|---|---|---|
| M5-1 | 올가미 고급: 회전 핸들(15° 맞춤), 색 변경, 잘라내기, 붙여넣기, 획과 객체를 함께 선택 (PLAN 5.1) | 전부 | ✔ | — | 웹(통합 직후) | — |
| M5-2 | 텍스트 상자: 키보드 입력, 글자 크기·색·굵게·정렬, 이동·크기·회전 (PLAN 5.1) | 전부(서식은 상자 단위, 글자 단위 서식 없음) | ✔ (한글 IME 조합은 실기기 확인 항목) | — | 웹 | 글자 단위 서식, 목록·표 |
| M5-3 | 이미지 삽입: 사진·카메라·파일·(웹) 클립보드 붙여넣기, 이동·크기·회전 (PLAN 5.1) | 전부 | ✔ (`navigator.clipboard.read` 지원 시 붙여넣기) | 네이티브 클립보드 이미지 붙여넣기는 이후 | 웹, APK | 자르기(crop), 네이티브 클립보드 |
| M5-4 | 이미지 페이지 (F-13, 1차 7.8 이후 항목) | 전부: 페이지 추가 시트 '이미지', 화면·썸네일·PDF 내보내기 | ✔ | — | 웹 | — |
| M5-5 | 도형 도구: 직선·화살표·사각형·원/타원·삼각형·다각형·별, 테두리 색·굵기·선 스타일·채우기, 크기·회전·꼭짓점 편집 (F-11) | 전부 | ✔ | — | 웹 | 그리드 스냅·자(F-11 P1) |
| M5-6 | 자동 도형 보정: 그리다 펜을 멈추면(500 ms) 반듯한 도형으로 (F-11) | 직선·원·타원·삼각형·사각형·다각형 | ✔ | — | 웹(문턱값을 실제 획으로 다시 맞춤) | 별·화살표 자동 보정 |
| M5-7 | 제스처 사용자 지정: 두·세 손가락 탭, 손가락 길게 누르기, 펜 버튼, Pencil 더블탭·스퀴즈의 동작 변경·끄기 (F-12) | 전부(드래그·핀치·펜 전용 모드 스크롤은 고정) | ✔ | Pencil 항목은 네이티브에서만 보임 | 웹 | — |
| M5-8 | S펜 측면 버튼 — 누른 채 쓰면 임시 지우개 (F-12) | 전부 | △ 안드로이드 Chrome(접촉 비트 판정) | 플러그인 불필요(Flutter가 버튼 비트를 줌) | APK(S펜 기기가 있을 때) | — |
| M5-9 | Apple Pencil 더블탭·스퀴즈·배럴 롤·호버 높이 (F-12, F-03) | Dart 쪽 동작 매핑·설정 + iOS 플러그인(Swift) 작성 + macOS CI 컴파일 확인 | ✘ (웹 API 없음 — 항목 숨김) | 전부 | **TF 뒤** | — |
| M5-10 | 붓펜·캘리그래피·점선 (F-03 P1) | 전부 | ✔ (웹 캘리그래피는 고정 펜촉 각 — 웹은 방위각이 항상 0) | 배럴 롤로 펜촉 각 돌리기 | 웹, TF 뒤(롤) | — |
| M5-11 | 레이저 포인터 — 잠시 뒤 사라짐, 저장 안 함 (F-03, E-3) | 전부 | ✔ | — | 웹 | 외부 모니터 발표 모드(PLAN 5.2) |
| M5-12 | 암기 테이프 — 가렸다가 탭하면 보임 (F-03, PLAN 5.2) | 전부(드러냄 상태는 저장 안 함) | ✔ | — | 웹 | 드러냄 상태 저장·학습 기록 |
| M6-1 | 녹음 시작·일시정지·정지, 노트당 여러 녹음, 이름·삭제, 녹음 동의 안내 (F-16) | 전부 | ✔ 앞에 있을 때(Safari는 AAC/mp4) | — | 웹 | — |
| M6-2 | 백그라운드 녹음 (F-16) | 네이티브 코드·설정 전부(안드로이드 포그라운드 서비스, iOS `UIBackgroundModes: audio`) + 웹 대체 동작(가려지면 자동 일시정지·화면 꺼짐 방지) | ✘ (대체 동작만) | 전부 | APK, **TF 뒤**(iOS) | — |
| M6-3 | 재생 바: 0.5~2배속, 10초 앞뒤, 탐색, 녹음 목록, 용량 표시 (F-16) | 전부 | ✔ | — | 웹 | 잠금 화면 재생 제어 |
| M6-4 | 획별 녹음 시점 → 재생 시 필기 강조, 필기 탭 → 그 시점부터 재생 (F-16) | 전부 | ✔ | — | 웹, APK(시계 오차 측정) | 시계 보정 필드(실측 뒤 판단) |
| M6-5 | 녹음 끊김 대비 — 녹음 중 조각을 임시 저장해 탭이 닫혀도 복구 | 저장소 API(CORE) 전부 + 웹 자체 녹음기(MediaRecorder, 1초 조각 → `RecordingDraftStore`) + 다음 실행 때 복구 안내 — **P-A**(D13) | ✔ | — | 웹(탭 닫기·새로 고침 뒤 복구) | — |
| M6-6 | 녹음 동기화 (F-16 '압축 후 동기화') | 에셋·`Recording` 동기화 경로는 1차에 있음 — 실연결 뒤 동작 | — | — | 실연결 뒤 | 실연결(3.3) |
| M7-1 | 손글씨 → 텍스트: 올가미 선택 → 후보·직접 편집 → 텍스트 상자로 바꾸기 / 복사 (F-10) | 엔진 교체 구조 + ML Kit 어댑터 + 변환 UI 전부 | ✘ (메뉴는 보이되 '이 기기에서는 쓸 수 없음' 안내) | ML Kit 인식 | **APK가 첫 판정**, iPad는 TF 뒤 | 웹 인식(서버 경유 OCR) |
| M7-2 | 손글씨 검색 색인 (PLAN 5.2) | 색인 테이블·질의·결과 UI·색인기 전부 | 검색 ✔ / 손글씨 색인 생성 ✘ (동기화된 인식 결과로만 — 실연결 뒤) | 손글씨 인식 | APK | — |
| M7-3 | 라이브러리 전역 PDF 텍스트 검색 (1차 7.8 이후 항목) | 전부(M7-2와 같은 테이블) | ✔ | — | 웹 | — |
| M7-4 | 텍스트 상자·수식 내용 검색 | 전부(같은 테이블) | ✔ | — | 웹 | — |
| M7-5 | 수식 객체: LaTeX 직접 입력·편집, 렌더, 이동·크기·색, LaTeX 복사, PDF 출력 (F-14) | 전부(PDF는 래스터 300 dpi) | ✔ | — | 웹 | PDF 벡터 수식 |
| M7-6 | 수식 인식 엔진 비교 구조 + 손글씨 수식 → LaTeX (F-14) | 앱 쪽 엔진 포트·가짜·서버 호출 클라이언트, 서버 함수 코드(에뮬레이터 시험까지), 수식 입력 패드(멈춤 1초 뒤 미리보기), 엔진 비교 도구 | ✔ (엔진 연결 뒤) | — | **Firebase(Blaze)·로그인·엔진 계정 생긴 뒤** | 실제 엔진 호출·비교 실험 실행 |
| 공통-1 | 네이티브 저장(파일 DB·파일 에셋 블롭) — APK·네이티브 실사용의 선행 조건 | 전부 | — | 전부 | APK | — |
| 공통-2 | 동기화 실연결(M4 앱 연결·로그인 화면) | **넣지 않는다**(3.3). SYNC 사전 정비(새 엔티티 종류·모르는 종류 보류)는 넣는다 | — | — | 실연결 미니 라운드 | 실연결 |

### 3.2 1차 7.8에서 미룬 항목

| 1차 7.8 항목 | 1차 결정 | 2차 처리 |
|---|---|---|
| 올가미 회전·색 변경 계산 | INK API만, UI는 M5 | **이번**: EDITOR 회전 핸들·색 변경·잘라내기, 객체까지 함께 선택(M5-1) |
| 제스처 켜기/끄기 | 탭 3종 켜기/끄기만 | **이번**: 동작 매핑(M5-7). 1차 bool 키는 읽기 호환으로 남긴다(7.2.10) |
| 다른 노트 페이지 복사, 이미지 페이지 (F-13) | 이후 | 이미지 페이지는 **이번**(M5-4). 다른 노트 페이지 복사는 **이후**(노트·페이지 고르기 UI가 필요하고 M5와 무관). 단, `PageDraft`가 객체까지 복사하므로(7.2.3) 나중에 UI만 더하면 된다 |
| 라이브러리 전역 PDF 텍스트 검색·색인 | 이후 | **이번**: 손글씨 색인과 같은 `search_units` + FTS5 테이블(M7-3, 7.2.5) |
| 동기화 실연결 | M4(Firebase 프로젝트 생성 후) | **이후**(3.3). 새 엔티티 종류는 실연결 **전에** 코덱·병합에 넣는다 |
| 다중 탭 리더 선출, tombstone 정리, 고아 에셋 GC | 이후 | **이후** 유지. '녹음만 따로 삭제'는 소프트 삭제까지(바이트 회수는 GC와 함께 — 9 U13) |
| 백업 내보내기 | 1차 권장 작업 | 새 엔티티(페이지 객체·손글씨 결과·녹음 이름)를 백업 JSON에 포함한다(CORE). 색인·녹음 초안은 넣지 않는다 |

### 3.3 동기화 실연결(M4)을 이번 라운드에 넣지 않는다

판단 근거:

1. Firebase 프로젝트가 없어 실연결을 **검증할 수 없다**. 컨테이너에서는 gstatic이 막혀 `firebase_core_web` 경로도 Chrome에서 시험할 수 없다(조사 04 6.5).
2. 앱에 `sync_engine`(Firebase 네이티브 SDK, SwiftPM)을 넣는 순간 ML Kit(CocoaPods 전용)과의 **iOS 혼합 모드 중복 의존 위험**이 이번 라운드로 들어온다(조사 04 요약 9). 2차는 ML Kit만 pod로 들어가는 상태에서 iOS 컴파일을 먼저 확인하는 편이 원인 분리가 쉽다.
3. 대신 **실연결 전에 해야 싼 일**은 이번에 한다: 새 엔티티 종류(`pageObject`, `handwriting`)를 코덱·병합·게이트에 넣고, 모르는 종류 기록을 청크째 버리지 않고 그 기록만 보류하도록 바꾼다(조사 01 R2, 7.2.8). 배포된 옛 앱이 없을 때 바꾸면 형식 전환 규칙이 필요 없다.
4. 서버 함수(수식 인식 키 보호)도 코드 + 에뮬레이터 시험까지만 하고 배포는 Firebase·Blaze 뒤로 둔다.
5. (v2.1 — 검토 뒤에도 유지) Firebase 프로젝트가 생겨도 이번 라운드에는 Hosting(Spark)만 연결한다(3.7). 7개 계획서 검토 결과 SYNC 사전 정비·서버 함수 에뮬레이터 시험이 실연결 전에 끝나므로, 미니 라운드에는 INFRA·SYNC의 연결 작업(로그인 화면·`SyncModule`·`idTokenProvider`·배포 순서 — 7.4.7)만 남는다.

**실연결 미니 라운드**: 사용자가 Firebase 프로젝트를 만들면 2차 통합이 끝난 뒤 INFRA·SYNC 두 영역만으로 짧게 한다(1차 7.3.3 M4 행 + 로그인 화면 + `cloud_functions`/`firebase_auth` 연결 + iOS 혼합 모드 컴파일 확인). 2차 도중 프로젝트가 생겨도 2차 범위에 끼워 넣지 않는다(범위 팽창 방지). 사용자 질문 U3.

### 3.4 우선순위 등급 — 범위를 줄여야 할 때

동시 개발 중 일정이 밀리면 아래 순서로 자른다. 각 영역 계획서의 작업 분해도 이 등급을 표시한다.

| 등급 | 뜻 | 포함 |
|---|---|---|
| P-A | 2차 완료 조건 | M5-1~5, M5-7, M5-8, M5-10~12, M6-1, M6-3, M6-4, M6-5(웹 조각 저장·복구), M7-2(색인·질의·결과 UI), M7-3, M7-4, M7-5, 공통-1, SYNC 사전 정비 |
| P-B | 해야 하지만 미뤄도 2차 완료 | M5-6 자동 도형 보정, M5-9 Pencil 플러그인, M6-2 백그라운드(네이티브), M7-1 ML Kit 어댑터·변환 UI, M7-6 수식 엔진 포트·패드·서버 함수 |
| P-C | 여유가 있으면 | iOS 컴파일 확인 실행, 안드로이드 에뮬레이터 CI 잡, 별·화살표 꼭짓점 편집, 수식 엔진 비교 도구 |

### 3.5 총괄 결정 (확정 — 초안 A의 기본값 + B에서 옮긴 것)

| # | 결정 사항 | 결정 |
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
| D11 | 우선순위 등급(3.4) | 그대로 |
| D12 | 간접 의존 '2주 규칙'을 pubspec 간접 고정으로 지킴 | 그대로(R9에 포함) |
| D13 | 웹 녹음 끊김 대비(조각 저장)의 등급 | **P-A**(B에서 옮김). 웹 녹음기는 `record_web` 대신 MediaRecorder 자체 구현(`*_browser.dart`)으로 1초 조각을 `RecordingDraftStore`에 쓴다. 주 기기가 iPad Safari라 탭이 닫히면 녹음 전체를 잃는 위험이 가장 크다 |
| D14 | 기능 스위치 | INFRA `AppFeatures`(`--dart-define=FEATURE_MEDIA/RECOGNITION/MATH_ENGINE=false` + 개발자 메뉴)로 서비스 모듈 연결을 통째로 뺀다(PLAN 7.6, B에서 옮김). 기본은 모두 켬 |
| D15 | 외부 엔진 전송 동의 | 설정 `recog.mathConsent`(synced, 기본 false) 동의 전에는 `MathRecognizer` 서버 호출 경로가 닫힌다(G-3, B에서 옮김) |
| D16 | 실연결 미니 라운드 담당 | INFRA + SYNC 두 영역(로그인 화면·`SyncModule` 연결·`cloud_functions`/`firebase_auth` 판단·iOS 혼합 모드 컴파일 확인). 2차 통합 뒤, 사용자가 Firebase 프로젝트를 만든 다음 |
| D17 | (v2.1) 기능 스위치 `FEATURE_MEDIA`의 범위 | **녹음만** 끈다(오디오 override·녹음 패널·초안 복구·이탈 경고). 이미지 삽입·이미지 페이지(P-A)는 스위치와 무관하게 연결한다(7.3.3). PLAN 7.6이 든 스위치 대상은 '유료가 될 기능'이고 이미지 삽입은 아니다 |
| D18 | (v2.1) 실기기 확인 경로와 Firebase 없는 동안 | 3.7 |
| D19 | (v2.1) 녹음 지원 범위 | 한 녹음 연속 3시간(64 kbps ≈ 86 MB)까지 지원 범위다. 같은 출처를 탭 두 개로 여는 것은 범위 밖(안내)으로 두되, 다른 탭이 진행 중인 초안을 복구하지 못하게 하는 최소 보호는 넣는다(7.2.4). 웹 정지 저장이 끝내 실패하면 마지막 수단으로 '파일로 내려받기'를 보인다 |
| D20 | (v2.1) 안드로이드 기기 자동 백업 | 끈다(`android:allowBackup="false"` — 25 MB 상한, 실행 중 파일 복사 불일치, 다른 기기로 복원할 때 기기 식별·HLC 노드 id 복제가 동기화 전제와 충돌). iOS는 기본값(실연결 미니 라운드에서 다시 본다). 보존 수단은 백업 내보내기 → 실연결 뒤 동기화(U27) |
| D21 | (v2.1) 1차 V7(iPad 확인)과 2차 시작 | 2차 기반 단계의 전제가 아니다. Hosting이 생기면 2차 동시 개발과 병행하고, 결과가 2차 범위를 바꾸면 7.4.9 절차 |
| D22 | (v2.1) 웹 메모리 예산 | 7.4.5 재배분(합계 296 MB ≤ 300 MB). INK 타일과 이미지 디코드가 한 장부를 나눠 쓰고 PDF 미리보기를 줄인다. 한 장의 래스터·디코드는 4 Mpx 상한 |
| D23 | (v2.1) 손글씨 결과 쓰기 경합 | 로컬 쓰기(색인기·변환 창)는 CORE `HandwritingRepository.update`(한 쓰기 트랜잭션 안에서 읽고-병합-쓰기)만 쓴다(G-4). '신선함' = `sourceRev` + 언어(엔진 판·기기 무시) — 실연결 뒤 기기 간 이중 인식을 막는다 |
| D24 | (v2.1) 기반 단계와 동시 개발 시작 | CORE는 계약 표면(B2-α)을 먼저 커밋해 해시를 알리고, 다른 영역은 그 위에서 코드를 쓰기 시작한다. 동시 개발 시작 조건은 R2-B1~R2-B6이 `main`에 있음이고 R2-B8(INFRA 앱 셸)은 조건이 아니다(7.6) |

### 3.6 이번 범위에서 제외

- 동기화 실연결(앱 연결·로그인 화면·Firebase 배포·App Check) — 3.3의 '실연결 미니 라운드'로.
- 웹(iPad Safari)의 손글씨 인식(서버 경유 OCR — 조사 03 W2), 수식 엔진 실제 호출·엔진 결정, 획마다 실시간 수식 미리보기.
- 객체 z 순서 바꾸기(맨 앞/뒤), 이미지 자르기·투명도, 텍스트 부분 서식·목록·표, 그리드 스냅·자, 발표 모드(외부 화면), 별·화살표 자동 판정.
- 다른 노트의 페이지 복사(F-13) — `PageDraft.objects`가 객체까지 복사하므로 나중에 고르기 UI만 더한다(U23).
- 에셋 바이트 회수(고아 에셋 GC), 녹음 텍스트 변환(P2), 다중 탭 리더 선출, tombstone 정리.
- TestFlight 실제 업로드(계정 뒤 — 워크플로·안내서는 갱신), 무료 Apple ID 사이드로드(U4).

### 3.7 실기기 확인 경로와 Firebase 없는 동안 (v2.1, D18)

| 경로 | 지금 되는가 | 필요한 것 | 확인하는 것 | 데이터 |
|---|---|---|---|---|
| 안드로이드 APK | **된다** | GitHub Actions `android.yml`(Firebase 불필요 — 1차 통합에서 개발 브랜치 푸시마다 빌드), 안드로이드 기기(U2), 고정 서명 키(U20) | 7.8 A | 네이티브 파일 DB·파일 블롭(공통-1). 고정 키 2차 APK끼리 덮어 설치하면 유지 |
| iPad 웹(Safari·홈 화면 앱) | **Firebase Hosting이 있을 때** | Firebase 프로젝트 **Spark(무료, 결제 계정 없음) + Hosting만**, GitHub 시크릿 `FIREBASE_SERVICE_ACCOUNT`·변수 `FIREBASE_PROJECT_ID`(1차 안내서 01·02, 약 15분 — U24) | 7.8 B, 1차 V7 | live 채널(`<프로젝트 ID>.web.app`, 홈 화면 앱) = 실사용. 브랜치 미리보기 채널 = 시험(출처가 달라 데이터가 따로이고 7일 뒤 만료) |
| iOS 컴파일만 | 된다(계정 불필요) | macOS 러너 `ios-compile.yml`(무료 시간 10배 — U19) | Swift(`pencil_bridge`)·Podfile·ML Kit pod 컴파일 | — |
| TestFlight(iPad 네이티브) | Apple 유료 계정 가입 뒤 | `ios-testflight.yml`(1차), 개발자 계정 | 7.8 C | 네이티브 저장 |

- **Hosting(Spark)은 '실연결'이 아니다.** 동기화·로그인·Firestore·Storage·Functions(Blaze)는 3.3대로 실연결 미니 라운드에서 한다. 사용자가 2차 도중 Spark 프로젝트를 만들면 **Hosting 시크릿만** 연결하고 2차 범위는 바꾸지 않는다.
- **Hosting이 없는 동안**: CI는 배포 단계를 건너뛴다(1차 `ci.yml` 그대로). iPad 확인(7.8 B)·1차 V7·EDITOR IME 시제품의 첫 주 미리보기(04-editor Q1)는 Hosting이 생길 때까지 밀린다. 2차 완료 판정(컨테이너 V1~V16)은 영향을 받지 않는다. 대신 통합 9단계에 릴리스 웹 빌드를 컨테이너의 정적 서버 + Playwright Chromium(1032×1376, `ko-KR`)으로 열어 콘솔 오류 0·주요 흐름을 확인하는 스모크(1차 G4 방식)를 둔다. 마이크·클립보드·저장소 지속은 HTTPS 보안 문맥에서만 되므로 '같은 와이파이의 http 주소로 열기'는 대체가 되지 않는다. GitHub Pages는 비공개 저장소에서는 유료이고 저장소를 공개하지 않으므로(U19) 쓰지 않는다.
- **Firebase가 없는 동안 기능별 처리**: 서버 함수는 에뮬레이터(`demo-noteapp` — 실제 프로젝트 불필요)로만 시험하고 컨테이너·CI에서 돈다. 앱 빌드(미리보기·live)에는 `MATH_ENDPOINT`를 넣지 않아 수식은 LaTeX 직접 입력 + 미리보기(`ManualOnlyMathRecognizer`)다. 로그인 화면·`idTokenProvider`는 없다. 손글씨 결과는 만든 기기(안드로이드 APK)에만 있고 iPad 웹에는 오지 않는다(위험 2). 데이터 보존은 백업 내보내기(1차) + 마이그레이션 직전 v1 사본(7.2.7).
- **실사용 노트**: iPad 실사용은 live 채널의 홈 화면 앱에서만 한다(1차 안내서 04 — Safari 탭은 가장자리 스와이프 '뒤로 가기'가 있고 저장 공간이 홈 화면 앱과 따로일 수 있다). 2차 첫 배포는 브랜치 미리보기 채널(빈 데이터)에서 확인하고, live 반영(= 실제 노트의 v1 → v2 이주) 전에 백업 내보내기를 한다(7.8 B-1).

## 4. 의존 그래프와 동시 개발

### 4.1 패키지 의존 방향 (v2.0)

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
  fn[functions/<br/>Node · SYNC 소유] -. HTTP callable 형식 7.2.13 .- recog
```

규칙은 7.1(1차 규칙 1~3 + 2차 규칙 4~6)이다. 요지: 서비스 패키지(`media_io`·`ink_recognition`·`pencil_bridge`)와 피처 패키지는 서로 import하지 않고, 둘의 연결은 앱 셸(INFRA)만 한다(7.3.3). 앱은 이번에도 `sync_engine`에 의존하지 않는다(3.3).

### 4.2 기능 흐름별 의존

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

### 4.3 동시 개발 — 누가 누구의 가짜로 개발하는가

| 영역 | 의존 대상 | 개발 중 쓰는 것 | 실제와 맞춰 보는 시점 |
|---|---|---|---|
| CORE | (없음) | 자기 실제 구현. SYNC 쪽 동작은 1차 `SyncStore` 계약 시험 그대로 | — |
| INK | CORE | `createFakeNoteStore()`(v2: 객체·에셋), CORE 값 타입 실제 | 통합 2단계(INK 골든·불변식) |
| EDITOR | CORE, INK, (자리) media·recog·pencil | CORE 가짜 저장소 + `FakeAudioRecorder`·`FakeAudioPlayback`(CORE `testing.dart`), INK 실제(기반 단계 단순 구현 → 개발 중 INK 진행분은 통합 때), 자리는 테스트용 `EditorSelectionMenuItem`·가짜 `EditorImageImporter`·가짜 `StylusExtrasSource` | 통합 태그 E-2x(실제 INK + 실제 CORE) |
| LIBRARY | CORE, INK(recog만) | CORE 가짜 저장소(v2: `searchLibrary`가 가짜 색인으로 `pages`를 채움), `FakeHandwritingRecognizer`·`FakeMathRecognizer`(자기 `testing.dart`), INK 실제(`InkShapeFitter` 포트·`MathPreview`) | 통합 태그 L2x(실제 CORE 색인) |
| PDF | CORE, INK | CORE 가짜 저장소, INK 벡터 v2(기반 단계에서 객체 항목을 '단순 동작'으로 냄), `record`·`just_audio` 플랫폼 인터페이스 가짜(media_io 내부), Chrome 가짜 마이크 | 통합 태그 `integration`(PDF 객체 내보내기), `media`(실제 CORE 에셋 + Chrome 녹음) |
| SYNC | CORE | 1차와 같이 자기 `fake_sync_store`(v2 종류 지원)·`FakeSyncServer`. 실제 CORE v2는 `openTestNoteStore` — CORE의 DB v2가 들어오는 대로(개발 중 CORE 커밋을 읽기만) | 통합 태그 T16-v2(실제 CORE 2개, 객체·손글씨 시나리오) |
| INFRA | 전부 | 기반 단계 자리표시 구현, `pencil_bridge`는 가짜 `EventChannel` | 통합 7단계(실제 모듈 연결, V5 스모크) |

### 4.4 임계 경로

```
R2-B2 CORE 계약 타입 ─┬→ R2-B3 INK 공개 표면 ─┬→ EDITOR (객체 도구·녹음 연동)
                      │                        ├→ PDF (객체 벡터화)
                      │                        └→ LIBRARY/recog (패드·도형 판정기)
                      ├→ R2-B7a SYNC 컴파일 패치(EntityKind 값 추가는 SYNC switch를 깸)
                      └→ PDF/media_io (오디오 포트·이미지 타입)
통합: CORE → INK → SYNC → PDF(+media) → LIBRARY(+recog) → EDITOR → INFRA
```

- 가장 긴 사슬은 **CORE 객체 모델 → INK 객체 렌더·선택 → EDITOR 객체 도구**다. 기반 단계에서 INK가 객체를 '경계 상자 + 단순 그리기'로라도 그려 두면 EDITOR는 개발 첫날부터 실제 화면으로 상호작용을 만들 수 있다.
- 오디오·인식은 CORE 포트 타입만 있으면 독립적으로 진행된다(가짜로 EDITOR가, 실제로 media/recog가 각자).

## 5. 동시 개발 방식과 환경 제약

1차 4장(계약 우선, 소유 경로만 수정, 가짜로 시험, 기반 단계 먼저, 통합 단계)과 1차 5장(환경 제약)을 그대로 따른다. 바뀌거나 더하는 것만 적는다.

- **환경**: Flutter 3.47.9 / Dart 3.13.7(`/opt/flutter`), 리눅스 컨테이너(CPU 4, 메모리 15GB), 헤드리스 Chrome(`CHROME_EXECUTABLE=/usr/local/bin/chrome-nosandbox`) 가능. Android SDK 없음·`dl.google.com` 막힘 → APK·Gradle은 GitHub Actions에서만 [조사 04 요약 1]. `flutter build ios` 하위 명령 없음 → iOS는 macOS 러너 컴파일 확인만. `api.mathpix.com` 등 외부 엔진 주소는 막혀 있다.
- **사용자**: iPad Pro 13"(Apple Pencil — 종류 확인 필요, U1)를 가지고 있고 실기기 시험이 된다. Mac·Apple 유료 계정·Firebase 프로젝트는 없다(계정·프로젝트는 나중). 안드로이드 태블릿 여부 미확인(U2).
- **확인 경로**: 2차의 완료 판정은 언제나 **컨테이너에서 도는 시험**(7.7 V1~V16)이다. 실기기 확인(7.8)은 합격 판정이고, 확인 시점이 'TestFlight 뒤'인 항목도 이번 라운드에 코드·시험은 끝낸다.
- **웹 우선 규칙(1차 그대로)**: `lib/`에 `dart:io` 금지(조건부 import로 `*_native.dart`), 웹 안전 수치(`Int64List` 금지 등), `package:material_ui`, Riverpod 3.4.3 codegen 없음, 외부 패키지 정확한 버전 고정. 새 규칙은 7.4.1(네이티브 전용 플러그인)·7.5(게시 14일 규칙).
- **동시 실행 부하**(B에서 옮김): 같은 컨테이너에서 영역 7개와 다른 에이전트가 시험을 돌린다. 평소에는 패키지 단위·`ws test --affected-since`만 돌리고, 전체 `ws test`·Chrome 전체는 체크포인트 때만 돌린다. Chrome 가짜 마이크 시험(`media`)과 Firebase 에뮬레이터 시험(`emulator`)은 **한 번에 하나만**(시작·끝 시각을 진행 기록에 남김). (v2.1) 이 규칙은 `ws`의 컨테이너 전역 잠금이 기계적으로 지킨다(7.4.6).
- **변경 요청**: 소유 경로 밖이 필요하면 1차처럼 결과 보고·진행 기록에 '변경 요청'으로 남긴다. 네이티브 설정(Info.plist·매니페스트·Podfile)은 플러그인을 쓰는 영역이 계획서 14절(또는 부록 B)에 요구를 적고 INFRA가 넣는다((v2.1) INFRA 동시 개발 첫 작업 J0 — 7.6).

## 6. 계획서 공통 목차

1차 6장의 12항목을 그대로 쓰고 두 절을 더한다. 파일은 `docs/plans/m5-7/NN-<id>.md`(01-infra, 02-core, 03-ink, 04-editor, 05-library, 06-pdf, 07-sync). 패키지를 둘 가진 영역(INFRA·LIBRARY·PDF·SYNC)은 3·4·6·8절을 패키지별 하위 절로 나눈다.

1. 목적과 범위 — 이번 범위 / 이후 범위 / 제외 (3.1 표의 자기 행, 3.4 등급 표시)
2. PLAN.md 요구사항 대응표 — F-xx·로드맵 항목 → 작업
3. 소유 경로와 패키지 구조 — 디렉터리 트리(1차 트리에 더하는 것 표시)
4. 공개 API — 7장 정의를 그대로 옮기고, 영역 내부에서 정하는 세부(예: 내부 상수)만 더한다
5. 사용하는 다른 영역의 계약 — 7장 이름·형태 그대로, 시험용 가짜(4.3 표)
6. 설계 상세 — 1차 계획서의 해당 절 번호를 밝히고 바뀌는 것만
7. 외부 패키지 — 7.5 표의 자기 행(버전·웹 지원·라이선스)
8. 작업 분해 — 순서, 작업별 완료 조건, **P-A/P-B/P-C 등급**(3.4)
9. 테스트 계획 — 컨테이너 자동 시험 / 사용자 실기기 확인(7.8의 자기 항목)
10. 완료 기준
11. 리스크와 대응
12. 총괄에게 묻는 질문
13. **확장 지점·자리 사용표**(새) — 이 영역이 여는 자리(provider·`EditorExtensions` 필드·포트)와, 채우는 자리(어느 자리를 어떤 id로)
14. **네이티브·권한 요구표**(새) — 플러그인별 iOS 배포 대상·Info.plist 키·안드로이드 권한·서비스 선언·minSdk/compileSdk. INFRA `native_config_test`·`ws native-reqs`의 입력(7.4.3)

(v2.1) 7개 계획서 중 6개가 13절을 '검토 반영 내역'으로 쓰고 위 13·14를 **부록 A·B**로 두었다. 이 모양도 공통 목차로 인정한다(내용은 같음 — 번호를 다시 매기지 않는다). 시험용 위젯 키는 부록 C(INFRA V5·V6 입력).

## 7. 통합 계약 v2.2

> **계약 v2.7** (2026-11-12, 2차 통합 — 시그니처 변경 없음, 7.9 'v2.7' C27-01~07: 웹 예산 기준 이동, 점선·빈 도형 적중·읽기 규칙 해석 확정, 웹 안전 수 규칙, P-B 판정·미룸 표, V14 나눔). v2.3~v2.6은 동시 개발 중 결정(7.9). 절 제목의 'v2.2'는 링크를 지키려고 그대로 둔다.
>
> **계약 v2.2 확정** (2026-11-05, 총괄 최종 승인 — v2.1에 영역 계획서 수정 회차의 미판정 CP 6건·EDITOR Q16 답·바탕 HEAD를 더함, 7.9 'v2.2' 표 C22-01~09. 시그니처 변경은 `dev_tools.dart` 추가 하나). **계약 v2.1 확정** (2026-11-05, 총괄 — 7개 영역 계획서 초안·대리 검토 반영, [00-review.md](00-review.md)). 1차 계약 v1.5(시그니처는 v1.4와 같음) 위에 덮어쓴다. 여기 적지 않은 것은 1차 계약 그대로다. v2.0 초안에서 바뀐 곳은 본문에 `(v2.1)`로 표시했고 7.9 'v2.1' 표(C21-01~35)에 모두 있다. 영역 계획서는 이 장에 맞춰 고친다(00-review 3장). 개발 중 변경은 7.4.9 절차(v2.2 …).
> - **적용 시점**: 이 장의 모든 변경은 **1차 통합(1차 7.7) 이후** 2차 기반 단계(7.6)에서 적용된다. 1차 작업 트리(`area/<id>`)에서 개발 중인 코드는 이 장 때문에 바꾸지 않는다.
> - 시그니처 변경은 최소로 했다. '깨짐' 변경은 7.0.2에 모두 있고, 각각 영향받는 코드 위치를 1차 작업 트리에서 확인했다.

### 7.0 1차 계약(v1.4) 대비 변경

#### 7.0.1 변경 표

'적용'은 그 변경을 `main`에 넣는 2차 기반 단계(7.6)다. '영향'은 컴파일·시험이 바뀌는 영역이다.

| # | 1차 절 | 변경 | 분류 | 영향 | 적용 · 2차 절 |
|---|---|---|---|---|---|
| C2-01 | 7.1 | 새 패키지 3개(`media_io` PDF, `ink_recognition` LIBRARY, `pencil_bridge` INFRA) 행 추가, `noteapp` 허용 의존에 셋 추가, `functions/`(SYNC, 워크스페이스 밖) 행 추가. 규칙 4~6(서비스 패키지 ↔ 피처 패키지 import 금지) | 규칙 | INFRA(`allowed_dependencies` R8) | R2-B1 · 7.1 |
| C2-02 | 7.2.1 | 소유표에 2차 타입 행 추가 | 규칙 | — | — · 7.2.1 |
| C2-03 | 7.2.3 | `PageElement`(sealed)에 하위 계층 `PageObject`(sealed) + 5종(`ShapeObject`·`TextBoxObject`·`ImageObject`·`MathObject`·`UnknownObject`)을 같은 라이브러리의 `part`로 추가. 새 기초 타입 `PagePoint`·`ElementFrame` | 깨짐(형식상) | CORE 내부 switch. [확인] 다른 패키지의 `PageElement` switch는 SYNC `fake_sync_store.dart`의 `SyncEntity` switch(`default:` 있음)뿐 — 영향 없음 | R2-B2 · 7.2.2 |
| C2-04 | 7.2.4 | `StrokeStyle.extras` 키 추가(INK 소유 `InkStyleExtras`: 펜촉 각·비율·롤 따르기, 점선 간격, 레이저 시간, 테이프 모양). `StrokeStyle.defaultsFor`의 P1 5종 값은 v1.4 값 그대로 | 추가 | INK, CORE(값 없음) | R2-B3 · 7.2.9 |
| C2-05 | 7.2.6 | `EntityKind`에 `pageObject`·`handwriting` 추가(wire 이름 = enum 이름) | 깨짐 | CORE·SYNC의 exhaustive switch [확인 — (v2.1 정정) SYNC `lib/`의 기본 갈래 없는 switch 4곳(`keysOf`·`groupsOf`·`scopeOf`·`_purged`) + 목록 `kindOrder`(컴파일은 되나 정렬이 틀어짐) + 시험 `fixtureJson`. 나머지 4곳은 기본 갈래가 있다]. LIBRARY는 `==` 비교만 | R2-B2 + R2-B7 **한 묶음** · 7.2.2 |
| C2-06 | 7.2.6 | `Recording.title`(선택, JSON 키 `title`, 없으면 null), `copyWith(title:, clearTitle:)` | 추가 | CORE, SYNC(필드 단위) | R2-B2 · 7.2.4 |
| C2-07 | 7.2.6 | `kDatabaseSchemaVersion` 1 → 2(마이그레이션 한 단계). `kNoteSchemaVersion`은 **1 유지** | 규칙 | CORE, INFRA(웹 배포 되돌리기 금지 안내) | 동시 개발 · 7.2.7 |
| C2-08 | 7.2.7 | `EditCommand`에 `AddObjects`·`UpdateObjects`·`RemoveElements` 추가 | 깨짐(형식상) | CORE 해석기만(EDITOR·PDF·LIBRARY에 `EditCommand` exhaustive switch 없음 [확인]) | R2-B2 · 7.2.3 |
| C2-09 | 7.2.7 | `TransformElements` 의미를 객체까지 넓힘(시그니처 같음), `ClearPage`에 선택 인자 `includeObjects`(기본 false), `PageDraft.objects`(기본 빈 목록), `InsertPages`·`DuplicatePages`·`PageDraft.copyOf`·`DeletePages`·노트 복사·휴지통·백업이 객체를 함께 다룸 | 추가 + 규칙 | CORE. EDITOR·PDF는 시그니처 그대로 — 객체가 든 페이지 복제 시험만 추가 | R2-B2 · 7.2.3 |
| C2-10 | 7.2.8 | `PageContent.objects`·`objectById`·`elementById`·`objectCount`(생성자 선택 인자). `PageContentChange.added/removed/updated`에 객체 id도 담김 — 소비자는 모르는 id를 무시한다 | 추가 + 규칙 | CORE, INK(`updateContent` diff), EDITOR | R2-B2 · 7.2.3 |
| C2-11 | 7.2.9 | `LibrarySearchResult.pages`·`pagesTruncated`(선택 인자, 기본 빈 목록), `searchLibrary`가 내용 결과(`pages`)도 채움 | 추가 + 규칙 | CORE, LIBRARY | R2-B2 · 7.2.5 |
| C2-12 | 7.2.9 | 새 인터페이스 `RecordingRepository`·`RecordingDraftStore`·`HandwritingRepository`·`SearchIndex`(`SearchIndexWriter`), 값 타입·오디오 포트(`AudioRecorderService`·`AudioPlaybackService`). (v2.1) `HandwritingRepository.update`(원자적 읽고-병합-쓰기)·`notesWithStalePages` | 추가 | CORE(정의), PDF(media 구현), EDITOR·LIBRARY(소비) | R2-B2 · 7.2.4·7.2.5 |
| C2-13 | 7.2.10 | outbox·`EntityChange` 힌트 규칙에 새 두 종류(`noteId`·`pageId` 항상), 병합 단위·청크 범위·정렬·게이트 표(7.2.8) | 규칙 | CORE, SYNC | R2-B2·B7(자리), 동시 개발 · 7.2.8 |
| C2-14 | 7.2.11 | `AssetStorageUsage.bytesByType`(**선택 인자, 기본 `const {}`**) | 추가 | CORE, INFRA(저장 공간 섹션 '종류별 용량' — v2.1 문구) | R2-B2 · 7.2.6 |
| C2-15 | 7.2.12 | `NoteStore`에 getter 4개(`recordings`·`recordingDrafts`·`handwriting`·`search`) | **깨짐** | CORE 실제·가짜. [확인] 다른 영역의 시험 구현 4곳 중 PDF 2곳·SYNC 1곳은 `noSuchMethod`라 영향 없음, **INFRA `app/test/fakes/counting_note_store.dart`는 명시 위임이라 컴파일 실패** → R2-B2 묶음에 INFRA 위임 4줄 포함 | R2-B2 묶음 · 7.2.6 |
| C2-16 | 7.2.12 | `NoteStoreConfig.nativeAssetDirectoryPath`(선택). 네이티브는 `nativeDatabasePath`와 둘 다 있으면 파일 DB + 파일 블롭 | 추가 + 규칙 | CORE, INFRA(`path_provider` 경로) | R2-B2(필드)·동시 개발(구현) · 7.2.6 |
| C2-17 | 7.2.14 | CORE provider 추가: `audioRecorderServiceProvider`·`audioPlaybackServiceProvider`(기본 '지원 안 함'), `recordingRepositoryProvider`·`noteRecordingsProvider`, `handwritingRepositoryProvider`, `searchIndexProvider` | 추가 | CORE, INFRA(override 표) | R2-B2 · 7.2.4~7.2.5 |
| C2-18 | 7.2.15 | INK 추가: `InkPageContent.fromCore(objects:)`, `InkPageController`의 `hitTestObject`·`setHiddenObjectIds`·`setPreviewObjects`·`setPlaybackFocus`·`hitTestRecorded`·테이프 API, `select`가 객체 id도 받음(규칙), `beginStroke(shapeAssist:)`·`StrokeSession.shapePreview`, `InkSelection.objectIds/allIds/objects`, `LassoOptions.includeObjects`, `EraserSpec.eraseShapes`, `InkEdit.addedObjects/updatedObjects`, `InkShapeFitter`·`inkShapeFitterProvider`. (v2.1) + 읽기 getter `previewObjects`·`hiddenObjectIds`·`playbackFocus`·`StrokeSession.shapeAssist`, `InkEdit.removedObjectIds` | 추가 | INK, EDITOR(소비) | R2-B3 · 7.2.9 |
| C2-19 | 7.2.15 | enum 값 추가: `InkEditKind.addShape`, `InkRenderMethod`(+`nibOutline`·`dashedPolyline`·`transientTrail`), `InkLayer.cover`, `InkRenderLayer`(+`underlay`·`annotation`·`cover`) | 깨짐(형식상) | [확인] INK 밖에서는 EDITOR가 `InkRenderLayer.overlay`·`InkEditKind.addStroke`를 값으로 비교할 뿐 exhaustive switch 없음 — 영향 없음(R2-B3 때 다시 grep) | R2-B3 · 7.2.9 |
| C2-20 | 7.2.16 | `pageBackgroundBuildersProvider` 기본값 `[template]` → `defaultPageBackgroundBuilders(ref)` = `[image, template]`. `pdfIoOverrides()`가 내는 목록 `[pdf, template]` → `[pdf, ...defaultPageBackgroundBuilders(ref)]`. **'PDF만 override' 규칙은 유지** | 규칙 | INK, PDF, INFRA(override 표 문구) | R2-B3·B4 · 7.2.9·7.2.12 |
| C2-21 | 7.2.16 | `InkBackgroundSpec.imageFit`, `ImageBackgroundLayerBuilder`·`InkImageCache`, `InkPageVectors.underlay/annotations/cover`(기본 빈 목록 — 1차 소비자 그대로 동작), 썸네일 객체 합성, `InkMathRenderer`·`MathPreview`·`InkFonts`·`InkTextLayout`. (v2.1) + `InkTextLayout.measureSync`·`textStyleOf`·`strutStyleOf`·`rasterize`, `InkFillShape.objectId`, `InkRenderConfig` 예산 필드 | 추가 | INK, PDF, EDITOR | R2-B3 · 7.2.9 |
| C2-22 | 7.2.17 | `EditorExtensions`에 `selectionMenuItems`·`insertMenuItems`·`recordingPanel`(기본값 있음), 새 값 타입(`EditorSelectionContext`·`EditorSelectionMenuItem`·`EditorInsertContext`·`EditorInsertMenuItem`·`EditorPanelContext`·`EditorImageImporter`), `editorImageImporterProvider`, `EditorScreen.initialFocusRectPt` | 추가 | EDITOR, INFRA(연결) | R2-B5 · 7.2.10 |
| C2-23 | 7.2.17 | `GestureSettings.actions`(선택 인자) + `EditorGesture`·`EditorAction`. 1차 bool 3개는 유지하고 JSON 읽기·쓰기 호환 | 추가 | EDITOR | R2-B5 · 7.2.10 |
| C2-24 | 7.2.17 | `StylusExtrasSource.capabilities` getter | 깨짐 | [확인] 구현은 EDITOR `NoStylusExtras` 하나(+ INFRA 새 어댑터) | R2-B5 · 7.2.10 |
| C2-25 | 7.2.17 | `StylusExtraEvent`(sealed)에 `StylusHoverPose`, `StylusDoubleTap`·`StylusSqueeze`에 선택 인자(`preferredAction`·`phase`·`hoverPosition`), `StylusPreferredAction`·`StylusSqueezePhase`·`StylusCapabilities`. (v2.1) `StylusExtraEvent.timestamp`(선택) | 깨짐(형식상) + 추가 | 구독자 없음 [확인 — 조사 01 3.7] | R2-B5 · 7.2.10 |
| C2-26 | 7.2.18 | `LibraryScreen.onOpenNoteAt`(선택) | 추가 | LIBRARY, INFRA(라우트 `?page=&focus=`) | R2-B6 · 7.2.11 |
| C2-27 | 7.2.19 | `PdfSearchIndexer`·`pdfSearchIndexerProvider` 추가. PDF 검색 정규화는 CORE `SearchText.normalize`와 같은 결과(시험) | 추가 + 규칙 | PDF, CORE | R2-B4 · 7.2.12 |
| C2-28 | 7.3.1~7.3.3 | 인터페이스 X18~X36, 동작 보장(K-6~K-9, C-11~C-14, E-4~E-7, M-1~M-3, G-1~G-3, S-13, F-1), override 표 행 추가(오디오·인식·도형 판정·`stylusExtrasProvider`·`editorImageImporterProvider`), 모듈 순서, 기능 스위치 `AppFeatures` | 규칙 | INFRA(연결), 각 영역 | R2-B8 · 7.3 |
| C2-29 | 7.4.3 | `native_only_imports` 추가(ML Kit·`flutter_foreground_task`·`path_provider`), 새 검사 R16(플러그인 없는 멤버의 직접 의존에 플러그인 없음 — (v2.1) 대상과 기존 예외는 7.4.1), `dart:io` `Platform`은 `*_native.dart` 안에서도 금지 | 규칙 | INFRA(`ws check`), 플러그인 쓰는 영역 | R2-B1 · 7.4.1 |
| C2-30 | 7.4.6 | ID 규칙 예외 `HandwritingText.idFor(pageId) = 'hw_' + pageId`(결정적 id, `isValidEntityId` 통과 [확인 — `^[0-9A-Za-z_-]{1,64}$`, 39자]), 설정 키 접두사 `media.*`·`recog.*` | 규칙 | CORE, PDF, LIBRARY | R2-B2 · 7.4.4 |
| C2-31 | 7.4.8 | 테스트 태그 `media`(Chrome 가짜 마이크)·`emulator`(Firebase 에뮬레이터), `skip_by_default_tags`에 추가, Chrome 가짜 미디어 래퍼 `tool/chrome-fakemedia` | 규칙 | INFRA, PDF(media), LIBRARY(recog), SYNC(functions) | R2-B1 · 7.4.6 |
| C2-32 | 7.4.9·7.4.10 | 텍스트 글꼴 지연 적재(시작 때 받지 않음), KaTeX 글꼴 시작 적재를 예산표에, 메모리 예산 재배분((v2.1) 2차 항목을 더하면 352 MB라 INK 타일·이미지 공유 장부, PDF 미리보기 축소 — 합계 ≤ 300 MB 유지) | 규칙 | INK, PDF, INFRA | R2-B8(측정) · 7.4.5 |
| C2-33 | 7.4.11 | 색 하드코딩 예외 추가: 재생 강조·흐림, 레이저 색(종이 위 표시 색, `InkTuning` 한 곳) | 규칙 | INK | R2-B3 · 7.4.10 |
| C2-34 | 7.5 | 새 외부 의존 + '게시 14일' 규칙과 간접 고정. **기존 잠금 변화 1건: `xml 7.1.0 → 7.0.1`** | 규칙 | INFRA(lock 재생성), INK(`flutter_math_fork` 계열) | R2-B1 · 7.5 |
| C2-35 | 7.6·7.7 | 2차 기반 단계 R2-B1~B8, 통합 순서, 검증 기준 V1~V16 | 규칙 | 전 영역 | — · 7.6·7.7 |
| C2-36 | 7.8 | 범위 결정 갱신: 올가미 회전·색 변경 UI, 제스처 동작 변경, 이미지 페이지, 라이브러리 전역 PDF 텍스트 색인 → **이번**. 다른 노트 페이지 복사·다중 탭 리더·tombstone·GC → 이후 | 규칙 | — | — · 3.2 |
| C2-37 | 7.3.2 E-3 | '레이저 획은 저장하지 않음'을 INK 쪽에서도 보장(K-9: 레이저 `StrokeSession.end()`가 `InkEdit`을 만들지 않음) | 규칙 | INK, EDITOR | R2-B3 · 7.3.2 |
| C2-38 | 7.2.3 `Stroke.transformed` | (v2.1) 캘리그래피 획(`tool == calligraphy`)을 변형하면 extras `nibAngleDeg`(없으면 45)에 `m.rotation`(도)을 더해 [0, 180)으로 접는다 — 회전한 글씨가 화면 그대로 같이 돈다(INK CP-INK-4). 뒤집기는 EDITOR가 보내지 않는다. 해석기는 바뀐 `style` 키를 이미 기록하므로 동기화 영향 없음 | 규칙(CORE 동작) | CORE(구현·시험), INK(미리보기 = 다시 기록 그대로) | R2-B2 · 7.2.3 |
| C2-39 | 7.1 | (v2.1) `note_core` 진입점 `testing_web.dart` — 브라우저 시험 전용, 실제 웹 저장소 열기(`openWebTestNoteStore`) | 추가 | CORE, INFRA(R4 예외·진입점 목록), PDF(V8·V16) | R2-B2 · 7.6 |
| C2-40 | 7.1 (`dev_tools.dart`) | (v2.2, C22-01) v1 DB 사본 API `V1DatabaseCopyInfo`·`v1DatabaseCopyInfo`·`readV1DatabaseCopy`·`deleteV1DatabaseCopy`(가짜 저장소는 `null`·아무것도 안 함) | 추가 | CORE, INFRA(개발자 메뉴 'v1 DB 사본 내보내기·지우기' — J14b) | R2-B2(B2-α 선언)·동시 개발(T24 동작) · 7.2.7 |

#### 7.0.2 깨짐 변경 요약과 대응

| 변경 | 실제로 깨지는 코드 [확인 2026-11-05] | 대응 |
|---|---|---|
| C2-05 `EntityKind` 값 2개 | CORE 내부 switch, SYNC `lib/`의 기본 갈래 없는 switch 4곳(`keysOf`·`groupsOf`·`scopeOf`·`_purged`)·`kindOrder` 목록·시험 `fixtureJson`(v2.1 정정 — 나머지 4곳은 기본 갈래가 있음) | R2-B2(CORE)와 R2-B7(SYNC — 새 두 값을 '노트 범위 일반 기록'으로)을 총괄이 **한 묶음으로 병합**한 뒤 검사 |
| C2-15 `NoteStore` getter 4개 | INFRA `app/test/fakes/counting_note_store.dart`(명시 위임) | 같은 묶음에 INFRA 위임 4줄(`recordings => inner.recordings` …) |
| C2-03·C2-08 sealed 하위 타입 | CORE 내부만 | — |
| C2-19 INK enum 값 | 없음(값 비교만) | R2-B3 커밋 전 `grep -rn "InkLayer\.\|InkRenderLayer\.\|InkRenderMethod\.\|InkEditKind\."`로 다시 확인 |
| C2-24·C2-25 스타일러스 | EDITOR `NoStylusExtras`(같은 영역) | R2-B5에서 함께 |

나머지는 '추가'·'규칙'이다. 생성자에 더하는 인자는 모두 **기본값이 있는 선택 인자**로 해, 다른 영역 시험이 값 객체를 직접 만들어도 그대로 컴파일된다(`PageContent`·`PageDraft`·`Recording`·`AssetStorageUsage`·`NoteStoreConfig`·`LibrarySearchResult`·`InkPageContent.fromCore`·`EditorExtensions`·`GestureSettings`·`LassoOptions`·`EraserSpec`·`InkEdit`).

### 7.1 패키지 구조와 의존 방향 (1차 7.1)

| 패키지 | 소유 | 종류 | 허용 의존(형제) | 공개 진입점 |
|---|---|---|---|---|
| `note_core` | CORE | 순수 Dart | — | v1.4 그대로(`note_core.dart`·`testing.dart`·`testing_vm.dart`·`dev_tools.dart`) + (v2.1) `testing_web.dart`(브라우저 시험 전용 — `test/web/`에서만, R4 예외 목록). (v2.2) `dev_tools.dart`에 v1 DB 사본 API(7.2.7) |
| `ink_engine` | INK | Flutter 패키지 | `note_core` | v1.4 그대로. 패키지 에셋 `assets/fonts/` 추가 |
| `feature_editor` | EDITOR | Flutter 패키지 | `note_core`, `ink_engine` | v1.4 그대로 |
| `feature_library` | LIBRARY | Flutter 패키지 | `note_core` | v1.4 그대로 |
| `pdf_io` | PDF | Flutter 패키지 | `note_core`, `ink_engine` | v1.4 그대로 |
| `sync_engine` | SYNC | v1.4 그대로 | `note_core` | v1.4 그대로 |
| **`media_io`** (새) | PDF | Flutter 패키지(플러그인 사용) | `note_core` | `media_io.dart`, `testing.dart`(테스트 전용) |
| **`ink_recognition`** (새) | LIBRARY | Flutter 패키지(플러그인 사용) | `note_core`, `ink_engine` | `ink_recognition.dart`, `testing.dart`(테스트 전용) |
| **`pencil_bridge`** (새) | INFRA | Flutter 플러그인(iOS만 구현, 그 밖은 지원 안 함) | — | `pencil_bridge.dart`(웹 안전) |
| `noteapp` (`app/`) | INFRA | Flutter 앱 | 위 전부(`sync_engine` 제외 — 3.3) | — |
| `functions/` | SYNC | Node 22 + TypeScript (워크스페이스 멤버 아님) | — | Firebase callable 함수(7.2.13) |

`tool/workspace_rules.yaml` `allowed_dependencies`(R8)에 새 세 패키지와 `noteapp: [..., media_io, ink_recognition, pencil_bridge]`를 더한다. `ws check`는 `functions/`를 검사 대상에서 뺀다(R1~R15는 Dart 멤버만).

규칙(1차 7.1 규칙 1~3에 더함)

4. `media_io`·`ink_recognition`·`pencil_bridge`는 **서비스 패키지**다. 피처 패키지(`feature_editor`, `feature_library`, `pdf_io`, `sync_engine`)를 import하지 않고, 피처 패키지도 이들을 import하지 않는다. `media_io`↔`ink_recognition`도 서로 import하지 않는다.
5. 서비스 패키지와 피처 패키지의 연결은 앱 셸(INFRA)만 한다(7.3.3 표). 서비스 패키지가 다른 패키지의 provider를 덮어쓰는 것은 자기 `*Overrides()` 함수를 통해서만 한다(1차 `pdfIoOverrides()`와 같은 방식).
6. 앱은 이번 라운드에도 `sync_engine`에 의존하지 않는다(3.3). `functions/`는 Dart 워크스페이스 멤버가 아니고 `ws check` 대상이 아니다.

### 7.2 공유 타입 소유표와 최종 정의

#### 7.2.0 소유 원칙 (1차 7.2.0에 더함)

- **공유 데이터 타입은 CORE**(1차 4장 원칙 1). 2차의 새 공유 타입 — 페이지 객체, 녹음 저장소·오디오 포트, 손글씨 인식 결과, 검색 색인, 이미지 가져오기 결과 — 은 모두 `note_core`(순수 Dart)가 정의한다. Flutter 타입(`BuildContext`, `Widget`, `Rect`)이 필요한 자리만 소비하는 패키지(EDITOR·LIBRARY)가 정의한다.
- **렌더는 INK 한 곳**. 화면·썸네일·PDF 벡터가 모두 INK를 거친다(1차 원칙 유지). 새 객체·새 펜의 그리기 의미는 INK가 정하고 CORE가 저장한다(1차 7.2.4 원칙 확장).
- **플랫폼 코드는 서비스 패키지 한 곳**. 녹음·재생·이미지 선택(`media_io`), 인식 엔진(`ink_recognition`), Pencil 이벤트(`pencil_bridge`)만 플러그인을 쓴다. 피처 패키지는 CORE 포트나 자기 자리 provider만 안다.
- 새 이름은 9개 패키지 공개 진입점에서 서로 겹치지 않는다(1차 7.2.0, R14). Flutter·`material_ui`와 겹치는 이름도 피한다: `TextBox`(dart:ui)·`Ink`(material_ui) 대신 `TextBoxObject`·`HandwritingTrace`를 쓴다. ML Kit은 `as mlkit` 접두어로만 가져온다(`Ink`·`StrokePoint`가 겹침).

#### 7.2.1 소유표 추가분 (1차 7.2.1)

| 타입 · 인터페이스 | 소유 | 사용 영역 | 정의 |
|---|---|---|---|
| `PagePoint`, `ElementFrame` | note_core | 전 영역 | 7.2.2 |
| `PageObject`(sealed) · `ShapeObject` · `TextBoxObject` · `ImageObject` · `MathObject` · `UnknownObject`, `ShapeKind`·`ShapeGeometry`(`PolylineGeometry`·`EllipseGeometry`)·`ShapeStyle`·`LineDash`·`ArrowHeads`, `TextBoxStyle`·`TextAlignKind`, `MathStyle`, `PageObjectLimits` | note_core | INK, EDITOR, PDF, SYNC, recog | 7.2.2 |
| `AddObjects`, `UpdateObjects`, `RemoveElements`, `ClearPage.includeObjects`, `PageContent.objects`, `PageDraft.objects` | note_core | EDITOR, INK, PDF, recog | 7.2.3 |
| `Recording.title`, `RecordingRepository`, `RecordingDraftStore`·`RecordingDraft`, `AudioRecorderService`·`RecorderStatus`·`RecorderPhase`, `AudioPlaybackService`·`PlaybackStatus`·`PlaybackPhase`, `AudioSupport`, 오디오 provider | note_core | EDITOR, media | 7.2.4 |
| `HandwritingText`·`HandwritingLine`, `HandwritingRepository`, `SearchIndex`·`SearchIndexWriter`·`SearchSource`·`SearchUnitDraft`·`PageSearchHit`·`SearchIndexStatus`, `SearchText`, `LibrarySearchResult.pages` | note_core | LIBRARY, recog, PDF, SYNC | 7.2.5 |
| `ImageImportSource`, `ImportedImage`, `ImageImportLimits`, `AssetStorageUsage.bytesByType`, `NoteStoreConfig.nativeAssetDirectoryPath` | note_core | EDITOR, media, INFRA | 7.2.6 |
| 펜 extras 키, 렌더 층, 객체 렌더·선택·적중 API, `InkShapeFitter`, `InkPlaybackFocus`, 테이프·레이저, `ImageBackgroundLayerBuilder`·`InkImageCache`, 벡터 내보내기 v2, `InkMathRenderer`·`MathPreview`, `InkFonts`·`InkTextLayout` | ink_engine | EDITOR, PDF, recog, INFRA | 7.2.9 |
| `EditorExtensions` v2 · 선택/삽입 메뉴 자리 · 녹음 패널 자리 · `EditorImageImporter`, `EditorGesture`·`EditorAction`·`GestureSettings` v2, `StylusExtras` v2, `EditorScreen.initialFocusRectPt` | feature_editor | INFRA | 7.2.10 |
| `LibraryScreen.onOpenNoteAt` | feature_library | INFRA | 7.2.11 |
| 인식 엔진 포트·가짜·`recognitionOverrides`·`RecognitionAction`·`HandwritingIndexer`·`GeometricShapeFitter`·`RecognitionSettingsSection` | ink_recognition | INFRA | 7.2.11 |
| `pdfIoOverrides` v2, `PdfSearchIndexer` | pdf_io | INFRA | 7.2.12 |
| `initializeMediaIo`·`mediaIoOverrides`·`importImageForNote`·`supportedImageSources`·`RecordingPanel`·`mediaDevOverlayLinesProvider` | media_io | INFRA | 7.2.12 |
| `PencilBridge`·`PencilEvent` 계열·`PencilCapabilities` | pencil_bridge | INFRA | 7.2.13 |
| `recognizeMath` callable 형식 | functions/ | recog | 7.2.13 |

#### 7.2.2 페이지 객체 (note_core)

결정 (조사 01 R1·R3 채택, 변형 포함):

- 획이 아닌 페이지 요소는 **`EntityKind` 하나(`pageObject`)와 테이블 하나(`page_objects`)**로 넣고, 종류는 JSON `type`(`shape`·`text`·`image`·`math`)으로 나눈다. 종류마다 `EntityKind`를 두면 SYNC·CORE switch와 매핑이 네 배가 된다.
- 모르는 `type`은 원본 JSON을 보존하는 `UnknownObject`로 읽고, `frame` 자리에 자리표시를 그리고, 그대로 동기화한다(다음 라운드에 종류가 늘어도 옛 앱이 기록을 잃지 않음).
- 모든 객체는 회전 가능한 상자 `ElementFrame`을 가진다. 도형만 꼭짓점 기하(`ShapeGeometry`)가 원본이고 `frame`은 거기서 계산한다.
- z 순서는 1차 `Stroke.compareOrder`(createdAt → id) 그대로다. '맨 앞/뒤로'는 이번에 하지 않는다(3.5 D2). 층(어느 묶음이 위에 그려지는가)은 INK가 종류로 정한다(7.2.9 L-1).

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
  factory ElementFrame.fromJson(List<Object?> json);   // FormatException on bad input; (v2.1) never normalizes
  // (v2.1, CP-4) static const double maxSide = 14400 (= PageSize.maxSide; fromJson rejects larger);
  //   ElementFrame normalized() — sides clamped [0, maxSide] around the center, rotation folded
  //   into (-pi, pi]; ==, hashCode. PagePoint: ==, hashCode (no JSON of its own).
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
  /// (v2.1) THE object transform rule. CORE's resolver (TransformElements) and every preview
  /// (INK selection / pending display, EDITOR) call this same function (INK review M-2):
  ///   frame / geometry transformed by m; s = m.uniformScale;
  ///   ShapeObject: style.strokeWidth × s clamped [0.1, 30] when [scaleWidth];
  ///   TextBoxObject: style.fontSizePt × s clamped [6, 144] (CP-2 — wrap width and text scale
  ///   together, so the frame height still fits; K-6);
  ///   MathObject: style.fontSizePt × s clamped [6, 144]; ImageObject: frame only;
  ///   UnknownObject: returns itself unchanged.
  PageObject transformed(Affine2 m, {bool scaleWidth = true});
  /// Paste / duplicate / page copy: new id, page and createdAt; version and deletedAt cleared.
  PageObject copyTo({required ElementId id, required PageId pageId, required EpochMillis createdAt});
  PageObject copyWithMeta({EpochMillis? updatedAt, EpochMillis? deletedAt,
      bool clearDeletedAt = false, Hlc? version});
  /// (v2.1, CP-4) History memory estimate (02-core 4.3 formula).
  int get estimatedBytes;
  @override Map<String, Object?> toJson();
  /// Dispatches on `type`; an unknown type → UnknownObject (never throws for that reason).
  /// (v2.1, CP-6) A known type with an enum name this app does not know (`shape`, `dash`,
  /// `arrowHeads`, `align`) is also read as UnknownObject. Never normalizes (remote values
  /// round-trip unchanged; normalization happens when a LOCAL command is resolved).
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
  /// INK InkTextLayout.measure (7.2.9). INK clips the text to the frame (K-6).
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
  final AssetId assetId;                         // AssetType.image, mime image/jpeg | image/png (7.2.6)
  final int pixelWidth, pixelHeight;             // intrinsic size of the stored bytes
  @override PageRect get bounds => frame.bounds;
  @override Set<AssetId> get referencedAssets => {assetId};
  ImageObject copyWith({ElementFrame? frame, EpochMillis? updatedAt});
}

@immutable
final class MathStyle {
  const MathStyle({this.colorArgb = 0xFF1A1A1A, this.fontSizePt = 18});
  static const double minFontSize = 6, maxFontSize = 144;   // (v2.1, CP-5)
  final int colorArgb;
  final double fontSizePt;                       // [6, 144]; scaled by TransformElements
  MathStyle normalized();                        // (v2.1) alpha 0xFF, size clamped
  MathStyle copyWith({int? colorArgb, double? fontSizePt});   // (v2.1)
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

/// Object written by a newer app (or, v2.1 CP-6, a known type with an unknown enum name). It can
/// be selected, deleted and copied as a whole and is synced unchanged; it cannot be transformed or
/// edited. JSON round-trips key-for-key (C-12).
final class UnknownObject extends PageObject {
  /// (v2.1, CP-4) rawJson must carry id, pageId, type, createdAt, updatedAt (FormatException
  /// otherwise); kept as an unmodifiable deep copy; frame / deletedAt / version read from it.
  UnknownObject(Map<String, Object?> rawJson);
  @override final String type;
  final Map<String, Object?> rawJson;
  /// From rawJson['frame'] when decodable, else ElementFrame(PageRect(0, 0, 1, 1)).
  @override final ElementFrame frame;
  @override PageRect get bounds => frame.bounds;
  /// (v2.1) A string `assetId` key in rawJson is reported (so a later asset GC keeps it).
  @override Set<AssetId> get referencedAssets;
  /// (v2.1) rawJson with the meta keys (id, pageId, createdAt, updatedAt, deletedAt, version) set
  /// to the current values; every other key as read. ==, hashCode: deep equality of toJson().
  @override Map<String, Object?> toJson();
}
```

- `EntityKind`(깨짐): `enum EntityKind { folder, note, page, stroke, penPreset, asset, recording, setting, pageObject, handwriting }` — 뒤에 둘을 더한다. 이름(wire)은 enum 이름 그대로다.
- `Stroke.compareOrder(PageElement a, PageElement b)`는 그대로 객체에도 쓴다(createdAt → id).
- 붙여넣기·복제된 객체는 `copyTo`로 새 `createdAt`(= 붙여넣은 시각 + i, 1차 획 클립보드 규칙과 같음)을 받는다.
- (v2.1, CP-4·CP-5) 4종의 공통 필드(`id`·`pageId`·`createdAt`·`updatedAt`(생성자 `updatedAt ?? createdAt`)·`deletedAt`·`version`)와 값 `==`·`hashCode`는 종류마다 같다. 스타일 정규화: `ShapeStyle.normalized()`는 `strokeColorArgb`·`fillColorArgb` 알파를 0xFF로(불투명도는 `*Opacity`가 가짐), `TextBoxStyle.backgroundArgb` 알파는 그대로(반투명 배경 허용). 정규화는 **로컬 명령 해석 때만** 하고 `fromJson`은 하지 않는다. 세부 표·`estimatedBytes` 공식은 02-core 4.3·6.2.3이 단일 출처다.
- (v2.1) 소비자는 객체 종류를 Dart 타입(`is TextBoxObject`, `switch`)으로 나눈다. `type` 문자열은 저장 형식용이다(`UnknownObject`도 `'shape'` 같은 알려진 이름을 가질 수 있다).

#### 7.2.3 페이지 내용 · 초안 · 편집 명령 (1차 7.2.7, 1차 7.2.8 — note_core)

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
// (v2.1, CP-1) new commands in the v1.4 command shape — const, named arguments, label.
// EditCommand is sealed; the only exhaustive switch is CORE's resolver.
/// objects: new ids, version == null, pageId == this.pageId. ≤ PageObjectLimits.maxObjectsPerPage.
final class AddObjects extends EditCommand {
  const AddObjects({required this.pageId, required this.objects});
  final PageId pageId; final List<PageObject> objects;
  @override String get label => 'add-objects';
}
/// Replace by id (same id, same type). UnknownObject or a missing id → ArgumentError before any
/// change. Only JSON keys whose value changed get a new field version (1차 7.2.10, C-11).
final class UpdateObjects extends EditCommand {
  const UpdateObjects({required this.pageId, required this.objects});
  final PageId pageId; final List<PageObject> objects;
  @override String get label => 'update-objects';
}
/// Removes strokes AND objects by id; unknown / already deleted / repeated ids ignored (like
/// RemoveStrokes). (v2.1) A List like every v1.4 id list (RemoveStrokes.strokeIds,
/// TransformElements.elementIds) — callers write [id], not {id}.
final class RemoveElements extends EditCommand {
  const RemoveElements({required this.pageId, required this.elementIds});
  final PageId pageId; final List<ElementId> elementIds;
  @override String get label => 'remove-elements';
}

// changed meaning — 규칙 (v1.4 constructors are named; shown here as v1.4 defines them)
// TransformElements({pageId, elementIds, transform, scaleStrokeWidth = true}): strokes as v1.4
//   (Stroke.transformed(m, scaleWidth:) — (v2.1) calligraphy nib angle turns with it, C2-38) AND
//   objects via PageObject.transformed(m, scaleWidth: scaleStrokeWidth) — the single rule (7.2.2).
// ClearPage({pageId, filter = StrokeFilter.all, includeObjects = false}) — 추가 (named, optional):
//   includeObjects removes every PageObject too (filter applies to strokes only).
// InsertPages / DuplicatePages: PageDraft.objects copied with new ids.
// DeletePages / note purge / note copy / backup: objects follow strokes (CORE 동작 계약).
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
| 붙여넣기 | `CompositeCommand([AddStrokes, AddObjects])` (빈 쪽은 뺌) |
| 손글씨 → 텍스트 상자 | `CompositeCommand([RemoveElements(획), AddObjects([TextBoxObject])])` (recog가 `execute`로) |
| 이미지 삽입 | `AddObjects([ImageObject])`, 이미지 페이지: `InsertPages([PageDraft(background: ImageBackground)])` |
| (v2.1) 텍스트 편집 세션 끝 — 내용을 모두 지움 | `RemoveElements` |
| (v2.1) 현재 페이지 전체 지우기(객체 포함) | `ClearPage(includeObjects: true)` |
| (v2.1) 선택 복제 | `CompositeCommand([AddStrokes, AddObjects])` (빈 쪽은 뺌) |
| (v2.1) 부분 지우개가 도형에 닿음 | `CompositeCommand([SplitStrokes 또는 RemoveStrokes, RemoveElements(도형)])` (INK `toCommand` — CP-INK-2. 되돌리기 1번에 조각과 도형이 함께 돌아온다) |

(v2.1) 표의 명령은 위 블록의 이름 있는 인자 모양이다(표에서는 줄여 적는다).

#### 7.2.4 녹음 (note_core) — 엔티티 · 저장소 · 오디오 포트 · 획 연결 규칙

```dart
// Recording (v1.4 CORE 4.2) — 추가: title
final class Recording implements SyncEntity {
  const Recording({/* v1.4 fields */, this.title});
  final String? title;                           // trimmed 1..100 chars; null → UI shows '녹음 N' by startedAt order
  Recording copyWith({/* v1.4 */, String? title, bool clearTitle = false});
  // JSON: 'title' — (v2.1, CP-7) always written (null when unset); absent on read = null.
  // Old apps ignore it (no deployed old app before 실연결).
}

/// (v2.0) Local create / list API (v1.4 had only the remote-apply path).
abstract interface class RecordingRepository {
  Stream<List<Recording>> watchRecordings(NoteId noteId);   // active, startedAt asc
  Future<List<Recording>> recordingsOf(NoteId noteId);
  Future<Recording?> getRecording(RecordingId id);           // also deleted ones
  /// Called by media_io AFTER AssetStore.put(audio) returned (M-1). [id] was chosen at
  /// record start so strokes could link to it immediately. (v2.1, CP-7) Idempotent per id: a retry with the
  /// same id returns the existing row (recovery after a failed save does not duplicate).
  Future<Recording> createRecording({required RecordingId id, required NoteId noteId,
      required AssetId assetId, required int durationMs, required EpochMillis startedAt, String? title});
  Future<void> renameRecording(RecordingId id, String? title);
  /// Soft delete; no restore UI this round. Strokes keep recordingId (R-7). Asset bytes stay
  /// until asset GC (later, 3.2).
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
  /// (v2.1) An empty chunk is allowed and only updates activeMs / updatedAt (keep-alive while
  /// paused). Unknown draftId → StateError (the draft was recovered or discarded elsewhere).
  Future<void> append(String draftId, Uint8List chunk, {required int activeMs});
  /// Leftovers after a crash / closed tab. (v2.1) A web draft whose chunks are stored but whose row
  /// was not yet durable is rebuilt from the meta the store writes next to the chunks at begin();
  /// a draft with a row and 0 chunks (native — media writes rows only) is normal and kept. Orphan
  /// cleanup removes only prefixes that have neither a row nor a meta.
  Future<List<RecordingDraft>> listDrafts();
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
  bool get isActive;                             // recording || paused (UI only — recovery uses pendingDrafts)
  // ==, hashCode (1차 7.4.4), (v2.1, CP-7) copyWith
}

abstract interface class AudioRecorderService {
  RecorderStatus get status;
  Stream<RecorderStatus> get statusStream;       // emits current value on listen
  Future<AudioSupport> checkSupport({bool requestPermission = false});
  /// [recordingId] is generated by the caller (core.idGeneratorProvider) BEFORE start so the
  /// first stroke can link to it. Throws StateError when another recording is active and
  /// (v2.1, CP-PDF-5) UnsupportedError when checkSupport() != supported (fakes too).
  Future<void> start({required RecordingId recordingId, required NoteId noteId});
  Future<void> pause();
  Future<void> resume();
  /// Finishes the file, stores Asset(audio) then Recording (M-1). null when nothing was recorded.
  /// (v2.1, CP-PDF-5) If storing fails the draft is kept and stop() throws — the next start-up
  /// recovery finishes it with the same recordingId (createRecording is idempotent per id).
  Future<Recording?> stop();
  Future<void> cancel();                         // discards the draft; no Recording row
  /// Audio-timeline ms now (pauses excluded); null unless phase == recording. Synchronous and
  /// cheap — EDITOR calls it at pen down (R-1, R-2).
  int? offsetNowMs();
  /// (v2.1, CP6 = CP-PDF-3 + PDF review M-5) Drafts to recover. Excludes this app's active session
  /// (phase starting … finishing), drafts being recovered, and drafts updated within
  /// max(10 s, 5 × the chunk interval) — they may belong to another tab that is still recording
  /// (D19). The recovery decision uses this list only (callers do not look at status.isActive).
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
  // ==, hashCode, (v2.1, CP-7) copyWith. Unsupported* behaviour table: 02-core 6.8.2 (CP-7).
}
abstract interface class AudioPlaybackService {
  PlaybackStatus get status;
  Stream<PlaybackStatus> get statusStream;
  /// Bytes via AssetStore; when missing locally and remoteAssetFetcherProvider is set,
  /// ensureLocal first (P-2 pattern). Closes any open recording.
  Future<void> open(Recording recording);
  Future<void> play();                           // (v2.1, CP-PDF-10) no-op while the recorder is active
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
//               FakeAudioPlayback (manual position, speed) — 1차 7.4.8 공용 가짜
```

획 ↔ 녹음 연결 규칙(계약 문장, 조사 02 6·12.4 채택):

| # | 규칙 |
|---|---|
| R-1 | 펜 다운 순간 `recorder.status.phase == recording` **그리고** `status.noteId == 지금 노트`일 때만 `InkStrokeMeta(recordingId, offsetNowMs())`를 넘긴다. 일시정지 중·다른 노트에서 녹음 중에 쓴 획은 연결하지 않는다(사용자 질문 U12 기본값) |
| R-2 | `recordingOffsetMs`는 **오디오 타임라인 위치**(일시정지 제외)다. 벽시계 차(`createdAt − startedAt`)를 쓰지 않는다. media_io는 단조 `Stopwatch`를 녹음기 상태 이벤트에 맞춰 멈추고 이어 간다 |
| R-3 | `Recording.durationMs` = 저장된 파일 안의 오디오 타임라인 길이(디코더가 읽는 길이). (v2.1) 웹 WebM에는 Duration이 없으므로 media가 **마지막 블록의 타임코드 + 그 블록(패킷)의 길이**(`TimecodeScale` 반영. (v2.2, C22-04) 블록 길이는 Opus면 TOC의 프레임 크기 × 프레임 수 — Chrome은 20 ms × 3 = 60 ms)로 계산해 넣는다 — 녹음 시계 값으로 패치하지 않는다(파싱이 실패할 때만 시계 값 + 개발자 표시 'duration from clock'). 시계 활성 시간과의 차이는 개발자 표시에만 보인다(보정 필드는 실측 뒤 판단 — 조사 02 D9, 7.8 A-5) |
| R-4 | 재생 위치 p에서 획은 `recordingOffsetMs + t_last ≤ p`이면 '쓴 획', `offset ≤ p < offset + t_last`이면 '쓰는 중'이다(INK 7.2.9 재생 강조) |
| R-5 | 필기 탭 재생은 `seekMs(max(0, offset − preRollMs))` 후 재생, `preRollMs` 기본 1500(설정 `editor.playback.preRollMs`, synced). (v2.1) **탭 재생 상태**에서만 가로챈다: 설정 `tapToSeek` 켬 + 녹음기 `phase == idle` + ① 손가락 한 번 탭은 녹음 패널이 열려 있거나 재생기가 `playing`·`paused`일 때 ② 펜 탭(이동 ≤ 4 px·≤ 200 ms — 점만)은 재생기가 `playing`·`paused`일 때만. 판정은 획 세션 `end()` **전에** 하고 가로채면 `cancel()` — 가로채지 않은 펜 입력은 언제나 획이 된다(필기 손실 없음). 재생 강조 초점은 이 녹음을 연 뒤 한 번이라도 `playing`이었거나 `seekMs`가 불린 뒤에만 넣는다 — 열기만 한 `ready`(패널 열기·녹음 정지 직후 자동 열기)는 초점 없음(정지 직후 필기가 흐려지지 않게, PDF 검토 M-8) |
| R-6 | 부분 지우개 조각·붙여넣기·복제는 `recordingId/OffsetMs`를 유지한다(v1.4 그대로). **노트 복사**는 녹음 행도 새 id로 복사하고(에셋은 같은 해시), 복사된 획의 `recordingId`를 새 id로 바꾼다(CORE `copyNote` 동작 계약) |
| R-7 | `recordingId`가 가리키는 녹음 행이 없거나 삭제됐으면 '연결 없음'으로 다룬다(오류 아님). 녹음이 취소(`cancel`)되면 이미 쓴 획의 `recordingId`는 그대로 남고 연결 없음이 된다 |
| R-8 | 녹음 시작·정지·이름·삭제는 되돌리기 히스토리 밖이다(삭제는 확인 창) |

#### 7.2.5 손글씨 인식 결과 · 검색 색인 (note_core)

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
  /// Set by the conversion UI. (v2.1) Auto re-recognition keeps a confirmed line's text while
  /// ≥ 80 % of its old strokeIds are still in the new line and the added strokes are small (each
  /// box ≤ the line's median glyph height); otherwise the engine text replaces it, userConfirmed
  /// becomes false and the old confirmed text goes first in alternatives. Rule owner: recog
  /// (05-library 6.9.4); writers merge through HandwritingRepository.update (G-4).
  final bool userConfirmed;
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
  final String engineId;                         // 'mlkit-digital-ink/19.0.0:ko' — provenance only.
  // (v2.1) Freshness = same sourceRev AND same language tail (':ko'); a result from another engine,
  // engine version or device is fresh (no double recognition across devices after 실연결).
  final String sourceRev;
  final List<HandwritingLine> lines;             // reading order
  @override EntityKind get kind => EntityKind.handwriting;
  // createdAt, updatedAt, deletedAt, version, isDeleted, toJson / fromJson, ==,
  // (v2.1, CP-13) copyWith (HandwritingLine too); put validation: 02-core 6.9.4
}

abstract interface class HandwritingRepository {
  Future<HandwritingText?> forPage(PageId pageId);
  Stream<HandwritingText?> watchPage(PageId pageId);
  /// Upsert. Also re-indexes the page's ink units (same transaction when possible; an index
  /// failure never fails the write — C-13). (v2.1) Local writers (indexer, conversion UI) use
  /// [update] so a write that arrived meanwhile is merged, not overwritten (G-4).
  Future<void> put(HandwritingText value);
  /// (v2.1) Read-merge-write in ONE CORE write transaction: [transform] gets the stored value
  /// (null if none / deleted) and returns the value to store (null = leave as is). Synchronous and
  /// pure (no await inside). Returns the stored value afterwards. Same validation as put.
  Future<HandwritingText?> update(PageId pageId,
      HandwritingText? Function(HandwritingText? current) transform);
  Future<void> removeForPage(PageId pageId);
  /// Active pages of [noteId] whose input strokes' sourceRevOf differs from the stored value
  /// (or that have none and at least one input stroke). Cheap: uses DB columns, no point decode.
  /// (v2.1) Page order.
  Future<List<PageId>> stalePages(NoteId noteId);
  /// (v2.1) Active notes with ≥ 1 stale page, one query over the pages.ink_rev cache — the
  /// indexer's start-up catch-up. Most recently updated note first.
  Future<List<NoteId>> notesWithStalePages();
}
final handwritingRepositoryProvider = Provider<HandwritingRepository>(/* store.handwriting */);
```

```dart
enum SearchSource { ink, pdf, text, math }

@immutable
final class SearchUnitDraft {
  const SearchUnitDraft({required this.body, this.rects = const [], this.pdfPageAspect});
  final String body;                             // original text (CORE normalizes)
  /// source pdf: fractions [0,1] of the PDF page — one per char of body, or empty; PageRect.zero =
  /// position unknown (skipped when hit rects are merged per line). (v2.1) CORE may store them at
  /// reduced precision (≥ 1/65535 of the page) and outside SQLite (7.4.5 index size).
  final List<PageRect> rects;
  final double? pdfPageAspect;                   // (v2.1, CP-3) pdf only: PDF page width / height
}

/// For pdf_io (source pdf only). ink / text / math are indexed by CORE itself from
/// HandwritingText and PageObject rows (no other package writes them).
abstract interface class SearchIndexWriter {
  /// ownerKey for pdf: '<assetId>#<pdfPageIndex>' (one entry per PDF page, shared by every note
  /// that uses the asset). sourceRev for pdf: '<assetId>:<SearchText.normalizerVersion>' plus an
  /// optional pdf_io tail (':x<extractorVersion>', v2.1 CP-PDF-2); CORE compares it as a string.
  Future<String?> sourceRevOf(SearchSource source, String ownerKey);
  /// ownerKey → sourceRev of every owner of [source] (a feeder's start-up catch-up in one query).
  Future<Map<String, String>> sourceRevs(SearchSource source);
  /// (v2.1) An empty [units] list still records the owner with [sourceRev] (a scanned page, or the
  /// '#0 last' completion mark of pdf_io) — sourceRevOf / sourceRevs then return it.
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
  /// excluded; results grouped by page, best score first. (v2.1) At most 2,000 candidates, most
  /// recent units first; candidates are judged without reading body excerpts or rects — only the
  /// returned hits read them. createFakeNoteStore uses the same judgement and order (CP-14).
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
  /// (v2.1, CP-10) normalize with a map back to source offsets (pdf_io highlight) — the same
  /// result text as normalize(); fields: 02-core 4.6.
  static SearchTextMapping normalizeMapped(String text);
}

// LibrarySearchResult (1차 7.2.9) — 추가
final class LibrarySearchResult {
  const LibrarySearchResult({required this.query, required this.folders, required this.notes,
      this.pages = const [], this.pagesTruncated = false});
  final List<PageSearchHit> pages;               // content hits (ink, pdf, text, math)
  final bool pagesTruncated;                     // (v2.1, CP-14) more pages than limit, or the 2,000-candidate cap was hit
}
// LibraryRepository.searchLibrary(query, {limit = 50}) now also fills pages (≤ 100).
```

#### 7.2.6 이미지 가져오기 · 에셋 · 저장소 묶음 (1차 7.2.11, 1차 7.2.12 — note_core)

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
- 이미지 에셋은 `ImageImportLimits.storedMimeTypes`만 저장한다(PDF 이미지 객체 입력 형식과 같게 — JPEG는 `FPDFImageObj_LoadJpegFileInline`, PNG는 비트맵). (v2.1, CP-11) 로컬 `AssetStore.put(type: image)`이 `storedMimeTypes` 밖이면 `ArgumentError`다(원격 `putDownloadedBytes`는 검사하지 않음 — PDF 내보내기는 그래도 다른 형식에 대비한다).
- (v2.1) 네이티브 블롭 루트 디렉터리가 없으면 CORE가 만든다(INFRA는 경로만 넘긴다). 앱 셸이 네이티브에서 두 경로를 모두 넘기는지는 INFRA 정적 시험이 본다(1차 셸은 넘기지 않아 1차 APK가 노트를 저장하지 못했다).

#### 7.2.7 저장 형식 — JSON 키, DB 스키마 v2, 마이그레이션 (1차 7.4.6, CORE 6.3·6.15)

페이지 객체 JSON(동기화·백업 공통, camelCase, 모르는 키 무시 — 1차 규칙 그대로):

| `type` | 공통 키 | 종류별 키 |
|---|---|---|
| (모두) | `id`, `pageId`, `type`, `frame`(`[l,t,r,b,rot]` — **모든 종류가 쓴다**: 옛 앱이 모르는 종류를 자리표시로 그릴 수 있게. 도형은 기하에서 계산한 값을 쓰고 읽을 때는 무시), `createdAt`, `updatedAt`, `deletedAt`, `version` | |
| `shape` | | `shape`(`ShapeKind` 이름), `geometry`(`{"poly":[x0,y0,…],"closed":true}` 또는 `{"ellipse":[l,t,r,b,rot]}`), `style`(`ShapeStyle.toJson`) |
| `text` | | `text`, `style`(`TextBoxStyle.toJson`) |
| `image` | | `assetId`, `px`(`[w,h]`) |
| `math` | | `latex`, `style`(`MathStyle.toJson`), `engine`((v2.1) 항상 씀 — 없으면 `null`) |

예시(`shape`, 회전 0 사각형 — 키 순서는 JSON에서 의미 없음):

```json
{"id":"0193a1f0-…","pageId":"0193a1e2-…","type":"shape",
 "frame":[120.0,80.0,320.0,200.0,0.0],
 "shape":"rectangle",
 "geometry":{"poly":[120.0,80.0,320.0,80.0,320.0,200.0,120.0,200.0],"closed":true},
 "style":{"strokeColorArgb":4279900698,"strokeWidth":2.0,"strokeOpacity":1.0,"dash":"solid","fillColorArgb":null,"fillOpacity":1.0,"arrowHeads":"none"},
 "createdAt":1762300000000,"updatedAt":1762300000000,"deletedAt":null,"version":"…"}
```

- 종류별 키 이름(`style` 안 키 포함)은 CORE `entity_json` 골든과 SYNC 'JSON 키 대조' 시험(1차 T16)이 함께 검사한다. `style` 안 키는 각 `toJson`의 필드 이름(camelCase) 그대로다.
- (v2.1) 종류별 키 집합은 고정이다 — 값이 없어도 키를 쓴다(`engine: null`, `Recording.title: null`). SYNC `kPageObjectTypeKeys`와 CORE 골든이 같은 집합을 대조한다(`math` 골든에 `engine: null` 사례 포함).

손글씨 결과 JSON: `id`, `noteId`, `pageId`, `engineId`, `sourceRev`, `lines`(배열), `createdAt`, `updatedAt`, `deletedAt`, `version`. 녹음 JSON: v1.4 + `title`.

DB 스키마 v2(`kDatabaseSchemaVersion = 2`, 규칙 — CORE 내부, 이름은 CORE가 바꿀 수 있음):

| 테이블 | 열 | 비고 |
|---|---|---|
| `page_objects` | `id` PK, `page_id`, `note_id`(비정규화 — 영구 삭제·복사), `type`, `min_x`·`min_y`·`max_x`·`max_y`(= `bounds`), `data_json`(종류별 키 + `frame`), `asset_id`(이미지만, 참조·GC용), `created_at`, `updated_at`, `deleted_at`, `version`, `field_versions` | 색인 `(page_id, deleted_at)`, `note_id`, `asset_id` |
| `handwriting` | `id` PK(`hw_<pageId>`), `page_id`, `note_id`, `engine_id`, `source_rev`, `lines_json`, 시간 열, `version`, `field_versions` | |
| `recordings` | + `title` (NULL 허용) | `ALTER TABLE ADD COLUMN` |
| `recording_drafts` | `draft_id` PK, `recording_id`, `note_id`, `mime_type`, `started_at`, `chunk_count`, `bytes`, `active_ms`, `updated_at` | 기기 로컬, outbox·백업 제외 |
| `search_owners` · `search_units` | (v2.1 정정, CP-15) 소유자 `search_owners`(`source`, `owner_key`, `source_rev`, UNIQUE(`source`,`owner_key`)) + 단위 `search_units`(`id` INTEGER PK, `source`, `owner_key`, `seq`, `note_id`, `page_id`(pdf는 NULL), `body`, 정규화 열, UNIQUE(`source`,`owner_key`,`seq`)). PDF 글자 사각형은 줄인 정밀도로 SQLite 밖(블롭 저장소) 또는 압축 BLOB — CORE 선택, 7.4.5 크기 목표 | 파생, 기기 로컬 |
| `search_fts` | FTS5 `(g, content='', contentless_delete=1, tokenize='unicode61 remove_diacritics 0')`(v2.1 정정), rowid = `search_units.id` | 마이그레이션 단계의 `customStatement`로 만든다(drift `.drift` 파일·`sqlite_modules` 옵션은 쓰지 않아도 됨 — CORE 선택) |
| `strokes` | (변경 없음) | `stalePages`용으로 `(page_id, tool, updated_at)` 조회가 색인 범위 안인지 CORE가 확인 |

- `kNoteSchemaVersion`은 **1 그대로**다(조사 01 Q3 기본안). 객체가 든 노트도 옛 앱에서 읽기 전용이 되지 않는다. 배포된 옛 앱이 없고(실연결 전) 사용자 한 명이 모든 기기를 함께 갱신하기 때문이다.
- 마이그레이션 v1 → v2는 한 트랜잭션(1차 `runSchemaUpgrade`)이고, `dart run drift_dev make-migrations`가 만든 단계 도우미(`note_database.steps.dart` — (v2.1 정정) INFRA `generated_files`에 `*.steps.dart`)와 생성 시험을 커밋한다. **1차 v1 DB 고정 자료**(1차 통합이 `main`에 들어간 커밋의 코드로 만든 노트·획·PDF 에셋 — CORE가 R2-B2 전에 만든다)를 v2로 여는 시험을 VM과 Chrome 둘 다 둔다(V7). iPad에 1차 웹으로 쓴 실제 노트가 생길 수 있기 때문이다((v2.1) Hosting이 없어 아직 배포된 적은 없다 — U25).
- (v2.1) **업그레이드 직전 v1 사본**: 업그레이드 트랜잭션 전에 같은 저장소 안에 v1 사본을 만든다. (v2.2, C22-02 — CORE CP-16) 방법은 저장 방식마다 정한다 — **네이티브 파일 DB**: `VACUUM INTO '<nativeDatabasePath>-v1-backup.tmp'` 뒤 이름 바꾸기 `<nativeDatabasePath>-v1-backup`(있던 사본은 먼저 지움, 결과는 그대로 열리는 v1 SQLite 파일). **웹**: 블롭 저장소(`WebStorageConfig.blobDatabaseName` — 기본 `noteapp_blobs`)의 `db/v1-backup/` 접두사에 **정규 덤프**(≤ 4 MiB 조각, 마지막에 `meta`를 쓴다 — `meta`가 있어야 완전한 사본, 형식은 02-core 6.12.3·6.12.4). 웹 IndexedDB VFS 안의 `VACUUM INTO` 사본은 지울 길이 없고 열 때마다 메모리로 읽히므로 쓰지 않는다. 새 DB·메모리 DB는 사본을 만들지 않는다. 사본 만들기가 실패하면(용량·I/O) 이주는 그대로 진행하고 kv에 실패를 남긴다(개발자 표시·메뉴에 보임). kv에 사본 시각·방법·크기·정상 열기 횟수를 남기고, **정상 열기 5번 이상이면서 만든 지 7일이 지난** 첫 열기에서 자동 삭제하거나 개발자 메뉴('v1 DB 사본 내보내기·지우기' — INFRA, 아래 API)에서 지운다. `deleteLocalNoteData`는 사본도 지우고, 백업 내보내기에는 넣지 않는다. V7의 '정규 덤프 해시'는 같은 덤프 형식으로 낸다. 이주가 성공한 뒤 2차 버그로 데이터가 상해도 되돌릴 마지막 안전망이다(백업 **복원**은 이번 범위 밖).

```dart
// package:note_core/dev_tools.dart — (v2.2, C22-01 — CORE CP-17) v1 DB copy for the INFRA developer menu
@immutable
final class V1DatabaseCopyInfo {
  const V1DatabaseCopyInfo({required this.createdAt, required this.bytes,
      required this.normalOpens, required this.fileName, this.failure});
  final EpochMillis createdAt;
  final int bytes;
  final int normalOpens;
  /// 'noteapp-v1-backup.sqlite' (native, a SQLite file) | 'noteapp-v1-backup.sql.txt' (web, the canonical dump)
  final String fileName;
  /// Set when the copy could not be made ('quota' | 'io' | 'other'); bytes is 0 then.
  final String? failure;
}
/// null when there is no copy and no failure record (new DB, deleted, or a store without one — fakes).
Future<V1DatabaseCopyInfo?> v1DatabaseCopyInfo(NoteStore store);
/// The copy in ≤ 4 MiB chunks (INFRA writes a file / web download). StateError when there is none.
Stream<Uint8List> readV1DatabaseCopy(NoteStore store);
/// Deletes the copy and its kv record; no-op when none.
Future<void> deleteV1DatabaseCopy(NoteStore store);
```
- 옛 앱이 v2 DB를 열면 `NewerSchemaError` → 앱 전체가 열리지 않는다(1차 동작). 웹 배포를 되돌릴 때 주의(위험 8 #9).
- 검색 색인 채우기: 마이그레이션 직후 텍스트 상자는 없고, PDF는 `PdfSearchIndexer`가 백그라운드로 채운다(7.2.12). `search_state`(정규화 판·재구축 표시)는 CORE 메타 KV에 둔다.

#### 7.2.8 동기화 문서 매핑 (1차 7.2.10 — sync_engine)

원격 구조(Firestore `users/{uid}/changes/{chunkId}` + 코덱 v1 이진 페이로드)는 바뀌지 않는다. 문서 필드에 엔티티 종류가 없으므로 Firestore·Storage 규칙도 바뀌지 않는다(조사 01 3.11). 코덱 형식 `fmt`는 **1 그대로** 둔다 — 배포된 옛 앱이 없고, 이번에 '모르는 종류 보류'가 들어가므로 이후 종류 추가에도 `fmt`를 올릴 필요가 없다.

| `EntityKind` | 청크 범위 | outbox 힌트 (CORE, 1차 7.2.10 규칙 확장) | 병합 단위(필드 묶음) | 하위 기록·게이트 |
|---|---|---|---|---|
| `stroke` | 노트 | v1.4 | v1.4 (`{recordingId, recordingOffsetMs}`) | v1.4 |
| `pageObject` | 노트 | `noteId` 항상, `pageId` 항상 | **객체 단위 하나**: (v2.1, CP-S1) 메타 키와 `pageId`·`deletedAt`·`engine`을 뺀 **나머지 키 전부**(모르는 키 포함 — 알려진 키로는 `{type, frame, shape, geometry, style, text, assetId, px, latex}`) + 따로 `{engine}`. 같은 객체를 두 기기가 동시에 고치면 나중 것이 이긴다(삭제 규칙은 v1.4 그대로) | (v2.1 정정) 노트 영구 삭제 때 함께(`purge_guard`·`record_gate`에 추가 — 페이지는 소프트 삭제만 있다). 삭제된 페이지에 상대가 모르는 객체가 있으면 페이지를 되살림(`page_resurrection` — 획과 같은 근거) |
| `handwriting` | 노트 | `noteId` 항상, `pageId` 항상 | 하나: (v2.1, CP-S1) 메타 키와 `noteId`·`pageId`·`deletedAt`을 뺀 나머지 전부(알려진 키로는 `{engineId, sourceRev, lines}`) | (v2.1 정정) 노트 영구 삭제 때 함께. 되살림 근거가 **아니다**(파생 데이터). (v2.1) 편집으로 세지 않는다 — outbox 판정과 영구 삭제 보호의 '최근 보냄'(10분) 모두에서 손글씨만 실린 청크의 범위를 뺀다(SYNC 검토 M-3: 안드로이드 색인기의 업로드가 사용자가 지운 노트를 되살리지 않게) |
| `recording` | 노트 | v1.4 | v1.4 + `{title}` 따로 | v1.4 |
| (모르는 종류) | — | — | — | **보류**(아래) |

- 정렬(`chunk_packer.kindOrder`): `folder, note, page, penPreset, setting, asset, recording, stroke, pageObject, handwriting`.
- 이진 필드(`blobKeys`): 새 종류에는 없다(객체 JSON에 점 배열을 넣지 않는다).
- **모르는 종류 보류(S-13)**: `ChunkCodec`은 모르는 `kind` 기록을 실패시키지 않고 `UnknownKindRecord(kind, rawJson)`로 디코드한다. 다운로드 파이프라인은 같은 청크의 나머지 기록을 적용하고, 모르는 기록만 메타 KV(`sync.heldRecords`)에 보관한 뒤 `SyncIssueCode.needsAppUpdate`를 한 번 낸다. 앱이 갱신되어 그 종류를 알게 되면 보관분을 순서대로 다시 적용한다. 커서는 정상 진행한다(청크를 버리지 않는다). (v2.1, CP-S2 보강) ① 보관 단위는 기록 바이트(헤더 JSON + 이진 필드). ② 한 청크의 모르는 기록은 **전부 보관하거나 전부 표시**한다 — 상한에 걸리면 그 청크는 기록 없이 '되감기 표시'(종류·가장 이른 청크 시각)에만 올리고, 앱 갱신 뒤 커서를 되돌려 통째로 다시 받는다. ③ 보관은 메타 키 여러 개로 나눈다(키당 < 256 KiB, 총 상한 2 MiB). 깨진 값을 읽으면 '모든 종류 되감기 표시'로 바꾼다(비싸지만 잃지 않음). ④ 압축은 모르는 종류 기록이 든 청크를 지우지 않는다. ⑤ 다시 적용은 '로그인 상태로 연결할 때, 받기 전에' 하고, 세션 중복 제거 목록(LRU)에 넣지 않으며, 기존 `sync.held`를 풀지 않는다. 다시 적용 중 미래 시각(K1)에 걸린 기록은 보관에 남겨 다음 연결에서 다시 시도한다(원래 청크의 존재에 기대지 않음).
- 모르는 `type`의 `pageObject`는 CORE가 `UnknownObject`로 받아 저장·동기화하므로 SYNC 입장에서는 일반 기록이다(C-12).
- 에셋: 이미지·오디오는 1차 에셋 파이프라인 그대로(업로드 상한 300 MiB — 64 kbps 3시간 녹음 86 MB에 여유). `recording_drafts`·`search_units`·`search_fts`는 기기 로컬이라 동기화 대상이 아니다.
- SYNC T16 'JSON 키 대조'(1차)를 새 두 종류에도 돌린다. (v2.1, CP-S1) `handwriting`: CORE `toJson` 키 집합 = `FieldUnits.keysOf(kind)`. `pageObject`: 알려진 4종 골든 키의 합집합 = `keysOf(pageObject)`, 각 골든 키 = `kPageObjectTypeKeys[type]`, `unknown`은 키 대조에서 빼고 `SyncDoc` 왕복만 본다(R2-B7a에서). 이후 라운드에 두 종류에 키를 더해도 따로 병합 단위를 만들지 않는다('나머지 전부' 단위에 들어간다 — 판이 다른 앱끼리 승자가 갈리지 않게).

#### 7.2.9 펜 스타일 · 렌더 층 · 페이지 객체 렌더 (1차 7.2.4, 1차 7.2.15, 1차 7.2.16 — ink_engine)

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
| 4′ | (v2.1) ink 위 살아 있는 표시(`inkActive` 끝 — 기본 그림·타일과 무관하게 매 paint) | 재생 흐림·강조(K-7), 자동 도형 보정 미리보기 | — |
| 5 | annotation | `TextBoxObject`, `MathObject`, `UnknownObject` 자리표시 | `compareOrder` |
| 6 | cover | 암기 테이프 획(드러낸 것은 테두리만) | `compareOrder` |
| 7 | overlay | 선택 표시, 올가미, 레이저 자취. (v2.1) 재생 강조·도형 보정 미리보기는 4′로 옮겼다 — overlay에 두면 테이프·텍스트 위에 획 모양이 드러난다 | — |

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
  /// Transient objects drawn with the same renderer (shape tool drag, vertex drag, image being
  /// placed). An entry whose id equals a committed object REPLACES it on screen; the others are
  /// drawn in their L-1 layer. (v2.1) A preview is drawn even when its id is hidden (preview wins
  /// over setHiddenObjectIds). Empty list = none. Never stored, never exported.
  void setPreviewObjects(List<core.PageObject> objects);
  // (v2.1) read-only views of what was set (EDITOR tests observe their own calls — EDITOR M-1)
  Set<String> get hiddenObjectIds;
  List<core.PageObject> get previewObjects;
  InkPlaybackFocus? get playbackFocus;
  // playback (M6)
  void setPlaybackFocus(InkPlaybackFocus? focus);           // null = off (K-7)
  InkStroke? hitTestRecorded(Offset pagePoint, {String? recordingId, double tolerance = 8.0});
  // memorization tape (state per controller, never stored — U10)
  InkStroke? hitTestTape(Offset pagePoint);
  bool isTapeRevealed(String strokeId);
  void toggleTape(String strokeId);
  /// Applies to the tapes present now; tapes that arrive later start covered. (v2.1) EDITOR keeps
  /// the note-level 'show all' and re-applies it after every updateContent. Lifetime = controller.
  void setAllTapesRevealed(bool revealed);
}
@immutable
final class InkPlaybackFocus {
  const InkPlaybackFocus({required this.recordingId, required this.positionMs,
      this.style = InkPlaybackStyle.dimUnwritten, this.recentWindowMs = 2000});
  final String recordingId;
  final int positionMs;                          // audio timeline, same scale as Stroke.recordingOffsetMs
  final InkPlaybackStyle style;
  /// Strokes that started in (positionMs − recentWindowMs, positionMs] get the emphasis outline
  /// (both styles). dimUnwritten also draws unwritten ink-layer strokes at
  /// InkTuning.playbackDimOpacity ((v2.1, CP-INK-8) highlighter / tape strokes are not dimmed —
  /// emphasis outline only). Drawn in layer 4′, never over annotation / cover (K-9).
  /// Strokes of other recordings / without a recording: unchanged.
  final int recentWindowMs;
}
enum InkPlaybackStyle { dimUnwritten, highlightRecent }

// beginStroke (v1.4) + shapeAssist — 추가
StrokeSession beginStroke(InkSample first, {required core.StrokeStyle style,
    required double viewScale, InkStrokeMeta meta = const InkStrokeMeta(),
    ShapeAssist shapeAssist = ShapeAssist.off});
enum ShapeAssist { off, holdToSnap }
// StrokeSession — 추가: after the pen holds still ≥ InkTuning.shapeHoldMs (500) within
// InkTuning.shapeHoldRadiusPx (8 logical px) the session asks inkShapeFitterProvider; a fit
// shows in layer 4′ (v2.1); moving again cancels it; end() then yields InkEdit(addShape).
final class StrokeSession implements InkGestureSession {   // (v2.1 정정) final as in v1.4 — no outside implementations
  /* v1.4 */
  ValueListenable<InkShapeFit?> get shapePreview;
  ShapeAssist get shapeAssist;                   // (v2.1) what beginStroke received
}
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
/// Overridden ONLY through ink_recognition's recognitionOverrides() (7.3.3).
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
  /// (v2.1, INK C-3) Which of removedIds are objects — public optional constructor argument
  /// (default const {}); removedIds keeps every removed id; part of ==. A public-constructed
  /// eraseStrokes with a shape id therefore removes the shape instead of being ignored.
  final Set<String> removedObjectIds;
}
```

| `InkEditKind` | `toCommand()` (v2.0) |
|---|---|
| `addShape` | `core.AddObjects(pageId: …, objects: addedObjects)` |
| `eraseStrokes`, `deleteStrokes` | (v2.1) `removedObjectIds`가 비면 `core.RemoveStrokes`(v1.4), 아니면 `core.RemoveElements(elementIds: removedIds)` |
| `splitStrokes` | (v2.1, CP-INK-2) `removedObjectIds`가 비면 v1.4(`SplitStrokes`), 아니면 `core.CompositeCommand([SplitStrokes(획 조각) 또는 RemoveStrokes, RemoveElements(removedObjectIds)])`(빈 쪽은 뺌) — 한 제스처 = 한 명령 |
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
/// Budget (v2.1, 7.4.5): web — shares the 96 MB raster ledger with the tiles; native 128 MB.
/// Decodes at the display bucket (no full-res decode). (v2.1) Entries drawn by live pictures are
/// counted and not evicted; a request over budget gets the next lower bucket (no evict / re-decode
/// loop); change notices name the asset, so only chunks that draw it are re-recorded. Budgets are
/// InkRenderConfig fields (CP-INK-5: imageCacheBytes, mathRasterCacheBytes).
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
// (v2.1, CP-INK-1) InkFillShape + `final String? objectId` — ShapeObject id for shape pieces (then
//   strokeId = object id, tool = core.PenTool.ballpoint placeholder), null for strokes.
// (v2.1, CP-INK-10) UnknownObject is never exported (screen / thumbnail placeholder only).
// (v2.1, CP-INK-9) PDF awaits InkFonts.ensureLoaded() before export; when fonts are not loaded
//   InkTextVector.lines is empty (→ PDF raster fallback).

// --- math, fonts, text layout: 추가 ---
abstract final class InkMathRenderer {
  /// null = renderable; else a short English error (unknown command …) for the LaTeX editor.
  static String? validate(String latex);
  static InkMathLayout? layout(String latex, {required double fontSizePt});   // size in pt
  /// Offscreen raster (thumbnails, PDF at 300 dpi, screen cache buckets). Web (CanvasKit) safe.
  /// (v2.1) Waits for asynchronously loaded glyph pictures (\sqrt, stretchy arrows / braces —
  /// flutter_svg) before capturing, bounded in count and time; returns null rather than an
  /// incomplete image. Requests are served one at a time. Output ≤ 4 Mpx (7.4.5): pixelsPerPt is
  /// lowered to fit.
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
  // (v2.1) both fail after InkTuning.fontLoadTimeoutMs (5 s) instead of waiting forever;
  // Chrome tests use useInkTestFonts() (7.6 — rootBundle does not answer there)
  static bool covers(String text);              // every char in the bundled subset?
}
abstract final class InkTextLayout {
  /// Height EDITOR writes into TextBoxObject.frame for the given width (same metrics INK paints with).
  static Future<Size> measure(String text, core.TextBoxStyle style, {required double widthPt});
  /// (v2.1) Same value as measure once InkFonts is loaded; null before (EDITOR live drafts).
  static Size? measureSync(String text, core.TextBoxStyle style, {required double widthPt});
  /// (v2.1, CP-INK-3) The paragraph style INK paints with. EDITOR's text editor uses exactly these
  /// with zero inner padding, so the text does not jump when the session ends (E-6).
  static TextStyle textStyleOf(core.TextBoxStyle style);
  static StrutStyle strutStyleOf(core.TextBoxStyle style);   // forceStrutHeight: true, height = lineHeight
  /// (v2.1, CP-PDF-7) Frame-size raster on a transparent background (box background not drawn),
  /// same 4 Mpx cap as InkMathRenderer.rasterize — PDF raster fallback.
  static Future<ui.Image?> rasterize(core.TextBoxObject object, {required double pixelsPerPt});
}
```

- 썸네일(`InkPageThumbnailRenderer`): 이미지 배경·객체를 합성한다. 이미지·글꼴·수식이 2초 안에 준비되지 않으면 `null`(1차 규칙: 호출자는 캐시하지 않고 다시 시도). (v2.1, CP-INK-6) 썸네일 렌더러·`InkPageThumbnail`·컨트롤러는 배경 빌더 목록의 첫 `ImageBackgroundLayerBuilder.images`를 이미지 객체 캐시로 쓴다(목록에 없으면 자리표시 — `pdfIoOverrides()`가 기본 목록을 유지해야 하는 이유). `inkImageCacheProvider`·`defaultPageBackgroundBuilders`는 `core.assetStoreProvider`를 지연으로 읽는다. 텍스트 상자 페이지의 썸네일도 `NoteSans` 적재를 일으킨다(7.4.5 '처음 그릴 때'에 썸네일 포함).
- 웹 캘리그래피: 방위각이 항상 0이므로 `nibAngleDeg` 고정 각만 쓴다. 네이티브 iPad에서 `followBarrelRoll`이 켜져 있고 Pencil Pro 롤(7.2.10 `StylusBarrelRoll`)이 오면, EDITOR가 **펜 다운 순간의 롤 값**을 그 획 스타일의 `nibAngleDeg`에 더해 넘긴다. 획마다 고정 각이 되어 다시 열어도 같은 모양으로 그려지고, 점 코덱 v1(점별 롤 채널 없음)을 바꾸지 않는다(조사 02 9.3 '최근 롤 값 근사').
- (v2.1, CP-INK-7) 레이저 자취 색은 `InkTuning.laserArgb` 고정이고 `StrokeStyle.colorArgb`를 쓰지 않는다(EDITOR 펜 선택기는 레이저 색을 숨김).
- (v2.1, CP-INK-11) 계약이 INK에 맡긴 세부(`InkTuning` 상수, `testing.dart` v2, `MathPreview.onError`의 형 `ValueChanged<String>?`, `InkImageCache` 멤버)는 03-ink 4.10·4.12가 단일 출처다.
- (v2.1) 미리보기·대기 표시의 객체 변형은 CORE `PageObject.transformed(m, scaleWidth:)`를 그대로 쓴다(7.2.2 — 해석기와 같은 함수라 미리보기 = 커밋).

#### 7.2.10 에디터 확장 지점 · 제스처 · 펜 버튼 (1차 7.2.17 — feature_editor)

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

- (v2.1) **자리 콜백의 시작과 `context`**: EDITOR는 `EditorSelectionMenuItem.onSelected`·`EditorInsertMenuItem.onSelected`·`EditorImageImporter.pick`을 사용자 누름 처리(`onPressed`) 안에서 **동기적으로** 부른다 — 돌아온 Future를 기다리는 일과 메뉴·시트 닫기는 그 뒤다. 넘기는 `context`는 메뉴가 아니라 **에디터 본문**의 것이고, 항목이 끝날 때까지 에디터가 열려 있으면 mounted다. 받는 쪽은 브라우저 API(파일 선택 input, `navigator.clipboard.read`·`writeText`)를 첫 `await` 전에 부르고, `ProviderScope.containerOf`·`ScaffoldMessenger`·`Navigator`도 첫 `await` 전에 잡는다. iPad Safari는 사용자 동작 직후에만 선택기·클립보드를 연다 [추측 — 7.8 B-3·B-11에서 확인].
- (v2.1) `isVisible`은 메뉴를 그릴 때마다 불린다 — 가볍게, provider를 읽지 않는다(CP-L5). 그 예외는 항목을 숨기고 보고만 한다(E-7 예외).

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
- Pencil 항목은 `stylusExtrasProvider.capabilities`가 지원할 때만 설정 화면에 보인다. (v2.1) `squeeze`·`barrelRoll` 능력은 OS 가용성(iPadOS 17.5+)일 뿐 펜 종류가 아니다 — 스퀴즈·롤 설정은 그 기기에서 첫 스퀴즈·롤 이벤트를 받은 뒤 보인다(Pencil 2·USB-C 펜슬에서 쓸 수 없는 항목을 숨김, U1).

```dart
// --- stylus extras: 깨짐(구독자 없음) / 추가 ---
// (v2.1, CP-E6) base class gains an optional event time; subclasses pass super.timestamp.
//   sealed class StylusExtraEvent { const StylusExtraEvent({this.timestamp}); final Duration? timestamp; }
//   iOS: same base as PencilEvent.timestamp (systemUptime); null when the source has none.
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
  StylusCapabilities get capabilities;           // (v2.0) read once at app start — (v2.1) a change in
                                                 // iPadOS settings applies on the next app start
  Stream<StylusExtraEvent> get events;           // v1.4
}
```

입력 규칙(E-4, 조사 02 8·10·12.5): **네이티브**에서는 `PointerDownEvent` 자체가 '닿음'이고, **웹**에서는 `buttons & kStylusContact(0x01) != 0`일 때만 닿음이다(웹은 버튼을 누른 채 띄우면 닿기 전에 `down(0x02)`가 온다). 닿는 순간 `buttons & kPrimaryStylusButton != 0`이면 `penButton` 동작, `kind == invertedStylus`이면 `invertedStylus` 동작으로 그 제스처를 시작한다. 띄운 채 버튼만 눌렀다 떼는 토글은 쓰지 않는다(삼성 Air command·엔진이 `ACTION_BUTTON_PRESS`를 넘기지 않음). (v2.1, CP-E4) 웹에서 접촉 중 `buttons & kStylusContact == 0`인 `move`가 오면 그 접촉의 끝이다(이후 다시 닿으면 새 접촉 — 버튼을 누른 채 펜만 떼면 `up` 없이 `move(0x02)`가 온다, 조사 02 8.4).

#### 7.2.11 라이브러리 · 인식 (1차 7.2.18 — feature_library, ink_recognition)

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
  final Float64List ts;                          // Float64List, NOT Int64List (dart2js, 1차 7.4.3 웹 안전 수치)
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
final class RecognizerConsentRequired extends RecognitionFailure {}   // math engine before recog.mathConsent (G-3)
final class RecognizerEngineError extends RecognitionFailure {
  RecognizerEngineError(this.code, this.message); final String code, message; }

abstract interface class HandwritingRecognizer {
  String get engineId;                           // 'mlkit-digital-ink/19.0.0', 'fake'
  bool get isAvailable;                          // false on web
  Future<RecognitionModelState> modelState(String languageTag);
  /// (v2.1) Android honours wifiOnly (the download waits for Wi-Fi); the iOS plugin ignores it —
  /// on iOS the app asks before downloading (two-press warning, 05-library Q2).
  Future<void> ensureModel(String languageTag, {bool wifiOnly = true});
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
/// (v2.1, CP-L7) Lines in reading order, strokes in a line by first-sample time; gapFactor = the
/// horizontal gap that still joins a line ÷ the median glyph-box height; deterministic.
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
  /// (v2.1, CP-L5) Called on every menu build: cheap, reads no provider; never hides just because
  /// no engine is available (7.4.2 '보이되 안내').
  final bool Function(RecognitionTarget target)? isVisible;
}
/// (v2.1, CP-L6) recog.copyText: strokes → recognized text (copy button in the sheet); no strokes
/// and one MathObject → its LaTeX, one TextBoxObject → its text (copied before the first await —
/// 7.2.10 rule).
List<RecognitionAction> recognitionSelectionActions();   // recog.toText, recog.copyText, recog.toMath, recog.editMath
List<RecognitionAction> recognitionInsertActions();      // recog.mathPad

// --- background indexing ---
final class HandwritingIndexer {
  HandwritingIndexer({required core.NoteStore store, required HandwritingRecognizer recognizer,
      required ValueListenable<bool> enabled,
      ValueListenable<bool>? foreground});        // (v2.1, CP-L10) default: AppLifecycleListener
  /// Watches NoteStore.changes (stroke → pageId; (v2.1) handwriting → abandon that page's job and
  /// requeue it), waits for idle (≥ 3 s no local input on that page, 30 s after a remote change),
  /// asks stalePages first (no point decode), recognizes line by line yielding between lines, writes
  /// with HandwritingRepository.update (merged with what is stored — G-4). (v2.1) Fresh = same
  /// sourceRev and language; another engine id / version / device is fresh. Start-up catch-up:
  /// notesWithStalePages(). Never runs on web. dispose() is idempotent.
  void start();
  Future<void> dispose();
  ValueListenable<HandwritingIndexerStatus> get status;
}
// (v2.1, CP-L1) status fields (05-library 4.4.1 — toString() is the one-line overlay form):
enum HandwritingIndexerPhase { off, disabled, waitingModel, idle, waitingInput, recognizing, paused }
@immutable final class HandwritingIndexerStatus {
  const HandwritingIndexerStatus({this.phase = HandwritingIndexerPhase.off, this.languageTag,
      this.queuedPages = 0, this.indexedPages = 0, this.failedPages = 0, this.currentPageId,
      this.lastError});
  final HandwritingIndexerPhase phase; final String? languageTag;
  final int queuedPages, indexedPages, failedPages; final String? currentPageId, lastError;
}
/// (v2.1, CP-L2 = INFRA CP4) Developer overlay lines; same shape as mediaDevOverlayLinesProvider.
final recognitionDevOverlayLinesProvider = Provider<ValueListenable<List<String>>>(/* … */);
final handwritingIndexerProvider = Provider<HandwritingIndexer?>(/* null unless recognizer available */);
class RecognitionSettingsSection extends ConsumerWidget { const RecognitionSettingsSection({super.key}); }
// testing.dart: FakeHandwritingRecognizer, FakeMathRecognizer, SyntheticHandwriting (lines),
//               (v2.1) SyntheticShapes — 7.6
```

- 변환 UI(텍스트 변환 창, 수식 입력 패드, LaTeX 편집 창)는 `ink_recognition` 안의 위젯이고 `RecognitionAction.run`이 띄운다. 수식 입력 패드는 INK `InkPageView`를 저장하지 않는 임시 `core.Page`로 쓰고(1차 `InkPageContent.fromCore` 미리보기 방식), 멈춤 1초 뒤 `MathRecognizer`를 부르며 미리보기는 INK `MathPreview`로 그린다. 엔진이 없으면 LaTeX 직접 입력 + 미리보기만 보인다.
- 혼용 전략: 실기기 실험(7.8 A-4) 전까지 `ko` 단독 + 변환 창 언어 바꾸기(한국어/영어)를 기본으로 하고, 인터페이스는 두 모델 결과 선택(조사 03 3.4 B)을 넣을 수 있게 둔다.
- ML Kit은 `import 'package:google_mlkit_digital_ink_recognition/…' as mlkit;`로만 가져온다(`Ink`가 `material_ui`와, `StrokePoint`가 CORE와 겹친다).
- (v2.1) `HandwritingIndexer`·`PdfSearchIndexer`는 `final class`다. 앱 셸의 시작·종료 시험은 provider override 가짜가 아니라 INFRA 모듈 생성자의 주입 이음새로 한다(7.3.3).

#### 7.2.12 PDF · 미디어 (1차 7.2.19 — pdf_io, media_io)

```dart
// pdf_io — 규칙 / 추가
/// The ONLY override of ink.pageBackgroundBuildersProvider (v1.4 rule kept):
///   [pdfBackgroundLayerBuilder, ...ink.defaultPageBackgroundBuilders(ref)] (+ pdfIoConfigProvider).
List<Override> pdfIoOverrides({PdfIoConfig? config});
/// Library-wide PDF text index (1차 7.8 이후 항목): watches PDF assets / PdfBackground pages,
/// extracts with PdfTextService, writes core.SearchIndexWriter (source pdf, rects as page
/// fractions). Skips owners whose sourceRev is current. Idle-time, one PDF page per slice.
/// (v2.1) Pauses while SearchIndex.status.rebuilding is true (drops its queue) and re-judges every
/// asset afterwards. The public constructor stays as below — CP-PDF-1 rejected: the document pool
/// and the schedule gate are injected inside pdf_io (provider / src-only factory), no new public
/// type. dispose() is idempotent.
final class PdfSearchIndexer {
  PdfSearchIndexer(core.NoteStore store);
  void start();
  Future<void> dispose();
}
final pdfSearchIndexerProvider = Provider<PdfSearchIndexer>(/* started by INFRA PdfModule */);
// Export (06-pdf 6.11 확장, 내부): order = InkPageVectors L-1; ImageObject / image background →
// PDF image object (JPEG inline, PNG via bitmap); TextBoxObject → text object with embedded
// InkFonts.noteSans (searchable; falls back to raster when InkFonts.covers(text) is false, font
// loading fails or (v2.1, CP-PDF-8) InkTextVector.lines is empty; a text box background is a
// vector rect under the text); MathObject → raster 300 dpi (U17); tape → covered; laser → none.
// (v2.1) Every raster and image decode ≤ 4 Mpx (16 MiB RGBA, 7.4.5) — dpi / target size lowered.
```

```dart
// package:media_io/media_io.dart — web-safe entry
Future<void> initializeMediaIo({MediaIoConfig config = const MediaIoConfig()});   // idempotent
@immutable
final class MediaIoConfig {
  const MediaIoConfig({this.bitRate = 64000, this.sampleRate = 44100, this.allowNonAacOnWeb = true,
      this.webDraftChunkMs = 1000, this.androidForegroundService = true});
  final int bitRate;                             // AAC-LC mono (U8)
  final int sampleRate;
  final bool allowNonAacOnWeb;                   // Chrome: opus/webm with a warning (crossPlatformPlayable false)
  final int webDraftChunkMs;                     // web: MediaRecorder timeslice; each chunk appended to RecordingDraftStore (loss ≤ 1 s)
  final bool androidForegroundService;           // microphone FGS while recording (M6-2)
}
/// Overrides core.audioRecorderServiceProvider and core.audioPlaybackServiceProvider.
List<Override> mediaIoOverrides({MediaIoConfig? config});

/// EditorImageImporter parts (INFRA wraps them).
Set<core.ImageImportSource> supportedImageSources();          // web: photos, camera, files (+ clipboard when navigator.clipboard.read exists)
/// Pick → decode → downscale to ImageImportLimits → re-encode (JPEG for photos, PNG when alpha)
/// → AssetStore.put(type: image). null = cancelled (or a handled error shown as a message).
/// (v2.1) Opens the system picker / clipboard read before its first await (7.2.10 rule); a long
/// normalization shows a preparing sheet (showModalBottomSheet — CP-PDF-11) after the pick.
/// Works without initializeMediaIo (image import is outside FEATURE_MEDIA — D17).
Future<core.ImportedImage?> importImageForNote(BuildContext context, core.ImageImportSource source);

/// Recording + playback panel for EditorExtensions.recordingPanel (INFRA adapts EditorPanelContext).
/// Record / pause / stop, recordings list (rename, delete, size), play / pause, ±10 s, speed
/// 0.5–2.0, scrubber, tap-to-seek toggle, consent notice on first record (F-16), web hidden-tab notice,
/// '복구된 녹음' badge on recordings made by recoverDraft().
class RecordingPanel extends ConsumerWidget {
  const RecordingPanel({super.key, required this.noteId, required this.tapToSeek,
      required this.onTapToSeekChanged, required this.onClose});
  final String noteId; final ValueListenable<bool> tapToSeek;
  final ValueChanged<bool> onTapToSeekChanged; final VoidCallback onClose;
}
/// Developer overlay lines: encoder support table, last recording MIME / duration / clock error (R-3).
final mediaDevOverlayLinesProvider = Provider<ValueListenable<List<String>>>(/* … */);
// testing.dart — 7.6 (v2.1: no MockPlatformInterfaceMixin; platform fakes are VM-only)
```

media_io 내부 결정(계약 아님, PDF 계획서에서 상세): 네이티브는 `record`(AAC-LC/m4a, 모노, `manageAudioSession(false)`) + `audio_session`으로 세션을 혼자 관리, 안드로이드는 `flutter_foreground_task`의 microphone 서비스(`*_native.dart`), 재생은 `just_audio`(네이티브 `setFilePath` — 에셋을 캐시 파일로, 웹 `setUrl(blob:)`). 웹 녹음은 처음부터(P-A, D13) MediaRecorder 조각을 `RecordingDraftStore`에 1초마다 쓰는 자체 녹음기(`*_browser.dart`, 약 300줄 — `record_web`의 MediaRecorder 위임 코드를 참고, `isTypeSupported`로 MIME 선택 — Safari AAC/mp4 우선, Chrome opus/webm + WebM 길이 보정)다. `record`는 네이티브에서만 부른다(`record_web`은 빌드에 들어가지만 웹 녹음에 쓰지 않는다). 탭이 닫혀(또는 앱이 죽어) 남은 초안은 다음 실행 때 앱 시작 뒤 유휴 시간에 INFRA `MediaModule`이 `audioRecorderServiceProvider`의 `pendingDrafts()` → 각각 `recoverDraft()`로 **묻지 않고** 녹음으로 만든다(media_io가 제목을 '복구된 녹음'으로 넣음). 필요 없으면 사용자가 녹음 목록에서 지운다. (v2.1) 복구 대상 판단은 `pendingDrafts()`만 따른다(진행 중 세션·최근 갱신 초안 제외 — 7.2.4). media는 초안마다 복구 시도 횟수를 기기 설정 `media.recoverAttempts`에 **시도 전에** 기록하고, 끝나지 않은 시도가 2번 쌓인 초안은 자동 복구에서 빼 패널·개발자 표시에 '복구하지 못한 녹음이 있어요'로 알린다(큰 복구가 매 실행 탭을 죽이는 반복 방지). 영구 실패(노트가 영구 삭제됨 등)는 분류해 정리한다. 정지·복구는 같은 바이트를 전체 크기로 여러 벌 들지 않는다(M-4). 웹 정지 저장이 끝내 실패하면 마지막 수단으로 '파일로 내려받기'를 보인다(D19). 같은 출처의 다른 탭이 진행 중 녹음을 건드리지 못하게 녹음하는 탭은 가능하면 Web Locks(`noteapp-rec-<draftId>`)를 쥔다(없으면 시각 규칙만). 웹에서 `visibilitychange`로 가려지면 먼저 `pause()`하고 `interrupted = true`, 녹음 중에는 Screen Wake Lock을 건다.

#### 7.2.13 펜슬 플러그인 (pencil_bridge) · 서버 함수 (functions/)

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
             //   (v2.1, CP-L8) x, y: page pt with 1 decimal; t: integer ms from the first
             //   sample of the first stroke
             pngBase64?: string (≤ 2 MB), locale?: 'ko' | 'en' }
  out    : { latex: string, confidence?: number, alternatives?: string[],
             engine: string, engineVersion: string, ms: number }
           (v2.1) engineVersion = the engine / model that actually answered (a server-side
           fallback may switch models — taken from the engine response, fallback logged)
  errors : unauthenticated | permission-denied | invalid-argument | resource-exhausted
           (daily cap per uid, Firestore counter) | unavailable | internal
  rules  : (v2.1, CP-S3) engine omitted = 'auto' = server MATH_ENGINE; 'fake' only where
           ALLOW_FAKE_ENGINE (demo project); v ≠ 1 → invalid-argument; unknown input keys ignored;
           input the engine cannot take (strokes only, image engine) → invalid-argument;
           unavailable = engine not configured / temporarily down (engine 429 included — not
           resource-exhausted); internal = unreadable or refused engine response.
           (CP-S6) daily counter in top-level Firestore `fnQuota` (TTL expireAt, clients denied by
           default — no rules file change); the default emulator run uses QUOTA_STORE=memory.
  App Check: enforceAppCheck false this round (sideloaded APK cannot pass Play Integrity).
tool   : functions/tool/math_eval.ts — reads fixtures (stroke JSON + expected LaTeX), calls each
         engine with keys from developer env vars, writes the 03-recognition 6.6 score table.
```

앱 쪽 `CallableMathRecognizer`(ink_recognition)는 `package:http`로 callable 규약(`{"data": …}` + `Authorization: Bearer`)을 직접 구현한다 — `cloud_functions`(Firebase 네이티브 SDK)를 이번에 넣지 않아 iOS 혼합 모드 위험을 피한다(3.3). 실연결 미니 라운드에서 `cloud_functions 7.0.1`로 바꿀지 다시 정한다.

### 7.3 영역 간 인터페이스 목록

#### 7.3.1 제공 → 소비 (1차 7.3.1의 X1~X17 뒤에 더함)

| # | 제공 | 소비 | 인터페이스 | 핵심 규칙 |
|---|---|---|---|---|
| X18 | CORE | EDITOR | `PageObject` 계열, `AddObjects`·`UpdateObjects`·`RemoveElements`·`ClearPage.includeObjects`, `PageContent.objects` | 7.2.3 명령 매핑, C-11 |
| X19 | CORE | EDITOR, media | 오디오 포트(`audioRecorderServiceProvider`·`audioPlaybackServiceProvider`), `RecordingRepository`, `noteRecordingsProvider` | R-1~R-8, M-1·M-2 |
| X20 | CORE | media | `AssetStore.put(audio/image)`, `RecordingRepository.createRecording`, `RecordingDraftStore`, `ImageImportLimits` | 에셋 먼저, 녹음 행은 그 뒤(M-1) |
| X21 | CORE | LIBRARY | `LibrarySearchResult.pages`, `PageSearchHit` | 결과를 그대로 표시(1차 L-1) |
| X22 | CORE | recog | `HandwritingRepository`(`stalePages`·`put`·(v2.1) `update`·`notesWithStalePages`), `HandwritingText.sourceRevOf`·`isRecognitionInput`, `NoteStore.changes` | 웹에서는 쓰기 없음 |
| X23 | CORE | PDF | `SearchIndexWriter`(source pdf), `PageContent.objects`, 이미지 에셋 | 사각형은 PDF 페이지 비율 좌표 |
| X24 | CORE | SYNC | `EntityKind.pageObject`·`handwriting`, JSON(7.2.7), outbox 힌트, `UnknownObject` | 7.2.8 매핑, S-13 |
| X25 | INK | EDITOR | 객체 렌더·`select`·`hitTestObject`·`setHiddenObjectIds`, `ShapeAssist`·`shapePreview`, `InkEdit` v2, `setPlaybackFocus`·`hitTestRecorded`, 테이프 API, `InkTextLayout`, `MathPreview`, `InkFonts` | K-6~K-9 |
| X26 | INK | PDF | `InkPageVectors` v2, `InkMathRenderer.rasterize`, `InkFonts.noteSansBytes`, `defaultPageBackgroundBuilders` | L-1 순서로 그린다 |
| X27 | INK | recog | `InkShapeFitter`(구현), `MathPreview`, `InkPageView`(수식 패드), `InkMathRenderer.validate` | |
| X28 | media | INFRA → CORE | `mediaIoOverrides()` | 오디오 provider의 유일한 override |
| X29 | media | INFRA → EDITOR | `supportedImageSources`·`importImageForNote` → `editorImageImporterProvider`; `RecordingPanel` → `EditorExtensions.recordingPanel`; `mediaDevOverlayLinesProvider` → `DevOverlaySection` | INFRA가 감싼다(1차 X14와 같은 방식) |
| X30 | recog | INFRA → EDITOR | `recognitionSelectionActions`·`recognitionInsertActions` → `EditorSelectionMenuItem`·`EditorInsertMenuItem` | `RecognitionTarget` ↔ 에디터 문맥 1:1 변환. (v2.1, CP13·CP-L3) `done`: 삽입 문맥 = `execute`로 마지막에 추가된 객체를 `selectObject`(없으면 아무것도 안 함), 선택 문맥 = `clearSelection` — recog는 바꾸기(toText·toMath) 뒤에만 부른다 |
| X31 | recog | INFRA → INK | `recognitionOverrides()` 안의 `inkShapeFitterProvider` override | `inkShapeFitterProvider`의 유일한 override |
| X32 | recog | INFRA | `recognitionOverrides`, `handwritingIndexerProvider`(시작·종료), `RecognitionSettingsSection` | 설정 화면 '인식' 섹션 |
| X33 | PDF | INFRA | `pdfSearchIndexerProvider`(시작·종료), `pdfIoOverrides` v2 | |
| X34 | LIBRARY | INFRA | `LibraryScreen.onOpenNoteAt` → `AppRoutes.note(noteId, pageId: , focus: )` → `EditorScreen.initialFocusRectPt` | 주소 `?page=<id>&focus=l,t,r,b` |
| X35 | pencil_bridge | INFRA → EDITOR | `PencilBridge.events`·`capabilities` → `PencilStylusExtrasSource` → `stylusExtrasProvider` | 웹·안드로이드는 `NoStylusExtras` 그대로 |
| X36 | functions/ (SYNC) | recog | `recognizeMath` callable 형식(7.2.13) | 형식 바꿀 때 1차 7.4.12 절차 |

#### 7.3.2 동작 보장 추가 (1차 7.3.2)

| # | 주체 | 보장 |
|---|---|---|
| K-6 | INK | 모든 `PageObject`의 렌더 외곽 ⊆ CORE `bounds`. 텍스트는 frame으로 자르고, 수식은 frame 안에 contain으로 맞추고, 도형은 둥근 이음·캡으로 `strokeWidth·0.75` 안에 그린다. 새 펜 5종도 1차 K-1을 지킨다(불변식 시험에 추가) |
| K-7 | INK | `setPlaybackFocus`가 바뀌어도 기본 래스터 타일을 다시 만들지 않는다. 다시 그리는 비용은 '쓴/안 쓴' 경계를 넘은 획 수에 비례한다(재생 중 매 프레임 호출해도 됨) |
| K-8 | INK | 그리기 순서 = L-1. 화면·썸네일·벡터 내보내기가 같은 순서다 |
| K-9 | INK | 레이저 획은 `InkEdit`을 만들지 않는다(1차 E-3 보장의 INK 쪽). 테이프 드러냄 상태는 저장하지 않고, 썸네일·벡터 내보내기는 항상 가린 상태다. (v2.1) 화면의 재생 흐림·강조와 도형 보정 미리보기도 가린 테이프와 annotation 층(텍스트·수식)의 픽셀을 바꾸지 않는다(층 4′) |
| C-11 | CORE | `TransformElements`는 획과 객체를 한 커밋으로 바꾼다. `UpdateObjects`는 값이 바뀐 JSON 키만 새 필드 버전을 받는다 |
| C-12 | CORE | `UnknownObject`는 읽은 JSON을 키 하나 빠짐없이 그대로 쓴다(동기화·백업 왕복 시험) |
| C-13 | CORE | 검색 색인은 파생 데이터다: `rebuild()`는 멱등이고, 색인이 비어 있어도 원천 데이터로 다시 만든다. 색인 실패는 원천 쓰기를 실패시키지 않는다(같은 커밋에서 색인 쓰기만 미루고, (v2.1) CORE의 다음 쓰기 트랜잭션 또는 저장소 열기 때 다시 한다 — 타이머 없음. 남은 보류는 `status.pendingOwners`로 보인다) |
| C-14 | CORE | 마이그레이션 v1 → v2는 1차 데이터(노트·페이지·획·에셋·설정·outbox)를 바꾸지 않는다(V7) |
| E-4 | EDITOR | 펜 접촉·버튼 판정 규칙(7.2.10). 웹에서 공중 `down(0x02)`로 획·지우기가 시작되지 않고, (v2.1) 접촉 비트가 빠진 `move`는 그 접촉의 끝이다 |
| E-5 | EDITOR | 펜 다운 시 R-1 규칙으로만 `InkStrokeMeta`를 채운다. `offsetNowMs()`는 펜 다운 이벤트 처리 안에서 동기적으로 읽는다 |
| E-6 | EDITOR | 텍스트 상자 편집 세션(포커스 들어옴 → 나감) 1회 = 명령 1회 = 되돌리기 1단계. 편집 중에는 INK에서 그 상자를 숨긴다(`setHiddenObjectIds`) |
| E-7 | EDITOR | 자리(선택 메뉴·삽입 메뉴·녹음 패널·이미지 가져오기)가 비어 있으면 해당 UI를 숨긴다(자리표시 안내 없음). 자리 콜백의 예외는 `FlutterError.reportError` 후 사용자 문구로 보인다. (v2.1) 예외: 보이기 판정(`isVisible`)의 예외는 그 항목을 숨기고 보고만 한다(메뉴를 그릴 때마다 문구가 뜨지 않게). 자리 콜백은 누름 처리 안에서 동기적으로 시작하고 에디터 본문 `context`를 받는다(7.2.10) |
| M-1 | media | `stop()`은 에셋(`AssetStore.put`)을 먼저 쓰고 그다음 `createRecording`을 부른다. `offsetNowMs()`는 한 녹음 안에서 단조 증가하고 일시정지 구간을 빼며, `durationMs`는 파일 안 타임라인 길이다(R-2·R-3). (v2.1) 저장(`put`·`createRecording`)에 실패하면 초안을 지우지 않고 예외로 끝난다 — 다음 실행 복구가 같은 `recordingId`로 마무리한다 |
| M-2 | media | 웹에서 탭이 가려진 동안 녹음하지 않는다: 가려지는 즉시 `pause()`(`interrupted = true`), 돌아와도 자동 재개하지 않는다. 녹음 중 Screen Wake Lock. 웹 녹음 조각은 `webDraftChunkMs`(1초)마다 `RecordingDraftStore.append`로 쓰고, 탭이 닫히거나 새로 고침되면 다음 실행 때 INFRA가 `pendingDrafts()` → `recoverDraft()`로 **묻지 않고** 녹음으로 만든다(7.2.12 — 잃는 것은 마지막 1초 이하). (v2.1 정리) 돌아왔을 때의 '이어서 녹음할까요?' 안내(7.4.2)는 가려짐 일시정지에 대한 것이고 복구와 다르다 |
| M-3 | media | 이미지 에셋은 `ImageImportLimits`를 지킨다(긴 변 2048 px, 8 MiB, JPEG/PNG만) |
| M-4 | media | (v2.1) 웹 녹음의 `durationMs`는 파일 안 타임라인(WebM 블록 타임코드)에서 계산한다(R-3). 정지·복구는 같은 녹음 바이트를 전체 크기로 두 벌 넘게 동시에 들지 않는다(앞 단계 버퍼를 버리고, (v2.2, C22-05 — CP-PDF-13) 길이 보정은 머리만 새로 만들어 원본 나머지와 한 번 복사해 합친 뒤 원본을 바로 버린다 — `AssetStore.put`이 연속한 `Uint8List` 한 벌을 받으므로 그 순간만 두 벌). 다른 탭이 녹음 중인 초안을 복구하지 않는다(7.2.4 `pendingDrafts`) |
| G-1 | recog | 웹에서 ML Kit을 부르지 않는다(조건부 import + `RecognizerUnsupported`). 인식 실패는 EDITOR로 예외를 던지지 않고 recog 자기 창에서 문구로 보인다 |
| G-2 | recog | 색인기는 사용자가 쓰는 페이지를 방해하지 않는다: 마지막 입력 3초 뒤, 한 번에 한 줄, 앱이 뒤로 가면 멈춘다. (v2.1) 먼저 `stalePages`로 낡았는지 보고(점 디코드 없음) 낡았을 때만 페이지를 읽고, 줄 사이마다 양보한다 |
| G-3 | recog | 외부 수식 엔진 호출(`CallableMathRecognizer`)은 설정 `recog.mathConsent`(synced, 기본 false)가 true일 때만 한다(D15). 동의 전에는 `RecognizerConsentRequired`로 끝나고 수식 입력 패드는 동의 안내 + LaTeX 직접 입력을 보인다. 보내는 것은 사용자가 고른 수식 영역의 획(엔진이 이미지를 받으면 그 영역 PNG)뿐이다 |
| G-4 | recog · CORE | (v2.1) 손글씨 결과의 로컬 쓰기(색인기·변환 창)는 `HandwritingRepository.update`로 저장된 값과 한 트랜잭션에서 병합한다 — 그 사이 들어온 확정 줄·원격 결과를 덮지 않는다. 변환 창의 복사 경로는 `NoteStore.flush()` 뒤 `loadPage`로 방금 쓴 획까지 본다. 확정 줄 유지 규칙은 7.2.5 `userConfirmed` 주석 |
| S-13 | SYNC | 모르는 `kind` 기록은 그 기록만 보류하고 같은 청크의 나머지는 적용한다. 보류분은 앱 갱신 뒤 다시 적용된다. (v2.1) 보류는 청크 단위 전부/전무이고 넘치면 되감기 표시다 — 어느 경로로도 기록을 잃지 않는다(7.2.8) |
| F-1 | SYNC(functions) | 외부 API 키는 Secret Manager(에뮬레이터는 `.secret.local`)에만 있고 앱·저장소에 없다. 로그인 + 소유자 UID 목록 밖 호출은 거절한다 |

#### 7.3.3 앱 셸 연결(override) 추가 행 (1차 7.3.3)

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

override가 아닌 연결: `MediaModule`이 앱 시작 뒤 유휴 시간에 남은 녹음 초안을 복구하고(7.2.12, M-2), `PdfModule`이 `pdfSearchIndexerProvider`를, `RecognitionModule`이 `handwritingIndexerProvider`를 앱 시작 뒤 유휴 시간에 `start()`하고 종료 때 `dispose()`한다. 라우터는 `LibraryScreen.onOpenNoteAt`을 `AppRoutes.note(noteId, pageId:, focus:)`로 잇는다.

(v2.1, CP15 수정) **시점과 순서**: 녹음 이탈 경고(웹 `beforeunload`)는 유휴 작업이 아니라 시작 성공 화면 직후 바로 건다(구독 하나라 비용이 없다). 유휴 작업은 루트 화면 첫 프레임 3초 뒤, 앱이 보일 때(생명 주기 `resumed`·`inactive`·값 없음 — `hidden`·`paused`·`detached`면 기다림; 웹은 창 `blur`에도 `inactive`를 보낸다), 한 번에 하나씩 **데이터 보호 먼저**: `media.recoverDrafts` → `pdf.searchIndexer` → `recognition.indexer`. 종료는 scope가 사라질 때 역순이고 색인기 `dispose()`는 멱등이다. 시간 초과 뒤 늦게 끝난 비필수 모듈의 기여는 버리고 기록한다.

(v2.1) **시험 이음새**: 두 색인기는 `final class`라 provider override로 가짜를 넣지 않는다. 앱 셸 시험은 INFRA 모듈 생성자의 주입 인자(시작·종료 함수)로 횟수를 보고, 실제 색인기는 가짜 저장소로 '두 번 `dispose`해도 안전'만 본다. 앱 스모크(V5·V6)의 녹음기·재생기·이미지 선택기·인식기·수식 엔진 가짜도 모듈 주입 인자로 넣고, override의 출처·횟수는 실제 모듈 경로로 확인한다(Riverpod는 같은 provider 두 번 override를 막는다).

모듈 순서(v2.0): `core` → `pdf`(비필수) → `media`(비필수) → `recognition`(비필수) → `featureWiring` → (실연결) `sync`. '비필수' 모듈이 시작에 실패하면 그 기능만 꺼지고 앱은 뜬다(1차 PDF 규칙과 같음).

기능 스위치(D14, PLAN 7.6): INFRA `AppFeatures`가 `--dart-define=FEATURE_MEDIA=false`·`FEATURE_RECOGNITION=false`·`FEATURE_MATH_ENGINE=false`(기본 모두 true)와 개발자 메뉴 값을 읽어, 꺼진 모듈은 **시작하지도 연결하지도 않는다**(위 표의 해당 행 override 없음 → 각 자리의 기본값 '숨김·지원 안 함'). `FEATURE_MATH_ENGINE=false`는 `RecognitionConfig.mathEndpoint`를 null로 둔다(수식 객체·LaTeX 직접 입력은 남음). 유료가 될 기능은 이 스위치로 켜고 끈다. (v2.1, D17) `FEATURE_MEDIA=false`는 **녹음만** 끈다(오디오 override·녹음 패널·초안 복구·이탈 경고). `editorImageImporterProvider`(이미지 삽입·이미지 페이지 — P-A)는 스위치와 무관하게 연결한다(`importImageForNote`는 `initializeMediaIo` 없이 동작). `FEATURE_RECOGNITION=false`는 `recognitionOverrides()`를 빼므로 자동 도형 보정도 꺼진다(`inkShapeFitterProvider` 기본 `NoShapeFitter` — EDITOR는 그때 보정 토글을 숨김).

### 7.4 공통 규칙 (1차 7.4에 더함)

#### 7.4.1 네이티브 플러그인 · 플랫폼 분기 (1차 7.4.3 확장)

- **네이티브 전용 플러그인**은 `*_native.dart`에서만 import하고 조건부 import로 고른다. `workspace_rules.yaml` `native_only_imports`에 더한다: `package:google_mlkit_digital_ink_recognition/`, `package:google_mlkit_commons/`, `package:flutter_foreground_task/`, `package:path_provider/`. (조사 04 7절: 이 플러그인들은 웹으로 **컴파일은 되지만** 부르면 `MissingPluginException`이므로 경계는 컴파일러가 아니라 규칙으로 지킨다.)
- **웹 구현이 있는 플러그인**(`record`, `just_audio`, `audio_session`, `image_picker`)은 일반 파일에서 써도 되지만, 서비스 패키지(`media_io`) 밖으로 나가지 않는다. 피처 패키지의 pubspec에 플러그인을 넣지 않는다(새 규칙 R16 — (v2.1 정정) `plugin_free_members` = `feature_editor`·`feature_library`·`ink_engine`·`note_core`(CP7) + `pdf_io`·`sync_engine`의 직접 의존에 `plugin_packages`가 없다. 기존 예외는 `pdf_io`의 `file_picker`(1차 `pdf_io`가 직접 의존하는 플러그인은 이것뿐 — `pdfrx`·`pdfium_dart`는 pubspec에 `flutter: plugin:`이 없다)와 `sync_engine`의 Firebase 플러그인. `plugin_packages`는 앱이 해석한 플러그인 **전부**(웹 전용 `record_web`·`just_audio_web`·`image_picker_for_web`, 간접 `shared_preferences_*`, dev `integration_test` 포함)이고 `ws native-reqs`가 `.flutter-plugins-dependencies`의 **`dependencyGraph` 이름 집합**과 같은지 검사한다 — 목록 누락이 위반으로 드러난다. (v2.2, C22-03 — INFRA CP17) `plugins.<플랫폼>` 목록은 비교 대상이 아니다 — 플랫폼 구현 패키지만 들어 있고 앱용 패키지 `file_picker`·`path_provider`·`url_launcher`가 없다(1차 통합 HEAD `app/.flutter-plugins-dependencies` 확인)).
- 플랫폼 판정은 `kIsWeb` + `defaultTargetPlatform`만 쓴다. `dart:io` `Platform`은 `*_native.dart` 안에서도 쓰지 않는다(조사 02: `apple_pencil_double_tap`의 `Platform.isIOS`가 웹에서 예외). UI는 플랫폼을 직접 묻지 않고 서비스의 능력(`checkSupport()`, `isAvailable`, `capabilities`, `supportedImageSources()`)을 묻는다.
- 이름 충돌: ML Kit은 `as mlkit` 접두어 필수(`Ink`↔`material_ui`, `StrokePoint`↔CORE). `rendering.dart`의 `SelectionGeometry` 규칙(v1.4 C14-01)은 그대로.

#### 7.4.2 웹 대체 동작 (iPad Safari)

| 기능 | 웹에서의 동작 |
|---|---|
| 백그라운드 녹음 | 가려지면 자동 일시정지 + 돌아오면 '녹음이 멈췄어요. 이어서 녹음할까요?' 안내(M-2). 녹음 중 화면 꺼짐 방지 |
| AAC를 못 내는 브라우저(데스크톱 Chrome) | opus/webm으로 저장하고 녹음 목록에 '아이패드 앱에서는 재생되지 않을 수 있어요' 표시(`crossPlatformPlayable = false`) |
| 손글씨 인식 | 선택 메뉴 '텍스트로 변환'은 보이되 누르면 '이 기기(웹)에서는 손글씨 인식을 쓸 수 없어요. 안드로이드 앱에서 쓸 수 있어요.' 손글씨 색인은 만들지 않는다(텍스트 상자·PDF·수식 검색은 됨) |
| 수식 인식 | 엔진이 없으면 LaTeX 직접 입력 + 미리보기만 |
| Pencil 더블탭·스퀴즈·롤·호버 높이 | 설정 항목 숨김, 캘리그래피는 고정 각 |
| S펜 버튼(안드로이드 Chrome) | 접촉 비트 판정으로 동작(E-4) |
| 이미지 붙여넣기 | `navigator.clipboard.read`가 있을 때만 메뉴. 카메라는 file input `capture`. (v2.1) 선택기·클립보드는 누름 처리 안에서 동기적으로 연다(7.2.10) |
| 같은 출처를 탭 두 개로 열기 (v2.1) | 범위 밖(안내 — D19). 다만 다른 탭이 진행 중인 녹음 초안을 복구하지 않고, 그 초안에 쓰기가 거절되면(`StateError`) 녹음을 멈추고 '다른 창에서 이 녹음을 정리했어요'로 알린다 |

#### 7.4.3 권한

- `permission_handler`는 넣지 않는다(조사 02 7.2, 04 5절). 마이크는 `record.hasPermission(request: true)`, 안드로이드 13+ 알림(포그라운드 서비스)은 `flutter_foreground_task`, 사진은 시스템 선택기(권한 대화상자 없음)로 받는다.
- 거절·영구 거절은 해요체 문구 + '설정 → 필기노트 → 마이크' 안내로 처리한다(설정 앱 열기 버튼 없음).
- Info.plist·매니페스트 키는 INFRA 소유다. 플러그인을 쓰는 영역은 필요한 키를 계획서 7절에 적고 INFRA가 기반 단계에서 넣는다: iOS `NSMicrophoneUsageDescription`, `UIBackgroundModes: [audio]`, `NSPhotoLibraryUsageDescription`, `NSCameraUsageDescription`, `ITSAppUsesNonExemptEncryption = false`, 배포 대상 15.5(3곳) + `Podfile`(`platform :ios, '15.5'`, ML Kit `post_install`). 안드로이드 `main` 매니페스트 `INTERNET`(지금 debug·profile에만 있음), `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MICROPHONE`, `POST_NOTIFICATIONS`, microphone 서비스 선언, 라벨 `필기노트`, 부팅 수신기 제거(`tools:node="remove"`). (v2.1) 문구는 INFRA 것으로 확정한다 — `NSPhotoLibraryUsageDescription` = "사진을 노트에 넣으려면 사진 보관함에 접근해야 해요."(PDF 부록 B의 제안 문구를 이것으로 맞춘다). 안드로이드 `android:allowBackup="false"`(D20).

#### 7.4.4 ID · 설정 키 · 문구 (1차 7.4.6, 1차 7.4.5)

- ID 규칙 예외 추가: `HandwritingText.idFor(pageId) = 'hw_' + pageId`(결정적 id). 녹음 id는 녹음 시작 전에 `idGeneratorProvider`로 만든다.
- 설정 키 접두사 추가: `media.*`(PDF 영역), `recog.*`(LIBRARY 영역), (v2.1, CP12) `app.*`(INFRA — `app.features.*`, `device`). 외부 수식 엔진 전송 동의 `recog.mathConsent`(bool, 기본 false, `synced` — D15·G-3).
- (v2.1) 키 확정: **recog**(CP-L9) `recog.language`(synced, 'ko')·`recog.mathConsent`(synced, false)·`recog.autoIndex`(device, (v2.9) **true** — C29-01)·`recog.modelWifiOnly`(device, true) — 별도 '인식 켜기' 키는 없다(기능 전체는 `FEATURE_RECOGNITION`). **EDITOR**(CP-E7) `editor.toolOptions`(synced), `editor.playback.preRollMs`(synced, 정수 키 — 1차 `jsonMap` 관례의 예외), 탭 재생 켬 = `editor.settings.device`의 `tapToSeek`(패널은 `EditorPanelContext`로만 읽고 쓴다). **media** 녹음 비트레이트(synced), 녹음 동의 안내 본 여부(device), `media.recoverAttempts`(device — 초안별 복구 시도 횟수, 7.2.12). 제스처 동작 매핑은 1차 `editor.settings.synced`의 `gestures` 안(`synced`).
- 녹음 동의 안내 문구(F-16, 고정): "다른 사람의 목소리를 녹음할 때는 미리 동의를 받아 주세요." — 바꿀 때 1차 7.4.12 절차.

#### 7.4.5 글꼴 · 웹 예산 · 메모리 (1차 7.4.9, 1차 7.4.10)

- 텍스트 상자 글꼴 `NoteSans`는 INK 패키지 에셋(한글 KS X 1001 2,350자 + 라틴 부분 집합, 보통·굵게 — 사용자 질문 U7)이고, `FontManifest`에 넣지 않아 **웹 첫 로드에 내려받지 않는다**(텍스트 상자를 처음 그릴 때 `InkFonts.ensureLoaded`). 라이선스(OFL) 고지는 INFRA 앱 정보 화면.
- KaTeX 글꼴(`flutter_math_fork`, 20개, gzip 371 KB)은 패키지가 `fonts:`로 선언해 웹 시작 때 모두 내려받는다. 이번에는 받아들이고 예산표에 올린다(U15). 초과하면 포크해 지연 적재. (v2.1) 시작 글꼴 한도(지금 400,000 B까지 여유 약 22 KB)는 묶음별(KaTeX / 아이콘)로 R2-B8 뒤 첫 실측(INFRA J0)에서 정한다.
- (v2.1) 웹 크기 예산의 기준은 1차 통합 빌드 실측이다(`main.dart.js` 4,633,843 B, gzip 1,366,038 B — 1차 INFRA 진행 기록 G4). 2차 한도는 '기준 + 300 KB(gzip)'로 시작하고 J0 실측 뒤 다시 정한다. (v2.7, C27-01) 2차 통합 빌드 실측(통합 끝 `42b01c7` — gzip 1,902,969 B, 원본 6,477,160 B — 한도 1,666,038 B 초과)으로 **기준을 이 빌드로 옮기고** `main.dart.js` 한도를 gzip 2,000,000 B로 정한다(라운드당 증가 300 KB 규칙은 새 기준에서 그대로). 첫 적재에서 녹음·인식·수식·PDF 내보내기를 빼는 `deferred` import는 3라운드 후보(iPad 첫 실행 실측 뒤 판단).
- (v2.1) 글꼴 파일·녹음 표본·DB 고정 자료는 `.gitattributes`에 `binary`(INFRA — `*.ttf`·`*.otf`·`*.webm`·`*.m4a`·`*.sqlite`). INK는 `flutter: assets:`에 파일 단위로 적는다(`NoteSans` 두 파일 + `OFL.txt` — 글꼴 폴더의 README는 앱 자산에 넣지 않는다).
- 웹 예산표(INFRA 6.13)에 추가 측정: `main.dart.js` 증가분, 시작 때 받는 글꼴 바이트, `record_web` 워크릿 JS(빌드에는 들어가지만 웹 녹음에 쓰지 않음 — D13). 텍스트 글꼴이 `FontManifest.json`에 없는지(지연 적재) 확인한다.
- 메모리 예산(1차 7.4.10) — (v2.1, D22) 2차 항목(이미지 48 + 수식 8 + 내보내기 임시 16 + 녹음 조각 8)을 1차 표(272 MB)에 그대로 더하면 웹 352 MB라 다시 나눈다. **웹 합계 296 MB ≤ 300 MB**(1차 상한 유지 — DB 메모리 사본·CanvasKit·wasm 힙·재생 `Blob`은 별도):

| 영역 | 항목 | 웹 | 네이티브 |
|---|---|---|---|
| INK | 외곽선 캐시 | 32 MB (1차) | 1차 |
| INK | **래스터 공유 장부**: 타일 + 이미지 객체·이미지 배경 디코드(한 LRU. 넘치면 이미지는 한 단계 낮은 버킷, 그리는 중인 항목은 쫓아내지 않음) | 96 MB (1차 타일 96 + 2차 이미지 48을 합침) | 타일 1차 · 이미지 128 MB |
| INK | 수식 래스터 캐시 | 8 MB | 8 MB |
| PDF | 미리보기 / 타일 / 썸네일 | **24** (1차 32에서 줄임) / 64 / 16 MB | 1차 |
| PDF | 내보내기 중 이미지·래스터 임시 | 16 MB | 16 MB |
| CORE | 되돌리기 히스토리 | 32 MiB (1차) | 1차 |
| media | 웹 녹음 메모리 조각(그 이상은 초안 저장소로) | 8 MB | — |

- (v2.1) 한 장의 래스터·디코드는 **픽셀 수 상한 4 Mpx**(16 MiB RGBA)다 — INK `rasterize`(수식·텍스트 상자), PDF 내보내기 디코드(동기화로 온 큰 이미지 포함)가 같은 규칙으로 해상도를 낮춘다. 긴 변 상한(4096)만으로는 '임시 16 MB'가 성립하지 않는다(쪽 크기 텍스트 상자 300 dpi ≈ 24 MiB).
- (v2.2, C22-06 — CP-PDF-14) 'PDF 내보내기 중 이미지·래스터 임시(16 MB)'는 Dart가 내보내기 동안 함께 드는 이미지 메모리 — 디코드·래스터 RGBA, 읽은 이미지 바이트, 같은 내보내기의 JPEG 캐시 — 의 합이다. 예외 둘: ① 네이티브는 이미지가 든 조각을 워커 isolate로 넘기는 동안 그 조각의 사본(`TransferableTypedData` — 한 번에 한 조각, ≤ 16 MiB)이 더 있을 수 있다(별도). 워커가 PDFium에 넘기려고 잡는 네이티브 버퍼는 웹의 wasm 힙처럼 별도다. ② 계약 전제(M-3) 밖의 큰 이미지 바이트(12 MiB 초과 — 이 앱의 가져오기가 만들지 않는 크기)는 그 그림을 디코드하는 동안 이 행의 합이 입력 바이트 + 4 MiB(1 Mpx RGBA)까지 커질 수 있다 — 그림을 빼지 않고 PDF가 개발자 표시에 센다. 웹 합계 296 MB에 늘 있는 몫은 생기지 않는다(①은 네이티브만, ②는 M-3 밖 입력을 디코드하는 그 순간만).
- (v2.1) 개발자 표시의 '앱 캐시 합계'가 B-13·INK I-B11의 같은 기준(≤ 300 MB)이다. 영역별 수치는 각자 개발자 표시에 낸다(1차 규칙).
- (v2.1) **검색 색인 크기**(CORE): PDF 색인은 SQLite(웹은 열 때 DB 파일 전체가 메모리에 올라온다 — 1차 02-core)에 원문·정규화·FTS만 두고, 글자 사각형은 줄인 정밀도로 SQLite 밖(블롭 저장소) 또는 압축 BLOB에 둔다. 목표: 실제 모양(쪽당 2,000~3,000자 + 글자 상자, 한국어·영어) 500쪽 색인이 DB 파일을 ≤ 12 MB 키우고 Chrome 저장소 다시 열기 시간 증가 ≤ 300 ms. 넘으면 CORE가 원문 열도 블롭으로 옮기거나 색인 범위 축소(노트가 쓰는 쪽만)를 총괄에 올린다.

#### 7.4.6 테스트 (1차 7.4.8 확장)

| 항목 | 규칙 |
|---|---|
| 태그 `media` | Chrome 가짜 마이크 시험. `tool/chrome-fakemedia`(INFRA — `--use-fake-device-for-media-stream --use-fake-ui-for-media-stream --autoplay-policy=no-user-gesture-required`)를 `CHROME_EXECUTABLE`로 쓴다. 패키지 `dart_test.yaml`에 선언·기본 skip, CI의 별도 단계에서 실행. 시험 파일이 `RecordPluginWeb.registerWith`·`JustAudioPlugin.registerWith`를 직접 부른다. (v2.1, CP10) `ws test`가 `media` 태그에 래퍼를 자동으로 쓴다(영역은 `CHROME_EXECUTABLE`을 바꾸지 않음) |
| 태그 `emulator` | `functions/` 에뮬레이터 + Dart HTTP 클라이언트(VM) 시험. 기본 skip. (v2.1 정정) **컨테이너에서 전역 잠금으로 돌리고 CI `functions` 잡에서 반복**한다(조사 04 6.4·07-sync 6.8.11에서 컨테이너 실행 확인 — V13은 컨테이너 기준) |
| 무거운 시험 잠금 (v2.1) | `media`·`emulator`·전체 Chrome 실행은 컨테이너 전역 잠금 하나로 한 번에 하나만 돈다. 잠금 파일은 고정 경로 `/tmp/noteapp-heavy-tests.lock`(환경 변수 `NOTEAPP_HEAVY_LOCK`으로 바꿈 — 에이전트마다 `$TMPDIR`가 다를 수 있다). 잠금을 쥔 프로세스는 자식에게 `NOTEAPP_HEAVY_LOCK_HELD=1`을 넘기고, 그 환경의 `ws test`는 잠금을 다시 잡지 않는다(중첩 교착 방지 — SYNC 검토 X-2). npm·셸 스크립트는 `dart run tool/ws.dart with-heavy-lock -- <명령>`으로 감싼다(INFRA. bash 쪽 구현을 따로 두지 않는다). 재시도·`--member-timeout` 동안 잠금을 유지한다 |
| Chrome 시험 글꼴 (v2.1) | `flutter test --platform chrome`에서 `rootBundle.load`는 응답하지 않는다 [확인 — INK]. `InkFonts`·`InkTextLayout`을 쓰는 Chrome 시험(EDITOR·LIBRARY·PDF·INFRA)은 `setUpAll(useInkTestFonts)`(INK `testing.dart` — 7.6). KaTeX 글꼴은 Chrome 시험에서 적재하지 않고 배치·잉크 픽셀만 단언한다 |
| 플러그인 가짜 | EDITOR·LIBRARY 시험은 CORE `FakeAudioRecorder`·`FakeAudioPlayback`, recog `FakeHandwritingRecognizer`·`FakeMathRecognizer`, 가짜 `EditorImageImporter`·`StylusExtrasSource`만 쓴다(플러그인 채널을 건드리지 않음). (v2.1) 예외: 서비스 패키지(`media_io`·`ink_recognition`·`pencil_bridge`)의 플러그인 어댑터 자체 시험은 메서드 채널 가짜를 건다 |
| 글자 골든 | 1차 규칙 그대로(Ahem만). `NoteSans`·수식 렌더는 픽셀 단언(경계 안·비어 있지 않음)과 실기기로 확인 |
| 합성 자료 | 도형 판정·줄 나누기는 고정 시드 합성 획(조사 03 4.2·7.4). 실기기 표본은 사용자 동의 뒤 `test/fixtures/real/`(U18) |
| 네이티브 설정 정적 시험 | INFRA `tool/test/native_config_test.dart`(매니페스트·Info.plist·pbxproj·Podfile·gradle 파싱) + `ws native-reqs`(플러그인 podspec·`Package.swift`·gradle 요구 vs 앱 값, CocoaPods 전용 목록) |

#### 7.4.7 서버 함수 (functions/)

- 저장소 루트 `functions/`(SYNC). npm 의존은 **정확한 버전** + `package-lock.json` 커밋 + `npm ci`. `.env.local`·`.secret.local`·`node_modules/`·`lib/`·(v2.1) `eval-out/`·`firebase-debug*.log`는 `.gitignore`(INFRA가 기반 단계에서 넣음).
- (v2.1, CP-S4) **`functions/.env.demo-noteapp`은 커밋한다**(데모 값만: `OWNER_UIDS=owner-uid`, `MATH_ENGINE=fake`, `ALLOW_FAKE_ENGINE=true`, `QUOTA_STORE=memory`, `DAILY_CAP=1000`) — 어떤 무시 규칙에도 걸리지 않음을 INFRA 시험이 확인한다. 시험 비밀값은 없다(`MATH_API_KEY` 없음 → 빈 값 + 경고, 가짜 엔진은 키를 쓰지 않음 [확인 — 07-sync 6.8.11]). 에뮬레이터 사용자는 `owner-uid`·`stranger-uid`(Auth 에뮬레이터 관리 REST — `Authorization: Bearer owner` + `localId`, 이미 있으면 로그인)로 SYNC·LIBRARY 시험이 같이 쓴다.
- `app/firebase.json`에 `"functions": [{"source": "../functions"}]`(INFRA, 에뮬레이터에서 동작 확인됨 — 조사 04 6.4).
- CI `functions` 잡(INFRA 소유 워크플로, SYNC 스크립트 호출): `ubuntu-latest`, Node 22, `npm ci && npm test && npm run test:emulator`(`firebase emulators:exec --only functions,auth --project demo-noteapp`, firebase-tools 15.34.2). 경로 필터 `functions/**`. (v2.1, CP11) `firebase-tools`는 `functions/package.json` devDependency(정확한 판)로 잠그고, 스크립트 이름은 `build`·`test`·`test:emulator`, 에뮬레이터 설정은 `--config ../app/firebase.json`이다. `npm test`는 따옴표 친 글롭(`node --test 'lib/test/**/*.test.js' 'lib/tool/test/**/*.test.js'` — 디렉터리 인자는 Node 22에서 실패한다 [확인 — SYNC 검토 M-2])이고 완료 조건에서 돌린 시험 수 > 0을 본다. `functions/`가 아직 없는 커밋에서는 잡을 건너뛴다(`hashFiles('functions/package.json')` 가드).
- 배포(`firebase deploy --only functions`)는 Firebase 프로젝트 + Blaze 뒤(3.3, U3·U6). (v2.1) 미니 라운드의 순서: 비밀값(Secret Manager — 엔진이 정해지기 전에도 자리 값이 있어야 함 [추측 — 배포 때 확인]) → 커밋하는 `functions/.env.<projectId>`(운영 `OWNER_UIDS` — uid는 비밀이 아니고, `.env.local`은 에뮬레이터만 읽는다) → 배포 → `MATH_ENGINE=none`에서 소유자 호출 = `unavailable`·남 계정 = `permission-denied` 확인 → 엔진 설정 뒤 실제 호출 1회. 운영에서는 가짜 엔진을 쓸 수 없다(`ALLOW_FAKE_ENGINE=false`).

#### 7.4.8 시간 · 녹음 시계

- 녹음 시계는 단조 `Stopwatch`를 녹음기 상태 이벤트에 맞춰 멈추고 이어 간다(R-2). 시험은 시계 팩토리를 주입하고 `fake_async`로 돌린다. `package:clock`의 `clock.stopwatch()`는 단조가 아니라 쓰지 않는다 [조사 02 6.2].
- `Recording.startedAt` = 녹음 시작 벽시계(CORE `clockProvider`), 획 `createdAt`은 1차 그대로(펜 다운 벽시계). 둘의 차로 녹음 위치를 계산하지 않는다(R-2).

#### 7.4.9 계약 변경 절차 · 브랜치 (1차 7.4.12에 더함)

- 절차는 1차 7.4.12 그대로(변경 요청 → 총괄 승인 → 이 장 수정 + `v2.x` → 영향 영역 공지). 브랜치는 `area2/<id>`, GitHub 푸시는 체크포인트·통합 때만.
- **여러 영역이 동시에 구현·소비하는 표면**(CORE 오디오 포트·`SearchIndexWriter`·`HandwritingRepository`, EDITOR 자리 타입·`EditorExtensions`, INK `InkShapeFitter`, `recognizeMath` 형식)은 동시 개발 중 **추가만** 허용한다(새 선택 인자·새 필드·새 타입). 기존 멤버의 의미·시그니처 변경은 통합 단계까지 미루고, 그 전에는 소비 영역이 우회한다.

#### 7.4.10 UX 공통 (1차 7.4.11에 더함)

- 색 하드코딩 예외 추가: 재생 강조 색·안 쓴 획 흐림 정도·레이저 색(종이 위 표시 색). 상수는 `ink_engine` `InkTuning` 한 곳(`playbackEmphasisArgb`·`playbackDimOpacity`·`laserArgb`)에만 둔다.
- 다른 영역이 에디터 안에 띄우는 UI(녹음 패널 — media, 변환 창·수식 입력 패드·LaTeX 편집 — recog)는 1차 7.4.11 규칙 그대로(`Theme.of(context).colorScheme`만, 탭 대상 ≥ 44×44, 해요체 문구) + **바닥 시트는 `material_ui`의 `showModalBottomSheet`, 높이는 화면의 50% 이하, 패널(`EditorPanelBuilder`)은 에디터 아래쪽에 붙고 높이는 화면의 40% 이하**로 통일한다. 자체 `Navigator.push`·전역 `Overlay`로 띄우지 않는다(에디터 수명과 묶기 위함). V5 스모크가 자리마다 한 번씩 연다.
- 에디터 도구 선택 저장값(EDITOR 내부 키)에 모르는 값이 오면 `pen`으로 읽는다(새 도구가 있는 판에서 옛 판으로 돌아가도 열림).

### 7.5 외부 패키지 버전 고정표 추가분 (1차 7.5)

확인: 2026-11-05 pub.dev, 1차 잠금 파일 복사본 + 아래 배치로 `flutter pub get` 해석 성공(`/tmp/claude-0/plan57-scratch/designA/ws` — `media_io`·`ink_recognition`·`pencil_bridge` 시험 멤버, `ink_engine`에 `flutter_math_fork`, 앱에 `path_provider`). **기존 잠금 변화는 `xml 7.1.0 → 7.0.1` 한 건**(원인: `flutter_math_fork` → `flutter_svg` → `vector_graphics_compiler 1.3.x`의 `xml <=7.0.1` — 1.3.0~1.3.4 모두 같아 피할 수 없음), 추가 44개.

| 패키지 | 버전 | 쓰는 멤버 | 비고 |
|---|---|---|---|
| `record` | 7.1.2 | media_io | 연합 플러그인(`record_web 2.1.3`, `record_android 2.2.0`, `record_ios 2.1.1` …). 7.0부터 안드로이드 백그라운드 서비스 없음 |
| `just_audio` | 0.10.6 | media_io | `just_audio_web 0.4.16` |
| `audio_session` | 0.2.4 | media_io | |
| `flutter_foreground_task` | 11.0.3 | media_io (`*_native.dart`) | `shared_preferences 2.5.6` 끌어옴 |
| `image_picker` | 1.2.4 | media_io | `image_picker_for_web 3.1.1`, `image_picker_android 0.8.13+25` |
| `image_picker_ios` | 0.8.13+13 | media_io (간접 고정) | 0.8.13+14는 2026-10-29 게시(7일)라 채택하지 않음. +13은 2026-10-22 |
| `shared_preferences_android` / `shared_preferences_foundation` | 2.5.3 / 2.6.0 | media_io (간접 고정 — v2.1, CP1) | `flutter_foreground_task` → `shared_preferences 2.5.6`이 끌어오는 2.5.4·2.6.1은 2026-10-27 게시(14일 미만). lock 변화 2줄 [확인 — INFRA] |
| `flutter_web_plugins`(SDK) · `record_web` · `just_audio_web` · `record_platform_interface` · `just_audio_platform_interface` · `image_picker_platform_interface` | SDK / 2.1.3 / 0.4.16 / 2.1.0 / 4.6.0 / 2.11.2 | media_io (직접 — v2.1, CP-PDF-9) | `testing.dart`의 웹 등록·가짜 플랫폼이 `lib/`에 있어 `dependencies`여야 한다. 모두 1차 잠금에 간접으로 있어 lock 변화 없음. `plugin_platform_interface`는 넣지 않는다(`MockPlatformInterfaceMixin`은 `@visibleForTesting` — `lib/`에서 분석 오류) |
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
| (npm) `@anthropic-ai/sdk` | 1.1.0 | functions/ (v2.1, CP-S5 — P-C Claude 어댑터만) | 2026-10-21 게시, Apache-2.0. 쓰는 매개변수(`fallbacks`·`output_config`)가 타입에 있음 [확인 — SYNC 검토]. 간접 의존 판은 lock 만들 때 확인 |
| (도구) `firebase-tools` | 15.34.1 (v2.3, C23-01) | CI, (v2.1) `functions/` devDependency | v1.4 INFRA 고정값. 2026-10-28 게시라 (v2.1) R2-B1·R2-B7b 커밋 때 14일이 지났는지 다시 확인한다(2026-11-11부터 통과) |
| `xml` | 7.0.1 | 루트 dev (v2.1, CP2 — `native_config_test`) | 이미 간접으로 7.0.1, lock 변화 없음 |
| `integration_test`(SDK) | SDK | `app` dev (v2.1 — INFRA J21) | `webdriver`·`sync_http` 등 hosted 항목이 lock에 새로 들어오므로 R2-B1에서 함께 해석한다. 플러그인이라 `plugin_packages`에도 |

넣지 않음: `permission_handler`(권한은 7.4.3), `cloud_functions`·`firebase_auth`(실연결 미니 라운드), `apple_pencil_double_tap`·`stylet`(참고 구현만 — 직접 만든 `pencil_bridge`), `one_dollar_unistroke_recognizer`(도형 판정 정확도·전역 상태 — 조사 03 4.2), `super_clipboard`, `audioplayers`, `flutter_sound`/`taudio`.

(v2.1) 위 추가 행은 R2-B1에서 다시 해석해 lock 변화를 진행 기록에 남긴다.

**게시 14일 규칙**(2차 공통 규칙): 게시된 지 14일이 안 된 판은 직접·간접 의존 모두 채택하지 않는다(1차 `go_router 18.1.3` 미채택과 같은 취지). 간접 고정(이번에 처음 생긴 방식): 14일이 안 된 간접 의존이 해석되면 그 의존을 끌어오는 패키지의 pubspec에 정확한 버전으로 적어 내린다(주석 `# 간접 고정`). `ws check` R9 `pinned_external`에도 올린다.

### 7.6 기반 단계 (동시 개발 시작 전 `main`에 커밋)

#### 7.6.1 전제

- 1차 통합(1차 7.7 1~6단계, V1~V6)이 끝나고 `main`에 병합되어 있다. (v2.1, D21) 1차 V7(iPad 확인)은 전제가 아니다 — Firebase Hosting이 생기면 2차와 병행한다(3.7).
- 2차 작업 트리: `/home/user/wt2/<id>`, 브랜치 `area2/<id>`(1차 `area/<id>`와 섞이지 않게). 계획 작업 트리 `plan57`의 계획서는 승인 뒤 `main`의 `docs/plans/m5-7/`로 들어간다.
- 계약 변경 절차는 7.4.9(1차 7.4.12 + 동시 개발 중 '추가만')다(변경 요청 → 총괄 승인 → 이 문서 7장 수정 + `v2.x`).

#### 7.6.2 기반 단계 표

각 단계 뒤 `ws check`·`flutter analyze --fatal-infos`·`ws test`(VM·Chrome)·`dart test tool/test`가 통과해야 다음 단계로 간다(1차 7.6 규칙). **예외 하나**: R2-B2(CORE `EntityKind` 값·`NoteStore` getter 추가)는 SYNC switch와 INFRA 시험 가짜를 깨므로(7.0.2) R2-B7a(SYNC)·**R2-B2i(INFRA `app/test/fakes/counting_note_store.dart` 위임 4줄)**와 **한 묶음으로 병합**한다(총괄이 세 브랜치를 함께 병합한 뒤 검사).

| 단계 | 담당 | 경로 | 내용 | 완료 조건 |
|---|---|---|---|---|
| R2-B1 | INFRA | 루트 `pubspec.yaml`·`pubspec.lock`·`.gitignore`·`.gitattributes`, `packages/{media_io,ink_recognition,pencil_bridge}/pubspec.yaml`·`README.md`·빈 진입점·스모크 시험, `packages/pencil_bridge/ios/**`(빈 Swift 등록 파일·`Package.swift`·podspec), (v2.1 한 번 예외, CP3) `packages/ink_engine/pubspec.yaml`의 의존 4줄, `tool/workspace_rules.yaml`(R8 v2.0, `native_only_imports`·`pinned_external`·R16 `plugin_free_members`·`plugin_packages`, `generated_files` `*.steps.dart`, `lib_exceptions` `note_core/lib/testing_web.dart`), `tool/chrome-fakemedia`, 무거운 시험 잠금(`with-heavy-lock`), `app/firebase.json`(`functions`), `.github/workflows/functions.yml` 골격(`hashFiles` 가드) | 7.5의 **모든** 새 의존((v2.1) 추가 행 포함 — `media_io` 직접 6줄·간접 고정 2줄, `xml` dev, `integration_test`)을 각 pubspec에 미리 넣고 lock을 만든다(간접 고정 포함). `pencil_bridge`는 빈 `register(with:)` Swift까지 둔다(그 뒤 `main`의 iOS 빌드가 깨지지 않게). `.gitignore`는 7.4.7 목록(`.env.demo-noteapp`은 무시하지 않음), `.gitattributes`는 7.4.5 `binary` 목록. `firebase-tools` 판의 14일 재확인. 바탕은 1차 통합 HEAD(ink lab 멤버·`app_members`·`analyzer`·`ws test` 시간 제한 포함 — 2.5) | `flutter pub get --enforce-lockfile`, `ws check`, `ws test`, `dart test tool/test` |
| R2-B7b | SYNC | `functions/` | (v2.1, C-5) `functions/` 골격: `package.json`(정확한 고정, `firebase-tools` devDependency, 스크립트 `build`·`test`·`test:emulator`), `tsconfig.json`, 가짜 엔진, 단위 시험 1개, `.env.demo-noteapp`. Dart와 무관하므로 **R2-B1 바로 뒤에 따로 병합**한다 | `npm ci && npm test`(돌린 시험 수 > 0) |
| R2-B2 | CORE | `packages/note_core/lib/**`, `test/**` | (v2.1, 세션 크기로 나눔 — CORE 검토 M-2) **B2-α 계약 표면**(약 0.5세션): 7.2.2~7.2.7(v2.1 추가 포함)의 모든 공개 선언 — enum·한도 상수·생성자·필드·`==`·`EntityKind` 2값·`NoteStore` getter 4개·provider·진입점 export(`testing_web.dart` 포함) — 를 실제로 두고 알고리즘 본문(`SearchText`·템플릿·`sourceRevOf`·해석기 객체 분기 등)은 작업 번호를 단 `UnimplementedError`로 + `api_surface_test` v2. **이 커밋 해시를 '계약 타입 커밋'으로 알린다.** **B2-β 동작**(1.5~2세션): JSON·골든(SYNC 키 대조가 기대므로 맨 앞) → `SearchText`·템플릿·`bounds`·`transformed` 단일 규칙·캘리그래피 각(C2-38) → 해석기·세션(새 명령·`ClearPage.includeObjects`·`PageDraft.objects`) → `testing.dart` v2(가짜 저장소 v2: 객체·녹음·초안·손글씨(`update` 포함)·검색(실제와 같은 판정·순서), `FakeAudioRecorder`·`FakeAudioPlayback`·`PageObjectFixtures`)·`testing_web.dart`. 조각별 완료 조건·세션 추정은 02-core 8.1. DB v2·마이그레이션·FTS5·파일 저장은 동시 개발에서(`openTestNoteStore`는 v1 DB로 계속 동작). V7 고정 자료는 1차 통합이 `main`에 들어간 커밋의 코드로 이 단계 전에 만든다 | B2-α: `api_surface_test` v2 / B2 전체: CORE 계약 시험 |
| R2-B7a | SYNC | `packages/sync_engine/lib/**`, `test/**` | (R2-B2와 한 묶음, 바탕 = B2-α 해시) `EntityKind` switch 4곳·`kindOrder`·`fixtureJson`에 새 두 값을 '노트 범위 일반 기록'으로, `kPageObjectTypeKeys`, `core_json_keys_test` v2 단언(7.2.8) | SYNC 기존 시험 전부. 새 종류 디코드·키 대조 시험(CP-S9)은 B2-β JSON 조각이 들어온 뒤 |
| R2-B2i | INFRA | `app/test/fakes/counting_note_store.dart` | (R2-B2와 한 묶음) `CountingNoteStore`에 새 getter 4개를 `inner`로 위임 | INFRA 기존 시험 전부 |
| R2-B3 | INK | `packages/ink_engine/lib/**`, `assets/fonts/`, `test/**` | 7.2.9 공개 표면 전부를 **단순하지만 동작하는 구현**으로(03-ink 4.13 표가 상세): 객체는 L-1 층에 경계 상자 + 기본 그리기(도형 폴리라인·타원, 텍스트는 시스템 글꼴 `Paragraph`, 이미지는 회색 상자, (v2.1 정리) **`MathObject`는 연한 상자, `MathPreview` 위젯은 실제 `Math.tex` 동작**), `select`·`hitTestObject`·`setHiddenObjectIds`·`setPreviewObjects`(같은 id 대체·숨김보다 우선) 동작, (v2.1) 읽기 getter 4개, `hitTestRecorded`(획 적중)·테이프 API(드러냄 집합 동작, `hitTestTape`는 bounds), 레이저 `end() → null`, `InkEdit.removedObjectIds`·`toCommand` v2.1 표, P1 펜은 볼펜 프로필(v1.4), `ShapeAssist`는 받기만, `NoShapeFitter`, 재생 초점은 상태만, `ImageBackgroundLayerBuilder`는 종이 색, `defaultPageBackgroundBuilders`, 벡터 v2 필드는 빈 목록, `InkMathRenderer.validate`·`layout`은 실제 동작(`rasterize` → `null`), `InkFonts`·`InkTextLayout.measure`·`measureSync`·`textStyleOf`·`strutStyleOf` 동작(글꼴 파일 포함), `testing.dart` v2(`useInkTestFonts`·`InkVectorFixtures` 포함 — 7.6 블록). T24(표면) 커밋 해시를 알린다 | 스모크 + 다른 영역이 컴파일·기본 동작 가능 |
| R2-B4 | PDF | `packages/pdf_io/lib/**`, `packages/media_io/lib/**`, 각 `test/**` | `pdfIoOverrides()` v2 목록(`defaultPageBackgroundBuilders` 사용), `PdfSearchIndexer`(원문 생성자 — `start()` 아무것도 안 함). media_io: `initializeMediaIo`·`mediaIoOverrides()`(B4에서는 빈 목록 → CORE 기본 '지원 안 함'), `supportedImageSources()` = 빈 집합, `importImageForNote` = `null`, `RecordingPanel` 자리표시(제목 + 닫기), `mediaDevOverlayLinesProvider` 빈 목록, `testing.dart`(7.6 블록 — 믹스인 없음) | `api_surface_test`, `pdfIoOverrides()`만 넣은 컨테이너에서 provider read 예외 없음 |
| R2-B5 | EDITOR | `packages/feature_editor/lib/**` | 7.2.10 공개 표면: `EditorExtensions` v2 + 문맥·메뉴 항목 타입, `editorImageImporterProvider`, `EditorScreen.initialFocusRectPt`(받기만), `EditorGesture`·`EditorAction`·`GestureSettings` v2(JSON 왕복 동작), Stylus v2 타입((v2.1) `timestamp` 포함) + `NoStylusExtras.capabilities` | 스모크 위젯 시험, `GestureSettings` JSON 시험(v1.4 JSON 읽기 포함) |
| R2-B6 | LIBRARY | `packages/feature_library/lib/**`, `packages/ink_recognition/lib/**` | `LibraryScreen.onOpenNoteAt`(받기만). recog: 7.2.11 공개 표면 — 포트·실패 타입·`HandwritingTrace.fromStroke`(동작), `Unsupported*`·`ManualOnlyMathRecognizer`, `recognitionOverrides()`(B6: 도형 판정기만 `NoShapeFitter`로), 동작 목록 빈 목록, `HandwritingIndexer`(`start()` 아무것도 안 함)·(v2.1) `HandwritingIndexerStatus`·`recognitionDevOverlayLinesProvider`, `RecognitionSettingsSection` 자리표시, `testing.dart` 가짜 엔진((v2.1) 추가 멤버·`SyntheticShapes`) | `api_surface_test`, 스모크 |
| R2-B8a · R2-B8b | INFRA | `app/lib/**`, `app/test/**`, `packages/pencil_bridge/**` | (v2.1, 세션 크기로 나눔 — INFRA 검토 M-5) **B8a**: 부트스트랩 확장·`AppFeatures`(D14·D17)·`MediaModule`·`RecognitionModule`(주입 이음새 포함)·7.3.3 연결(기반 단계 구현)·유휴 작업 v2.1 규칙. **B8b**: 라우팅 `?page=&focus=`·`pencil_bridge` Dart 표면(이벤트 디코딩)·`PencilStylusExtrasSource`(가짜 채널 시험). 네이티브 설정 파일(`app/android/**`·`app/ios/**` 매니페스트·Info.plist·pbxproj·Podfile·xcconfig — CP8)·`tool/src/native_config.dart`·`native_config_test`와 웹 빌드 실측은 **INFRA 동시 개발 첫 작업(J0)**으로 내린다(다른 영역이 기다릴 이유가 없다) | B8a·B8b 각각: `ws check` 0, analyze 0, `ws test`(VM·Chrome), `dart test tool/test`. J0: `cd app && flutter build web --release`, **`main.dart.js` 크기·시작 글꼴 바이트를 기록**해 웹 예산표 갱신, CI 단계별 시간 실측 |

- 순서(v2.1): R2-B1 → R2-B7b → (R2-B2 + R2-B7a + R2-B2i 묶음) → R2-B3 → (R2-B4, R2-B5, R2-B6 병렬 — INK 타입을 쓰므로 B3 뒤). **동시 개발 시작 조건 = R2-B1~R2-B6이 `main`에 있음**이다. R2-B8a·B8b는 INFRA 동시 개발의 앞 작업이고 다른 영역의 시작 조건이 아니다(다른 영역은 앱 셸을 import하지 않는다 — D24). 각 영역은 B2-α 해시(CORE)·T24 해시(INK) 뒤 자기 작업 트리에서 코드 작성을 시작해도 되지만 `main` 커밋은 위 순서다(1차 v1.2 풀이와 같음).
- (v2.1) **이정표 커밋 알림**(진행 기록 양식에 고정 — 기다리는 쪽이 시점을 판단): CORE — B2-α, B2-β JSON 골든, T24(DB v2·마이그레이션), T26(쓰기 경로), T27(객체 읽기·쓰기 DB), T28(동기화 창구 v2), T29(복사·휴지통·백업), T30(녹음 저장소), T31(실제 초안 저장소), T32(손글씨 저장소), T33(검색 색인). INK — T24(표면), T26a(글꼴·측정), T33(도형 렌더), T34(텍스트 렌더), T36(수식 래스터), T42(벡터 v2). SYNC T16-v2·PDF `media`·LIBRARY L2x·EDITOR E-2x가 이 커밋을 기다린다.
- 기반 단계가 끝나면 각 계획서 5절 '가정' 블록을 실제 타입으로 바꾸고 동시 개발을 시작한다. (v2.2, C22-09) 그때 각 영역은 계획서의 계약 인용 중 v2.2가 바꾼 문장(C22-01~08)을 이 장에 맞추고, 상태 줄을 '승인 · 계약 v2.2'로 두며, 00-review '최종 승인'의 자기 영역 항목을 처리한다. 그 전까지 계획서와 이 장이 다르면 이 장이 우선이다.

기반 단계 시험 도우미 (계약 — 바꿀 때 7.4.9 절차. 다른 영역이 동시 개발 중 이것으로 시험한다)

```dart
// package:note_core/testing.dart — v2.0 additions (web-safe, test/ only)
/// v1.4 signature unchanged. v2.0 behaviour: page objects (AddObjects / UpdateObjects /
/// RemoveElements / TransformElements / ClearPage.includeObjects / PageDraft.objects), recordings
/// (RecordingRepository), recording drafts (memory), handwriting (HandwritingRepository, (v2.1)
/// incl. update / notesWithStalePages) and a memory SearchIndex that applies (v2.1, CP-14) the
/// SAME judgement, candidate order and ranking code as the real FTS index — results AND order
/// equal the real store for the 7.7 V10 query set. openTestNoteStore (testing_vm.dart) is the
/// real CORE v2.
NoteStore createFakeNoteStore({/* v1.4 args */});
abstract final class PageObjectFixtures {
  static ShapeObject shape({required String pageId, ShapeKind kind = ShapeKind.rectangle,
      PageRect rect = const PageRect(100, 100, 300, 220), int createdAt = 1, String? id});
  static TextBoxObject textBox({required String pageId, String text = '안녕 hello',
      PageRect rect = const PageRect(100, 300, 400, 340), int createdAt = 1, String? id});
  static ImageObject image({required String pageId, required AssetId assetId,
      PageRect rect = const PageRect(100, 400, 300, 550), int pixelWidth = 400,
      int pixelHeight = 300, int createdAt = 1, String? id});
  static MathObject math({required String pageId, String latex = r'\frac{a}{b}',
      PageRect rect = const PageRect(100, 600, 200, 650), int createdAt = 1, String? id});
  static UnknownObject unknown({required String pageId, String type = 'sticker',
      PageRect rect = const PageRect(400, 100, 450, 150), String? id});
}
/// Controllable recorder: no real time, no plugin. stop() writes Asset(audio, 'audio/mp4',
/// silent bytes) then Recording (M-1) into [store]. (v2.1) start() with support != supported
/// throws UnsupportedError (as the real recorder); recording writes drafts to
/// store.recordingDrafts; pendingDrafts() follows the 7.2.4 exclusion rule. With the real
/// in-memory CORE inside testWidgets, asset writes go through idb_shim timers — pump / runAsync.
final class FakeAudioRecorder implements AudioRecorderService {
  FakeAudioRecorder({required NoteStore store, AudioSupport support = AudioSupport.supported});
  void advance(Duration elapsed);        // recorder clock; offsetNowMs() follows (pauses excluded)
  void interrupt();                      // system / hidden-tab pause → interrupted = true
  int stopDurationErrorMs = 0;           // durationMs = clock + this (R-3)
  /// (v2.1, CP-8) Closed tab / killed app: in-memory state dropped, phase idle, the draft written
  /// so far stays for pendingDrafts() / recoverDraft() of a new recorder (V16 shape).
  Future<void> abandon();
}
final class FakeAudioPlayback implements AudioPlaybackService {
  FakeAudioPlayback();
  void setPositionMs(int positionMs);    // positionMs() returns it; seekMs() also sets it
  /// (v2.1, CP-8) Calls in order: 'open:<recordingId>', 'play', 'pause', 'seek:<ms>', 'speed:<x>', 'close'.
  List<String> get calls;
}

// package:note_core/testing_web.dart — (v2.1) browser tests only (test/web/, Chrome)
/// The REAL web store (IndexedDB + drift web worker) under a unique [name]; needs the files of
/// CORE's tool/prepare_web_test.dart. For PDF V8 / V16 / V11 and CORE's own browser tests.
Future<NoteStore> openWebTestNoteStore(String name);
Future<void> deleteWebTestNoteStore(String name);

// package:ink_engine/testing.dart — (v2.1) contract additions (INK 4.12 is the full list:
// createTestPageController(shapeFitter:), FakeInkShapeFitter, SyntheticInk.loopThenHold /
// pageContentWith, loadKatexFontsForTest (VM), debugSetInkFontSource, testPngBytes)
/// Installs the small bundled test font (base64 Hangul + Latin subset) as the InkFonts source.
/// Every Chrome test that touches InkFonts / InkTextLayout (EDITOR, LIBRARY, PDF, INFRA) calls it
/// in setUpAll. Web safe.
Future<void> useInkTestFonts();
/// Hand-built vector export values (PDF tests before INK T42). Each factory takes every public
/// field of its value type as a named argument with the same name and type.
abstract final class InkVectorFixtures {
  static InkPageVectors pageVectors({/* highlighterGroups, inkShapes, underlay, annotations, cover, bounds */});
  static InkFillShape fillShape({/* strokeId, tool, path, colorArgb, opacity, objectId */});
  static InkHighlighterGroup highlighterGroup({/* … */});
  static InkHighlighterLine highlighterLine({/* … */});
  static InkImageVector imageVector({/* assetId, frame, pixelWidth, pixelHeight */});
  static InkTextVector textVector({/* object, lines */});
  static InkTextLine textLine({/* text, x, baselineY, width */});
  static InkMathVector mathVector({/* object */});
}

// package:ink_recognition/testing.dart (test/ only)
final class FakeHandwritingRecognizer implements HandwritingRecognizer {
  /// [answer] default: '줄 <n>' for the n-th call; engineId 'fake'.
  FakeHandwritingRecognizer({String Function(HandwritingLineInput line)? answer,
      bool isAvailable = true, Duration latency = Duration.zero});
  // (v2.1, CP-L4) calls, failNext, modelStates, ensureModelCalls, disposed — 05-library 4.3
}
final class FakeMathRecognizer implements MathRecognizer {
  FakeMathRecognizer({String latex = r'x^2', RecognitionFailure? failWith,
      Duration latency = Duration.zero});
  // (v2.1, CP-L4) calls, alternatives, isAvailable — 05-library 4.3
}
abstract final class SyntheticHandwriting {   // fixed-seed lines as core.Stroke lists
  /// (v2.1) stroke ids 'syn_<seed>_l<line>_<n>' (CP-L4)
  static List<core.Stroke> lines({required String pageId, int lineCount = 5, int seed = 1});
}
/// (v2.1) Paths that GeometricShapeFitter with the default ShapeFitTuning always judges as the
/// named shape — app smoke tests drive pointers along it and hold (V5 '합성 멈춤').
abstract final class SyntheticShapes {
  static List<Offset> rectanglePath(Rect boundsPt, {int pointsPerSide = 24});
}

// package:media_io/testing.dart (test/ only) — (v2.1, CP-PDF-6 + PDF review M-1)
// registerMediaWebPlugins() — Chrome tests call it (flutter test --platform chrome does not run
//   the plugin registrant).
// VM only (assert !kIsWeb): FakeRecordPlatform extends RecordPlatform, FakeJustAudioPlatform
//   extends JustAudioPlatform, FakeImagePickerPlatform extends ImagePickerPlatform — plain
//   `extends` (the token check passes); NO MockPlatformInterfaceMixin (@visibleForTesting → an
//   analysis error in lib/). installFakeMediaPlatforms({bool micPermission = true}) →
//   MediaFakePlatforms. For media_io's own service tests; the web recorder is MediaRecorder, so
//   these have no effect in Chrome — Chrome tests and the app smoke override CORE's audio ports
//   with FakeAudioRecorder / FakeAudioPlayback (INFRA: through module injection arguments).
```

```text
// functions/ fake engine — (v2.1, CP-S3 ⑥) deterministic; SYNC's emulator test and LIBRARY's Dart
// emulator test (CallableMathRecognizer) assert the same values. engine 'fake', engineVersion '1'
// → app engineId 'fake/1'. Demo config only (ALLOW_FAKE_ENGINE).
//   strokes (S strokes, P points in total) → latex "\frac{S}{P}", confidence 1, alternatives ["S/P"]
//   pngBase64 only (B decoded bytes)       → latex "\sqrt{B}", confidence 1, alternatives []
//   first point of the first stroke (-1,-1) → unavailable; (-2,-2) → internal; (-3,-3) → unavailable
```

### 7.7 통합 순서와 검증 기준

#### 7.7.1 통합 순서

1. **CORE** 병합 → lock 재생성 → 검사 + **마이그레이션 시험(V7)**
2. **INK** 병합 → 검사 + INK 골든·불변식(K-1·K-6)
3. **SYNC** 병합 → 검사 + T16-v2(실제 CORE 2개: 객체 동시 편집·삭제 대 수정·모르는 `type` 왕복·모르는 `kind` 보류·손글씨 결과) + `functions` 시험
4. **PDF**(`pdf_io` + `media_io`) → 검사 + `integration`(객체 내보내기) + `media`(Chrome 녹음 → 실제 CORE 에셋·녹음 행 → 재생)
5. **LIBRARY**(`feature_library` + `ink_recognition`) → 검사 + 실제 CORE 색인 시험(L2x) + 도형 판정 합성 시험 + (v2.1) 자동 도형 보정 흐름(`ink_recognition/test/integration/shape_assist_flow_test.dart` — INK `createTestPageController(shapeFitter:)`, 의존 방향상 INK 쪽에는 둘 수 없다. (v2.2) P-B — 7.7.2 'P-B에 기대는 기준') + 수식 클라이언트 에뮬레이터 시험(3단계 SYNC 병합 뒤)
6. **EDITOR** → 검사 + E-2x(실제 INK + 실제 CORE: 객체 도구·올가미 혼합 선택·녹음 연동(가짜 오디오 포트))
7. **INFRA** → 실제 모듈 연결, `pencil_bridge`, 네이티브 설정 정적 시험, 스모크 V5·V6, (v2.2) V5b(P-B — 7.7.2 표의 작업이 모두 병합됐을 때만)
8. 통합 태그 시험 전체(`ws test --run-skipped -t integration`, `-t media`, `-t emulator`) — (v2.1) `media`·`emulator`는 전역 잠금으로 하나씩(7.4.6). `emulator`는 `firebase emulators:exec --only functions,auth --project demo-noteapp "dart run tool/ws.dart test --run-skipped -t emulator"`처럼 잠금을 넘겨 한 번에 돈다
9. (v2.1) 릴리스 웹 빌드 Playwright 스모크(컨테이너 — 3.7) → 미리보기 배포(Hosting이 있을 때 — 3.7) → 사용자 iPad 웹 확인(7.8 B) / `android.yml` APK → 안드로이드 확인(7.8 A, 기기가 있을 때) / `ios-compile.yml` 1회(U19 승인 시 — V14) → PLAN.md 체크리스트 갱신(총괄)

3~6은 1차처럼 순서를 바꿔도 된다(서로 import하지 않음). 위 순서는 '데이터 → 렌더 → 소비자' 순으로 실패 원인을 좁히기 위한 권장이다.

#### 7.7.2 컨테이너 검증 기준 (전부 통과해야 '2차 통합 완료')

(v2.2, C22-07 — EDITOR Q16 총괄 답) **P-B에 기대는 기준**: 3.4대로 P-B는 '미뤄도 2차 완료'다. 아래 표의 기준(또는 그 부분)은 '기대는 P-B 작업'이 **모두** 병합됐을 때만 판정에 든다. 하나라도 빠졌으면 그 시험을 만들지 않거나(따로 뗀 시험 — V5b·E2-21b·L2-I3) 기대 목록에서 그 항목을 빼고(V15), 통합 진행 기록에 '미룸 — <기준>, 빠진 작업(<작업 id>)'을 적는다. 이것은 2차 통합 완료를 막지 않는다. 병합 여부는 그 시점의 영역 진행 기록으로 가리고, 모두 병합됐는데 실패하면 보통 실패다. **P-B 단계는 P-A 시험 안에 두지 않는다** — 시험은 실행 중에 병합 여부를 알 수 없고, 한 단계의 실패가 뒤의 P-A 단계를 막기 때문이다. 영역 계획서 10장 완료 기준도 이 규칙으로 읽는다(계약 우선).

| 기준(부분) | 시험 | 기대는 P-B 작업 |
|---|---|---|
| V5b 자동 도형 앱 스모크 | `app/test/integration/app_smoke_shape_assist_test.dart`(INFRA, VM · `integration`) | INK T39 · EDITOR E2-15 · LIBRARY L2-06 |
| 7.7.1 5단계 자동 도형 보정 흐름 | `ink_recognition/test/integration/shape_assist_flow_test.dart`(LIBRARY L2-I3) | INK T39 · LIBRARY L2-06 |
| EDITOR 자동 도형 통합 스모크(7.7.1 6단계) | `feature_editor/test/integration/shape_assist_smoke_test.dart`(EDITOR E2-21b) | INK T39 · EDITOR E2-15 |
| V9 중 도형 판정 합성 1,400개 | `ink_recognition/test/unit/shape_fitter_test.dart` | LIBRARY L2-06 |
| V13 | 서버 함수 몫 `functions/` 시험·에뮬레이터 시험 / Dart 몫 `CallableMathRecognizer` `emulator` 시험 | SYNC S2-10a·S2-10b·S2-11 / LIBRARY L2-16·L2-I6 |
| V15 기대 목록의 '자동 도형 보정' | `app/test/integration/feature_switch_test.dart` | EDITOR E2-15 · LIBRARY L2-06 |

(v2.7, C27-06 — 2차 통합 판정) 위 표의 P-B 작업(INK T39 `edd7834` · EDITOR E2-15 `6fa0a30` · LIBRARY L2-06 `54e263f` · SYNC S2-10a·S2-10b·S2-11 · LIBRARY L2-16)은 **모두 병합**됐으므로 표의 기준이 전부 판정에 들었고 모두 통과했다(V5b·L2-I3 6/6·E2-21b·V9 도형 1,400개·V13·V15 자동 도형 항목). 미룬 작업(2차 완료를 막지 않음 — 이 규칙대로 '미룸'):

| 미룸 | 등급 | 빠진 작업 · 이유 | 다시 볼 때 |
|---|---|---|---|
| ink lab 예제 v2 | P-C | INK T44 — C25-04 | 3라운드 여유가 있을 때 |
| 웹 텍스트 입력 대체안 B `textarea` | P-C | EDITOR E2-11 — B-2에서 `inline`·`sheet`가 둘 다 불합격일 때만 | 7.8 B-2·B-15 결과 뒤(E2-24) |
| `webTextInput` 기본값·자동 도형 표본·S펜 접촉 규칙 조정 | — (실기기 대응) | EDITOR E2-24 · LIBRARY L2-I5 · INK 9.6 조정 | 7.8 A·B 결과 뒤 |
| iOS 컴파일 확인 1회 | P-C | `ios-compile.yml`(V14 뒷부분) — U19 | 사용자 승인 뒤 1회. 거절이면 '미확인', 첫 TestFlight 빌드 전 필수 |
| 릴리스 빌드 Playwright 나머지 흐름 | — | INFRA H7(이미지 `setInputFiles`·2초 실제 녹음·검색 → `?page=&focus=` → 새로고침) — V6 v2·V8·V16이 같은 단계를 덮음 | Hosting 미리보기(U24) 뒤 7.8 B |

| # | 기준 |
|---|---|
| V1 | `flutter pub get --enforce-lockfile`, `ws check`(R1~R16) 위반 0 |
| V2 | 루트 `flutter analyze --fatal-infos` 0건, `dart format` 변경 없음 |
| V3 | `ws test`(VM, 골든 포함)·`ws test --platform chrome`·`dart test tool/test`·통합 태그(`integration`) 전부 통과. (v2.1) Chrome 시험은 INK 시험 글꼴(`useInkTestFonts`)로 글꼴 적재에서 멈추지 않는다 |
| V4 | `cd app && flutter build web --release` 성공, `web-assets verify` 통과, 웹 예산표 갱신(`main.dart.js` 증가분, 시작 글꼴 바이트) |
| V5 | **앱 스모크 v2**(`app/test/integration/app_smoke_v2_test.dart`, 1차 V5 확장 — 메모리 CORE + 실제 모듈. (v2.1) 녹음기·재생기·이미지 선택기·인식기·수식 엔진 가짜는 **INFRA 모듈의 주입 인자**로 넣는다): 새 노트 → 획 1개 → 텍스트 상자 입력 → 도형 도구 사각형 → 가짜 가져오기로 이미지 1개 → 올가미로 전부 선택 → (v2.1, CP-E8) 선택 메뉴의 90° 돌리기·색 변경·잘라내기·붙여넣기 → 되돌리기 사슬 → 닫기·다시 열기 → 모두 유지(1차 v1.5 C15-04 순서 — 다시 연 세션은 되돌리기 없음). 이어서 녹음(가짜) 중 획 3개 → 정지 → 재생 위치에 따라 강조 대상이 바뀜 → 획 탭 → 그 시점 탐색 → 라이브러리 검색에서 텍스트 상자 글자 찾음 → 결과 열기(페이지·위치) → 내보내기 구조 확인((v2.1) INK `InkPageVectors` v2의 이미지·텍스트·수식 개수 — 실제 PDFium 합성은 V11). override의 출처·횟수는 실제 모듈 경로로 확인하고(같은 provider 두 번 override 없음), 자리(선택 메뉴·삽입 메뉴·녹음 패널·이미지 가져오기)를 한 번씩 연다. 위젯 키는 각 계획서 부록 C. (v2.2, C22-07) 합성 '멈춤'으로 자동 도형(`SyntheticShapes.rectanglePath`)은 본 흐름에서 떼어 **V5b**(P-B — 위 'P-B에 기대는 기준')로 둔다: `app/test/integration/app_smoke_shape_assist_test.dart`(VM, 같은 주입 인자 — 인식 모듈의 `GeometricShapeFitter()`) — 새 노트 → 펜 포인터를 `SyntheticShapes.rectanglePath`를 따라 움직이고 INK 멈춤 시간보다 오래 유지 → 떼기 → `ShapeObject`(`ShapeKind.rectangle`) 1·획 0·되돌리기 1단계 → 되돌리기 → 다시 실행 → 닫기·다시 열기 → 도형 유지(다시 연 세션은 되돌리기 없음) |
| V6 | 같은 스모크를 Chrome에서(웹 런타임에 `dart:io`·네이티브 전용 플러그인 호출 없음 확인). (v2.2) V5 본 흐름만 — V5b는 VM |
| V7 | **마이그레이션**: 1차 코드로 만든 v1 DB 고정 자료(노트 3개·페이지 20장·획 2,000개·PDF 에셋 1개·설정·outbox 미전송 기록)를 v2로 열기 — VM(파일 DB)과 Chrome(웹 워커) 둘 다, 모든 행·필드 버전·outbox 유지, drift 생성 마이그레이션 시험 통과. (v2.1) 업그레이드 직전 v1 사본이 같은 저장소에 있고 그 정규 덤프 해시가 고정 자료 manifest와 같음 |
| V8 | `media` 태그(Chrome 가짜 마이크): 2초 녹음(가운데 1초 일시정지) → 정지 → 에셋 + `Recording` 행 → 재생·2배속·탐색, (v2.1) **파일 안 타임라인 길이**(WebM 블록 타임코드에서 계산 — 녹음 시계로 패치하지 않음, R-3)와 `offsetNowMs` 누적 비교 — (v2.2, C22-04 — CP-PDF-12) 시계 누적이 **파일의 마지막 패킷 구간 ±50 ms 안**: 마지막 블록 시작 − 50 ms ≤ 시계 ≤ 파일 끝(R-3 길이) + 50 ms. 마지막 패킷이 정지 시점 뒤를 무음으로 채워 '파일 끝 − 시계'가 +37~+59 ms로 나온다(06-pdf 6.1 E9~E11, 헤드리스 Chrome 6회 — 옛 판정식 '차 ≤ 50 ms'는 2/6 실패). 두 값(시계 − 마지막 블록 시작, 파일 끝 − 시계)을 진행 기록에 남긴다(조사 02 실측 −3~+7 ms는 시계로 패치한 파일이라 참고값) |
| V9 | 인식: `groupIntoLines` 합성 자료 정확도 ≥ 95%((v2.1) 생성기 = 05-library 6.6 v2.1 명세 — 페이지 공통 기울기·줄 사이 틈 보장, 정확도 계산법 포함. 실험 E-L5 결과로 문턱을 바꿀 때는 7.4.9 절차), 도형 판정 합성 1,400개(조사 03 4.2 조건) — 원 ≥ 98%, 직선·사각형·타원 ≥ 85%, 삼각형 ≥ 80%, 낙서 거부 ≥ 90%, 잘못 바꿈(다른 도형으로) ≤ 10%. 색인기 낡음 판정 시험(가짜 엔진), 웹 경로 `RecognizerUnsupported` |
| V10 | 검색: 조사 03 9.2의 질의(2·3글자, 낱말 중간, 영문 접두사, 여러 낱말 AND, 1글자 LIKE 대체)를 VM·Chrome에서 같은 결과로. 5,000쪽 합성 색인 질의 중앙값 ≤ 5 ms(VM). PDF 출처 결과의 사각형이 노트 페이지 pt로 맞음. (v2.1) 실제 모양 500쪽 PDF 색인 고정 자료로 DB 증가·Chrome 저장소 다시 열기 시간을 기록하고 7.4.5 목표 안 |
| V11 | PDF 내보내기(실제 PDFium VM·Chrome): 객체 4종 + 이미지 페이지 + 테이프 + 점선이 든 노트 → 내보낸 PDF를 pdfrx로 다시 열어 텍스트 상자 한글이 텍스트로 추출되고, 이미지 객체 수·수식 래스터·점선 조각이 맞음 |
| V12 | 네이티브 설정 정적 시험(매니페스트 `INTERNET`·서비스·권한·라벨, Info.plist 키, 배포 대상 15.5 × 3, Podfile 줄, release 서명 분기) + `ws native-reqs` 위반 0, CocoaPods 전용 플러그인 = ML Kit 둘뿐 |
| V13 | `functions/`: `npm ci && npm test`, 에뮬레이터 시험(로그인 없이 → `unauthenticated`, 목록 밖 UID → `permission-denied`, 잘못된 입력 → `invalid-argument`, 가짜 엔진 정상), Dart HTTP 클라이언트(`CallableMathRecognizer`) VM 시험(`emulator` 태그). (v2.1) 컨테이너에서 전역 잠금으로 실행 + CI 반복, 두 언어 시험이 가짜 엔진 값(7.6)을 같게 단언, 로그인 사용자 `owner-uid`·`stranger-uid` |
| V14 | CI에서 `android.yml` release APK가 고정 서명으로 만들어져 아티팩트로 남음(통합 때 1회). (v2.1) 고정 키를 쓰기로 한 저장소(변수 `ANDROID_CERT_SHA256` 있음)에서 서명 재료가 빠지면 잡이 **실패**하고, 고정 키 전에는 debug 서명이 아티팩트 이름(`noteapp-debug-signed-<run>`)에 드러난다. `ios-compile.yml` 1회 성공(U19 승인 시 2차 완료 조건 — 거절이면 '미확인'으로 기록하고 첫 TestFlight 빌드 전 필수) |
| V15 | 기능 스위치(D14): `FEATURE_MEDIA=false`·`FEATURE_RECOGNITION=false`·`FEATURE_MATH_ENGINE=false` 빌드에서 앱 스모크(1차 V5 범위)가 통과하고, 켠 빌드와의 차이가 기여 항목((v2.1) 녹음 버튼·인식 메뉴·수식 엔진·자동 도형 보정)뿐이고, 이미지 삽입·이미지 페이지는 모든 조합에서 남는다(D17)(`app/test/integration/feature_switch_test.dart`) |
| V16 | 웹 녹음 복구(D13, `media` 태그, Chrome 가짜 마이크): (v2.1) **실제 웹 CORE 저장소**(`openWebTestNoteStore`)에서 녹음 3초 중 녹음기를 dispose 없이 버림(탭 닫힘 흉내) → 최근 갱신 시간이 지난 뒤 새 컨테이너에서 `pendingDrafts()` 1개 → `recoverDraft()` → 에셋 + `Recording` 행, 길이 ≥ 2초, 원래 `recordingId` 유지(녹음 중 쓴 획의 연결이 살아 있음). (v2.1) 같은 저장소의 두 번째 녹음기는 녹음 중(최근 갱신) 초안을 복구 대상으로 내지 않음 |

### 7.8 실기기 체크리스트

A. **안드로이드 APK** (안드로이드 태블릿이 있을 때 — U2. 없으면 '코드만, 확인은 이후'로 표시)

| # | 확인 | 근거 |
|---|---|---|
| A-1 | (v2.1) 고정 키 2차 APK에서 노트·이미지·녹음 작성 → 다음 판 고정 키 APK를 덮어 설치 → 모두 남아 있음(파일 DB·파일 에셋). 처음 한 번은 기존 앱(1차 debug 서명 APK — 러너마다 키가 다르고 노트를 저장하지 못했다)을 지우고 설치한다. '설치되지 않음'이 뜨면 앱을 지우지 말고 알린다 | 공통-1, INFRA 검토 M-7 |
| A-2 | S펜: 닿은 채 측면 버튼 누르고 쓰기 → 지우기, 버튼 떼면 펜. Air command 켬/끔 각각 | M5-8, 조사 02 D6 |
| A-3 | 녹음 → 홈으로 나감·화면 끔 5분 → 돌아와 정지 → 길이·재생 정상, 알림 표시 | M6-2 |
| A-4 | ML Kit `ko` 모델 받기(크기 기록), (v2.1) `en` 모델도 받기(크기 기록), 한국어 문장·혼용 문장 30줄 문자 오류율(`ko` 단독 vs `ko`+`en`), 줄당 인식 시간 | M7-1, 조사 03 R1 |
| A-5 | 녹음 시계 오차 10회(파일 길이 − 시계) → 150 ms 넘게 일정하면 보정 필드 검토 | R-3, 조사 02 D9 |
| A-6 | 가로·세로·분할 화면에서 에디터·녹음 패널 | 조사 04 3.3 |

B. **iPad 웹(Safari, 홈 화면 앱)** — (v2.1) Firebase Hosting이 생긴 뒤(3.7, U24). 통합 미리보기 채널에서 확인하고, B-1만 실제 노트가 있는 live 채널

| # | 확인 | 근거 |
|---|---|---|
| B-1 | (v2.1) 1차로 쓴 실제 노트가 있는 출처(live 채널 홈 화면 앱 — U25)에서: 배포 전 백업 내보내기 → 그 출처에 2차 배포 → 첫 실행 → 노트가 그대로 열림(DB v2 이주) → 개발자 메뉴에 v1 사본 있음. 실제 노트가 없으면 1차 빌드로 노트 몇 개를 만든 뒤 같은 절차 | V7 실사용, CORE 검토 M-3 |
| B-2 | 텍스트 상자 한글 입력: 조합 중 글자·자동 완성·받침 이동·줄바꿈, 확대 상태에서 입력 | M5-2 |
| B-3 | 사진 보관함·카메라로 이미지 삽입(HEIC 사진 포함), 이미지 페이지. (v2.1) 삽입 메뉴·페이지 추가 시트에서 사진 보관함·카메라·붙여넣기가 한 번 눌러 바로 열림(사용자 동작 활성화 — 7.2.10) | M5-3·4 |
| B-4 | 도형 도구 7종, 자동 도형 보정(멈춤 500 ms)의 오인식 체감, 꼭짓점 편집 | M5-5·6 |
| B-5 | 올가미 회전 15° 맞춤·색 변경·잘라내기·붙여넣기(획 + 객체) | M5-1 |
| B-6 | 붓펜·캘리그래피·점선 필기감, 레이저 사라짐, 테이프 가림·탭 드러냄 | M5-10~12 |
| B-7 | 제스처 동작 바꾸기(두 손가락 탭 → 다시 실행 등) | M5-7 |
| B-8 | 녹음 30분(앞에 둔 채) → 재생 강조·필기 탭 재생·배속, `isEncoderSupported`·MIME(개발자 표시). (v2.1) 패널 열기 직후 재생 바 길이 표시, 녹음 정지 직후 필기가 흐려지지 않음 | M6, 조사 02 D1·D2 |
| B-9 | 녹음 중 앱 전환·화면 잠금 → 자동 일시정지·안내, Screen Wake Lock. (v2.1) 앱 전환 → 돌아와 이어서 녹음 → 정지 → 한 파일로 재생 | M-2, 조사 02 D3·D4 |
| B-10 | 검색: 텍스트 상자·PDF 텍스트·수식으로 찾기 → 결과 누르면 그 페이지·위치로 | M7-2~4 |
| B-11 | 수식: LaTeX 입력 → 렌더, 크기·색, LaTeX 복사((v2.1) 선택 메뉴 '텍스트 복사' → 메모에 붙여넣기 됨), PDF 내보내기(루트·연립방정식 기호 포함) | M7-5 |
| B-12 | Pencil 호버가 `kind: stylus` 호버로 오는가(개발자 표시) | 조사 02 D8 |
| B-13 | 복합: PDF 200쪽 + 이미지 20개 + 녹음 30분 노트에서 스크롤·필기·재생·내보내기 → 탭 재로드 없음, 개발자 표시 캐시 합계 ≤ 300 MB, 내보낸 PDF를 다른 앱에서 열어 텍스트 상자 글자가 검색됨. 1차 7.7 V7 복합 항목(PDF 500쪽)도 다시. (v2.1) PDF 500쪽 색인이 끝난 뒤 앱 다시 열기 시간·메모리 기록 | 7.4.5, B W10 |
| B-14 | 녹음 중 Safari 탭 닫기(또는 새로 고침) → 다시 열면 '복구된 녹음'이 목록에 있고 길이가 닫기 직전까지(오차 ≤ 1초), 녹음 중 쓴 획의 탭 재생 동작 | M-2, D13 |
| B-15 | (v2.1) 텍스트 상자(키보드 없이): 두 번 탭 낱말 선택·선택 손잡이·붙여넣기 메뉴, 편집 중 두 손가락 스크롤·핀치에도 편집이 이어짐, 편집이 끝날 때 글자가 튀지 않음 | M5-2, EDITOR 검토 M-2 |
| B-16 | (v2.1) 녹음 패널을 연 채(재생 안 함) 녹음된 글씨 위에 마침표 → 점이 남음, 손가락 탭 → 그 시점부터 재생, 재생 중 펜 점 → 그 시점으로 이동 | R-5, U26 |

C. **TestFlight 뒤(Apple 유료 계정 가입 후)** — 2차 완료 조건이 아니다

| # | 확인 |
|---|---|
| C-1 | Pencil 더블탭·스퀴즈(시스템 설정 따르기·앱 설정), 배럴 롤 캘리그래피, 호버 높이 |
| C-2 | 백그라운드 녹음(앱 전환·잠금), 녹음 → 재생 전환 때 세션·스피커, 다른 앱 음악 재개(조사 02 D5) |
| C-3 | ML Kit iOS 인식(A-4와 같은 목록), 모델 받기가 셀룰러를 막는지 |
| C-4 | 네이티브 필기 지연(PLAN 5.4 20 ms) — 1차부터 미뤄진 판정 |

### 7.9 계약 변경 이력

#### v2.9 (2026-11-13, 손글씨 검색 — 사용자 요청 '텍스트로 변환하지 않더라도 적은 글씨를 검색하면 검색이 되어야 해')

추가와 기본값 하나. 설계는 05-library 6.19a, 02-core 6.10.2 '손글씨 띄어쓰기'.

| # | 절 | 변경 | 출처 | 반영할 영역 |
|---|---|---|---|---|
| C29-01 | 7.4.4 설정 키, 7.8 U16 | `recog.autoIndex` 기본값 false → **true**. 첫 값이 켬이면 색인기 provider가 `onAutoIndexTurnedOn`으로 모델을 요청 | 사용자 요청 | LIBRARY(처리됨) |
| C29-02 | 7.2.11 recog 내보내기 | `HandwritingSearchPhase`·`HandwritingSearchStatus`·`HandwritingSearchReadiness`·`handwritingSearchReadinessProvider`(엔진 없음 → null) | 05-library 6.19a | LIBRARY(처리됨) |
| C29-03 | 7.2.11 라이브러리 자리 | `LibraryInkSearch`·`LibraryInkSearchPhase`·`LibraryInkSearchState`·`libraryInkSearchProvider`(기본 null → 안내 없음). 앱 셸 `libraryInkSearchOf`가 C29-02를 옮기고 `ShellContribution.libraryInkSearch`로 FeatureWiringModule이 덮어쓴다. 새 패키지 의존 없음(R8) | 05-library 6.19a | LIBRARY·INFRA(처리됨) |
| C29-04 | 7.2.5 검색 판정 | `SearchSource.ink` 단위만 CJK 사이 공백(검토 반영: 한글–숫자 사이 포함)을 지운 글로도 색인·판정(조각 범위 포함, 줄인 글로만 맞으면 점수 −0.1, 두 글자 이하 CJK 질의는 제외). 옛 ink 행은 저장소 열 때 한 번 ink만 재구축(kv `search.inkTermsVersion` = 2, ink 행이 없으면 바로 기록). 다른 출처 결과는 그대로 | 02-core 6.10.2 | CORE(처리됨) |
| C29-05 | 7.2.11 recog·라이브러리 자리 | (검토 반영) `HandwritingSearchPhase.unsupported`·`LibraryInkSearchPhase.unsupported`(이 기기에서 쓸 수 없음 안내) 추가 | 05-library 6.19a | LIBRARY·INFRA(처리됨) |

#### v2.10 (2026-11-13, 텍스트 펜 1단계 — 사용자 요청 '글씨를 쓰면 글씨로 변환')

(번호: v2.9·C29-xx는 같은 날의 손글씨 검색 트랙이 쓴다 — 겹치지 않게 v2.10·C210-xx.)

추가만(옛 앱·옛 JSON 호환, 저장 형식 변경 없음 — 텍스트 상자는 기존 `TextBoxObject`). 편집기 설명은 [04-editor.md 15절](04-editor.md#15-텍스트-펜-1단계-2026-11-13-계약-v210-c210-01), recog 설명은 [05-library.md 15절](05-library.md#15-텍스트-펜-1단계-2026-11-13-계약-v210-c210-02).

| # | 절 | 변경 | 출처 | 반영할 영역 |
|---|---|---|---|---|
| C210-01 | 7.2.10 EDITOR 확장 지점 | `EditorExtensions.textPen: EditorTextPen?`와 새 타입 `EditorTextPen`·`EditorTextPenSession`(update·interrupt·clear·`convert(group)`·`fix(group)`·changes·`buildBubble(…, onConvert, onFix)`·dispose), 별칭 `EditorPenContext`(= `EditorMathPenContext`)·`EditorPenGroup`(= `EditorMathGroup`). `EditorTool.textPen`(편집기 내부, `textPen == null`이면 펜처럼). `EditorSelectionMenuItem.pinned`(기본 false — true면 선택 막대에서 언제나 ⋯ 앞). 변환은 말풍선 탭(또는 변환 창)에서만 — 배경 변환 없음 | 사용자 요청 | EDITOR(처리됨) |
| C210-02 | 7.2.11 recog 내보내기 | `RecognitionTextPen`·`RecognitionPenContext`(= `RecognitionMathPenContext`)·`RecognitionTextPenSession`·`recognitionTextPen()`, `RecognitionAction.pinned`(`recog.toText` true). 앱 셸 `editorTextPenOf`가 편집기 자리로 바꾸고(`ShellContribution.textPen`) `selectionMenuItemOf`가 `pinned`를 넘긴다. 패키지 사이 새 의존 없음(R8), 이름 겹침 없음(R14) | 사용자 요청 | LIBRARY·INFRA(처리됨) |

#### v2.8 (2026-11-13, 수식 펜 1단계 — 사용자 승인 '1단계 진행해줘')

추가만(옛 앱·옛 JSON 호환). 설계와 구현 결과는 [research/math-pen-phase1.md](research/math-pen-phase1.md)(0절 '구현 결과').

| # | 절 | 변경 | 출처 | 반영할 영역 |
|---|---|---|---|---|
| C28-01 | 7.2.2 `MathObject`·`PageObjectLimits` | `MathObject.ink: List<Stroke>`(변환한 손글씨 — 다시 열기용, 기본 빈 목록, `copyWith(ink:)`, `transformed`가 함께 변형, `copyTo`가 페이지를 바꿈, `==`·`estimatedBytes`에 포함). `PageObjectLimits.maxMathInkStrokes = 400`·`maxMathInkPoints = 40000`(로컬 명령 해석 때 `ArgumentError`) | 수식 펜 설계 5 | CORE(처리됨) |
| C28-02 | 7.2.7 JSON 키 표 `math` 행 | 키 `ink` 추가 — 언제나 쓴다(빈 목록이면 `null`). 읽기: 키 없음(옛 JSON)·`null`·깨진 항목 → 빈 목록(수식은 살림). 옛 앱은 알려진 종류의 모르는 키를 무시한다(CORE 6.2.6) | 수식 펜 설계 5.3 | CORE(골든 `math_ink.json` 등 — 처리됨) |
| C28-03 | 7.2.8 SYNC 키 | `keysOf(pageObject)`에 `ink`. `wholeUnitExcept`는 그대로 → `ink`는 frame·latex·style과 한 병합 단위 | 수식 펜 설계 5.3 | SYNC(처리됨) |
| C28-04 | 7.2.10 EDITOR 확장 지점 | `EditorExtensions.mathPen: EditorMathPen?`와 새 타입 `EditorMathPen`·`EditorMathPenContext`·`EditorMathGroup`·`EditorMathConvertTrigger`·`EditorMathPenSession`. `EditorTool.math`(편집기 내부, `mathPen == null`이면 펜처럼). (1단계 검토 반영) `EditorMathPenSession.convert`·`RecognitionMathPenSession.convert`에 선택 인자 `stillWanted`(배경 변환이 execute 직전에 묻는 편집기 기록 확인 — 호출자 불변) | 수식 펜 설계 11.1 | EDITOR(처리됨) |
| C28-05 | 7.2.11 recog 내보내기 | `RecognitionMathPen`·`RecognitionMathPenContext`·`RecognitionMathPenSession`·`recognitionMathPen()`. 앱 셸 `editorMathPenOf`가 편집기 자리로 바꾼다(`ShellContribution.mathPen`). 패키지 사이 새 의존 없음(R8), 이름 겹침 없음(R14) | 수식 펜 설계 11.1 | LIBRARY·INFRA(처리됨) |

#### v2.7 (2026-11-12, 2차 통합 — 총괄)

시그니처 변경 없음(문구 해석 확정·규칙 추가·예산 값). 통합 결과는 [00-review.md '2차 통합 결과'](00-review.md#2차-통합-결과).

| # | 절 | 변경 | 출처 | 반영할 영역 |
|---|---|---|---|---|
| C27-01 | 7.4.5 웹 예산, 7.7.2 V4 | **총괄 결정(INFRA '총괄 결정 필요')**: `main.dart.js` gzip 1,902,969 B(원본 6,477,160 B — 통합 끝 `42b01c7`에서 `ws web-budget check`로 다시 잰 값. INFRA 통합 단계 실측 1,902,938 B / 6,476,935 B는 INK `55bf85a`(`Int64List` 제거) 전 빌드라 31 B 작다)가 한도 1,666,038 B를 236,931 B 넘었다(1차 기준 +536,931 B — 영역 2차 구현 몫, 기능 끈 빌드와의 차 원본 −420 KB). 선택지 ③(둘 다)을 단계로 고른다: **지금** 기준(`baseline`)을 이 통합 빌드로 옮기고 `main_dart_js_gzip_max` = 2,000,000 B(약 +5 %), 라운드당 증가 300,000 B 규칙은 새 기준에서 그대로. **나중**(3라운드 후보) `deferred` import로 녹음·인식·수식·PDF 내보내기를 첫 적재에서 뺀다 — iPad Safari 첫 실행 시간(7.8 B, Hosting 뒤)을 본 뒤 판단한다. 근거: 개인용 홈 화면 앱이라 첫 적재는 배포마다 한 번이고 캐시되며, 컨테이너 첫 프레임 1,580 ms(H7)는 1차(약 1.7 s)와 같다. 시작 글꼴(385,521 B — C24-01 한도 안)은 그대로 | INFRA H5·V4 | INFRA(`tool/web_budget.yaml` 기준·한도, 01-infra 6.15 표 — CI `web` 잡 'Web budget' 단계가 다시 통과. 반영 전까지 V4는 '대기') |
| C27-02 | 7.2.9 벡터 내보내기 v2, 7.7.2 V11 | '점선은 대시 조각으로 미리 나눔'의 뜻을 확정: 점선 획 하나 = **`InkFillShape` 하나**, 그 경로의 하위 경로(`moveTo`)마다 대시 하나(03-ink 6.21). V11의 '점선 조각' = 그 하위 경로 수(> 1), PDF 쪽 칠한 경로 객체 수 = 그 모양 수 | INK 변경 요청 → PDF `48168da` | PDF(V11 VM·Chrome — 처리됨) |
| C27-03 | 7.2.9 `hitTestObject`·지우개 | 채우지 않은 도형은 **외곽선(tol + w/2, 지우개는 R + w/2) 근처에서만** 맞고, 안쪽은 채웠을 때만 맞는다(03-ink 6.14·6.15, U22). 기반 단계의 경계 상자 적중은 단순 구현이었다. 안쪽 탭으로 빈 도형을 골라야 한다는 결과가 실기기(7.8 B-4·B-5)에서 나오면 그때 7.4.9 절차로 바꾼다 | INK 변경 요청 → EDITOR `311e209` | EDITOR(VM 시험 4개 — 처리됨) |
| C27-04 | 7.2.3 `NoteContentReader.getPage`, 7.2.4 `renameRecording` | 문장 그대로 확정: `getPage`는 **활성 페이지 또는 null**(삭제된 페이지도 null — 삭제 여부는 동기화 JSON `deletedAt`으로 본다), `renameRecording`은 없거나 삭제된 녹음이면 `EntityNotFoundException`. 시험용 가짜(SYNC `TestDevice`)도 이 규칙을 따른다 | CORE 변경 요청 → SYNC `04602cc` | SYNC(H3·R1·`TestDevice.renameRecording` — 처리됨) |
| C27-05 | 7.2.5 `SearchIndexWriter` 소유 키 | 시험 탐침도 계약 키 형식(`<assetId>#<pdfPageIndex>`, 64자 16진 `assetId`)을 지킨다 — 형식이 틀리면 `ArgumentError`(미구현 신호가 아님). 실제 저장소 변형을 `UnimplementedError` 탐침으로 건너뛰던 시험은 이정표가 모두 병합된 지금 탐침을 걷어 낸다(통합 단계 공통) | CORE 변경 요청 → PDF `48168da` | PDF(처리됨), 전 영역(탐침 제거 — 처리됨) |
| C27-06 | 7.4.3 웹 안전 수, 7.7.2 P-B 판정 | ① **`lib/` 코드에 `Int64List`·`Uint64List`를 쓰지 않는다**(dart2js·DDC 미지원 — 웹에서 실행 중 예외). 정수 배열은 `List<int>`·`Int32List`(범위가 맞을 때)·`Float64List`. 웹에서 칠하거나 계산하는 경로는 Chrome 시험을 하나 이상 둔다. ② P-B 기준 판정과 미룬 작업 표를 7.7.2에 둔다(위) | INFRA V6 v2 → INK `55bf85a` | INK(처리됨), 전 영역(규칙). `ws check` 규칙화는 3라운드 INFRA 후보 |
| C27-07 | 7.7.2 V14, 7.7.1 9단계 | V14의 판정을 둘로 나눈다: **컨테이너 몫**(`workflows_test`·`native_config_test` 정적 시험 — 서명 분기·아티팩트 이름·재료 빠짐 실패)은 2차 통합 완료 조건, **GitHub 실행**(`android.yml` release APK 1회 — 고정 키 등록 U20 전에는 `noteapp-debug-signed-<run>`, `ios-compile.yml` 1회 — U19)은 총괄 푸시 뒤 수동 실행(사용자 'Run workflow')으로 확인하고 진행 기록에 남긴다. 1차 V7처럼 '사용자 확인 대기'로 두되 2차 완료를 막지 않는다 | 총괄(H6) | INFRA(결과 기록) |

#### v2.6 (2026-11-06, 2차 동시 개발 끝 — 총괄)

| # | 절 | 변경 | 출처 | 반영할 영역 (통합 단계) |
|---|---|---|---|---|
| C26-01 | 7.7.2 V8 판정식(C22-04) | 위쪽 한계를 `endMs + 50 + 60 × (일시정지 수)` ms로 넓힌다(실제 Chrome MediaRecorder에서 일시정지 한 번마다 파일이 패킷 하나 ≈ 60 ms 짧아짐 — PDF T39 실측 +35·+46·+52·+65 ms). 아래쪽 한계는 그대로 | PDF T39 | PDF(record_playback_media_test 판정식) |
| C26-02 | 7.2.12 PDF 공개 표면, 7.3.3 | `pdfDevOverlayLinesProvider`(`Provider<List<String>>`, 기본 빈 목록, media_io의 `mediaDevOverlayLinesProvider`와 같은 모양)를 **추가만**으로 둔다 — 내보내기 장부 `overBudget`·`peakBytes` 줄(C22-06 ②). INFRA가 FeatureWiringModule의 PDF DevOverlaySection에 붙인다 | PDF T26 | PDF(provider + 시험, debugPrint 제거), INFRA(연결 + overrides 시험) |
| C26-03 | 7.2.5 `searchPages` 스니펫·사각형 | PDF 결과의 강조 사각형은 **질의 낱말마다 그 페이지 첫 일치**를 합친 목록으로 준다(1차 `searchNote`처럼 구 전체가 강조되게). 순서·후보 규칙(7.2.5, CP-14)은 그대로 | PDF 검토 | CORE(실제·가짜 같게 — 공유 계약 시험 갱신) |
| C26-04 | PDF 엔진 어댑터 | PDFium이 줄 끝 하이픈 낱말을 이어 붙일 때 넣는 U+0002(낱말 글자 사이)는 PDF 엔진 어댑터가 U+00AD로 바꿔 넘긴다(같은 길이 — 글자 상자 1:1 유지). CORE 정규화는 바꾸지 않는다 | PDF 검토 | PDF(어댑터 + 'IN-/DEXING' 시험) |

#### v2.5 (2026-11-06, 2차 동시 개발 중 — 총괄)

| # | 절 | 변경 | 출처 | 반영할 영역 |
|---|---|---|---|---|
| C25-01 | 7.7.2 V10, 02-core 6.19 PF-3·PF-4 | **CP-18 승인.** 5,000쪽 합성 색인 질의 예산을 '후보 100개 미만 질의 중앙값 ≤ 5 ms(1글자 LIKE ≤ 15 ms), 그 밖의 질의(후보 상한 2,000까지) ≤ 50 ms(VM)'로 바꾼다. 7.2.5 후보 규칙(살아 있는 후보만, 2,000개, 최신순)과 CP-14(가짜와 같은 판정·순서)는 그대로 — 흔한 낱말 질의 비용은 이 두 규칙에서 나오고, 개인용 검색에서 50 ms는 충분하다 | CORE T33b·T37 | CORE(search_perf_test 'V10 as written' → v2.5 판정, 계획 6.19·6.10.7 문구) |
| C25-02 | 7.2.9 INK 진단 | `InkDiagnostics`에 **`Map<String, num> get developerValues`**를 추가한다('추가만' — 기존 시그니처 불변). 키: `playbackPaintUs`(층 4′ 재생 그리기 p95 µs), `annotationPaintUs`(annotation 층 p95 µs), `mathCacheBytes`(수식 래스터 캐시 바이트, 6.22). 값이 없으면 키를 넣지 않는다 | INK T40·T43 | INK(`@internal` 제거·`mathCacheBytes` 추가·시험), EDITOR(개발자 표시에 세 값 — 통합 단계에서) |
| C25-03 | 03-ink 6.25 B14·B17 | 벤치 기준(디버그 VM): B14 ≤ 25 ms, B17 ≤ 100 ms. 원래 기준(12 ms·60 ms)은 iPad 릴리스 빌드 실측(9.6)으로 판정 | INK T43 | INK(benchmark README·계획 6.25) |
| C25-04 | 3.4 우선순위 | INK T39(자동 도형 보정 멈춤 감지·미리보기, P-B)는 미루지 않고 이번 라운드에 한다 — F-11 '펜을 잠시 멈추면 반듯한 도형'의 핵심이고 EDITOR E2-15·LIBRARY L2-06은 이미 끝났다. EDITOR E2-18(Pencil 소비)·E2-10b(텍스트 초안)도 같은 이유로 이번에 한다. INK T44(ink lab v2, P-C)는 미룸 | 총괄 | INK, EDITOR |

#### v2.4 (2026-11-06, 2차 동시 개발 중 — 총괄)

시그니처 변경 없음.

| # | 절 | 변경 | 출처 | 반영할 영역 |
|---|---|---|---|---|
| C24-01 | 7.4.5 (시작 글꼴 예산) | 묶음별 시작 글꼴 한도: **KaTeX gzip ≤ 380,000 B, 아이콘 gzip ≤ 20,000 B, 합계 ≤ 400,000 B**(J0 실측 KaTeX 371,014 B·아이콘 11,414 B). 410,000 B로 올리는 대안은 기각 — 합계를 늘리지 않고 KaTeX 여유 2.4%로 충분 | INFRA J0 | INFRA(`tool/web_budget.yaml` gzip_max 두 값 — 통합 단계 H에서) |
| C24-02 | 7.7 (통합 순서) | INFRA 2차 체크포인트 병합을 다른 영역보다 먼저 한다(INFRA Q14, J0 ④ CI 실측용). 다른 영역은 앱 셸을 가져오지 않으므로(D24) 순서 영향 없음. INFRA 통합 단계(H1~H8)는 7.7 순서대로 마지막 | 총괄 | 없음 |

#### v2.3 (2026-11-06, 2차 기반 단계 R2-B1~R2-B6 완료 후 — 총괄)

시그니처 변경 없음. 기반 단계 결과 보고의 총괄 결정 요청을 처리했다.

| # | 절 | 변경 | 출처 | 반영할 영역 (개발 중) |
|---|---|---|---|---|
| C23-01 | 7.4.7, 7.5 | `firebase-tools` 고정 판을 **15.34.1**(2026-10-21 게시)로 한다. 15.34.2는 14일 규칙상 2026-11-11 23:18 UTC 뒤에야 넣을 수 있어 기반 단계를 막는다. 올리는 것은 실연결 미니 라운드 때 다시 판단 | SYNC R2-B7b | SYNC(07-sync 3.4·7.2 표기), INFRA(CI·functions.yml 고정값 확인) |
| C23-02 | 7.4 (코드에 모델 이름 금지), 07-sync 6.8 | 서버 함수 매개변수 `CLAUDE_MODEL`의 기본값은 **빈 문자열**이다. 비어 있으면 Claude 엔진은 `notConfigured`(unavailable)로 답한다. 모델 이름은 코드·커밋에 쓰지 않고, 프로젝트별 `.env.<projectId>`(실연결 미니 라운드, 사용자 결정 U6)에만 둔다 | SYNC R2-B7b | SYNC(S2-12 전에 07-sync 6.8.4·6.8.9·1770행 표 고침) |
| C23-03 | 7.6.2 R2-B3 | INK 글꼴 `flutter: assets:` 블록(파일 3줄)은 03-ink 3.1대로 INK 몫이지만 기반 단계 지시에서 빠져, 총괄이 `packages/ink_engine/pubspec.yaml`에 직접 넣었다(lock 변화 없음, `ws test --package ink_engine`·웹 빌드·`web-assets verify` 통과). 이후 이 블록의 소유는 INK | INK R2-B3, INFRA R2-final | INK(`pubspec_assets_test` T26a 확인) |
| C23-04 | 7.4 CI 정책 | INFRA R2-B1의 CI 세부를 승인한다: ① 기본 브랜치(main 아님) 푸시마다 동시성 그룹을 따로(`run_id`) — 바뀐 멤버만 시험하므로 취소되면 그 변경이 시험되지 않기 때문 ② 바뀐 멤버만 시험할 때도 `check --strict`는 돈다 ③ 기본 브랜치 수동 실행은 전체 ④ `android.yml`은 수동 실행만. 월 추정 약 1,346분 | INFRA R2-B1 | INFRA(그대로) |
| C23-05 | 04-editor 4.3.1·4.3.2 | `recordingPanel` 등 함수 값 비교는 `identical` 대신 Dart 함수 `==`(1차 `EditorMenuItem`·`appBarTrailing`과 같음 — 같은 인스턴스 메서드의 tear-off가 다른 값으로 보이지 않게). 4.3.2의 `withAction` 예외 문구는 EDITOR가 코드에 맞춰 고친다 | EDITOR R2-B5 | EDITOR(계획서 문구) |
| C23-06 | 03-ink 6.10.1·8.1 | 글꼴 크기·해시(Regular 466,936 B `b8acd7a9…`, Bold 466,440 B `f53c5385…`, google/fonts `24ddc1f`)와 '강제 strut 줄 높이는 정수 pt로 반올림' 사실을 INK 계획서에 반영(진행 기록 '## 2차' 근거) | INK R2-B3 | INK(계획서) |
| C23-07 | 7.2.9 시험 도우미 | `FakeInkShapeFitter`의 설정 필드 이름은 `result`(`fit`은 `InkShapeFitter.fit` 메서드와 겹침). 생성자 인자는 `fit:` 그대로. InkFonts·InkTextLayout을 쓰는 Chrome 시험은 `useInkTestFonts()`를 setUpAll에서, `InkMathRenderer.layout`은 WidgetsBinding 초기화 필요(일반 `test()`면 `TestWidgetsFlutterBinding.ensureInitialized()`) | INK R2-B3 | EDITOR·LIBRARY·PDF·INFRA(시험 작성 시) |

#### v2.2 확정 (2026-11-05, 총괄 최종 승인 — 근거: [00-review.md '최종 승인'](00-review.md#최종-승인))

영역 계획서 수정 회차에서 새로 올라와 '판정 대기'로 남은 CP 6건(CORE CP-16·CP-17, INFRA CP17, PDF CP-PDF-12·13·14)을 모두 받아들이고, EDITOR 12.2 Q16에 답하고(V5b·'P-B에 기대는 기준'), 바탕 HEAD를 고쳤다. **시그니처 변경은 추가 하나**(C22-01 — 아직 아무도 구현하지 않은 `dev_tools.dart` 함수, CORE·INFRA 계획서가 이미 같은 모양을 쓴다)이고 나머지는 규칙 문구다. 모두 해당 계획서의 CP·질문·설계에 이미 적힌 동작·기준을 계약으로 옮긴 것이라 어느 영역도 재승인이 필요 없다. 계획서의 인용 문장은 개발 착수 때 맞춘다(C22-09).

| # | 절 | 변경 | 분류 | 출처 | 반영할 영역 (개발 중) |
|---|---|---|---|---|---|
| C22-01 | 7.1 표·7.0.1 C2-40·7.2.7 | `dev_tools.dart` v1 DB 사본 API(`V1DatabaseCopyInfo`·`v1DatabaseCopyInfo`·`readV1DatabaseCopy`(≤ 4 MiB 조각)·`deleteV1DatabaseCopy`). 가짜 저장소는 `null`·아무것도 안 함 | 추가 | CORE CP-17(INFRA 옛 CP16은 거두고 지지 — 01-infra 12.2) | CORE(B2-α 선언·T24 동작 — 02-core 6.12.4 그대로), INFRA(J14b `V1CopyApi` — 이미 이 모양) |
| C22-02 | 7.2.7 | v1 사본 방법을 저장 방식별로: 네이티브 `VACUUM INTO` 임시 이름 → 이름 바꾸기, 웹 블롭 저장소 정규 덤프(`meta` 마지막), 수명 = 정상 열기 5번 이상 + 7일, 실패해도 이주 진행 | 규칙 | CORE CP-16(T24 첫날 Chrome 확인 항목은 정규 덤프 사본의 만들기·해시·지우기·다시 열기 시간으로) | CORE(T24), INFRA(안내서 04·08 문구 — 이미 이 내용) |
| C22-03 | 7.4.1 | `ws native-reqs` 비교 대상 = `.flutter-plugins-dependencies`의 `dependencyGraph` 이름 집합 | 규칙 | INFRA CP17 | INFRA(NR6 — 이미 이 기준) |
| C22-04 | 7.2.4 R-3, 7.7.2 V8 | R-3 '프레임 길이' → '그 블록(패킷)의 길이', V8 판정식 → 시계 누적이 마지막 패킷 구간 ±50 ms 안 | 규칙 | CP-PDF-12(06-pdf 6.1 E9~E11 실측) | PDF(6.8.7 — 두 값을 기록하고 새 판정식으로 단언), CORE(R-3 주석 인용만) |
| C22-05 | 7.3.2 M-4 | 길이 보정 = 머리 + 원본 나머지를 한 번 복사해 합친 뒤 원본을 바로 버림(`AssetStore.put`이 연속 `Uint8List`) — 보장 문장 '두 벌 넘게 들지 않음'은 그대로 | 규칙 | CP-PDF-13 | PDF(이미 이 구현 — `BufferLedger` `peakCount ≤ 2`) |
| C22-06 | 7.4.5 | 내보내기 임시 16 MB의 범위와 예외 둘(네이티브 isolate 전달 사본, M-3 밖 큰 입력 디코드) | 규칙 | CP-PDF-14 | PDF(이미 장부 `copy`·`overBudget` — 06-pdf 6.2.10) |
| C22-07 | 7.7.1 5·7단계, 7.7.2 | 'P-B에 기대는 기준' 규칙과 표. V5 본 흐름에서 '합성 멈춤으로 자동 도형'을 떼어 V5b(P-B, VM)로. V6은 본 흐름만 | 규칙 | EDITOR 12.2 Q16(총괄 답) | INFRA(9.1 V5 2단계·V5b·H3·10 #3 — 총괄 직접 수정, 01-infra 13.7), EDITOR(E2-23·10 #5 — 총괄 직접 수정, 04-editor 13.4), LIBRARY(10 #4·#5의 L2-06·L2-I3·L2-I6 몫을 이 규칙으로 읽음), SYNC(V13 몫 — 이미 P-B 표시) |
| C22-08 | 2.5 | 바탕 = 1차 통합 HEAD `b6c9d0a`(`18c5ae5` 뒤 8커밋 — INK 퇴화 판정 문구·시험, 문서, INFRA CI `bb1bc60`) | 규칙(사실) | INFRA 수정 2회차(01-infra 13.6 #2) | 전 영역(인용), INK(`lasso_polygon.dart`·`lasso_options.dart`는 `446518e` 판에서 시작) |
| C22-09 | 7.6.2 마지막 bullet | 기반 단계 뒤 '가정' 블록 교체 때 계약 인용(v2.2)·상태 줄을 맞추고 00-review '최종 승인'의 자기 항목을 처리 | 규칙 | 총괄(최종 승인 절차 — 1차 C13-05와 같음) | 전 영역 |

기각·보류: 없음. 함께 답한 질문(계약 문장 변화 없음): EDITOR Q15(내부 기기 키 2개를 7.4.4 '키 확정'에 올리지 않음), CORE Q11·Q12(CP-16·17 판정 시점 — 지금 판정, 수명 5번 + 7일), INFRA Q14·Q15·Q16 — 00-review '최종 승인'.

#### v2.1 확정 (2026-11-05, 총괄 — 7개 영역 계획서 초안 + 대리 검토 7건 반영)

시그니처 변경은 모두 아직 아무도 구현하지 않은 2차 표면이거나 기본값이 있는 추가다(1차 표면의 깨짐은 C2-38 동작 하나 — CORE 내부). 출처의 '검토'는 `reviews/<영역>.md`, 'CP'는 그 영역 계획서 12장 제안이다. 결정 근거와 영역별 할 일은 [00-review.md](00-review.md).

| # | 절 | 변경 | 출처 | 반영할 영역 |
|---|---|---|---|---|
| C21-01 | 머리말·7장 머리 | 1차 기준을 v1.5(1차 통합 반영, 시그니처는 v1.4와 같음)로 | 총괄(1차 통합 완료) | 전 영역(인용 문구) |
| C21-02 | 1·2.5·7.6.1 | 바탕 코드 = 1차 통합 HEAD(`/home/user/noteapp` `18c5ae5`). 1차 V7(iPad)은 2차 기반 단계의 전제가 아님(D21) | INFRA 검토 M-1, PDF 검토 S-13 | 전 영역('전체' 블록·시험 수·예산 기준) |
| C21-03 | 3.3·3.5·3.7(새) | D17~D24, 실기기 확인 경로와 Firebase 없는 동안의 처리(Hosting Spark ≠ 실연결) | 총괄, INFRA 검토 M-4, PDF 검토 Q-1·Q-4 | INFRA(안내서), 전 영역 |
| C21-04 | 7.0.1·7.0.2 | C2-05 깨지는 곳 정정(switch 4 + `kindOrder` + `fixtureJson`), C2-14·C2-29·C2-32 문구, C2-12·18·21·25 추가분, 새 행 C2-38(캘리그래피 각)·C2-39(`testing_web.dart`) | SYNC 검토 C-1, INFRA CP9·C-4, INK CP-INK-4 | SYNC(없음 — 계획서 6.4가 맞음), CORE |
| C21-05 | 7.1 | `note_core/testing_web.dart` 진입점 | PDF 검토 X-6②·PDF Q2 | CORE, INFRA(R4 예외) |
| C21-06 | 7.2.2 | `PageObject.transformed(m, {scaleWidth})` = 객체 변형의 단일 규칙(도형 굵기·텍스트·수식 글자 크기), CORE 확정 세부 계약화(`UnknownObject` 생성자·`toJson` 메타 키·`estimatedBytes`·`ElementFrame.normalized`·`==`), 스타일 정규화·`fromJson` 비정규화, 모르는 enum → `UnknownObject`, `UnknownObject.referencedAssets` | INK 검토 M-2·C-6, CORE CP-2·CP-4·CP-5·CP-6, CORE 검토 S-1·S-13 | CORE, INK(미리보기), EDITOR |
| C21-07 | 7.2.3 | 새 명령 3개 = 이름 있는 인자 + `const` + `label`, `RemoveElements.elementIds: List`, 1차 명령 표기 정리, 매핑 표 4행 추가 | CORE CP-1, EDITOR CP-E1·CP-E5·C-6, INK CP-INK-2 | CORE, INK(`toCommand`), EDITOR, LIBRARY(recog) |
| C21-08 | 7.2.4 | `pendingDrafts` 제외 규칙, `start` `UnsupportedError`·`stop` 실패 시 초안 유지·`createRecording` 멱등, `play` 녹음 중 무시, 빈 조각 `append`·`listDrafts` meta 복원, `copyWith`, R-3 WebM 타임코드 길이, R-5 탭 재생 상태·강조 초점 시점 | INFRA CP6, PDF CP-PDF-3·5·10·검토 M-5·M-6·M-8·C-4·C-6, CORE CP-7·검토 S-3·S-14, EDITOR 검토 M-3·C-7 | CORE, PDF(media), EDITOR, INFRA |
| C21-09 | 7.2.5 | `HandwritingRepository.update`·`notesWithStalePages`, `userConfirmed` 유지 규칙, 신선함 = `sourceRev` + 언어, `copyWith`, `SearchUnitDraft.pdfPageAspect`·사각형 정밀도·저장 위치, 빈 단위 = 소유자 유지, 후보 선택 기준·가짜 같은 순서, `normalizeMapped`, `pagesTruncated` 뜻, pdf `sourceRev` 꼬리 | LIBRARY 검토 M-1·S-2·S-3·C-3·C-4·Q8, CORE CP-3·CP-10·CP-13·CP-14·검토 M-1·S-6·S-8, PDF CP-PDF-2 | CORE, LIBRARY, PDF, SYNC(손글씨 LWW 수용) |
| C21-10 | 7.2.6 | 로컬 이미지 `put` 형식 검사, 네이티브 블롭 루트는 CORE가 만듦 | CORE CP-11, INFRA 검토 S-16 | CORE, INFRA |
| C21-11 | 7.2.7 | `math.engine` 항상(null), 키 집합 고정, 검색 테이블 정정(`search_owners`·`seq`·FTS 옵션·사각형), `*.steps.dart`, 고정 자료 생성 커밋, 업그레이드 직전 v1 사본 | CORE CP-15·검토 C-7·S-2·M-3·Q-2 | CORE, SYNC(`kPageObjectTypeKeys`), INFRA(`generated_files`·개발자 메뉴) |
| C21-12 | 7.2.8 | 병합 단위 = 나머지 키 전부(CP-S1), 영구 삭제 문구(노트 단위), 손글씨는 편집으로 세지 않음(최근 보냄 포함), S-13 보강(청크 단위 전부/전무·메타 키 나눔·깨진 값 되감기·LRU 제외·K1 보관 유지), JSON 키 대조 v2 | SYNC CP-S1·CP-S2·검토 M-1·M-3·M-4·S-1·S-3·C-2·C-3·C-4 | SYNC, CORE(설명만) |
| C21-13 | 7.2.9 | L-1 층 4′(재생 강조·도형 보정 미리보기), `StrokeSession` = `final class` + `shapeAssist`, 읽기 getter 3개, 미리보기 > 숨김, 테이프 '모두 보이기' 시점, `InkEdit.removedObjectIds`·`toCommand` 표, 이미지 캐시 규칙·예산 필드, `InkFillShape.objectId`, 벡터 규칙(글꼴 적재·`UnknownObject`), 수식 래스터 비동기 적재 대기·4 Mpx, 글꼴 적재 시간 상한, `InkTextLayout.measureSync`·`textStyleOf`·`strutStyleOf`·`rasterize`, 썸네일 이미지 캐시 문장, 레이저 색 고정 | INK 검토 M-1·M-3·M-4·M-7·C-1~C-3·S-11, CP-INK-1·3·5~11, EDITOR 검토 M-1·C-1·C-2·S-8·X-3, INK X-4·X-6, PDF CP-PDF-7·검토 M-3 | INK, EDITOR, PDF, LIBRARY |
| C21-14 | 7.2.10 | 자리 콜백 동기 시작·에디터 본문 `context`, `isVisible` 규칙, `StylusExtraEvent.timestamp`, 능력은 다시 시작 때 반영, 스퀴즈·롤 항목은 첫 이벤트 뒤, E-4 접촉 끝 | EDITOR 검토 S-6·C-3·CP-E4·CP-E6, LIBRARY 검토 S-12·C-8, INFRA 검토 S-9 | EDITOR, INFRA, LIBRARY, PDF |
| C21-15 | 7.2.11 | `ensureModel`·`groupIntoLines`·`isVisible`·`copyText` 주석, `HandwritingIndexer`(`foreground`, 손글씨 변경 구독, `update`, 신선함, 따라잡기), `HandwritingIndexerStatus`·`Phase`, `recognitionDevOverlayLinesProvider`, 색인기 시험은 앱 셸 이음새 | LIBRARY CP-L1·L2·L5·L6·L7·L10·검토 C-4·C-5·M-1·S-1, INFRA CP4·검토 M-2·C-2 | LIBRARY, INFRA |
| C21-16 | 7.2.12 | `PdfSearchIndexer` 원문 생성자 유지(CP-PDF-1 기각)·재구축 중 멈춤, 내보내기 래스터 조건·4 Mpx, `importImageForNote` 동기 시작·준비 중 시트·스위치 밖, 복구 시도 횟수·버퍼·내려받기·Web Locks | PDF CP-PDF-1·8·11·검토 M-4·M-7·S-1·S-5, INFRA 검토 M-4 | PDF, INFRA |
| C21-17 | 7.2.13 | `strokes` 좌표·시간 기준, `engineVersion` = 실제 응답 판, callable 규칙(CP-S3), 하루 상한 저장(CP-S6) | LIBRARY CP-L8, SYNC CP-S3·CP-S6·검토 S-8·C-7 | SYNC, LIBRARY |
| C21-18 | 7.3.1 | X22 `update`, X30 `done` 규칙 | INFRA CP13, LIBRARY CP-L3 | INFRA, LIBRARY |
| C21-19 | 7.3.2 | K-9 보강, C-13 재시도 시점, E-4·E-7 보강, M-1 저장 실패, M-2 '묻지 않고'로 정리, M-4·G-4(새), G-2·S-13 보강 | INK C-1, CORE 검토 C-3·C-4, EDITOR 검토 C-4·C-5, PDF CP-PDF-4·C-1, INFRA 검토 C-8, LIBRARY 검토 M-1·S-1·S-4 | 전 영역 |
| C21-20 | 7.3.3 | `FEATURE_MEDIA` = 녹음만(D17), `FEATURE_RECOGNITION`이 도형 보정도 끔, 유휴 작업 시점·순서(데이터 보호 먼저)·이탈 경고는 즉시, 늦은 기여 버림, 시험 이음새(모듈 주입 인자) | INFRA 검토 M-2·M-4·C-2·C-3·C-6·C-7·S-1·S-2·S-3, INFRA CP14·CP15, PDF 검토 X-3·X-4 | INFRA, PDF, LIBRARY |
| C21-21 | 7.4.1 | R16 대상·예외 정정, `plugin_packages` = 해석된 플러그인 전부(`native-reqs`가 대조) | INFRA 검토 M-3·C-4, INFRA CP7 | INFRA |
| C21-22 | 7.4.2 | 선택기·클립보드 동기 시작, 같은 출처 두 탭(범위 밖 + 최소 보호) | EDITOR 검토 S-6, PDF 검토 M-5·Q-1 | EDITOR, PDF |
| C21-23 | 7.4.3 | Info.plist 문구 확정, `allowBackup="false"`(D20) | INFRA 검토 X-1·X-4, INFRA Q13 | INFRA, PDF(부록 B), CORE(문구) |
| C21-24 | 7.4.4 | `app.*` 접두사, recog 키 4개, EDITOR 키, `media.recoverAttempts` | INFRA CP12, LIBRARY CP-L9, EDITOR CP-E7, PDF 검토 M-7 | INFRA, LIBRARY, EDITOR, PDF |
| C21-25 | 7.4.5 | 웹 메모리 재배분(296 MB), 4 Mpx 상한, 검색 색인 크기 목표, 웹 크기 기준 = 1차 통합 실측, 글꼴 묶음별 한도, `binary` 목록·자산 파일 단위 | INK 검토 M-5·C-4·X-10, PDF 검토 M-3·C-5, CORE 검토 M-1, INFRA 검토 M-1·S-14·S-15 | INK, PDF, CORE, INFRA |
| C21-26 | 7.4.6 | `media` 자동 래퍼, `emulator`는 컨테이너 + CI, 무거운 시험 잠금(고정 경로·중첩 넘김·`with-heavy-lock`), 어댑터 시험의 채널 가짜 허용, Chrome 시험 글꼴 | INFRA CP10·검토 S-4, SYNC 검토 X-2, LIBRARY 검토 C-1·C-2, INK 검토 M-7 | INFRA, SYNC, LIBRARY, 전 영역 |
| C21-27 | 7.4.7 | `.gitignore` 보강·`.env.demo-noteapp` 커밋, 에뮬레이터 규약, `firebase-tools` devDependency·스크립트·글롭·`hashFiles` 가드, 미니 라운드 배포 순서 | INFRA CP11·검토 S-11, SYNC CP-S4·검토 M-2·S-9·X-1 | SYNC, INFRA |
| C21-28 | 7.5 | CP1·CP2·CP-PDF-9(6개 — `plugin_platform_interface` 제외)·CP-S5·`integration_test` 행, `firebase-tools` 14일 재확인 | INFRA CP1·CP2·검토 S-5, PDF CP-PDF-9·검토 M-1, SYNC CP-S5·C-6·C-8 | INFRA, PDF, SYNC |
| C21-29 | 7.6.2 | 기반 단계 재구성: R2-B1 보강, R2-B7b 앞당김, B2-α/β, R2-B7a 바탕·완료 조건, R2-B3 목록, R2-B8a/b + J0, 시작 조건, 이정표 커밋 | CORE 검토 M-2, INFRA 검토 M-5·S-6·CP3·CP8, SYNC 검토 C-5·M-4·X-4·S-5, INK 검토 C-8·S-5, EDITOR CP-E3 | 전 영역 |
| C21-30 | 7.6 블록 | 시험 도우미 v2.1: 가짜 검색 같은 판정·순서, `FakeAudioRecorder`(`UnsupportedError`·초안·`abandon`), `FakeAudioPlayback.calls`, `testing_web.dart`, INK `useInkTestFonts`·`InkVectorFixtures`, recog 추가 멤버·`SyntheticShapes`, media 가짜(믹스인 없음·VM 전용), 가짜 엔진 출력 규칙 | CORE CP-8·CP-14·검토 C-2, PDF 검토 X-6·M-1·C-3·S-11·CP-PDF-6, INK 검토 M-7·C-5·X-7, LIBRARY CP-L4·검토 C-7·X-5, SYNC CP-S3⑥ | CORE, INK, LIBRARY, PDF, SYNC, INFRA |
| C21-31 | 7.7.1 | 5단계 도형 보정 흐름 시험 위치, 8단계 잠금, 9단계 Playwright 스모크·Hosting 조건·`ios-compile` | LIBRARY 검토 S-6·S-7, INFRA 검토 S-7 | LIBRARY, INK(I-4 문구), INFRA |
| C21-32 | 7.7.2 | V3 글꼴, V5(주입 인자·90° 메뉴·되돌리기 순서·벡터 개수·키), V7 사본, V8 타임코드, V9 생성기, V10 색인 크기, V13 컨테이너·같은 값, V14 서명 실패·`ios-compile`, V15 녹음만·도형 보정, V16 실제 웹 저장소·두 녹음기 | INFRA 검토 C-3·C-7·M-7, EDITOR CP-E8, PDF 검토 C-6·X-6, LIBRARY 검토 M-2·C-1, CORE 검토 M-1·M-3, INFRA CP14 | 전 영역 |
| C21-33 | 7.8 | A-1·B-1 현실화, A-4 영어 모델, B 머리(Hosting 뒤), B-3·B-8·B-9·B-11·B-13 보강, B-15·B-16(새) | INFRA 검토 C-1, CORE 검토 C-6·S-11, EDITOR 검토 S-6·M-2, LIBRARY 검토 S-10·S-12, PDF 검토 S-6·S-7·M-8 | INFRA(안내서 08), 전 영역 |
| C21-34 | 8 | 위험 1·9 보강, 17~19(새) | 총괄 | — |
| C21-35 | 9 | U2·U3·U19·U20 갱신, U24~U27(새) | 총괄 | — |

기각·보류: CP-PDF-1(공개 생성자 인자·`PdfIndexerGate` 공개 — 패키지 내부 주입으로 같은 효과). CORE CP-1의 `RemoveElements.elementIds` 형은 검토자 권고(`Set` 유지) 대신 1차 명령과 같은 `List`로 정했다(C21-07). 나머지 CP는 모두 받아들였다(00-review 2.2).

#### v2.0 초안 (2026-11-05, 총괄 — 설계 초안 A·B 채점 뒤, 영역 계획서 작성 전)

- 바탕: 초안 A(기존 패키지 중심). 채점 A 29 / B 21 — [judgement.md](drafts/judgement.md).
- B에서 옮김: 웹 녹음 조각 저장 P-A(D13·M-2), 기능 스위치(D14·V15), 외부 전송 동의 게이트(D15·G-3), INK `setPreviewObjects`, `SearchIndexWriter.sourceRevs`, `InkPlaybackFocus.recentWindowMs`, 녹음 시계 규칙(7.4.8), 컨테이너 시험 부하 규칙(5장), 동시 개발 중 '추가만' 규칙(7.4.9), 앱 스모크 v2·실기기 복합 확인 범위, 계획서 13·14절.
- A에서 고침: `NoteStore` getter 추가가 INFRA 시험 가짜를 깨뜨림을 확인하고 R2-B2 묶음에 넣음(C2-15), 1차 계약 대비 변경을 7.0 표로 모음, `AssetStorageUsage.bytesByType`을 선택 인자로, 게시 14일 규칙을 공통 규칙으로, 자리 UI 공통 규칙(7.4.10).
- 다음: 7개 영역 계획서(`m5-7/01-infra.md`~`07-sync.md`) → 총괄 검토(`m5-7/00-review.md`) → 확정(→ v2.1).

## 8. 위험

| # | 위험 | 영향 | 대응 |
|---|---|---|---|
| 1 | CORE·INK·EDITOR가 각 15~17 단위로 크고 객체 사슬(CORE → INK → EDITOR)의 임계 경로에 있다 | 2차 일정 지연 | 기반 단계에서 '단순하지만 동작하는 구현'까지 넣어 사슬을 끊는다(R2-B2·B3). 무거운 UI 둘(녹음 패널·변환 창)을 다른 영역으로 넘겼다(2.4). 일정이 밀리면 3.4의 P-B·P-C부터 자른다. (v2.1) CORE 표면을 B2-α로 먼저 내고(해시 알림), R2-B8을 시작 조건에서 뺐다(7.6, D24) |
| 2 | 사용자의 주 기기(iPad 웹)에서 손글씨 인식이 이번 라운드에 **동작하지 않는다**(ML Kit 웹 불가, 실연결 전이라 동기화된 결과도 없음) | M7-1·M7-2(손글씨 부분)의 체감 가치가 TestFlight 또는 실연결 뒤로 밀림 | 안드로이드 APK로 첫 판정(U2). 웹 인식은 서버 경유 OCR 어댑터 하나로 더할 수 있게 포트를 둔다(U5). 텍스트 상자·PDF·수식 검색은 웹에서 이번에 된다 |
| 3 | ML Kit 한국어 태그·품질·혼용 인식 미확인(외부 문서 접근 불가) | 인식률 불만족 | A-4 실기기 실험을 M7 첫 작업으로. 후보 고르기·직접 편집 UI. 엔진 포트 뒤라 상용 엔진으로 바꿀 수 있음 |
| 4 | iPad Safari의 Flutter 웹 텍스트 입력(한글 IME 조합) 품질 | 텍스트 상자 사용성 | EDITOR 첫 작업을 IME 시제품 + 미리보기 배포로(B-2 조기 확인). 문제가 크면 웹에서는 ① 시트 안의 일반 입력란으로 받고 상자에 반영하는 대체 UI, 또는 ② `HtmlElementView` 기반 `<textarea>`를 상자 위에 겹치는 웹 전용 편집기(`*_browser.dart`) 중 실기기 결과로 고른다(EDITOR 계획서에 두 안을 미리 적음) |
| 5 | 한글 글꼴 크기(부분 집합이라도 수백 KB~1 MB)와 부분 집합 밖 글자 | 첫 텍스트 상자 지연, 드문 글자 대체 글꼴(온라인) | 지연 적재(`InkFonts.ensureLoaded`), `covers()`가 거짓이면 PDF는 래스터로, 화면은 대체 글꼴. 크기는 R2-B8에서 측정 |
| 6 | `flutter_math_fork`는 1년 반 갱신이 없고, 끌어오는 `flutter_svg` 계열은 최신판이 2주 미만, `xml` 하향(7.1.0 → 7.0.1) | 빌드 깨짐·회귀 | 간접 고정(7.5), 순수 Dart라 깨지면 포크. 1차 코드는 `package:xml`을 직접 쓰지 않는다(작업 트리 7개 `grep` 확인) — 간접 사용처(빌드 도구 등)는 R2-B1 전체 시험으로 확인 |
| 7 | 웹 녹음은 탭이 닫히면 메모리 조각이 사라진다(`record_web`은 조각을 메모리에만 모음 — 조사 02 4.3) | 강의 녹음 손실 | CORE 초안 저장소 API를 R2-B2에 넣고, media_io 자체 웹 녹음기가 처음부터(P-A, D13) 1초마다 조각을 저장, 다음 실행 때 복구(V16, B-14). P-B가 늦으면 패널에 '녹음 중에는 탭을 닫지 마세요' 안내 |
| 8 | 네이티브 녹음 시계 오차 미측정 | 재생 강조가 어긋남 | 강조 허용 폭 + 탭 재생 1.5초 앞당김(R-5). A-5 실측 뒤 `Recording` 보정 필드(계약 변경) 판단 |
| 9 | DB 스키마 v2: 옛 앱(되돌린 웹 배포)이 v2 DB를 열지 못함, 1차 실제 노트의 마이그레이션 실패 | iPad 노트 접근 불가·손실 | V7 고정 자료 시험(VM·Chrome), 미리보기 채널은 출처가 달라 데이터가 따로(1차 7.4.9). live 배포 전에 '백업 내보내기'를 안내서에 넣는다. 웹 배포 되돌리기는 v2 이후 금지(안내서). (v2.1) 업그레이드 직전 v1 사본(7.2.7)으로 이주 성공 뒤의 손상에도 되돌릴 길을 둔다. 실제 노트의 이주는 그 노트가 있는 출처(live)에 배포될 때 처음 일어나므로 미리보기 확인으로는 보장되지 않는다 — 7.8 B-1 절차 |
| 10 | 페이지 객체가 많은 페이지(이미지 여러 장 + 텍스트)에서 iPad Safari 메모리·타일 재생성 | 탭 재로드 | 이미지 디코드를 표시 버킷 크기로, 캐시 예산(7.4.5), `PageObjectLimits`, B-13 확인 |
| 11 | ML Kit iOS는 CocoaPods 전용이고 CocoaPods trunk가 2026-12-02 읽기 전용. 실연결 때 Firebase(SwiftPM)와 혼합 모드 중복 | iOS 빌드 실패 | 이번에는 Firebase 네이티브를 앱에 넣지 않는다(3.3). `ios-compile.yml` 1회로 ML Kit 단독 상태 확인(P-C). 인식 엔진은 포트 뒤 |
| 12 | 서버 함수 코드를 배포 없이 오래 두면 낡음(firebase-functions 판, Node 런타임 2027-04-30 지원 중단 예정) | 실연결 때 재작업 | CI 에뮬레이터 시험을 계속 돌리고, 실연결 미니 라운드에서 판을 다시 확인 |
| 13 | 영역 주제가 어색한 배치(PDF가 오디오, LIBRARY가 인식, SYNC가 서버 함수) | 그 영역의 학습 비용 | 조사 02·03·04가 패키지 구조·코드 뼈대까지 적어 둠. 근거와 다른 배치(B)와의 비교는 [judgement.md](drafts/judgement.md) |
| 14 | 앱 셸 연결 코드(자리 변환)가 늘어남 | INFRA 통합 단계 부담, 변환 실수 | 변환을 `RecognitionTarget` ↔ 에디터 문맥 1:1로 단순하게 두고, V5 스모크가 자리 각각을 한 번씩 누른다 |
| 15 | 안드로이드 개발자 인증(2027 전 세계 시행 예정)·사이드로드 정책 | 시험 APK 설치 방법 변화 | 안내서에 감시 항목으로(조사 04 3.6) |
| 16 | 기능 확장 지점이 소비자 자리 + 앱 셸 변환 방식뿐이라, 다음 라운드(스티커·자·북마크 등)마다 EDITOR·INK가 계속 커진다(초안 B가 지적) | EDITOR·INK 계획서 비대, 다음 라운드 임계 경로 | 이번 라운드는 받아들인다(계약 비용 대비). 페이지 객체는 `UnknownObject` 보존·`type` 확장형이고, 자리 타입(`EditorSelectionMenuItem` 등)은 B의 `editor_api`로 옮길 수 있는 모양으로 둔다. 3라운드 설계 때 '에디터 확장 SDK' 분리를 다시 판단한다 |
| 17 | (v2.1) Firebase Hosting이 없어 iPad 웹 확인(7.8 B)·1차 V7을 할 수 없다 | 주 기기 확인이 늦어져 IME·Safari 사용자 동작 활성화·메모리 문제가 통합 뒤에야 드러남 | Spark 프로젝트(무료, Hosting만)를 먼저 만들도록 요청(U24). 그 전에는 컨테이너 Playwright 스모크(3.7)와 Chrome 시험으로 대신하고, 첫 Hosting 배포 때 EDITOR IME 시제품부터 본다 |
| 18 | (v2.1) PDF 전역 색인이 웹 DB(열 때 통째로 메모리에 올라오는 파일)를 키운다 | iPad 앱 시작 시간·메모리 | 사각형을 SQLite 밖에(또는 압축), 질의는 대표 결과만 읽음, 크기 목표·측정(7.4.5, V10, B-13). 넘으면 원문도 블롭으로 또는 색인 범위 축소 |
| 19 | (v2.1) 같은 출처를 두 탭으로 열면 다른 탭이 진행 중 녹음 초안을 건드릴 수 있다 | 녹음 손실 | 최근 갱신 초안 제외·(가능하면) Web Locks·`append` 거절 시 멈춤과 안내(7.2.4, D19) |

## 9. 사용자에게 물을 것 (기본값으로 진행하고, 답이 오면 바꾼다)

| # | 질문 | 왜 필요한가 | 기본값 |
|---|---|---|---|
| U1 | Apple Pencil 종류(Pro / USB-C / 2세대)와 iPad 정확한 모델명 | USB-C 펜슬이면 필압·더블탭·스퀴즈·롤이 없어 M5-9를 쓸 수 없다(PLAN 11장 1번) | Pro 기능까지 코드로 만들고 설정에서 능력에 따라 숨김 |
| U2 | S펜이 되는 안드로이드 태블릿이 있는가, 모델은? | A 체크리스트(S펜 버튼·백그라운드 녹음·ML Kit)의 완료 판정, (v2.1) iPad 웹에서 손글씨 검색을 볼 수 있는 유일한 길(실연결 뒤) | 없다고 보고 '코드만, 확인은 이후'. (P-C) 안드로이드 에뮬레이터 CI 잡으로 ML Kit 흐름만 자동 확인 |
| U3 | Firebase 프로젝트를 언제 만들 것인가 | 실연결·서버 함수 배포 시점 | 2차 통합 뒤 '실연결 미니 라운드'(3.3). 2차 도중 만들어도 2차에 끼우지 않음. (v2.1) Hosting만 쓰는 Spark 프로젝트는 U24로 따로 묻는다 |
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
| U16 | ~~손글씨 자동 인식(검색 색인용)은 설정에서 켜야 동작(기본 꺼짐)~~ → (v2.9, C29-01) 기본 켬 — 처음 실행에 모델을 Wi-Fi에서 받고, 끄면 검색 안내 줄이 [켜기]를 보인다. 모델(약 20 MB/언어)은 Wi-Fi에서 | 배터리·저장 공간 | 변경(사용자 요청 '변환하지 않아도 적은 글씨가 검색돼야 해') |
| U17 | PDF로 내보낼 때 수식은 300 dpi 이미지(벡터 아님) | F-15 '벡터 출력'은 필기 기준 | 그대로 |
| U18 | 실기기 도형·수식 획 표본을 시험 자료로 저장소에 넣어도 되는가(손글씨 문장은 넣지 않음) | 문턱값 회귀 시험 | 도형·수식만 넣음 |
| U19 | macOS 러너(10배 과금)로 iOS 컴파일 확인을 2차에 1~2회 해도 되는가, 저장소 공개 여부 | Actions 무료 시간 | 1회(통합 뒤, 무료 시간 약 150분), 비공개 유지. (v2.1) 승인되면 V14의 완료 조건 — Swift 컴파일 오류는 iOS 빌드 전체를 깨기 때문 |
| U20 | 안드로이드 고정 서명 키: 시크릿 등록(키 파일 따로 보관) | 덮어 설치·노트 보존 | 시크릿 방식(조사 04 3.5 A). (v2.1) 이 세션의 `gh`는 인증되지 않아(2026-11-05 확인) Claude가 시크릿을 직접 넣을 수 없다 → Claude가 컨테이너에서 키를 만들어 **파일로** 건네고 사용자가 GitHub 설정에 등록(안내서 05). 등록 전에는 debug 서명(아티팩트 이름에 표시) |
| U21 | 최종 앱 ID(`dev.noteapp.noteapp` 유지?) | 고정 키·App ID 등록 전에 확정해야 함 | 유지 |
| U22 | 지우개(획 지우개·부분 지우개 모두)가 닿은 도형은 통째로 지우고, 텍스트 상자·이미지·수식은 지우개로 지우지 않음(선택 → 삭제로만) | 지우개 규칙(`EraserSpec.eraseShapes`) | 그대로 |
| U23 | '다른 노트의 페이지 복사'(F-13)를 이번에 넣을지 | 노트·페이지 고르기 UI가 필요하고 M5와 무관 | 이후(데이터는 이미 `PageDraft.objects`로 준비됨) |
| U24 | (v2.1) Firebase 프로젝트를 **Spark(무료)·Hosting만**으로 지금 만들 수 있는가(1차 안내서 01·02, 약 15분, 결제 계정 없음) | iPad 웹 확인(7.8 B)·1차 V7·EDITOR IME 첫 주 미리보기의 유일한 경로(3.7) | 만들기를 권한다. 답이 없으면 B 확인은 Hosting이 생길 때까지 미룬다(2차 완료 판정은 영향 없음) |
| U25 | (v2.1) 1차 앱으로 iPad(또는 다른 기기)에 만든 실제 노트가 있는가, 있다면 어느 주소인가 | 첫 실제 v1 → v2 이주 시점과 B-1 절차(CORE 검토 M-3) | 없음(Hosting이 없어 배포된 적이 없음). V7은 고정 자료로만. Hosting 뒤 live에서 1차를 쓰기 시작했다면 2차 live 배포 전에 백업 내보내기 |
| U26 | (v2.1) 녹음된 글씨 탭 재생: 손가락 탭은 녹음 패널이 열려 있거나 재생 중일 때, 펜 점은 재생(·일시정지) 중일 때만 그 시점으로 이동하고 그 밖에는 점이 남는다. 녹음 중에는 가로채지 않는다 | 필기 손실 방지 vs 탭 재생 편의(R-5) | 그대로 |
| U27 | (v2.1) 안드로이드 기기 자동 백업(Google 드라이브)에 노트를 넣지 않는다 | 25 MB 상한·복원 때 기기 식별 복제(D20) | 넣지 않음 — 보존은 백업 내보내기, 실연결 뒤 동기화 |
