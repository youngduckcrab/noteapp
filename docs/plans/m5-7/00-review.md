# 00 · 2차 라운드 총괄 검토 결과

> 상태: **2차 통합 — 컨테이너 V1~V16 중 V4만 대기(INFRA `tool/web_budget.yaml` C27-01 반영 → `ws web-budget check` 0 뒤 '2차 통합 완료'), 실기기 확인 대기, 계약 v2.7** (2026-11-12 — 끝의 [2차 통합 결과](#2차-통합-결과) 절) · 그 앞: **최종 승인** (2026-11-05 — [최종 승인](#최종-승인) 절: 7개 계획서 승인, 통합 계약 **v2.2** 확정) · 이전: 1차 검토 완료 (2026-11-05) · 대상: `m5-7/01-infra.md`~`07-sync.md` 초안 7개 · 대리 검토 7건(`reviews/*.md`) · 확정한 공통 결정: [00-overview.md](00-overview.md) 7장 **통합 계약 v2.1**(변경 이력 7.9 — C21-01~35)
> 판정 기준(1차와 같음): ① 이 계획서들만 보고 서로 다른 개발자가 독립적으로 구현했을 때 통합이 깨지지 않는가 ② PLAN.md 요구사항(M5·M6·M7, F-03·F-10~F-16)이 빠짐없이 구현되는가 ③ 컨테이너와 iPad Safari 웹에서 검증 가능한가
> 표기: **M** = 반드시 고칠 것(재검토 승인 조건) · **S** = 권장 · 근거의 '검토'는 `reviews/<영역>.md`, 'CP'는 그 영역 계획서 12장의 계약 변경 제안, 'C21-xx'는 계약 v2.1 변경 이력 행

---

## 1. 전체 평가

**판정: 7개 계획서 모두 '수정 후 재검토'.** 계획서 각각은 1차보다 깊다. 계약 블록을 글자 그대로 옮기고(대리 검토가 기계 대조 — 7개 모두 차이 없음), 계약이 비워 둔 자리를 '확정 세부'로 채운 뒤 어긋나는 곳을 CP로 올리는 구조가 모든 영역에서 같다. 실험 근거도 많다(FTS5 바이그램·`contentless_delete`, 화면 밖 `RenderView` 래스터, CID 글꼴 한글 추출, 웹 접촉 비트 상태표, 도형 판정 1,400개, Functions·Auth 에뮬레이터 + Dart 클라이언트).

문제는 1차와 같이 **영역 사이**와, 이번에는 **'잃지 않음'의 구멍**이다. 대리 검토의 반드시 고칠 것 37개(INFRA 8·CORE 3·INK 8·EDITOR 4·LIBRARY 2·PDF 8·SYNC 4)와 권장 일부에, 데이터·필기를 잃거나 가리는 경로가 열한 가지 있다 — 웹 초안 고아 정리, 다른 탭의 초안 복구, 긴 녹음 복구의 매 실행 반복, 이주 성공 뒤 되돌릴 길 없음, 색인기의 확정 줄 덮어쓰기, 보류 기록이 세션 LRU에 걸림, 손글씨 업로드가 되살리는 지운 노트, 탭 재생이 버리는 짧은 획, 재구축 중 색인 누락, 정지 직후 필기 흐림, debug 서명 APK의 '지우고 설치'. 모두 계약 문장이나 영역 규칙으로 막을 수 있어 v2.1과 3장에 넣었다.

| 판정 기준 | 평가 | 주된 원인 |
|---|---|---|
| ① 독립 구현 후 통합 | **불충분 → v2.1로 해소** | `final class`(색인기·INK 컨트롤러·`StrokeSession`)를 가짜로 바꾸는 시험이 컴파일되지 않음, 미리보기와 해석기의 객체 변형 규칙이 두 벌, 명령 생성자 모양이 1차와 다름, 웹 메모리 합계 초과, 바탕 코드가 1차 통합 전, 손글씨 결과를 세 주체가 덮어씀, 무거운 시험 잠금 중첩 교착 |
| ② PLAN 요구사항 | **대체로 충족** | `FEATURE_MEDIA`가 P-A 이미지 삽입까지 끔, 수식 루트 기호가 네이티브 release 래스터에서 빠짐, 회전된 객체 크기 조절, iPad 키보드 없는 텍스트 선택·붙여넣기, 새 펜 미리보기 |
| ③ 컨테이너·웹 검증 | **대체로 충족, 실행 경로 수정 필요** | Chrome 시험이 글꼴 적재에서 멈춤, `MockPlatformInterfaceMixin`이 `lib/`에서 분석 오류, `npm test` 글롭, V8이 스스로를 재는 시험, iPad 웹 확인에 Firebase Hosting이 필요한데 프로젝트가 없음 |

총괄이 직접 확인한 것(2026-11-05)

- 1차 통합: `/home/user/noteapp` 브랜치 `claude/note-app-planning-bk29xb` HEAD `18c5ae5`, 1차 계약은 **v1.5**(통합 반영, 시그니처 변경 없음 — C15-01~08), 상태 'V1~V6 완료 · V7 사용자 기기 확인 대기'. 영역 1차 작업 트리에는 통합 커밋(`52de08c`·`d5938c6`·`5adf710`·`3cf0b84`·`c4966ce`·`1689f7e`·`9305235`·`22abbea`)이 없다 → 모든 계획서의 바탕을 통합 HEAD로 옮긴다(CD2-01).
- 1차 `ci.yml`은 **Firebase Hosting**으로만 웹을 배포하고, 시크릿이 없으면 배포를 건너뛴다. 사용자는 Firebase 프로젝트가 없으므로 지금은 iPad 웹 확인 경로가 없다(1차 V7도 같은 이유로 대기) → CD2-02·03.
- 1차 웹 빌드 실측(1차 INFRA 진행 기록 G4): `main.dart.js` 4,633,843 B, gzip **1,366,038 B** — INFRA Q4가 제안한 한도(gzip ≤ 1.3 MB)를 이미 넘는다. 한도 기준을 이 실측으로 바꾼다(C21-25).
- 1차 메모리 예산(1차 7.4.10): INK 128 + PDF 112 + CORE 32 = 272 MB. 2차 항목 80 MB를 더하면 352 MB > 300 MB(INK 검토 M-5 계산과 같음) → 재배분(CD2-10).
- 1차 명령은 `CompositeCommand`를 빼고 모두 `const` + 이름 있는 인자 + `label`이고 id 목록은 전부 `List<ElementId>`다(`RemoveStrokes.strokeIds`·`TransformElements.elementIds`·`RestyleStrokes.strokeIds`). 1차 INK `InkEdit.removedIds`는 `Set`이고 `toCommand`가 `.toList()`로 넘긴다 → CD2-06.
- 워크스페이스 `analysis_options.yaml` 16행 `invalid_use_of_visible_for_testing_member: error` → PDF 검토 M-1이 맞다.
- 이 세션의 `gh`는 인증이 되지 않는다(`GH_TOKEN` 무효) → INFRA Q-3의 답: Claude가 저장소 시크릿을 직접 넣을 수 없다(U20).
- 1차 안내서 04: 실사용은 live 주소의 홈 화면 앱, 미리보기 주소는 데이터가 따로이고 7일 뒤 사라진다 → 7.8 B-1 절차(C21-33).

수정 규모 예상: CORE·EDITOR·PDF 중간~큼(데이터 안전 규칙·시험 이음새) / INK·LIBRARY·SYNC 중간 / INFRA 중간(바탕 갱신 + 기반 단계 재구성). 계약 v2.1의 시그니처 변경은 모두 아직 아무도 구현하지 않은 2차 표면이거나 기본값이 있는 추가라, 재작업은 계획서 문장 범위다.

---

## 2. 공통 결정

### 2.1 공통 결정 요약 (상세: 00-overview 3장·7장)

| # | 결정 | 개요 |
|---|---|---|
| CD2-01 | 계약 v2.1 확정. 1차 기준은 v1.5. **바탕 코드 = 1차 통합 HEAD**(`/home/user/noteapp` `18c5ae5`). 계획서의 '전체' 설정 블록·시험 수·CI 시간·웹 크기 기준은 이번 수정에서 통합 HEAD로 고치고, 나머지 줄 번호 인용은 기반 단계 시작 때 고친다 | 머리말, 2.5 |
| CD2-02 | **실기기 확인 경로**: 안드로이드 APK는 지금 된다(`android.yml`, Firebase 불필요). iPad 웹은 **Firebase Hosting(Spark 무료·결제 계정 없음)만** 있으면 된다(사용자에게 요청 — U24). iOS 컴파일 확인은 계정 없이 macOS 러너로 1회(U19). TestFlight는 Apple 유료 계정 뒤 | 3.7, D18 |
| CD2-03 | **Firebase 없는 동안**: 실연결(M4·로그인·Firestore·Storage·Functions·Blaze)은 이번 라운드에 넣지 않는다(D6 유지 — 검토 결과 SYNC 사전 정비와 서버 함수 에뮬레이터 시험이 실연결 전에 끝나 미니 라운드에는 연결 작업만 남는다). Hosting(Spark)은 실연결이 아니며, 생기면 Hosting 시크릿만 연결한다. 그동안: CI는 배포를 건너뛰고, 통합 9단계에 컨테이너 Playwright 스모크(릴리스 웹 빌드, 1032×1376)를 두고, 서버 함수는 `demo-noteapp` 에뮬레이터로만 시험하고, 앱 빌드에는 `MATH_ENDPOINT`를 넣지 않고(LaTeX 직접 입력), 손글씨 결과는 안드로이드 기기 안에만 있다 | 3.3, 3.7 |
| CD2-04 | 1차 V7(iPad 확인)은 2차 기반 단계의 **전제가 아니다**. Hosting이 생기면 2차와 병행한다 | D21, 7.6.1 |
| CD2-05 | **기반 단계 재구성**: R2-B1(보강) → R2-B7b(`functions/` 골격, R2-B1 바로 뒤 따로 병합) → (R2-B2 + R2-B7a + R2-B2i 묶음) → R2-B3 → R2-B4·B5·B6. CORE는 **B2-α(계약 표면, 약 0.5세션)**를 먼저 커밋해 해시를 알리고 B2-β(동작)를 잇는다. **동시 개발 시작 조건 = R2-B1~B6이 `main`에 있음** — R2-B8(앱 셸)은 B8a·B8b로 나눠 INFRA 동시 개발의 앞 작업이 되고, 네이티브 설정·웹 빌드 실측은 J0로 내린다. 이정표 커밋(CORE T24·T26~T33, INK T24·T26a·T33·T34·T36·T42)을 진행 기록 양식에 고정한다 | D24, 7.6.2 |
| CD2-06 | 새 명령 3개는 **1차 명령 모양**(`const`, 이름 있는 인자, `label` `'add-objects'`·`'update-objects'`·`'remove-elements'`). `RemoveElements.elementIds`는 **`List<ElementId>`**(1차의 모든 id 목록과 같게 — 검토자 권고 `Set` 대신, 중복은 무시). 소비자는 `[id]`로 쓴다 | 7.2.3, C21-07 |
| CD2-07 | **객체 변형의 단일 규칙** = `PageObject.transformed(m, {scaleWidth = true})`: 도형 굵기 × s([0.1, 30]), 텍스트 상자·수식 글자 크기 × s([6, 144] — CP-2), 이미지는 frame만. CORE 해석기와 INK·EDITOR 미리보기가 **같은 함수**를 부른다. 캘리그래피 획 변형은 펜촉 각도 함께 돈다(C2-38, CP-INK-4) | 7.2.2, 7.2.3 |
| CD2-08 | INK 표면 추가(R2-B3에 넣음): 읽기 getter(`previewObjects`·`hiddenObjectIds`·`playbackFocus`·`StrokeSession.shapeAssist`), `StrokeSession`은 `final class`(계약 문구 정정), `InkEdit.removedObjectIds`(공개 선택 인자) + `toCommand` 표(CP-INK-2), 미리보기가 숨김보다 우선, `InkTextLayout.measureSync`·`textStyleOf`·`strutStyleOf`(CP-INK-3)·`rasterize`(CP-PDF-7), 시험 도우미 `useInkTestFonts`·`InkVectorFixtures` | 7.2.9, 7.6 |
| CD2-09 | **재생 흐림·강조와 도형 보정 미리보기는 층 4′**(ink 위·annotation 아래, `inkActive` 끝)에 그린다. overlay에 두면 테이프 아래 글씨 모양이 드러난다. K-9에 '화면 재생 강조도 테이프·텍스트 픽셀을 바꾸지 않음' | 7.2.9 L-1, K-9 |
| CD2-10 | **웹 메모리 재배분**(합계 296 MB ≤ 300 MB): INK 외곽선 32 · 래스터 공유 장부(타일 + 이미지 디코드) 96 · 수식 8, PDF 미리보기 24(32에서 줄임) · 타일 64 · 썸네일 16 · 내보내기 임시 16, CORE 32, 웹 녹음 조각 8. 한 장의 래스터·디코드는 **4 Mpx 상한**(INK `rasterize`, PDF 디코드 공통) | D22, 7.4.5 |
| CD2-11 | **검색 색인 크기**: PDF 글자 사각형은 줄인 정밀도(≥ 1/65535)로 SQLite 밖(블롭 저장소 — 기본) 또는 압축 BLOB에 둔다(CORE 선택). 질의는 후보에서 원문·사각형을 읽지 않고 돌려줄 대표 결과만 읽는다. 목표: 실제 모양 500쪽당 DB ≤ 12 MB·다시 열기 +300 ms 이하. 빈 단위 목록도 소유자(`sourceRev`)를 남긴다. PDF Q8(에셋 전체 색인)은 받아들이되 목표를 넘으면 범위를 줄인다 | 7.2.5, 7.2.7, 7.4.5 |
| CD2-12 | **손글씨 결과 쓰기**: CORE `HandwritingRepository.update`(한 쓰기 트랜잭션 안의 읽고-병합-쓰기)를 더하고 색인기·변환 창은 이것만 쓴다(G-4). 신선함 = `sourceRev` + 언어(다른 엔진·기기 결과도 신선). 확정 줄 유지 규칙(옛 획 ≥ 80 % 남고 새 획이 작으면 유지)을 계약 주석으로. SYNC는 손글씨만 실린 청크를 '편집'(outbox·최근 보냄 10분)으로 세지 않는다. `notesWithStalePages()` 추가 | D23, 7.2.5, 7.2.8 |
| CD2-13 | **녹음은 잃지 않는다**: 복구는 묻지 않고 녹음으로 만든다(M-2 문장 정리). `pendingDrafts`는 진행 중 세션(starting~finishing)·복구 중·최근 갱신(max(10 s, 5 × 조각 간격)) 초안을 뺀다. `stop` 저장 실패는 초안을 남긴다. 웹 초안은 `begin` 때 블롭 쪽 meta를 먼저 쓴다. WebM 길이는 블록 타임코드에서. 연속 3시간이 지원 범위, 같은 출처 두 탭은 범위 밖 + 최소 보호, 복구 시도 2회 상한, 정지·복구 버퍼 복사 줄이기, 웹 저장 실패의 마지막 수단은 '파일로 내려받기' | D19, 7.2.4, 7.2.12, M-1·M-2·M-4 |
| CD2-14 | **탭 재생 상태**(R-5): 설정 켬 + 녹음기 `idle` + 손가락 탭은 패널이 열려 있거나 재생·일시정지 중, 펜 탭(≤ 4 px·≤ 200 ms)은 재생·일시정지 중일 때만. 판정은 `end()` 전, 가로채면 `cancel()`. 재생 강조 초점은 열린 뒤 한 번이라도 `playing`이었거나 `seekMs` 뒤에만 — PDF 패널의 자동 열기는 그대로 둔다(EDITOR 쪽에서 해결) | 7.2.4 R-5, U26 |
| CD2-15 | **자리 콜백은 누름 처리 안에서 동기적으로 시작**하고 **에디터 본문 `context`**를 넘긴다. 받는 쪽은 브라우저 API·`containerOf`를 첫 `await` 전에. `isVisible`은 가볍게, 예외는 숨김 + 보고(E-7 예외) | 7.2.10, E-7 |
| CD2-16 | `FEATURE_MEDIA`는 **녹음만** 끈다. 이미지 삽입·이미지 페이지는 스위치 밖. `FEATURE_RECOGNITION`은 자동 도형 보정도 끈다(V15 차이 목록에 포함) | D17, 7.3.3, V15 |
| CD2-17 | 색인기(`final class`)의 앱 셸 시험은 **INFRA 모듈 생성자 주입 이음새**로 한다. CP-PDF-1(공개 생성자 인자·`PdfIndexerGate` 공개)은 기각 — 패키지 내부 주입. V5·V6의 가짜도 모듈 주입 인자로 넣고 override 출처·횟수는 실제 모듈 경로로 확인한다 | 7.3.3, V5 |
| CD2-18 | **유휴 작업**: 녹음 이탈 경고는 시작 성공 직후 바로(유휴 작업 밖). 유휴 작업은 첫 프레임 3초 뒤, `resumed`·`inactive`·값 없음에서 실행, 순서는 데이터 보호 먼저(`media.recoverDrafts` → `pdf.searchIndexer` → `recognition.indexer`), 종료는 역순, `dispose` 멱등, 시간 초과 뒤 늦은 기여는 버림 | 7.3.3 |
| CD2-19 | **시험 실행 규칙**: 무거운 시험 잠금은 고정 경로 `/tmp/noteapp-heavy-tests.lock` + `NOTEAPP_HEAVY_LOCK_HELD` 넘김 + `ws with-heavy-lock -- <명령>`(중첩 교착 해소). `emulator` 태그는 컨테이너(잠금)에서 돌리고 CI에서 반복. Chrome 시험은 `useInkTestFonts`. 서비스 패키지 어댑터 자체 시험은 채널 가짜 허용 | 7.4.6 |
| CD2-20 | **의존·검사**: CP1(`shared_preferences_*` 간접 고정)·CP2(`xml` dev)·CP-PDF-9(**6개** — `plugin_platform_interface` 제외)·`integration_test`·CP-S5(`@anthropic-ai/sdk 1.1.0`) 승인. R16 대상 = `feature_editor`·`feature_library`·`ink_engine`·`note_core` + `pdf_io`·`sync_engine`(예외 `file_picker`·Firebase), `plugin_packages`는 해석된 플러그인 전부(`native-reqs`가 대조). `firebase-tools 15.34.2`는 R2-B1·B7b 때 14일 재확인(2026-11-11부터 통과). `lib/`에서 `MockPlatformInterfaceMixin` 금지 | 7.4.1, 7.5 |
| CD2-21 | **SYNC '모르는 종류 보류' 보강**: 병합 단위 = 메타·범위 키를 뺀 나머지 전부(CP-S1), 청크 단위 전부/전무, 다시 적용은 LRU 밖·K1 기록은 보관에 남김, 메타 키 나눔(키당 < 256 KiB·총 2 MiB), 깨진 값 → 모든 종류 되감기, 압축은 모르는 기록 청크를 지우지 않음 | 7.2.8, S-13 |
| CD2-22 | **`functions/` 규약**: `.env.demo-noteapp` 커밋, 에뮬레이터 사용자 `owner-uid`·`stranger-uid`, 가짜 엔진 출력 규칙을 계약 시험 도우미로(두 언어 같은 값), `npm test` 따옴표 글롭 + 시험 수 > 0, `hashFiles` 가드, `engineVersion` = 실제 응답 판, 미니 라운드 배포 순서(비밀값 → `.env.<projectId>` 커밋 → 배포 → 503·403 확인 → 실제 1회) | 7.2.13, 7.4.7 |
| CD2-23 | **데이터 안전**: 마이그레이션 직전 v1 사본(`VACUUM INTO`) + 개발자 메뉴 내보내기·지우기, B-1 절차(배포 전 백업 내보내기 → 실제 노트가 있는 출처에 배포), 안드로이드 `allowBackup="false"`(D20), 고정 키 저장소에서 서명 재료가 없으면 APK 잡 실패 | 7.2.7, 7.4.3, V14 |
| CD2-24 | Pencil 스퀴즈·롤 설정은 그 기기에서 첫 이벤트를 받은 뒤 보인다(능력 플래그는 OS 가용성일 뿐). `StylusExtrasSource.capabilities`는 앱 시작 때 한 번 — iPadOS 설정 변경은 다음 시작 때 반영 | 7.2.10 |
| CD2-25 | 공통 목차: 13절 '검토 반영 내역' + 부록 A(자리 사용표)·B(네이티브 요구표)·C(위젯 키) 모양을 인정한다(6개 계획서가 이 모양 — 번호를 다시 매기지 않는다) | 6장 |

### 2.2 계약 변경 제안(CP) 판정

| 영역 | 승인 | 수정해서 승인 | 기각·보류 |
|---|---|---|---|
| INFRA | CP1·CP2·CP3(R2-B1 한 번 예외)·CP4(= CP-L2)·CP5·CP7·CP9·CP10·CP11·CP12·CP13(= CP-L3)·CP14 | CP6(= CP-PDF-3 — 최근 갱신 초안·starting~finishing까지 확장), CP8(경로는 R2-B8이 아니라 J0), CP15(순서를 우선순위로 — CD2-18) | — |
| CORE | CP-1(제안대로 `elementIds: List` — 검토자 권고 `Set`은 채택 안 함)·CP-2·CP-3·CP-4·CP-5·CP-6·CP-7·CP-8·CP-9(P-C)·CP-10·CP-11·CP-12·CP-13·CP-14 | CP-15(정보 — 사각형 열 변경까지 함께 정정) | — |
| INK | CP-INK-1·2·3·5·6·7·8·9·10·11 | CP-INK-4(CORE 동작 변경으로 C2-38 — 키가 없으면 45로 보고 더함) | — |
| EDITOR | CP-E1·E2(= CORE CP-1·CP-2)·E4·E5·E6(P-B)·E7·E8 | CP-E3(R2-B3 문장을 03-ink 4.13 표 + 읽기 getter로 정리) | — |
| LIBRARY | CP-L1·L2·L3·L5·L6·L7·L8·L9·L10 | CP-L4(+ `SyntheticShapes.rectanglePath`) | — |
| PDF | CP-PDF-2·3·4·5·7·8·10·11 | CP-PDF-6(믹스인 없음·VM 전용·INFRA V5는 모듈 주입 인자), CP-PDF-9(6개) | **CP-PDF-1 기각**(공개 생성자 인자·`PdfIndexerGate` — 패키지 내부 주입으로 같은 효과, 7.4.9 '추가만'과의 충돌도 없앰) |
| SYNC | CP-S1·S3·S4·S5·S6·S7(P-C)·S8(+ `checkConverged(kinds:)`)·S9 | CP-S2(청크 단위 전부/전무·메타 키 나눔·깨진 값 되감기·LRU 제외·K1 보관 유지로 보강) | — |

### 2.3 영역 간 문제(X-)와 계약 문제(C-) 판정

대리 검토 7건의 X-·C- 항목은 모두 아래 결정 중 하나로 닫는다. '→'는 계약 v2.1 변경 이력 행 또는 영역 할 일(3장)이다.

| 묶음 | 검토 항목 | 판정 |
|---|---|---|
| 바탕 코드 | INFRA M-1·Q-1, PDF S-13 | CD2-01 → C21-02, 각 영역 M |
| 색인기 `final class` | INFRA M-2·C-2·X-1·X-2, LIBRARY X-5, PDF C-2·X-3·S-1 | CD2-17 → C21-15·16·20 |
| 의존·플러그인 목록 | INFRA M-3·C-4·X-1, PDF M-1·X-2 | CD2-20 → C21-21·28 |
| 기능 스위치 | INFRA M-4·C-3·CP14, PDF X-4 | CD2-16 → C21-20·32 |
| R2-B8·기반 단계 | INFRA M-5·C-5·Q-4·S-6·CP3·CP8, CORE M-2, SYNC C-5·X-3·X-4, INK C-8·S-5, EDITOR CP-E3 | CD2-05 → C21-29 |
| 실기기 문구 | INFRA C-1·M-7, CORE C-6·S-11·M-3 | CD2-23, 7.8 A-1·B-1 → C21-33 |
| 유휴 작업 | INFRA C-6·S-1·S-2·S-3·CP15 | CD2-18 → C21-20 |
| V5 문장 | INFRA C-7·S-12, EDITOR CP-E8·X-8, PDF X-3 | CD2-17, V5 → C21-32 |
| 초안 복구 문장 | INFRA C-8, CORE C-3·CP-12, PDF C-1·CP-PDF-4 | '묻지 않고'로 정리 → C21-19 |
| 명령 모양 | CORE C-1·X-4, EDITOR X-7·C-6, INK X-2, LIBRARY X-4 | CD2-06 → C21-07 |
| 객체 변형 규칙 | INK M-2·C-6·X-1, CORE C-8·X-3 | CD2-07 → C21-04·06 |
| 가짜 검색 | CORE C-2·CP-14 | 같은 판정·같은 순서 → C21-30 |
| 색인 재시도 시점 | CORE C-4·S-12 | '다음 쓰기 트랜잭션 또는 저장소 열기' → C21-19 |
| `SearchIndexWriter` 의미 | CORE C-5·M-1·S-6·X-1, PDF Q3 | CD2-11 → C21-09·11·25 |
| `math.engine` 키 | CORE C-7·S-7, SYNC X-4 | 항상 씀 → C21-11 |
| 재생 강조 층 | INK C-1·M-1·S-11 | CD2-09 → C21-13 |
| `StrokeSession` 선언 | INK C-2, EDITOR C-2 | `final class` → C21-13 |
| 객체 id 구분 | INK C-3 | `removedObjectIds` → C21-13 |
| 웹 메모리 | INK C-4·M-5, PDF C-5·M-3 | CD2-10 → C21-25 |
| 벡터 값 생성 | INK C-5·X-7, PDF M-2·X-1 | `InkVectorFixtures` + PDF 중간 표현 → C21-30 |
| CP-INK-2·5 결정 시점 | INK C-7 | 지금 승인(R2-B3 전) |
| `MathPreview` 문구 | INK C-8·X-9, LIBRARY X-2·S-14 | 'MathObject는 상자, MathPreview는 실제' → C21-29 |
| 관찰 getter | EDITOR C-1·M-1·X-1, INK S-13 | CD2-08 → C21-13 |
| 텍스트 편집기 글자 모양 | INK X-3, EDITOR X-2·S-7 | CP-INK-3 승인, EDITOR가 사용 → C21-13 |
| 시트 미리보기 높이·숨김 우선 | INK X-4, EDITOR X-3·S-8 | `measureSync` + 미리보기 우선 → C21-13 |
| 빈 상자 테두리 | INK X-5 | EDITOR가 자기 overlay에 직접 그림(INK 변경 없음) |
| 테이프 모두 보이기 | INK X-6·Q3, EDITOR X-2 | EDITOR가 `updateContent` 뒤마다 다시 적용(INK 의미 그대로), 컨트롤러 수명 수용 → C21-13 |
| `rasterize` 답 | INK X-8·S-13, PDF CP-PDF-7·8 | 둘 다 승인 → C21-13·16 |
| `.gitattributes`·자산 | INK X-10, INFRA S-14·X-5 | `binary` 목록 + 자산 파일 단위 → C21-25 |
| 능력 알림 | EDITOR C-3·X-8, INFRA S-9 | CD2-24 → C21-14 |
| `isVisible` 예외 | EDITOR C-4, LIBRARY CP-L5 | E-7 예외 → C21-19 |
| CP-E4 표시 | EDITOR C-5 | CP-E4 승인으로 계약 문장 → C21-14 |
| 탭 재생 상태 | EDITOR C-7·M-3·X-4, PDF M-8·X-5·Q-3, CP-PDF-10 | CD2-14 → C21-08 |
| 사용자 동작·context | EDITOR S-6·X-5, LIBRARY C-8·S-12·X-1, PDF S-10 | CD2-15 → C21-14 |
| 도형 표본 형식 | EDITOR S-5·X-6, LIBRARY X-1, SYNC X-6 | 표본은 EDITOR 링 버퍼(개발자 토글 켬일 때만) → LIBRARY 형식 `{kind, points, viewScale}`. 수식 고정 자료(6.9.1 형식)는 LIBRARY 수식 패드의 P-C 개발자 동작 |
| `emulator` 실행 장소 | LIBRARY C-1·S-6, SYNC X-5 | CD2-19 → C21-26 |
| 어댑터 채널 가짜 | LIBRARY C-2 | 예외 허용 → C21-26 |
| `userConfirmed`·신선함 | LIBRARY C-3·C-4·M-1·S-2·S-3·X-3, SYNC X-5 | CD2-12 → C21-09·15 |
| `ensureModel` 주석 | LIBRARY C-5 | Q2 승인 → C21-15 |
| 설정 키 | LIBRARY C-6·CP-L9, INFRA CP12, EDITOR CP-E7 | → C21-24 |
| `SyntheticHandwriting` 'words' | LIBRARY C-7 | 'words' 삭제 → C21-30 |
| 도형 보정 흐름 시험 위치 | LIBRARY S-7·X-2 | `ink_recognition/test/integration/` → C21-31 |
| `notesWithStalePages` | LIBRARY Q8·X-4, CORE X-2 | 이번에 추가 → C21-09 |
| `pendingDrafts`·`isActive` | PDF C-4·M-5, INFRA CP6 | CD2-13 → C21-08 |
| `media_io/testing.dart` 주석 | PDF C-3·S-11·CP-PDF-6 | → C21-30 |
| WebM 길이·V8 | PDF C-6·M-6 | → C21-08·32 |
| `FakeAudioRecorder` 예외 형·웹 저장소 도우미 | PDF X-6 | `UnsupportedError`, `testing_web.dart` → C21-05·30 |
| 빈 조각 `append` | PDF X-6③ | `updatedAt`도 갱신 → C21-08 |
| `allowBackup` | INFRA X-4·Q13 | 끔(D20) → C21-23 |
| Info.plist 문구 | INFRA X-1 | INFRA 문구 → C21-23 |
| SYNC switch 수 | SYNC C-1 | → C21-04 |
| 영구 삭제 문구 | SYNC C-2 | 노트 단위 → C21-12 |
| JSON 키 대조 | SYNC C-3·M-4·CP-S1 | → C21-12 |
| S-13 보강 | SYNC C-4·M-1·S-1·S-3 | CD2-21 → C21-12 |
| `functions/` 따로 병합 | SYNC C-5·Q-5 | R2-B7b → C21-29 |
| `firebase-tools` 14일 | SYNC C-6·Q8 | R2-B1·B7b 재확인 → C21-28 |
| `engineVersion` | SYNC C-7·S-8 | 실제 응답 판 → C21-17 |
| `@anthropic-ai/sdk` | SYNC C-8·CP-S5 | 승인 → C21-28 |
| 잠금 중첩 | SYNC X-2, INFRA S-4 | CD2-19 → C21-26 |
| `.gitignore` 보강 | SYNC X-1, INFRA S-11 | → C21-27 |
| 손글씨 '최근 보냄' | SYNC M-3·Q-2·X-5 | CD2-12(1차 T11 결정 ① 변경 승인) → C21-12 |

### 2.4 대리 검토 판정에 대한 총괄 조정

- **방법을 바꾼 것**: LIBRARY M-1은 '`put` 직전 다시 읽기'가 아니라 CORE `update`(트랜잭션 안 병합)로 — 다시 읽기와 쓰기 사이의 틈도 없앤다. INK M-2의 'CORE 공개 도우미'는 따로 두지 않고 `PageObject.transformed`에 `scaleWidth`를 넣어 그 자체를 단일 규칙으로. CORE CP-1의 `elementIds`는 검토자 권고(`Set`)와 달리 `List`(1차 명령 전부가 `List`). EDITOR M-3은 검토자 안보다 더 좁혀 펜 탭은 재생·일시정지 중에만 가로챈다(패널만 열린 상태의 마침표는 획). PDF M-8은 PDF가 아니라 EDITOR 쪽(초점 시점)에서 푼다. INFRA M-3은 NR6를 좁히는 대신 `plugin_packages`를 '해석된 플러그인 전부'로 두고 R16을 플러그인 없는 멤버에만 적용한다.
- **권장 → 반드시로 올린 것**(P-A 기능의 손실·실패 경로이거나 계약 문장이 된 것): CORE S-3(웹 초안 meta), EDITOR S-2(회전 객체 크기 조절)·S-6(Safari 사용자 동작)·S-7(키보드 없는 선택·붙여넣기 + 글자 모양), LIBRARY S-1①·S-2·S-3·S-4·S-6·S-7·S-11, PDF S-10(`use_build_context_synchronously`는 `--fatal-infos`에서 실패)·S-11, SYNC S-1·S-3·S-4·S-5·S-6·S-8·S-9.
- **총괄이 수치를 정한 것**: 웹 메모리 재배분(CD2-10), 검색 색인 크기 목표(CD2-11), 웹 크기 한도 기준(1차 실측 + 300 KB), 줄 나누기 V9 문턱은 생성기를 좁힌 뒤에도 95 % 미만일 때만 낮춘다(LIBRARY Q4).
- 나머지 '권장(S)'은 영역이 판단해 반영하고 13절 '검토 반영 내역'에 반영 여부를 적는다. 반영하지 않으면 이유를 한 줄로 남긴다.

---

## 3. 영역별 반드시 고칠 것

각 영역은 아래 표를 모두 반영하고, 계약 v2.1(00-overview 7장)의 `(v2.1)` 표시 문장을 계획서 4·5절 '계약 원문' 블록에 다시 옮긴다(글자 그대로). 13절 '검토 반영 내역'에 항목 번호별로 반영 위치를 적는다.

### 3.1 INFRA — `01-infra.md` · 판정: 수정 후 재검토

| # | 근거 | 할 일 |
|---|---|---|
| INFRA-M1 | 검토 M-1, CD2-01 | 바탕을 1차 통합 HEAD로 옮긴다: 3장에 '1차 통합에서 바뀐 것' 표(ink lab 멤버·`app_members`·dev `analyzer 13.3.0`·`ws test` 시간 제한/재시도/종료 코드 2·3·79·`android.yml` 개발 브랜치 푸시), 3.2·4.3.1 '전체' 블록 교체, J15를 `resolveChrome` 구조 위에(재시도 동안 잠금 유지). **웹 예산 한도(Q4)를 1차 실측 기준**(gzip 1,366,038 B + 300 KB)으로 |
| INFRA-M2 | 검토 M-2, CD2-17 | 색인기 시험을 모듈 생성자 주입 이음새(시작·종료 함수)로. 5.8·J8·J10·9.1의 'provider override 가짜 색인기' 삭제. 실제 색인기는 가짜 저장소로 '두 번 `dispose` 안전'만 |
| INFRA-M3 | 검토 M-3, CD2-20 | `media_io` pubspec = PDF 3.4 확정본(CP-PDF-9 **6줄** + CP1 2줄, 승인 대기 표시 제거). `pinned_external`에 모두, `plugin_packages` = 해석된 플러그인 전부(웹 전용·간접·`integration_test` 포함 — `native-reqs`가 `.flutter-plugins-dependencies`와 대조), R16 `plugin_free_members` = `feature_editor`·`feature_library`·`ink_engine`·`note_core`, `pdf_io` 행은 `[file_picker]`로 정정. LIBRARY는 `google_mlkit_commons`를 직접 의존하지 않으니 그 줄 정리 |
| INFRA-M4 | 검토 M-4, CD2-16 | `FEATURE_MEDIA` = 녹음만. 이미지 가져오기 기여를 스위치와 떼어 연결(`MediaModule` 안에서 녹음 기여만 거르거나 `ImageImportModule` 분리 — INFRA 선택). 6.6 표('dart2js가 녹음 코드만 버림')·9.1 `feature_switch_test`·CP14·V15 문장을 하나로 |
| INFRA-M5 | 검토 M-5, CD2-05 | R2-B8 → B8a(부트스트랩 확장·`AppFeatures`·모듈 2개·7.3.3 연결·유휴 작업 v2.1)·B8b(라우팅·`pencil_bridge` Dart 표면·어댑터), 각각 완료 조건·세션 추정. 네이티브 설정 파일·`native_config.dart`·`native_config_test`·웹 빌드 실측은 J0. '다른 영역의 시작 조건이 아님'을 1.2·8.1에 |
| INFRA-M6 | 검토 M-6 | J0(또는 첫 체크포인트 푸시)에서 CI 단계별 시간을 실측해 6.16 재계산을 완료 조건으로. 잡 분리안(check·analyze·VM / Chrome / integration·media / 웹 빌드·배포)과 분 증가, 영역 브랜치는 affected만·`media`·integration은 main·수동만, 25분 제한 대책을 J15에 |
| INFRA-M7 | 검토 M-7, CD2-23 | `ANDROID_CERT_SHA256`가 있는데 서명 재료가 없으면 잡 실패, debug 서명이면 아티팩트 이름 `noteapp-debug-signed-<run>`. 안내서 05 '설치가 안 되면 앱을 지우지 말고 알려 주세요'. `workflows_test` 분기 |
| INFRA-M8 | 검토 M-8 | `PencilBridge.events`에서 `asBroadcastStream()` 제거(또는 `onCancel`로 취소). 시험: 두 구독 → 모두 취소 → cancel 1회 → 다시 구독 → listen 2회째 |
| INFRA-M9 | C21-20, CD2-18 | 유휴 작업 v2.1: 이탈 경고는 시작 성공 직후, 유휴 순서 `media.recoverDrafts` → `pdf.searchIndexer` → `recognition.indexer`, `resumed`·`inactive`·값 없음에서 실행, 늦은 `contribute` 무시 + 기록, `MediaModule.onStartAbandoned` 정의 |
| INFRA-M10 | C21-26, CD2-19 | 무거운 시험 잠금: 고정 경로 `/tmp/noteapp-heavy-tests.lock`(환경 변수로 바꿈), `NOTEAPP_HEAVY_LOCK_HELD` 넘김, `ws with-heavy-lock -- <명령>`(SYNC RQ-5), 잠금 형식 호환 시험. `emulator` 태그를 컨테이너에서 실행하는 경로 |
| INFRA-M11 | C21-29 | R2-B1 보강: 빈 `register(with:)` Swift·`Package.swift`·podspec(검토 S-6), `integration_test` 해석(S-5), INK pubspec 4줄(CP3), `.gitignore`(RQ-2 + `functions/eval-out/`·`firebase-debug*.log`) + `.env.demo-noteapp` 미무시 확인 시험, `.gitattributes` `binary` 목록(S-14), `functions.yml` `hashFiles` 가드(S-11), `generated_files`에 `*.steps.dart`, `lib_exceptions`에 `note_core/lib/testing_web.dart`, `firebase-tools` 14일 재확인 |
| INFRA-M12 | C21-32, CP-E8 | V5 단계 표: 가짜 = 모듈 주입 인자, 선택 메뉴 90° 돌리기(EDITOR 부록 C 키), 되돌리기 → 닫기 → 다시 열기 순서(1차 C15-04), 자동 도형은 `SyntheticShapes.rectanglePath`, 내보내기 구조는 INK `InkPageVectors` 개수(실제 PDFium은 V11 — 검토 S-12). `FakeAudioRecorder` + 실제 메모리 CORE의 시간 진행(pump·runAsync). 초안 복구 시험은 CP-8 `abandon()`(S-13) |
| INFRA-M13 | C21-23·C21-11·C21-10 | `allowBackup="false"` 확정, Info.plist 문구 확정(PDF에 알림), 개발자 메뉴 'v1 DB 사본 내보내기·지우기', 앱 셸이 네이티브에서 두 경로를 모두 넘기는지 정적 시험 |
| INFRA-M14 | C21-14·C21-18·C21-15 | Pencil 어댑터: `PencilEvent.timestamp` → `StylusExtraEvent.timestamp`(CP-E6), 능력은 시작 때 한 번(다시 시작 때 반영 안내), 스퀴즈·롤 항목은 첫 이벤트 뒤(S-9). X30 `done` 변환(CP13), `recognitionDevOverlayLinesProvider` 사용(CP4) |
| INFRA-M15 | C21-33, CD2-02·03 | 안내서: 01에 '2차는 Hosting(Spark)만 — 실연결과 별개', 04에 B 체크리스트 v2.1(B-1 절차·B-15·B-16), 05에 고정 키 전달(U20 — 파일로, `gh` 불가), 08에 7.8 문구 그대로(A-1 정정). 통합 9단계 Playwright 스모크 |

권장(반영 여부는 13절에): 검토 S-7(Swift 컴파일 실패 시 `pencil_bridge`를 앱에서 잠시 빼는 대안), S-8(attach 대상 `registrar.viewController` 먼저·호버 인식기 동시 인식 delegate), S-10(서명 키 전달 — U20), S-15(KaTeX·아이콘 글꼴 한도 분리 — J0 실측 뒤), S-16(블롭 루트 — CORE가 만들기로 정함).

질문 답

| Q | 답 |
|---|---|
| 계획 Q1 | U20 기본값(①, 키는 **파일로** 전달). 이 세션의 `gh`는 인증이 되지 않아 Claude가 시크릿을 넣을 수 없다 |
| Q2 | 커밋한다 |
| Q3 | 보인다(개인용, 기본 모두 켬) |
| Q4 | 기준을 1차 실측(gzip 1,366,038 B)으로 바꿔 '기준 + 300 KB', 시작 글꼴은 묶음별 — J0 뒤 다시 제안 |
| Q5 | U2 답에 따른다(없으면 P-C로 넣음) |
| Q6 | 맞다 — 미리보기·live 빌드에 `MATH_ENDPOINT` 없음 |
| Q7 | `stopWithTask="true"`, `allowAutoRestart: false` 확정(PDF 부록 B와 같음) |
| Q8 | 넣는다(경고 단계) |
| Q9 | 아니오 |
| Q10 | 필요 없다 |
| Q11 | 없음 |
| Q12 | 범위 밖 |
| Q13 | 끈다(D20, U27) |
| 검토 Q-1 | 지금(이번 수정) — CD2-01 |
| 검토 Q-2 | 녹음만(D17) |
| 검토 Q-3 | 안 된다(`GH_TOKEN` 무효, 2026-11-05) |
| 검토 Q-4 | 된다 — R2-B8은 시작 조건이 아니다(D24) |
| 검토 Q-5 | U19 승인 시 V14의 완료 조건 |

### 3.2 CORE — `02-core.md` · 판정: 수정 후 재검토

| # | 근거 | 할 일 |
|---|---|---|
| CORE-M1 | 검토 M-1, CD2-11 | PDF 글자 사각형을 SQLite 밖(블롭 저장소 키 `si/<source>/<ownerKey>/<seq>` — 기본) 또는 ≥ 1/65535 양자화 압축 BLOB으로. 질의 후보는 `id·source·owner_key·note_id·page_id·asset_id·pdf_index·norm`만 읽고 대표 `limit`개만 `body`·사각형. 6.10.7에 실제 모양 크기 예산(500쪽 ≤ 12 MB·다시 열기 +300 ms 목표), PF에 그 모양의 500쪽 고정 자료, Chrome '색인 뒤 저장소 다시 열기 시간' 시험(T33/T37), 9.5 B-13 항목, 위험 3을 '웹 DB 메모리·열기 시간'으로 |
| CORE-M2 | 검토 M-2, CD2-05 | R2-B2 = B2-α(공개 선언 전부 + `api_surface_test` v2, 약 0.5세션, 해시 알림) + B2-β(JSON·골든 먼저 → T20·T21 → T23a 해석기·세션 / T23b 가짜 v2·가짜 오디오·픽스처). 조각별 완료 조건·세션 추정을 8.1에. 검토 S-9(T33 → T33a·T33b)도 함께 |
| CORE-M3 | 검토 M-3, CD2-23 | 업그레이드 직전 v1 사본(`VACUUM INTO` — 웹 VFS는 T24 첫날 Chrome 시험, 안 되면 다른 사본 방법), 사본 수명(정상 열기 N번 뒤 삭제), V7에 '사본의 정규 덤프 해시 = manifest'. 위험 1·6.12.3·9.5 B-1 문구('실제 데이터의 이주는 그 데이터가 있는 출처에 배포될 때 처음 일어난다' + 배포 전 백업 내보내기 절차) |
| CORE-M4 | 검토 S-3 승격, C21-08 | 웹 초안: `begin`에서 행과 함께 블롭 저장소 `rd/<draftId>/meta`를 먼저 쓰고, `listDrafts`는 행이 없으면 meta로 되살리며, 고아 정리는 행·meta 둘 다 없을 때만. 6.7.3 내구성 문장 정정. 빈 조각 `append` = `active_ms`·`updated_at` 갱신. '조각 0 초안'(네이티브)은 정상(S-14) — 12.2 Q4 기본값을 PDF 답으로 |
| CORE-M5 | C21-06·07, CD2-06·07 | CP-1(`List<ElementId>`)·CP-2 승인 반영. `PageObject.transformed(m, {scaleWidth = true})` = 단일 규칙(해석기는 이것만 부름), `fromJson`은 정규화하지 않음(S-1 — `element_frame_test`에 `−π`·`3π`·변 0 왕복). `ClearPage` 1차 이름 있는 인자에 `includeObjects` 추가(S-17) |
| CORE-M6 | C21-04, CP-INK-4 | `Stroke.transformed`: 캘리그래피 `nibAngleDeg`(없으면 45) + `m.rotation`(도) → [0, 180). 키 문자열은 CORE 내부 상수 + 같은 값 확인 시험(INK 쪽 `InkStyleExtras.nibAngleDeg`와 대조는 통합 2단계). 시험은 `undo_objects_test` 옆 |
| CORE-M7 | C21-09, CD2-12 | `HandwritingRepository.update`(한 쓰기 트랜잭션 — 변환 함수는 동기·순수)·`notesWithStalePages()`(가장 최근 노트 먼저) 추가. 실제·가짜 공유 계약 본문에 경합 사례. `stalePages`는 페이지 순서. 검토 S-10: 10만 획 라이브러리의 첫 따라잡기 비용 PF, `updated_at` 위치(`points` BLOB 뒤) 보정·덮개 색인 검토 |
| CORE-M8 | C21-09·11, CD2-11 | `SearchIndexWriter`: 빈 목록도 소유자 유지(S-6, `search_index_test`), 후보 상한 2,000의 선택 기준 = 최근 단위 먼저(S-8) — 가짜도 같게(CP-14), `pdfPageAspect`(CP-3), `PageRect.zero` 건너뜀, pdf `sourceRev` 꼬리(CP-PDF-2) 문자열 비교. CP-15 표 정정에 사각형 열 변경 포함. 점수 문구(S-15) |
| CORE-M9 | C21-30·05 | `testing.dart` v2.1: `FakeAudioRecorder.start` 지원 안 함 → `UnsupportedError`(PDF X-6①), 초안 쓰기·`pendingDrafts` 제외 규칙, `abandon()`, `FakeAudioPlayback.calls`, idb_shim 시간 진행 안내(X-4). **`testing_web.dart`**: `openWebTestNoteStore`·`deleteWebTestNoteStore`(PDF Q2) |
| CORE-M10 | C21-08 | `pendingDrafts`·`recoverDraft` 계약 문장(CP-7 표에), `createRecording` 멱등, `Recording.toJson` `title` 항상 |
| CORE-M11 | C21-11 | `math` `engine` 키 항상(`null` 골든 사례, S-7), make-migrations 산출 `note_database.steps.dart`(S-2) — 3절 트리·6.12.1 정정, V7 고정 자료는 1차 통합이 `main`에 들어간 커밋으로 R2-B2 전에 생성(Q-2), Chrome 고정 자료 전달은 `tool/prepare_web_test.dart` 복사(S-5), T25 선행에 T35, 정규화 위임은 T24에(S-16) |
| CORE-M12 | C21-10·C21-23 | 네이티브 블롭 루트 디렉터리를 CORE가 만든다. `UnknownObject.referencedAssets`(S-13). 2272행 'DB·블롭은 백업 대상' → '안드로이드 자동 백업은 끈다(D20), iOS 기본' |
| CORE-M13 | C21-29 | 이정표 커밋 알림(B2-α, B2-β JSON, T24, T26~T33)을 진행 기록 양식에 고정. SYNC B7a 바탕 = B2-α 해시로 통일(SYNC X-4) |

질문 답

| Q | 답 |
|---|---|
| 계획 Q1 | CP-1 승인(이름 있는 인자, `List`) — 지금 결정 |
| Q2 | 커밋한다. 생성 커밋 = 1차 통합이 `main`에 들어간 커밋(아직 태그 없음 — 병합 뒤 총괄이 해시를 알림) |
| Q3 | 쪽 단위 + 글자 상자(PDF 결정), 저장은 CORE-M1 |
| Q4 | 행만(조각 0) + 파일 복구 시도(PDF 결정) |
| Q5·Q6·Q8·Q9·Q10 | 기본값대로 받아들임 |
| Q7 | 크기 목표·측정(CORE-M1). 'PDF 색인 끄기' 설정은 이번에 없음 |
| 검토 Q-1 | U25(기본: 실제 노트 없음 — Hosting이 없었다) |
| 검토 Q-2 | 위 Q2 |
| 검토 Q-3 | 기본 = SQLite 밖(블롭 저장소), 압축 BLOB도 허용(CORE 선택, 목표를 지키는 쪽) |
| 검토 Q-4 | U2 |

### 3.3 INK — `03-ink.md` · 판정: 수정 후 재검토

| # | 근거 | 할 일 |
|---|---|---|
| INK-M1 | 검토 M-1, CD2-09 | 재생 흐림·강조와 도형 보정 미리보기(S-11)를 층 4′(`inkActive` 끝)로. overlay = 선택·올가미·레이저만. 6.1 층 표·6.19·T40 수정, `widget/playback_focus_test`에 '가린 테이프 영역 픽셀 불변(두 스타일)'·'안 쓴 획 위 텍스트 픽셀 불변' |
| INK-M2 | 검토 M-2, CD2-07 | 객체 미리보기·대기 표시 = CORE `PageObject.transformed(m, scaleWidth:)` 그대로. 원칙 6·6.8.4·6.14·5.2 문장 정정, `selection_test` v2에 '도형 2배 미리보기 굵기 = 커밋 뒤 굵기', '텍스트 상자 배율 미리보기 = 커밋' |
| INK-M3 | 검토 M-3 | `OffscreenMathHost.rasterize`: 다시 build 요청이 오면 양보하며 반복(횟수·시간 상한 `InkTuning.mathSvgSettleMs`), 넘으면 `null` + `mathRasterFailed`, 요청은 큐로 하나씩. 지연 로더 이음새는 내부 `@visibleForTesting`. `\sqrt{x}`·`\sqrt[3]{x}`·`\vec{v}`·`\xrightarrow{f}`·`\left\{…\right.` 표본(VM·Chrome), 11장 '네이티브 release에서만 드러나는 경로' |
| INK-M4 | 검토 M-4, CD2-10 | 캐시 항목의 '그리는 중' 참조 수를 예산에 세고 쫓아내지 않음, 넘치면 한 단계 낮은 버킷, `changes`가 바뀐 `(assetId, bucket)`을 알림(S-6), 수식도 같은 규칙. T35·T36에 '작업 집합 > 예산 → 다시 기록 횟수 유한·모두 그려짐'. CP-INK-5 승인 |
| INK-M5 | 검토 M-5, CD2-10 | 6.22를 v2.1 예산(웹 래스터 공유 96 MB = 타일 + 이미지, 수식 8)으로, I-B11 기준 = 개발자 표시 앱 캐시 합계 ≤ 300 MB |
| INK-M6 | 검토 M-6 | `PenPreviewPainter` 새 펜 5종(레이저 빛 + 심 정지 그림, 테이프 가림·줄무늬, 캘리그래피 각·비율, 점선), T27~T31 완료 조건에 `pen_preview_test` v2·골든 미리보기 장, 트리 `[바뀜]` |
| INK-M7 | 검토 M-7, CD2-19 | `ensureLoaded`·`noteSansBytes`에 시간 상한(`fontLoadTimeoutMs` 5,000), `useInkTestFonts()`(base64 작은 글꼴 — 웹 안전)를 `testing.dart`에, 5.6~5.8에 'Chrome 시험은 `setUpAll(useInkTestFonts)`' + KaTeX는 적재 없이 단언 |
| INK-M8 | 검토 M-8 | 10장 7항(실기기 합격)을 9.6 머리의 '합격 판정(영역 완료 조건 아님)'으로 |
| INK-M9 | C21-13, CD2-08 | R2-B3(T24)에 읽기 getter 4개, `StrokeSession` `final class` 문구(4.10에 'final 유지'), `InkEdit.removedObjectIds` + `toCommand` 표(CP-INK-2 — R2-B3 전 승인됨, 6.15 대체 규칙 삭제), 미리보기 > 숨김 규칙(6.17), `textStyleOf`·`strutStyleOf`·`measureSync`(동작), `InkVectorFixtures`(PDF X-7), 4.13 표의 `MathPreview` 실제 동작 문구 |
| INK-M10 | C21-13·16 | CP-PDF-7 `InkTextLayout.rasterize`(투명 바탕·4 Mpx), `rasterize`(수식) 상한을 픽셀 수로(4096 긴 변 → 4 Mpx), CP-INK-1·3·5~11 반영, 12.3에 EDITOR·PDF 요청 답(CP-E3 = 4.13 충족, CP-PDF-7·8 동의) |
| INK-M11 | C21-31·29 | 03-ink I-4를 'LIBRARY `ink_recognition/test/integration/shape_assist_flow_test.dart`가 INK `createTestPageController(shapeFitter:)`로'로. T26 → T26a(글꼴·측정 — EDITOR 이정표)·T26b(수식 검증·배치·미리보기), 이정표 T24·T26a·T33·T34·T36·T42 알림 |
| INK-M12 | C21-25 | `flutter: assets:`를 파일 단위로(`NoteSans` 2개 + `OFL.txt`, README 제외), `.gitattributes`는 INFRA가 넣음 |

권장: 검토 S-1(웹 재생 프레임 비용 `playbackPaintUs`, 대체 경로), S-2(1차 사각 캡 재사용 — T27 축소), S-3(`InkLayer.cover` 분기 점검 목록을 T31에), S-4(이미지 배경 첫 디코드 원본 해상도 피하기), S-7(fonttools 4.67.0 고정 또는 개발 도구 예외 명시), S-8(시계 기준 한 줄), S-9(수식 `layout`은 프레임 단계 밖), S-10(화살표 머리 겹침), S-12(`ref.read` → 읽는 함수), S-14(빈 `recolor`), S-15(썸네일의 글꼴 적재 — 계약에 반영함).

질문 답: Q1 고정(CP-INK-7) · Q2 컨트롤러 수명 수용(EDITOR가 노트 단위 '모두 보이기'만 다시 적용) · Q3 음절 단위 · Q4 수용 · Q5 제외(CP-INK-8) · Q6 넣는다(`binary`) · Q7 실기기 뒤 판단 · Q8 단색 · Q9 닫음(recog는 INK `MathPreview`만). 검토 질문 1 층 이동 수락 · 2 CD2-10 · 3 EDITOR 쪽(a) · 4 둘 다 · 5 내부 `@visibleForTesting` · 6 U7(기본 2,350자 유지).

### 3.4 EDITOR — `04-editor.md` · 판정: 수정 후 재검토

| # | 근거 | 할 일 |
|---|---|---|
| EDITOR-M1 | 검토 M-1, CD2-08 | 위젯 시험 단언을 INK 읽기 getter(R2-B3)와 EDITOR 이음새(`shapeAssistFor(settings, penType, fitter)` 순수 함수, `PlaybackHighlightDriver` 출력 주입, 텍스트 숨김은 `TextEditState`)로. 레이저는 실제 R2-B3(`end() == null`)로 시험, 자동 도형은 `FakeInkShapeFitter`·`SyntheticInk.loopThenHold`(S-4). 5.2.4 표를 03-ink 4.13에 맞춤 |
| EDITOR-M2 | 검토 M-2 | 텍스트 세션 끝 판정은 라우터(펜 접촉·한 손가락 탭 확정·길게 누르기)만, 내비게이션·거부된 접촉은 유지. 뷰포트를 편집기·서식 바와 같은 `TapRegion` 묶음에, 포커스 잃음을 `TextEditEndReason`에. 시험: 두 손가락 끌기·핀치·손바닥·펜 전용 한 손가락 끌기 → 유지·명령 0·오버레이 갱신 |
| EDITOR-M3 | 검토 M-3, CD2-14 | 탭 재생 상태 = v2.1 R-5(손가락: 패널 열림 또는 재생·일시정지 / 펜: 재생·일시정지만 / 녹음기 `idle`일 때만), 펜 탭 문턱 4 px·200 ms(테이프 ②도 같은 문턱), `end()` 전 판정·`cancel()`. E2-17 시험 3개(정지 직후 패널 닫힘 → 15 px 획 커밋, 패널 열림 + `ready` → 손가락 탭 seek·펜 점은 획, 녹음 중 → 가로채지 않음). Q3 문구 |
| EDITOR-M4 | 검토 M-4 | 선택 우선 규칙 (a′): 그리기 도구(펜·도형·텍스트)에서 선택이 있으면 **핸들**만 우선, 본체 끌기 이동은 그 선택이 올가미(임시 올가미 포함)·붙여넣기·삽입 메뉴(이미지·수식)에서 생긴 경우만. 도형 도구로 그려 생긴 선택의 본체 down = 새 도형(이전 선택 해제). 6.6.2·6.6.3·Q8, 시험(사각형 안에서 원 그리기 → `AddObjects` 1회, 이미지 삽입 직후 본체 끌기 → 이동, 펜 도구 + 붙여넣은 선택 본체 끌기 → 이동) |
| EDITOR-M5 | 검토 S-2 승격 | `ObjectResize.cornerScale(frame, corner, deltaPagePt)` — frame 지역 축 투영·회전된 반대 모서리 고정. `object_resize_test` '30° 회전 이미지 모서리 끌기'. 폴리라인 회전은 상대 각 무리로, 회전 시험 각은 맞춤 경계 안쪽(32°) |
| EDITOR-M6 | 검토 S-6 승격, CD2-15 | `ExtensionRunner`·이미지 출처 항목: `onPressed` 안에서 `onSelected`·`pick` Future를 **동기적으로 시작**한 뒤 메뉴·시트 닫기, 넘기는 `context` = 에디터 본문(4.3.1). 9.4 B-3에 '한 번 눌러 바로 열림' |
| EDITOR-M7 | 검토 S-7 승격, CP-INK-3 | 편집기는 `material_ui` `TextField`(`InputDecoration.collapsed`) 또는 선택 손잡이·컨텍스트 메뉴 명시. 글자 모양은 INK `textStyleOf`·`strutStyleOf` + 안쪽 여백 0(6.11.3, 12.1에서 지지). 1.3 문구('캔버스 수준 붙여넣기는 없음, 편집 중 글자 붙여넣기는 됨') |
| EDITOR-M8 | PDF 검토 M-8, CD2-14 | 재생 강조 초점은 이 열림 뒤 `playing`이었거나 `seekMs` 뒤에만(6.15.2). `playback_highlight_test` '정지 직후 흐림 없음'. CP-PDF-10(녹음 중 `play` 무시)을 6.15.3에 |
| EDITOR-M9 | C21-07 | 명령 호출을 v2.1 모양으로(`RemoveElements(pageId: …, elementIds: [id])`, `ClearPage(pageId: …, includeObjects: true)`), 5.1.2 표에 부분 지우개 + 도형 행(CP-INK-2)·`erase_v2_test` '되돌리기 1번에 도형과 조각 복구' |
| EDITOR-M10 | INK X-4·X-5·X-6, EDITOR S-8 | 시트 모드: 숨김 대신(또는 함께) 같은 id 미리보기(미리보기 우선 규칙), 초안 높이는 `measureSync`(null이면 `measure`), 입력 패널은 화면 위쪽 또는 `viewInsets` 반영(EDITOR 자체 UI — 7.4.10 바닥 시트 규칙 대상 아님). 빈 곳 끌기 상자 테두리는 EDITOR overlay가 직접. 테이프 '모두 보이기'는 `updateContent` 뒤마다 다시 적용, 낱개 토글이 마운트에서 빠지면 사라짐을 6.14.4에 수용 |
| EDITOR-M11 | LIBRARY X-1, EDITOR S-5 | 도형 표본: 개발자 토글('도형 표본 모으기', device, 기본 끔)이 켜졌을 때만 마지막 5개 펜 세션의 페이지 좌표 점·`viewScale`·결과를 링 버퍼에, 개발자 메뉴가 LIBRARY 형식 `{kind, points, viewScale}`으로 복사(기대 종류는 선택 시트) |
| EDITOR-M12 | C21-14·19·24 | CP-E4(계약 문장 — 6.3.2 표시 정리)·CP-E6·CP-E7·CP-E8 반영, E-7 `isVisible` 예외, 능력은 시작 때 한 번(설정 안내), 스퀴즈·롤 항목은 첫 이벤트 뒤. `EditorSettingKeys.all` 형(`List<core.SettingKey<Object?>>`)·`editorPreRollMsProvider`(S-10), `PlaybackHighlightStyle` 대신 `ink.InkPlaybackStyle`, `WebTextInputMode`는 내부 키 검토 |
| EDITOR-M13 | 검토 S-3 | 작업 분해: E2-07 → (a) 클립보드·붙여넣기·컨텍스트 메뉴·단축키 (b) 선택 메뉴·색 (c) 확장 항목·`ExtensionRunner`, E2-04 → (a) 접촉·버튼·지우개 끝 (b) 손가락 동작·길게 누르기·펜 탭 훅, E2-16 선행에서 E2-13을 빼고 마이크 단추 자리를 E2-16에, E2-01 선행에 E2-03(또는 최소 진입점) |
| EDITOR-M14 | C21-26 | Chrome 시험에 `setUpAll(useInkTestFonts)`, 9.2·9.3 Chrome 텍스트 시험 설명을 '웹 컴파일·세션 규칙'으로(IME 판정은 B-2·B-15만 — S-9) |

권장: 검토 S-1(원본 사라짐을 명령 전에 동기 검사 — 스낵바·보고 없음), S-11(긴 텍스트 세션 초안을 device 키에 주기 저장·복구 제안, 읽기 전용 거절 때 클립보드 복사), S-12(b)~(f).

질문 답: Q1 Hosting이 있으면 한다(`area2/editor` 브랜치 미리보기 채널 — U24) · Q2 한다 · Q3 v2.1 R-5로 좁혀 그대로(U26) · Q4·Q5·Q6·Q7·Q9·Q10·Q11·Q13·Q14 기본값 · Q8 (a′) — 붙여넣기 뒤 도구는 바꾸지 않고 본체 끌기는 허용 · Q12 올리지 않아도 된다(다만 `PlaybackHighlightStyle`은 빼고 INK enum을 쓴다). 검토 질문 1 (a′), B-5는 올가미·붙여넣기 선택으로 그대로 · 2 펜은 재생 중에만 · 3 CP-INK-3 함수는 R2-B3에 들어온다 · 4 그렇다 · 5 개발자 토글 켬일 때만(U18 동의 범위 안 — 저장소에는 내보낸 것만).

### 3.5 LIBRARY — `05-library.md` · 판정: 수정 후 재검토

| # | 근거 | 할 일 |
|---|---|---|
| LIBRARY-M1 | 검토 M-1, CD2-12 | 색인기·변환 창의 쓰기를 CORE `HandwritingRepository.update`로(6.9.4 병합을 변환 함수 안에서 — 저장된 최신 값에 대해). 색인기는 `EntityKind.handwriting` 변경도 구독해 그 페이지 작업을 버리고 다시 큐에. 시험 3개(작업 도중 확정 줄 → 유지·쓰기 1회, 작업 도중 원격 손글씨 → 버림·재시도, 색인기 진행 중 복사 → 유지) |
| LIBRARY-M2 | 검토 M-2 | 줄 나누기 실험 E-L5(L2-05 첫 단계, `library57/lines/`), 생성기 명세 좁힘(페이지 공통 기울기 θ_p ∈ [−4°, +4°] + 줄마다 ±1°, 중심 = 줄 가운데, 이웃 줄 세로 틈 ≥ 0.25·H — 어기면 다시 뽑음, 경계 사례는 손 고정 자료), 정확도 계산법(일대일 짝). 95 % 미만이면 근거와 함께 V9 변경을 12.1에 |
| LIBRARY-M3 | 검토 S-2·S-3 승격, C21-09 | 확정 줄 유지 규칙(옛 획 id ≥ 80 % 남고 새 획 상자가 줄 글자 높이 중앙값 이하 → 유지, 아니면 엔진 글 + 옛 확정 글을 `alternatives` 맨 앞), 신선함 = `sourceRev` + 언어(엔진 판·기기 무시 — 6.9.3), 시험 |
| LIBRARY-M4 | 검토 S-1①·S-4 승격, G-2·G-4 | 페이지 작업은 `stalePages` 먼저, 줄 사이 양보(개발자 표시에 작업 ms), 복사 경로·색인기는 `await store.flush()` 뒤 `loadPage`, 시험 '쓰자마자 복사 → `sourceRev` 맞음'. 따라잡기는 `notesWithStalePages()` |
| LIBRARY-M5 | 검토 S-6 승격, C21-26 | L2-21을 통합 몫(3단계 SYNC 병합 뒤)으로, 완료 조건 = 컨테이너에서 `firebase emulators:exec … "dart run tool/ws.dart test --run-skipped -t emulator"`(잠금 넘김) + CI 반복, 경우 목록에 SYNC E1~E9 값(`\frac{2}{5}`·`\sqrt{67}`·`'fake/1'`·`gemini` → `UNAVAILABLE`), 사용자 만들기 REST 규약, '[추측]' → 확인 |
| LIBRARY-M6 | 검토 S-7 승격, C21-31 | `ink_recognition/test/integration/shape_assist_flow_test.dart`(INK `createTestPageController(shapeFitter: GeometricShapeFitter())` + 합성 사각형·원 + 500 ms 멈춤 → `shapePreview` → `end()` → `addShape`·`kind`), 8.3 L2-I3 문구 |
| LIBRARY-M7 | 검토 S-11 승격 | `RequestAbortedException` → `RecognizerCancelled`를 `ClientException`보다 먼저, 시험 '실제 `AbortableRequest` 취소 → 오프라인 아님' |
| LIBRARY-M8 | CD2-15, CP-L6, 검토 S-12 | `recog.copyText`의 바로 복사(수식·텍스트 상자)는 첫 `await` 전에 `Clipboard.setData`, 손글씨 복사는 창 안 단추. `containerOf`·`ScaffoldMessenger`는 첫 `await` 전에. B-11로 확인하고 실패하면 웹은 창 경유로 바꾼다 |
| LIBRARY-M9 | C21-15·30 | CP-L1~L10 반영(CP-L4 + `SyntheticShapes.rectanglePath` — INFRA V5용), C-2 어댑터 채널 가짜 예외, `ensureModel` 주석(Q2), `SyntheticHandwriting` 'words' 삭제, `RecognitionSettingsSection` 내부 상태 위젯(S-14) |
| LIBRARY-M10 | INK X-9, C21-26 | 5.8 INK 행 정정(R2-B3 `MathPreview` 실제 동작 — 패드 미리보기 시험을 기반 단계부터), Chrome 시험 `useInkTestFonts` |
| LIBRARY-M11 | SYNC X-6 | 수식 고정 자료 내보내기(SYNC 6.9.1 형식 `{strokes: {x, y, t}, expected}`)를 수식 패드의 P-C 개발자 동작으로. 도형 표본 판정·회귀 시험은 LIBRARY, 모으기는 EDITOR(Q7) |

권장: 검토 S-5(`note.isDeleted`도 숨김), S-8(L2-10·L2-17 나누기), S-9(셀룰러 [지금 받기]), S-10(A-4 영어 모델 — 계약 7.8에 반영함), S-13(디바운스 상한·결과 유지), S-14 나머지.

질문 답: Q1 별도 키 없음(CP-L9) · Q2 그렇게 한다 · Q3 그 기준 · Q4 SYNC 규약(CP-S4)과 같게 · Q5 둘 다(G-3 범위 안) · Q6 없음 · Q7 그렇게 나눈다 · Q8 `notesWithStalePages()`를 이번에 추가(CORE-M7) · Q9·Q10 기본값. 검토 질문 1 CORE `update` + 변경 구독 둘 다 · 2 다른 기기·엔진 결과도 신선 · 3 먼저 동기 시작으로, B-11 실패 시 창 경유 · 4 생성기를 좁힌 뒤에도 미달일 때만 문턱 조정.

### 3.6 PDF — `06-pdf.md` · 판정: 수정 후 재검토

| # | 근거 | 할 일 |
|---|---|---|
| PDF-M1 | 검토 M-1, CD2-20 | 가짜 플랫폼 세 개는 `extends …Platform`만(믹스인 없음), `plugin_platform_interface` 직접 의존 삭제, CP-PDF-9 6개 |
| PDF-M2 | 검토 M-2 | 해석기 내부 포트 `PdfMathRasterizer`·`PdfTextRasterizer`(기본 INK, 시험은 단색 RGBA), T24를 'INK 값 → PDF 중간 표현(층별 목록)'과 '중간 표현 → `PdfPagePlan` 순수 함수'로 나눠 순수 함수는 VM에서 손 표현으로, INK 값 변환만 `integration`. INK `InkVectorFixtures` 사용. 5.2 '`rasterize`는 R2-B3부터 실제' 문구 정정 |
| PDF-M3 | 검토 M-3, CD2-10 | 래스터·디코드 모두 4 Mpx 상한(`PdfTuning` 한 곳): 텍스트·수식은 dpi를 frame에 맞춰 낮춤, 엔진 디코드는 `targetWidth/targetHeight`로 긴 변 2048. T25·T26에 '쪽 크기 텍스트 상자', '6000×4000 PNG', '큰 수식 frame' 표본 + 16 MiB 계측 훅 |
| PDF-M4 | 검토 M-4 | 색인기 게이트에 `!status.rebuilding`, 재구축이 켜지면 진행 중 작업 멈춤·큐 비움, 끝나면 `sourceRevs`로 다시 판정, 시작 때 재구축 중이면 기다림. T27 '에셋 중간 재구축 → 끝난 뒤 모든 쪽 존재' |
| PDF-M5 | 검토 M-5, CD2-13 | `pendingDrafts` 최근 갱신 제외(max(10 s, 5 × `webDraftChunkMs`)), 일시정지 중 빈 조각 `append`(keep-alive), 가능하면 Web Locks, `append` `StateError` → 녹음 멈춤 + '다른 창에서 이 녹음을 정리했어요'. `recorder_service_test` '같은 저장소 서비스 둘' |
| PDF-M6 | 검토 M-6 | `webm_duration.dart`가 마지막 `Cluster` `Timecode` + 마지막 `SimpleBlock` 상대 타임코드 + 프레임 길이(`TimecodeScale`)로 계산해 패치, 실패 때만 시계 값 + 'duration from clock'. 복구(잘린 조각)도 같은 계산. V8 = 타임코드 길이 vs 시계 |
| PDF-M7 | 검토 M-7, CD2-13 | 정지·복구 버퍼: 빈 `unsaved`면 이어 붙이지 않음, 머리만 새로 만들어 `Blob([새 머리, 원본 나머지])`, 단계마다 참조 버림, 큰 녹음(≥ 32 MiB)은 정지 직후 같은 `Blob`을 넘김. 복구 시도 횟수 `media.recoverAttempts`(시작 전 기록, 2회 → 자동 복구 제외·알림), 영구 실패 정리. 6.17에 3시간 행. ①②④ P-A, 86 MB 계측 시험(③⑤)은 P-B |
| PDF-M8 | 검토 M-8, CD2-14 | 패널 자동 열기는 유지(EDITOR가 초점 시점을 바꿈). 6.13.3 'EDITOR 탭 재생 조건' 문장을 v2.1 R-5로, `recording_panel_test`에 '정지 직후 흐림 없음'(EDITOR와 같은 시나리오) |
| PDF-M9 | C21-16, CD2-17 | CP-PDF-1 기각 반영: `PdfSearchIndexer(store)` 원문 그대로, 풀·게이트는 `src/` 구성 함수·provider로 주입, `PdfIndexerGate` 내보내지 않음. T20 '최종 시그니처' 정정 |
| PDF-M10 | C21-16·14, 검토 S-10 승격 | `importImageForNote`: 선택기·클립보드를 첫 `await` 전에, `containerOf`·`ScaffoldMessenger`·`Navigator`도 첫 `await` 전에 잡고 `context.mounted` 확인, 준비 중 시트는 선택 뒤(`enableDrag: false`). 스위치 밖(D17) |
| PDF-M11 | C21-30, 검토 S-11 승격 | `testing.dart`: `installFakeMediaPlatforms`는 VM 전용(`assert`) — 임시 디렉터리 훅은 조건부 파일, Chrome·앱 스모크는 CORE 가짜 포트. 4.3.2 끝 문단 정리 |
| PDF-M12 | C21-08·05 | V8·V16·V11 Chrome을 CORE `testing_web.dart`의 실제 웹 저장소로(V16에 '두 번째 녹음기는 녹음 중 초안을 내지 않음'), Chrome 시험 `useInkTestFonts`(V11 한글 추출) |
| PDF-M13 | C21-09·23·25 | 사각형은 계속 글자마다(`PageRect.zero` = 위치 모름), `pdfPageAspect`, `sourceRev` 꼬리. Info.plist 문구는 INFRA 것으로 부록 B 정정. 웹 예산 6.17·6.22를 v2.1(미리보기 24 MB, 내보내기 임시 16 MB) |
| PDF-M14 | CD2-01 | 1차 통합 반영(S-13): `integration` 4개(`real_wiring_test` 포함)·V11은 `real_wiring_test` 구성을 넓힘·시험 수(VM 580·Chrome 54)를 통합 뒤 값으로 |

권장: 검토 S-2(조각 보내기 시점), S-3(JPEG 고정 상수 표본), S-4(작업 분해 — 순수 함수 앞으로), S-5(`unsaved` 재시도·8 MiB 상한·'파일로 내려받기' — 승인됨), S-6(`mute`/`unmute` 순서), S-7(웹 `preload: false`, 길이는 `durationMs`), S-8(색인기 웹 문서 임대), S-9(CMYK JPEG 느린 길), S-12(오프라인 글꼴 실패 시 멈춤), S-14.

질문 답: Q1 그렇게 한다 · Q2 CORE `testing_web.dart`로 공개(CORE-M9) · Q3 CORE 저장 형식은 CORE 내부(줄인 정밀도·SQLite 밖), `PageRect.zero`는 건너뜀 · Q4 제목 비교 · Q5 그렇게 한다 · Q6·Q7·Q9·Q10·Q11·Q12 기본값 · Q8 받아들임(색인 크기 목표를 넘으면 범위 축소 — CD2-11). 검토 Q-1 범위 밖 + 최소 보호 · Q-2 된다(D19) · Q-3 EDITOR 쪽 · Q-4 3시간까지 지원 범위(계측은 P-B).

### 3.7 SYNC — `07-sync.md` · 판정: 수정 후 재검토

| # | 근거 | 할 일 |
|---|---|---|
| SYNC-M1 | 검토 M-1, CD2-21 | 다시 적용 `_apply(remember: false)`(LRU 안 넣음), `HeldRecords.add` 청크 단위 전부/전무(이미 저장된 같은 청크 기록도 뺌). 시험: 상한이 청크 중간 → 전부 표시, 저장분 + 표시분 같은 청크 → 갱신 뒤 모두 적용, 다시 적용 직후 겹침 재수신 멱등, S27 (c) 모양 |
| SYNC-M2 | 검토 M-2, C21-27 | `npm test` = `node --test 'lib/test/**/*.test.js' 'lib/tool/test/**/*.test.js'`, 에뮬레이터 글롭 `'lib/test-emulator/**/*.emulator.test.js'`, RQ-4 문장 정정, B7b 완료 조건에 `# tests > 0` |
| SYNC-M3 | 검토 M-3, CD2-12 | `onScopesCommitted`에 넘기는 범위에서 손글씨만 실린 청크 제외(1차 T11 결정 ① 변경 — 총괄 승인), 6.2.5 문구, 시험(`purge_guard_test` 두 경우, S28 가상 시간 10분 안, `upload_pipeline_test`) |
| SYNC-M4 | 검토 M-4 | `core_json_keys_test` v2 단언(합집합·`kPageObjectTypeKeys`·`unknown` 제외)을 B7a로, 6.4 표·8.1 일치, `field_units_test` 77행도 종류별 비교 |
| SYNC-M5 | 검토 S-1·S-3 승격, CD2-21 | 다시 적용 중 K1 기록은 `sync.heldRecords`에 해제 시각과 함께 남김(원래 청크에 기대지 않음 — D-S4 `sync.held` 규칙 삭제). 메타 키 나눔(키당 < 256 KiB, 총 2 MiB), 깨진 값 → 모든 종류 되감기 표시, 6.12에 '기록 10 KB × n' 보관 개수 |
| SYNC-M6 | 검토 S-4·S-5 승격 | `checkConverged(…, {Set<EntityKind>? kinds})`를 4.3·CP-S8·`api_surface_test`에, 하네스 `knownKinds`·`restart`는 한 작업으로. 6.7.2에 파일·경우별 CORE 선행 작업 표(T27·T29·T30·T31·T32·T33) |
| SYNC-M7 | 검토 S-6·S-8 승격, C21-17 | `HandlerDeps.engineSignal(ms)` 주입(시험은 `AbortController`), `engineVersion` = 응답의 `model`(대체 여부는 로그). 어댑터는 생성자 주입, `params.ts`는 등록부만 읽음(S-7) |
| SYNC-M8 | 검토 S-9 승격, C21-27 | 미니 라운드 사실 정정: 운영 `OWNER_UIDS`는 커밋하는 `functions/.env.<projectId>`(Q9 기본값 변경), 배포 뒤 확인 = `MATH_ENGINE=none`에서 소유자 503·남 계정 403, 비밀값은 첫 배포 전(자리 값 가능) |
| SYNC-M9 | C21-12·17·29·30 | CP-S1~S9 v2.1 반영(CP-S2 보강, CP-S3 ⑥ 가짜 엔진 규칙은 계약 7.6), B7a 바탕 = CORE B2-α 해시(디코드 시험은 B2-β JSON 뒤), B7b는 R2-B1 바로 뒤 따로, 4.2 `handwriting` 범위 근거('페이지와 같음' — S-12) |
| SYNC-M10 | C21-26, 검토 X-2 | `emulator_suite.sh`는 `dart run tool/ws.dart with-heavy-lock -- …`로 감싸고 안쪽 Dart 시험은 잠금 넘김 환경을 받음. `.gitignore` RQ-2 확인(INFRA-M11) |

권장: 검토 S-2(다시 적용 지표·재시도 위치), S-10(S2-4·S2-7·S2-10 나누기), S-11(실기기 대체 경로 — 웹 ↔ 웹, SC-4만 안드로이드), S-12 나머지.

질문 답: Q1 그렇게 한다(모델은 매개변수 — 엔진·모델 결정은 U6 뒤) · Q2 200 · Q3 구현하지 않음 · Q4 LIBRARY P-C(LIBRARY-M11) · Q5 빈 열 · Q6 수동 · Q7 받아들임(LIBRARY 확정 줄 규칙 + CORE `update`로 같은 기기 안 경합은 막힘, 기기 간 LWW는 다음 라운드) · Q8 그대로, R2-B1·B7b 때 재확인 · Q9 커밋하는 `.env.<projectId>`(SYNC-M8). 검토 Q-1 둘 다 · Q-2 동의 · Q-3 U2 · Q-4 커밋 · Q-5 된다(R2-B7b).

---

## 4. 사용자 질문

답이 없으면 기본값으로 진행한다. 위에서부터 중요한 순서다. 나머지 U-xx(00-overview 9장)는 기본값 그대로 진행한다.

| # | 질문 | 선택지 | 기본값 | 기본값으로 진행할 때의 영향 |
|---|---|---|---|---|
| U24 | Firebase 프로젝트를 **Spark(무료)·Hosting만**으로 지금 만들 수 있나요? (1차 안내서 01·02, 약 15분, 결제 계정 없음 — 동기화·로그인은 켜지 않아요) | (a) 지금 만든다(권장) (b) 실연결 때 함께 만든다 (c) 다른 호스팅(저장소를 공개하고 GitHub Pages) | 답이 오기 전까지는 Hosting 없이 진행((b)와 같음). 총괄 권장은 (a) | iPad 웹 확인(7.8 B)·1차 V7·EDITOR 한글 입력 시제품의 첫 주 확인이 Hosting이 생길 때까지 밀린다. 2차 완료 판정(컨테이너 시험)은 영향 없고, 컨테이너 Playwright 스모크로 일부를 대신한다. 한글 IME·Safari 선택기·메모리 문제가 통합 뒤에야 드러날 수 있다 |
| U25 | 1차 앱으로 iPad(또는 다른 기기)에 만든 실제 노트가 있나요? 있다면 어느 주소인가요? | 없음 / live 주소에 있음 / 미리보기 주소에 있음 | 없음(Hosting이 없어 배포된 적이 없음) | V7은 고정 자료로만 확인한다. Hosting 뒤 live에서 1차를 쓰기 시작했다면 2차 live 배포 전에 백업 내보내기를 안내한다(B-1). 기본값이 틀리면 첫 실제 이주가 예상보다 일찍 일어나지만 v1 사본(7.2.7)이 안전망이다 |
| U2 | S펜이 되는 안드로이드 태블릿이 있나요? 모델은? | 있음(모델) / 없음 | 없음 | A 체크리스트(S펜 버튼·백그라운드 녹음·ML Kit 손글씨 인식)를 '코드만, 확인은 이후'로 둔다. 손글씨 인식(M7-1)의 첫 실기기 판정이 TestFlight 뒤로 밀리고, 안드로이드 에뮬레이터 CI 잡(P-C)을 넣어 ML Kit 흐름만 자동으로 본다 |
| U1 | Apple Pencil 종류(Pro / USB-C / 2세대)와 iPad 정확한 모델명은? | Pro / USB-C / 2세대 | Pro 기능까지 만들고, 스퀴즈·롤 설정은 첫 이벤트를 받은 뒤에만 보임 | 어느 쪽이든 재작업은 없다. USB-C 펜슬이면 필압·더블탭·스퀴즈·롤이 없어 M5-9 확인 항목(C-1)이 대부분 해당 없음이 된다 |
| U20 | 안드로이드 고정 서명 키를 어떻게 받을까요? (이 세션은 GitHub 시크릿을 직접 넣을 수 없어요) | ① Claude가 만들어 **파일로** 건넴 → 사용자가 GitHub 설정에 등록 ② 사용자가 수동 워크플로로 만들어 아티팩트로 받음(보관 기간 동안 GitHub에 남음) ③ 사용자가 Claude에 GitHub 시크릿 권한을 주어 Claude가 등록 | ① | 등록 전 APK는 debug 서명이라 판마다 '지우고 설치'가 필요하고 그때 기기의 노트가 사라진다 — 안드로이드에서 실제 노트를 쓰기 전에 등록해야 한다. 등록 뒤에는 덮어 설치로 노트가 남는다(A-1) |
| U19 | macOS 러너로 iOS 컴파일 확인을 2차에 1회 해도 되나요? (무료 시간 약 150분 사용, 저장소는 비공개 유지) | 1회(통합 뒤) / 2회(B8b 뒤 + 통합 뒤) / 안 함 | 1회(통합 뒤) — 승인되면 2차 완료 조건(V14) | 안 함이면 Swift(`pencil_bridge`)·ML Kit pod 컴파일이 TestFlight 첫 빌드 때 처음 확인된다(실패하면 iOS 빌드 전체가 막힘) |
| U26 | 녹음된 글씨를 탭해 그 시점부터 듣는 규칙: 손가락 탭은 녹음 패널이 열려 있거나 재생 중일 때, 펜 점 찍기는 재생(·일시정지) 중일 때만 이동하고 그 밖에는 점이 남아요. 녹음 중에는 가로채지 않아요. 괜찮나요? | 그대로 / 펜 탭은 항상 점(손가락만 재생) / 패널이 열려 있으면 펜 점도 재생 | 그대로 | 필기 손실을 막는 쪽으로 좁혔다. 재생 중이 아닐 때 펜으로 찍은 마침표는 늘 남는다 |
| U27 | 안드로이드 기기 자동 백업(Google 드라이브)에 노트를 넣지 않아요. 괜찮나요? | 넣지 않음 / 넣음(25 MB까지, 큰 노트는 빠짐) | 넣지 않음 | 기기를 바꾸거나 앱을 지웠다 깔면 노트가 돌아오지 않는다 — 보존은 '백업 내보내기'(지금)와 동기화(실연결 뒤)로 한다. 다른 기기로 복원할 때 기기 식별이 복제되어 동기화가 꼬이는 문제를 피한다 |
| U7 | 텍스트 상자 글꼴은 Noto Sans KR 부분 집합(한글 2,350자 + 라틴, 보통·굵게, 처음 그릴 때 받음)이에요. 부분 집합 밖 글자(드문 한자·옛한글 등)가 든 상자는 PDF에서 그림으로 들어가 검색되지 않아요. 괜찮나요? | 그대로 / 상용 한글 전체(굵기당 약 2 MB [추측], 지연 적재) / 다른 글꼴(예: Pretendard) | 그대로 | 드문 글자가 든 텍스트 상자는 화면에서 대체 글꼴로, PDF에서 상자 전체가 래스터로 나간다 |
| U6 | 수식 인식 엔진 비교용 유료 계정(Mathpix 설정비 약 $19.99 [추측], Anthropic API 등)과 수식 영역의 획·이미지를 외부로 보내는 데 동의하나요? | 지금 / 계정이 생기면 / 안 함 | 계정이 생기면 | 그때까지 수식은 LaTeX 직접 입력 + 미리보기만 된다. 서버 함수·클라이언트는 가짜 엔진으로 시험까지 끝난다 |

---

## 5. 다음 단계

1. 각 영역이 3장 표와 계약 v2.1을 반영해 계획서를 고친다(바탕 = 1차 통합 HEAD, 13절에 반영 위치). 서로 걸린 항목(명령 모양, 객체 변형 규칙, INK getter·도우미, 손글씨 `update`, 탭 재생 상태, 자리 콜백 동기 시작, 시험 잠금)은 계약 문장을 그대로 옮긴다.
2. 총괄 2차 검토(승인 검토) — 계약 반영과 M 항목만 본다.
3. 승인 뒤: 1차 통합을 기본 브랜치에 병합 → V7 고정 자료 생성(CORE) → 기반 단계 R2-B1 → R2-B7b → R2-B2(α 해시 알림) 묶음 → R2-B3 → R2-B4·B5·B6 → 동시 개발 시작(INFRA는 B8a·B8b·J0부터).
4. 사용자: U24(Hosting)를 먼저 답해 주면 iPad 웹 확인을 2차 동시 개발 중에 시작할 수 있다. U2·U20은 안드로이드 실사용 전에 필요하다.

---

## 최종 승인

> 날짜: 2026-11-05 · 총괄 관리자 · 기준: 통합 계약 **v2.2**([00-overview.md](00-overview.md) 7장 — 7.9 'v2.2' C22-01~09) · 00-overview 상태: **확정 — 개발 시작 가능**
> 앞선 절차: 1차 검토(이 문서 1~5장) → 영역별 수정 1~3회차와 승인 확인(영역마다 대리 재검토 — 각 계획서 13장) → 이 절(남은 항목 판단·미판정 CP 판정·계약 인용 대조·v2.2 확정)

### 승인 요약

| 영역 | 계획서 | 승인 확인 결과 | 승인한 판본 | 개발 중 반영 |
|---|---|---|---|---|
| INFRA | [01-infra.md](01-infra.md) | 승인(남은 항목 0) | 수정 2회차 + 총괄 직접 수정(13.7 — V5b 분리, CP17·Q14~Q16 답) | INFRA-F1~F4 |
| CORE | [02-core.md](02-core.md) | 승인(남은 항목 0) | 수정 1회차(+ 12장 판정 기입, v2.2 문장 3곳 인용 맞춤) | CORE-F1~F4 |
| INK | [03-ink.md](03-ink.md) | 승인(남은 항목 0) | 수정 1회차 | INK-F1~F3 |
| EDITOR | [04-editor.md](04-editor.md) | **미승인 2건 → 총괄 직접 수정으로 승인** | 수정 3회차 + 총괄 직접 수정(13.4 — E2-21 순서, E2-23 단계별 대응, Q15·Q16 답) | EDITOR-F1~F4 |
| LIBRARY | [05-library.md](05-library.md) | 승인(남은 항목 0) | 수정 2회차 | LIBRARY-F1~F3 |
| PDF | [06-pdf.md](06-pdf.md) | 승인(남은 항목 0) | 수정 3회차(+ 12.1 판정 기입, v2.2 문장 2곳 인용 맞춤) | PDF-F1~F3 |
| SYNC | [07-sync.md](07-sync.md) | 승인(남은 항목 0) | 수정 2회차 | SYNC-F1~F3 |

- 범위: PLAN.md M5 편집 강화(M5-1~12), M6 녹음(M6-1~5), M7 인식(M7-1~6), 1차 7.8에서 미룬 것 중 M5와 맞닿은 것(올가미 회전·색 변경 UI, 제스처 동작 변경, 이미지 페이지, 라이브러리 전역 PDF 텍스트 색인), SYNC 사전 정비(모르는 종류 보류)와 서버 함수 골격·에뮬레이터 시험(00-overview 3장). 우선순위 등급은 3.4(P-A 완료 조건 / P-B 미뤄도 완료 / P-C 여유).
- **동기화 실연결(M4 앱 연결·로그인 화면)은 이번 라운드에 넣지 않는다**(D6·D16 — 2차 통합 뒤 사용자가 Firebase 프로젝트를 만든 다음 INFRA + SYNC 미니 라운드). 사용자가 2차 도중 Spark(무료) 프로젝트를 만들면 **Hosting 시크릿만** 연결해 iPad 웹 확인 경로로 쓰고 2차 범위는 바꾸지 않는다(3.7, U24).
- 계약: v2.0 초안 → v2.1(35항목, 1차 검토) → **v2.2(9항목, 최종 승인)**. v2.2의 시그니처 변경은 추가 하나(C22-01 `dev_tools.dart` v1 사본 API — CORE·INFRA 계획서가 이미 같은 모양을 쓴다)이고 나머지는 규칙 문구다. 모두 계획서의 CP·질문·설계에 이미 적힌 동작을 계약으로 옮긴 것이라 어느 영역도 재승인이 필요 없다. 계획서와 계약이 다르면 **계약이 우선**이다.
- 계획서 01~07 머리 상태 줄을 **'승인'**으로 고쳤다(이전 상태 문장은 그 뒤에 이력으로 남김). 계획서 안의 '판정 대기'·'(답 대기)' 표기는 이 절과 각 계획서 12장의 '판정(총괄 기입)'·'총괄 답'으로 읽는다.

### EDITOR 남은 항목 판단 (총괄 직접 수정 — 04-editor 13.4)

두 항목 모두 **완료 조건을 글자 그대로 채울 수 없게 하는 모순**이라 '개발 중 주의 사항'으로 넘기지 않고 계획서를 직접 고쳤다.

| # | 남은 항목 | 판단 | 처리 |
|---|---|---|---|
| 1 | E2-21 `objects_smoke_test` 순서가 '… 붙여넣기 → 닫고 다시 열기 → 유지 → 되돌리기 사슬로 처음 상태'라 1차 v1.5 C15-04(다시 연 세션은 되돌리기 없음 — `noteSessionProvider` autoDispose)·계약 V5 문장·01-infra 9.1 V5 5단계와 어긋남 | **중대** — 총괄이 확인함: 1차 `/home/user/noteapp/packages/feature_editor/test/integration/real_core_ink_smoke_test.dart` 276행이 다시 연 세션의 `history.undoDepth == 0`을 단언한다. 이 순서로는 E2-21이 통과할 수 없어 10 #5도 채울 수 없다 | 순서를 '… 붙여넣기 → 되돌리기 사슬 끝까지(처음 상태) → 다시 실행으로 원래 상태 → 닫고 다시 열기 → 모두 유지·`content.objects` 종류·개수·다시 연 세션 `undoDepth == 0`(C15-04)'로 고쳤다. E2-21b는 이미 C15-04 순서라 그대로 |
| 2 | E2-23·10 #5·12.2 Q16의 '뒤 단계의 EDITOR 경로는 같은 순서를 P-A 기능만으로 거치는 E2-21로 판정'이 부정확(항목 1의 순서 차이, E2-21은 V5 6단계 `editor.panelSlot`·8단계 `editor.ext.recog.*`·9단계 `initialFocusRectPt`·`editor.focusFlash`를 거치지 않음) | **중대** — 판정 근거가 틀린 문장이다. 원인은 V5 본 흐름 안에 P-B 단계가 들어 있다는 계약 쪽 구조(Q16)라 계약에서 함께 풀었다 | Q16 총괄 답 = 계약 v2.2 C22-07: 7.7.2 'P-B에 기대는 기준' 규칙·표, V5 본 흐름에서 자동 도형 단계를 떼어 **V5b**(P-B)로. 그래서 '뒤 단계가 돌지 않을 때의 대체 판정'이 필요 없어져 그 문장을 지웠다. 대신 E2-23에 V5·V6 단계가 실패할 때 원인을 좁히는 EDITOR 시험을 **단계별로** 적었다(2~5단계 `objects_smoke_test`, 6~7단계 `recording_link_smoke_test` + E2-16 `recording_panel_slot_test`, 8단계 E2-07c `selection_extensions_test`·E2-12 `insert_menu_test`, 9단계 E2-19 `initial_focus_test`, V6만 실패 `web/editor_browser_smoke_v2_test`, V5b E2-21b·E2-15). 진행 기록 E2-23 줄에 실패 단계·대응 시험·원인을 적는다. INFRA 9.1 V5 2단계·H3·H5·10 #3도 같은 답으로 고쳤다(01-infra 13.7) |

### 미판정 제안·질문의 판정 (계약 v2.2)

수정 회차에서 새로 올라와 '판정 대기'로 남았던 것을 모두 판정했다. 기각·보류는 없다.

| 제안·질문 | 판정 | 계약 | 근거 |
|---|---|---|---|
| CORE CP-17 `dev_tools.dart` v1 사본 API 4개 | 승인 | C22-01(7.2.7 블록, 7.1 표, 7.0.1 C2-40) | INFRA 개발자 메뉴가 부를 표면이 계약에 없었다. CORE 6.12.4 블록과 INFRA 5.1 사본의 본문이 계약 블록과 글자 그대로 같음을 스크립트로 확인했다(머리 주석 한 줄만 계약 표기) |
| CORE CP-16 v1 사본 방법 구체화 | 승인 | C22-02(7.2.7) | 웹 VFS 사본은 지울 길이 없고 열 때마다 메모리로 읽힌다(02-core 6.12.4 [확인]). 계약이 이미 허용한 '같은 저장소 안의 다른 사본 방법' 갈래 |
| INFRA CP17 `native-reqs` 비교 대상 | 승인 | C22-03(7.4.1) | 총괄이 1차 통합 HEAD `app/.flutter-plugins-dependencies`에서 다시 확인: `plugins.<플랫폼>`에는 `file_picker`·`path_provider`·`url_launcher`가 없고 `dependencyGraph`에는 있다 |
| PDF CP-PDF-12 R-3 블록 길이·V8 판정식 | 승인 | C22-04(7.2.4 R-3, 7.7.2 V8) | 헤드리스 Chrome 6회 실측(06-pdf 6.1 E9~E11)에서 옛 식은 2/6 실패 — 마지막 패킷(60 ms)이 정지 뒤를 무음으로 채운다. 시계가 파일 타임라인과 맞는지 본다는 뜻은 같다 |
| PDF CP-PDF-13 M-4 길이 보정 문구 | 승인 | C22-05(7.3.2 M-4) | `AssetStore.put`(1차 표면)은 연속 `Uint8List` 한 벌을 받는다. `Blob` 합치기는 최고값이 같고 복사가 한 번 더 는다. 보장 문장은 그대로 |
| PDF CP-PDF-14 내보내기 임시 16 MB의 범위 | 승인 | C22-06(7.4.5) | 네이티브 isolate 전달 사본과 M-3 밖 큰 입력의 순간 초과를 숫자 밖으로 명시. 웹 296 MB 합계에 늘 있는 몫은 생기지 않는다. 대안(네이티브 2 Mpx)은 네이티브 PDF 화질만 낮춘다 |
| EDITOR Q16 V5 자동 도형 단계의 P-B 묶임 | V5 문장을 고친다 | C22-07(7.7.1·7.7.2) | 3.4 'P-B는 미뤄도 2차 완료'와 7.7.2 '전부 통과'가 V5·V9·V13·V15·7.7.1 5단계에서 부딪혔다. 시험은 실행 중에 병합 여부를 알 수 없으므로 P-B 단계는 따로 뗀 시험으로 둔다(EDITOR E2-21b와 같은 판단) |
| EDITOR Q15 내부 기기 키 2개 | 7.4.4 '키 확정'에 올리지 않음 | — | 1차 `editor.toolSelection`·`editor.viewport`와 같은 내부 키 |
| CORE Q11·Q12 | CP-16·17 지금 판정(위), 수명 = 정상 열기 5번 이상 + 7일 | C22-02 | — |
| INFRA Q14 | B8a·B8b·J0를 끝날 때마다 총괄이 체크포인트로 `main`에 병합 | — | 다른 영역은 앱 셸을 import하지 않는다. 병합 전 기반 단계 검사 묶음 통과 |
| INFRA Q15 | J0 실측에서 월 Actions가 2,000분을 넘으면 총괄이 '영역 브랜치 푸시는 체크포인트·통합 때만'을 모든 영역에 공지 | — | 7.4.9와 같은 뜻 |
| INFRA Q16 | CP-17 승인 → J14b는 지금 모양 그대로, '거절되면' 갈래는 쓰지 않음 | C22-01 | — |
| 바탕 HEAD | `18c5ae5` → **`b6c9d0a`** | C22-08(2.5) | `git log 18c5ae5..b6c9d0a` 8커밋: INK 퇴화 판정 문구·시험(`446518e` — 동작·API 같음), EDITOR·INK·INFRA 문서, INFRA CI 기본 브랜치 비교(`bb1bc60`). INFRA·INK 밖 소유 경로의 코드 변화 없음 |

### 계약 인용 표본 대조 (2026-11-05, 스크립트 — `/tmp/claude-0/plan57-scratch/final/cmp_blocks.py`·`cmp_types.py`)

- **코드 블록**: 계획서가 '계약 원문'으로 표시한 Dart 블록은 모두 v2.2 계약의 부분 문자열(글자 그대로)이다 — INFRA 13·CORE 14·INK 17·EDITOR 15·LIBRARY 9·PDF 14·SYNC 6블록(나머지 블록은 영역 '확정 세부'·내부 코드). '발췌' 블록(LIBRARY 5.2의 객체 발췌 61줄 등)은 줄 단위로 모두 계약에 있다. 표시가 계약처럼 보이지만 일치하지 않는 블록 4개는 모두 영역 상세다(INK `testing.dart` 전체 목록 — 계약 7.6은 이름만 적고 03-ink 4.12에 맡김, LIBRARY provider 본문, PDF 내부 시계).
- **공유 타입**: 계약 7.2.2~7.2.13·7.6.2 블록의 선언 237개(클래스·enum·provider·함수)가 **모두** 한 계획서 이상에 인용되어 있다(절마다 인용 계획서: 7.2.2 CORE·INK·EDITOR·LIBRARY·PDF·SYNC, 7.2.4 INFRA·CORE·EDITOR·LIBRARY·PDF·SYNC, 7.2.9 INFRA·INK·EDITOR·LIBRARY·PDF, 7.2.10 INFRA·EDITOR·LIBRARY·PDF, 7.2.11 전 영역 중 6, 7.2.13 INFRA, 7.6.2 7개 전부). 선언 줄이 다른 곳은 계약의 `/* … */` 자리를 계획서가 본문으로 펼친 경우(CORE `NoteStoreConfig`·`AssetStorageUsage`, LIBRARY `ShapeFitTuning`·`HandwritingIndexerStatus`, INFRA `PencilTap` 등)와 영역 시험 도구(SYNC 시험 하네스의 `renameRecording`)뿐이고 이름·형은 같다.
- **표 행**: 7.2.7 DB 스키마 표 14행(CORE 14·SYNC 6 사본), 7.2.8 동기화 매핑 6행(CORE·SYNC), 7.3.2 동작 보장(CORE 12·LIBRARY 5·PDF 5·SYNC 3)이 글자 그대로다.
- **v2.2가 바꾼 문장의 사본**: R-3 행(02-core·04-editor·06-pdf), M-4 행(02-core·06-pdf), 7.2.7 v1 사본 문단(02-core)은 이번에 v2.2 문장으로 맞췄다. 남은 인용은 C22-09대로 개발 착수 때 맞춘다(아래 '개발 중 주의할 점' 11).

### 개발 중 주의할 점

1. **진행 순서(7.6.2)**: 아래 '기반 단계 순서'대로 하고 매 단계 `ws check`·`flutter analyze --fatal-infos`·`ws test`(VM·Chrome)·`dart test tool/test`를 통과해야 다음으로 간다. 예외 하나 — R2-B2(CORE)·R2-B7a(SYNC)·R2-B2i(INFRA)는 **한 묶음**으로 총괄이 함께 병합한 뒤 검사한다(`EntityKind` 값·`NoteStore` getter 추가가 SYNC switch와 INFRA 가짜를 깨므로). 동시 개발 시작 조건은 R2-B1~R2-B6이 `main`에 있음이고 R2-B8a·B8b는 조건이 아니다(D24). 각 영역은 B2-α 해시(CORE)·T24 해시(INK) 뒤 자기 작업 트리에서 코드를 써도 되지만 `main` 커밋은 순서를 지킨다. 이정표 커밋(CORE B2-α·B2-β JSON 골든·T24·T26~T33, INK T24·T26a·T33·T34·T36·T42)은 진행 기록 양식대로 알린다.
2. **계약 고정과 변경(7.4.9)**: 기반 단계는 계약 블록의 이름·주석을 글자 그대로 옮긴다(`api_surface_test`). 동시 개발 중 계약 변경은 결과 보고 '변경 요청' → 총괄 승인 → 7장 `v2.x`이고, 그동안은 **'추가만'**(기존 시그니처·의미를 바꾸지 않음)이다. 승인 전에는 계약 이름·의미 그대로 쓴다. 다른 영역 소유 경로와 공용 파일은 직접 고치지 않는다(2.2 — 루트 `pubspec.yaml`·`pubspec.lock`·`workspace_rules.yaml`은 INFRA).
3. **P-B에 기대는 기준(C22-07, 이번 최종 승인의 핵심 결정)**: P-B 작업을 미루면 그 작업에 기대는 시험은 만들지 않거나 기대 목록에서 빼고 통합 진행 기록에 `미룸 — <기준>, 빠진 작업(<id>)`을 적는다 — 2차 통합 완료를 막지 않는다. 대상은 7.7.2 표가 전부다: **V5b**(INK T39·EDITOR E2-15·LIBRARY L2-06), 7.7.1 5단계 **L2-I3**(T39·L2-06), **E2-21b**(T39·E2-15), **V9 도형 판정**(L2-06), **V13**(SYNC S2-10a·S2-10b·S2-11 / LIBRARY L2-16·L2-I6), **V15의 '자동 도형 보정'**(E2-15·L2-06). P-B 단계를 P-A 시험 안에 넣지 않는다(INFRA `app_smoke_v2_test`에 자동 도형 단계 없음 — V5 2단계 기대값 `ShapeObject` 1). 모두 병합됐으면 보통 실패로 다룬다. 각 영역 10장 완료 기준(INFRA #3·#4, LIBRARY #4·#5, EDITOR #5, SYNC P-B 줄)도 이 규칙으로 읽는다. P-B를 미루는 영역은 자기 진행 기록 '2차' 절에 미룬 작업 id를 적는다 — 통합 때 병합 여부를 그 기록으로 가린다.
4. **되돌리기·다시 열기 순서(1차 v1.5 C15-04)**: 다시 연 세션은 되돌리기가 없다(`noteSessionProvider` autoDispose). 모든 통합 스모크(EDITOR E2-21·E2-21b, INFRA V5·V5b, LIBRARY·PDF 통합 시험)는 '변경 → 되돌리기 사슬 → 다시 실행 → 닫기 → 다시 열기 → 유지·`undoDepth == 0`' 순서로 단언한다.
5. **쓰기와 경합(1차 7.2.9~7.2.11 + v2.1)**: CORE는 커밋 실패를 무한 재시도하고 그동안 쓰기 `Future`는 완료되지도 오류로 끝나지도 않는다 — 소비자는 저장 실패를 예외로 기대하지 않고 지연 문구 + 닫기·취소로 처리한다(1차 규칙 그대로). 손글씨 결과의 로컬 쓰기는 색인기·변환 창 모두 `HandwritingRepository.update`만 쓴다(G-4, CD2-12 — `put`으로 확정 줄을 덮지 않음). 새 명령은 1차 모양(`const`·이름 있는 인자·`label`, id 목록은 `List<ElementId>` — CD2-06)이고, 객체 변형은 미리보기·해석기·붙여넣기 모두 `PageObject.transformed(m, {scaleWidth})` 하나다(CD2-07).
6. **`final class`와 시험 이음새**: 색인기·INK 컨트롤러·`StrokeSession`은 `final class`라 상속 가짜가 컴파일되지 않는다. 시험은 계약의 이음새만 쓴다 — INK `createTestPageController(shapeFitter:)`·`FakeInkShapeFitter`·`SyntheticInk`, CORE `createFakeNoteStore`·`openTestNoteStore`·`openWebTestNoteStore`·`FakeAudioRecorder.abandon()`·`FakeAudioPlayback.calls`, recog `SyntheticShapes`·`SyntheticHandwriting`, INFRA 모듈 생성자 주입 인자(`IndexerHandleReader`, V5의 가짜 — CD2-17). 같은 provider를 두 번 override하지 않는다(V5가 출처·횟수를 확인).
7. **잃지 않음(00-review 1장의 열한 가지 경로)**: 그 경로를 막는 v2.1 규칙(웹 초안 고아 정리 순서, 다른 탭 초안 복구 금지, 긴 녹음 복구 한 번, v1 사본(C22-02), 확정 줄 유지, 보류 기록 LRU 밖, 손글씨 업로드가 지운 노트를 되살리지 않음, 탭 재생이 짧은 획을 버리지 않음(R-5), 재구축 중 색인 누락 방지, 정지 직후 흐림 없음, 고정 서명 키)은 일정이 밀려도 **자르지 않는다**. INK M-1·M-3·M-4 규칙(층 4′·SVG 적재 대기·참조 수)도 같다(03-ink 8.2).
8. **웹 예산(7.4.5)**: 웹 메모리 합계 296 MB ≤ 300 MB(INK 래스터 공유 장부 96 MB, PDF 미리보기 24 MB), 한 장의 래스터·디코드 ≤ 4 Mpx, 내보내기 임시 16 MB의 예외는 C22-06의 둘뿐이다. 웹 크기 기준은 1차 실측(gzip 1,366,038 B) + 300 KB로 시작하고 J0 뒤 다시 정한다. 텍스트 글꼴 `NoteSans`는 `FontManifest`에 넣지 않는다(지연 적재). 개발자 표시 '앱 캐시 합계'로 B-13·I-B11을 본다.
9. **시험 실행 규칙(5장, CD2-19)**: 컨테이너는 4 CPU를 여러 에이전트가 함께 쓴다. 무거운 시험(`media`·`emulator`·통합 태그·웹 빌드)은 전역 잠금 `/tmp/noteapp-heavy-tests.lock`(`ws with-heavy-lock -- <명령>`, 안쪽은 `NOTEAPP_HEAVY_LOCK_HELD`로 다시 잡지 않음)으로 하나씩 돌린다. Chrome 시험은 `setUpAll(useInkTestFonts)`로 글꼴 적재에서 멈추지 않게 한다. 실제 시간 대기·네트워크는 시험에서 쓰지 않는다(`fake_async`, 녹음 `stop()`·에셋 저장은 `tester.runAsync` 안). 태그는 문자열 리터럴로, `dart_test.yaml`은 태그를 쓰는 첫 시험보다 먼저(R15).
10. **바탕 코드(C22-08)**: 2차 작업 트리는 1차 통합 HEAD **`b6c9d0a`**가 들어간 `main`에서 만든다(`/home/user/wt2/<id>`, 브랜치 `area2/<id>`). 계획서가 `18c5ae5`로 적은 곳은 이 HEAD로 읽는다 — 코드 차이는 INK `lasso_polygon.dart`·`lasso_options.dart`·`lasso_test.dart`(`446518e`, 동작 같음)와 INFRA `tool/`·CI(`bb1bc60`)뿐이다. 계획서의 1차 작업 트리 기준 줄 번호 인용은 기반 단계 시작 때 고친다(2.5).
11. **계약 인용 맞추기(C22-09)**: 기반 단계 뒤 '가정' 블록을 실제 타입으로 바꿀 때 각 영역은 상태 줄을 '승인 · 계약 v2.2'로 두고 v2.2가 바꾼 문장의 남은 인용을 맞춘다. 남은 곳: 01-infra 5.1 CP-17 블록 머리('판정 대기' — 이제 C22-01)·4.6.7·10 #10의 '거절되면' 갈래, 01-infra 4.1 W2-4 R16 행(`dependencyGraph` — C22-03), 02-core 12.1 CP-16·17 행, 05-library 4.3(668행)·5.9 표(1416행)·9.3 표·부록 표의 'INFRA V5 합성 멈춤'(→ V5b), 06-pdf 6.8.7의 'V8 판정(CP-PDF-12)' 문단·6.1 E10의 V8 '승인 전' 문장(→ C22-04 판정식으로 단언), 03-ink 8.3 I-6의 'V5 합성 멈춤'(→ V5b). 계약 블록 주석 `(V5 '합성 멈춤')`(7.6 `SyntheticShapes` 주석)은 V5b를 가리키는 것으로 읽고 고치지 않는다(세 계획서가 글자 그대로 복사함).
12. **웹 우선(7.4.1·7.4.2)**: `lib/`에서 `dart:io`·`dart:html`을 쓰지 않고 조건부 import(`*_browser.dart`·`*_native.dart`)로 나눈다. 네이티브 전용 플러그인(ML Kit·`flutter_foreground_task`·`path_provider`)은 `*_native.dart`에서만, 웹 구현이 있는 플러그인은 `media_io` 밖으로 내지 않는다(R16). 플랫폼 판정은 `kIsWeb` + `defaultTargetPlatform`만(`Platform` 금지), UI는 서비스 능력(`checkSupport()`·`capabilities`·`supportedImageSources()`)을 묻는다. 웹 안전 수치(64비트 정수·`Int64List` 금지), Material은 `material_ui`만, Riverpod 3.4.3 codegen 없이, ML Kit은 `as mlkit` 접두어.
13. **외부 패키지(7.5)**: 고정 버전 그대로, 게시 14일 규칙(간접 의존 포함). 추가·변경은 결과 보고 '의존성 추가' → 통합 때 INFRA가 lock을 다시 만든다. **`firebase-tools 15.34.2`는 2026-11-11부터 14일 규칙을 통과한다**(7.5 표) — R2-B1은 1차 CI 고정값을 그대로 두므로 새 채택이 아니고, 새로 넣는 곳은 R2-B7b `functions/package.json` devDependency다. R2-B7b 커밋이 2026-11-11 전이 되면 R2-B7b만 11-11 뒤로 미룬다(다른 기반 단계는 `functions/`에 기대지 않음 — SYNC-F2).
14. **Firebase 없는 동안(3.7)**: iPad 웹 확인(7.8 B)·1차 V7·EDITOR IME 첫 주 미리보기는 Hosting(U24)이 생길 때까지 밀린다. 그 대신 통합 9단계에 릴리스 웹 빌드 Playwright 스모크(INFRA H7 — 127.0.0.1 보안 문맥, 1032×1376, `ko-KR`, 가짜 마이크)를 둔다. 서버 함수는 에뮬레이터(`demo-noteapp`)로만 시험하고 앱 빌드에 `MATH_ENDPOINT`를 넣지 않는다(수식은 LaTeX 직접 입력 + 미리보기). 2차 완료 판정은 컨테이너 V1~V16이다.
15. **알려진 한계(결함 아님 — 그대로 둠)**: 자동 도형 보정으로 바뀐 도형은 녹음 연결을 잃는다(EDITOR Q9 — 객체에 녹음 필드 없음). 손글씨 결과는 한 단위 LWW라 기기 간에 확정 줄이 덮일 수 있다(SYNC Q7 — 같은 기기 안 경합은 `update`로 막힘, 실연결 뒤 다시 본다). '복구된 녹음' 배지는 제목 비교라 이름을 바꾸면 사라진다(PDF Q4). 녹음 삭제·고아 에셋의 바이트는 회수하지 않는다(U13, 3.6). 같은 출처를 탭 두 개로 여는 것은 범위 밖이고 다른 탭의 진행 중 초안만 보호한다(D19). 웹 정지 저장이 끝내 실패하면 마지막 수단은 '파일로 내려받기'다(D19). 텍스트 상자에 부분 집합 밖 글자가 있으면 PDF에서 상자 전체가 래스터다(PDF Q9, U7).
16. **기기 확인은 사용자 몫**: 각 계획서 9장 실기기 체크리스트와 7.8 A·B·C는 사용자가 기기에서 확인한다. A(안드로이드 — S펜·백그라운드 녹음·ML Kit)는 기기가 있을 때(U2), B(iPad 웹)는 Hosting 뒤(U24), C(TestFlight)는 Apple 계정 뒤(U4). 안드로이드에서 실제 노트를 쓰기 전에 고정 서명 키를 등록한다(U20 — 그 전 APK는 debug 서명이라 판마다 '지우고 설치'). iPad 실사용은 live 채널의 홈 화면 앱에서만, live 반영(= 실제 노트의 v1 → v2 이주) 전에 백업 내보내기(7.8 B-1).

#### 영역별 개발 중 반영

| ID | 영역 | 할 일 | 시점 |
|---|---|---|---|
| INFRA-F1 | INFRA | `app_smoke_v2_test`(V5)·`app_smoke_v2_browser_test`(V6)에 자동 도형 단계를 넣지 않는다(2단계 `ShapeObject` 1). **V5b** `app_smoke_shape_assist_test.dart`는 INK T39·EDITOR E2-15·LIBRARY L2-06이 모두 병합됐을 때 H3에서 만든다. V15의 '자동 도형 보정' 기대 항목도 같은 조건(H5) | J19(본 흐름)·H3·H5 |
| INFRA-F2 | INFRA | J14b `V1CopyApi`는 계약 C22-01 그대로(지금 모양). 5.1 머리 '판정 대기'·10 #10 '거절되면' 갈래 정리 | R2-B8 뒤 '가정' 교체 때 |
| INFRA-F3 | INFRA | B8a·B8b·J0 끝마다 체크포인트 병합 요청(Q14), J0 실측 Actions 분이 월 2,000분을 넘으면 총괄에게 알림(Q15) | 동시 개발 앞 작업 |
| INFRA-F4 | INFRA | H1: CORE 병합(DB v2) 푸시 전에 U25 답을 확인 — 미리보기 주소에 실제 노트가 있으면 백업 내보내기를 먼저 받는다(01-infra 8.3 H1) | 통합 1단계 |
| CORE-F1 | CORE | B2-α에 `dev_tools.dart` v1 사본 API 4개 선언(C22-01 — 본문 `UnimplementedError`, 가짜는 `null`·아무것도 안 함), T24에서 동작·`v1_copy_test`·`v1_copy_browser_test`. T24 첫날 Chrome 확인은 웹 정규 덤프 사본의 만들기·해시·지우기·다시 열기 시간(C22-02) | B2-α, T24 |
| CORE-F2 | CORE | V7 고정 자료(T25a)는 1차 통합이 `main`에 들어간 커밋(`b6c9d0a` 기준 — 병합 뒤 총괄이 해시를 알림)의 1차 코드로 R2-B2 전에 만든다. 고정 자료 manifest에 정규 덤프 해시 | 기반 단계 전 |
| CORE-F3 | CORE | R-3 주석(`Recording.durationMs`)을 C22-04 문장('그 블록(패킷)의 길이')으로 B2-α에 | B2-α |
| CORE-F4 | CORE | `openTestNoteStore`·가짜 저장소의 C15-04 성질(다시 연 세션 히스토리 비어 있음)을 그대로 유지 — EDITOR E2-21·INFRA V5가 단언한다 | 동시 개발 |
| INK-F1 | INK | 바탕 `b6c9d0a`의 `lasso_polygon.dart`·`lasso_options.dart`(퇴화 판정 문구 C15-01)에서 시작 — 계획서의 `18c5ae5` 인용은 이 판으로 읽는다 | R2-B3 |
| INK-F2 | INK | T39(P-B)를 미루면 진행 기록 '2차' 절에 `T39 미룸`을 명시(V5b·L2-I3·E2-21b의 '미룸' 판정 근거). T39가 들어오면 그 병합 때 LIBRARY L2-I3·EDITOR E2-21b·INFRA V5b를 다시 돌리도록 알린다 | 동시 개발·통합 2단계 |
| INK-F3 | INK | 03-ink 8.3 I-6의 'V5 합성 멈춤' 지원은 V5b로 읽는다(실패 원인이 멈춤 감지·미리보기면 고침) | 통합 7단계 |
| EDITOR-F1 | EDITOR | E2-21 `objects_smoke_test`를 C15-04 순서(13.4)로 — 다시 연 세션 `undoDepth == 0` 단언 포함 | 통합 6단계 |
| EDITOR-F2 | EDITOR | E2-23: V5·V6(·V5b) 실패 단계가 있으면 진행 기록 E2-23 줄에 실패 단계·대응 시험(13.4 단계별 표)·원인 | 통합 7단계 |
| EDITOR-F3 | EDITOR | E2-15(P-B)를 미루면 진행 기록에 `E2-15 미룸` — E2-21b·V5b·V15 자동 도형 항목의 판정 근거 | 동시 개발 |
| EDITOR-F4 | EDITOR | 텍스트 IME 시제품(E2-01)은 첫 작업 그대로 — Hosting이 생기면 `area2/editor` 미리보기 채널로 B-2만 먼저(Q1), 없으면 Chrome 시험과 통합 Playwright 스모크로 | 동시 개발 첫 주 |
| LIBRARY-F1 | LIBRARY | 10 #4(V9 도형 판정)·#5(L2-I3·L2-I6)는 C22-07 규칙으로 판정 — L2-06·L2-16(P-B)을 미루면 진행 기록에 `미룸`과 빠진 작업 | 동시 개발·통합 5단계 |
| LIBRARY-F2 | LIBRARY | `SyntheticShapes.rectanglePath`의 소비자는 INFRA **V5b**와 L2-I3다(05-library 4.3·9.3의 'INFRA V5' 표기). 기본 `ShapeFitTuning`을 바꾸는 커밋은 `synthetic_shapes_test`를 같이 돌린다 | 동시 개발 |
| LIBRARY-F3 | LIBRARY | 에뮬레이터 시험의 `owner-uid`·`stranger-uid`는 SYNC 규약(CD2-22)과 같게, 실행 명령은 `npx --prefix functions firebase emulators:exec …`(01-infra 6.13과 같은 글자) | 통합 8단계 |
| PDF-F1 | PDF | V8(`media`)은 C22-04 판정식(마지막 블록 시작 − 50 ms ≤ 시계 ≤ 파일 끝 + 50 ms)으로 단언하고 두 값을 진행 기록에 남긴다 | T 녹음 작업·통합 4단계 |
| PDF-F2 | PDF | 웹 길이 보정은 C22-05 한 번 복사 방식(`BufferLedger` `peakCount ≤ 2`), 내보내기 장부의 `copy`·`overBudget`는 C22-06 예외 둘로만. 기각 대안 코드(네이티브 2 Mpx·12 MiB 넘는 입력 빼기)는 만들지 않는다 | T26 전 |
| PDF-F3 | PDF | `media_io`를 바꾼 커밋은 컨테이너에서 `ws test --package media_io --platform chrome --run-skipped -t media`(잠금 아래) 결과를 진행 기록에 — 영역 브랜치 푸시에서는 CI `media`가 돌지 않는다(01-infra 13.6 #3) | 동시 개발 |
| SYNC-F1 | SYNC | 서버 함수 S2-10a·S2-10b·S2-11은 P-B — 미루면 V13을 `미룸`으로(LIBRARY L2-I6도 함께). R2-B7b 골격의 `npm ci && npm test`(시험 수 > 0)는 P-A처럼 지킨다 | R2-B7b·동시 개발 |
| SYNC-F2 | SYNC | `firebase-tools 15.34.2` devDependency는 2026-11-11 이후 커밋(14일 규칙). 그 전이면 R2-B7b만 뒤로 미루고 총괄에게 알린다 | R2-B7b |
| SYNC-F3 | SYNC | B7a는 B2-α 해시를 바탕으로 R2-B2·R2-B2i와 한 묶음 병합. 새 종류 디코드·키 대조 시험(CP-S9)은 B2-β JSON 조각 커밋 뒤 | 기반 단계 |

### 기반 단계 순서 (00-overview 7.6.2 — 동시 개발 시작 전 `main`에 커밋)

0. **전제** — 총괄: 1차 통합 HEAD `b6c9d0a`를 `main`(저장소 기본 브랜치)에 두고, 승인된 계획서 `docs/plans/m5-7/`를 `main`에 넣고, 2차 작업 트리 `/home/user/wt2/<id>`(브랜치 `area2/<id>`)를 그 `main`에서 만든다. 1차 V7(iPad 확인)은 전제가 아니다(D21).
1. **CORE T25a** — V7 v1 DB 고정 자료를 그 `main` 커밋의 1차 코드로 만든다(R2-B2 전 — CORE-F2).
2. **R2-B1 INFRA** — 새 패키지 3개 골격·pubspec 전부(7.5 새 의존)·`workspace_rules.yaml`(R8 v2.0·R16·`native_only_imports`·`pinned_external`)·`tool/chrome-fakemedia`·무거운 시험 잠금·`app/firebase.json`·`functions.yml` 골격, lock 재생성.
3. **R2-B7b SYNC** — `functions/` 골격(`npm ci && npm test`, 시험 수 > 0). R2-B1 바로 뒤 따로 병합. 2026-11-11 전이면 이 단계만 뒤로(SYNC-F2).
4. **R2-B2 CORE + R2-B7a SYNC + R2-B2i INFRA 묶음** — CORE B2-α(계약 표면 + `api_surface_test` v2, `dev_tools.dart` v1 사본 선언 포함) 커밋 해시를 '계약 타입 커밋'으로 알림 → SYNC B7a·INFRA B2i가 그 해시 위에서 → CORE B2-β(동작) → 총괄이 세 브랜치를 함께 병합한 뒤 검사.
5. **R2-B3 INK** — 7.2.9 공개 표면 전부를 단순하지만 동작하는 구현으로(T24 해시 알림).
6. **R2-B4 PDF · R2-B5 EDITOR · R2-B6 LIBRARY** — 병렬(INK 타입을 쓰므로 B3 뒤).
7. **동시 개발 시작**(R2-B1~R2-B6이 `main`에 있음). INFRA는 R2-B8a → R2-B8b → J0부터(체크포인트 병합 — Q14). 각 영역은 '가정' 블록 교체·C22-09 인용 맞춤·자기 F 항목부터.

### 통합 순서 (00-overview 7.7.1 — 검증 기준 7.7.2 V1~V16)

1. **CORE** 병합 → lock 재생성 → 검사 + V7 마이그레이션(VM·Chrome). 푸시 전 INFRA-F4.
2. **INK** → 검사 + 골든·불변식(K-1·K-6).
3. **SYNC** → T16-v2(실제 CORE 2개) + `functions` 시험.
4. **PDF**(`pdf_io` + `media_io`) → `integration`(객체 내보내기 — V11) + `media`(V8·V16).
5. **LIBRARY**(`feature_library` + `ink_recognition`) → 실제 CORE 색인(L2-I1·L2-I2) + 도형 판정(V9) + 자동 도형 흐름 L2-I3(P-B — C22-07) + 수식 클라이언트 에뮬레이터(L2-I6, 3단계 뒤).
6. **EDITOR** → E2-21(실제 INK + 실제 CORE, C15-04 순서) + E2-21b(P-B).
7. **INFRA** → 실제 모듈 연결·`pencil_bridge`·네이티브 설정 정적 시험(V12)·V5·V6·(P-B) V5b·V15.
8. 통합 태그 전체(`ws test --run-skipped -t integration`, `-t media`, `-t emulator` — `media`·`emulator`는 전역 잠금으로 하나씩).
9. 릴리스 웹 빌드 Playwright 스모크(H7) → (Hosting이 있으면) 미리보기 배포 → 사용자 iPad 웹 확인(7.8 B) / `android.yml` APK → 안드로이드 확인(7.8 A, 기기가 있을 때) / `ios-compile.yml` 1회(U19 승인 시 — V14) → V1~V16(P-B 미룸 제외)이 모두 통과하면 '2차 통합 완료' → PLAN.md 체크리스트 갱신(총괄).

3~6은 서로 import하지 않아 순서를 바꿔도 된다('데이터 → 렌더 → 소비자'로 실패 원인을 좁히기 위한 권장).

### 사용자 질문과 기본값

답을 기다리지 않고 기본값으로 개발한다(00-overview 9장 U1~U27 — 아래에 없는 것은 9장 기본값 그대로). 위에서부터 중요한 순서다.

| # | 질문 | 기본값 | 언제 필요한가 · 기본값의 영향 |
|---|---|---|---|
| U24 | Firebase 프로젝트를 **Spark(무료)·Hosting만**으로 지금 만들 수 있나요? (1차 안내서 01·02, 약 15분, 결제 계정 없음 — 동기화·로그인은 켜지 않아요) | 답이 오기 전까지 Hosting 없이 진행. 총괄 권장은 '지금 만든다' | 동시 개발 첫 주(EDITOR IME 미리보기). 없으면 iPad 웹 확인·1차 V7이 Hosting 때까지 밀리고, 컨테이너 Playwright 스모크로 일부를 대신한다. 한글 IME·Safari 선택기·메모리 문제가 통합 뒤에야 드러날 수 있다 |
| U25 | 1차 앱으로 iPad(또는 다른 기기)에 만든 실제 노트가 있나요? 있다면 어느 주소인가요? | 없음(Hosting이 없어 배포된 적 없음) | 통합 1단계 푸시 전(INFRA-F4). 기본값이 틀리면 첫 실제 v1 → v2 이주가 일찍 일어나지만 v1 사본(C22-02)과 백업 내보내기가 안전망이다 |
| U2 | S펜이 되는 안드로이드 태블릿이 있나요? 모델은? | 없음 | A 체크리스트(S펜 버튼·백그라운드 녹음·ML Kit 손글씨)를 '코드만, 확인은 이후'로. 손글씨 인식(M7-1)의 첫 실기기 판정이 TestFlight 뒤로 밀리고, 안드로이드 에뮬레이터 CI 잡(P-C)을 넣는다 |
| U20 | 안드로이드 고정 서명 키를 어떻게 받을까요? (이 세션은 GitHub 시크릿을 직접 넣을 수 없어요) | ① Claude가 만들어 파일 두 개로 건넴 → 사용자가 GitHub 설정에 등록(안내서 07) | 안드로이드에서 실제 노트를 쓰기 전. 등록 전 APK는 debug 서명이라 판마다 '지우고 설치'(노트 사라짐) |
| U1 | Apple Pencil 종류(Pro / USB-C / 2세대)와 iPad 정확한 모델명은? | Pro 기능까지 만들고, 스퀴즈·롤 설정은 첫 이벤트를 받은 뒤에만 보임 | 재작업 없음. USB-C면 M5-9 확인 항목 대부분이 해당 없음 |
| U19 | macOS 러너로 iOS 컴파일 확인을 2차에 1회 해도 되나요? (무료 시간 약 150분, 저장소 비공개 유지) | 1회(통합 뒤) — 승인되면 V14 완료 조건 | 통합 9단계. 안 하면 Swift(`pencil_bridge`)·ML Kit pod 컴파일이 첫 TestFlight 빌드 때 처음 확인된다 |
| U26 | 녹음된 글씨 탭 재생: 손가락 탭은 녹음 패널이 열려 있거나 재생 중일 때, 펜 점은 재생(·일시정지) 중일 때만 이동하고 그 밖에는 점이 남아요. 녹음 중에는 가로채지 않아요. 괜찮나요? | 그대로 | EDITOR E2-17. 필기 손실을 막는 쪽 |
| U27 | 안드로이드 기기 자동 백업(Google 드라이브)에 노트를 넣지 않아요. 괜찮나요? | 넣지 않음 | INFRA J0 매니페스트. 보존은 백업 내보내기(지금)와 동기화(실연결 뒤) |
| U7 | 텍스트 상자 글꼴 = Noto Sans KR 부분 집합(한글 2,350자 + 라틴, 처음 그릴 때 받음). 부분 집합 밖 글자가 든 상자는 PDF에서 그림으로 들어가 검색되지 않아요. 괜찮나요? | 그대로 | INK T26a. 드문 글자가 든 상자는 화면에서 대체 글꼴, PDF에서 래스터 |
| U6 | 수식 인식 엔진 비교용 유료 계정(Mathpix·Anthropic API 등)과 수식 영역의 획·이미지를 외부로 보내는 데 동의하나요? | 계정이 생기면 | 그때까지 수식은 LaTeX 직접 입력 + 미리보기. 서버 함수·클라이언트는 가짜 엔진으로 시험까지 끝난다 |
| U3 | Firebase 실연결(동기화·로그인)은 언제 하나요? | 2차 통합 뒤 '실연결 미니 라운드'(INFRA + SYNC — D16) | 2차 범위에는 넣지 않는다. Spark·Hosting만은 U24 |
| U21 | 최종 앱 ID(`dev.noteapp.noteapp` 유지?) | 유지 | 고정 서명 키·App ID 등록 전(U20·TestFlight 전)에 확정 |

### 다음 단계

1. 총괄: 이 계획 작업 트리(`area/plan57`)의 `docs/plans/m5-7/`을 커밋하고 `main`에 넣는다(이 절차에서는 커밋하지 않았다). 1차 통합 HEAD `b6c9d0a`가 `main`인지 확인하고 CORE에 해시를 알린다(CORE-F2).
2. 기반 단계 0~7(위) → 동시 개발(영역 작업 트리, 진행 기록 `docs/plans/progress/<id>.md` '2차' 절, GitHub 푸시는 체크포인트·통합 때만 — 7.4.9).
3. 통합 1~9(위) → '2차 통합 완료' → 이 문서에 '2차 통합 결과' 절(1차와 같은 양식).
4. 사용자: U24(Hosting)를 먼저 답해 주면 iPad 웹 확인을 동시 개발 중에 시작할 수 있다. U2·U20은 안드로이드 실사용 전에, U19는 통합 전에 필요하다.

## 2차 통합 결과

> 날짜: 2026-11-12 · 총괄 관리자 · 브랜치 `claude/note-app-planning-bk29xb`(INFRA 체크포인트 `b032244` 뒤 병합 HEAD `8c2256e`, 통합 끝 `55bf85a`) · 기준: 통합 계약 **v2.7**([00-overview.md](00-overview.md) 7장 — 통합에서 바뀐 곳은 [7.9](00-overview.md#79-계약-변경-이력) 'v2.7' C27-01~07, 시그니처 변경 없음) · 판정: **V4 대기 — 나머지 컨테이너 기준(V1~V3·V5~V16) 통과, 실기기 확인 대기**. '2차 통합 완료'는 INFRA가 C27-01 값을 `tool/web_budget.yaml`에 반영해 `ws web-budget check`가 0이 된 뒤 선언한다(지금은 한도 1,666,038 B 그대로라 1 — 아래 V4·'남은 일'). V14의 GitHub 실행(APK·iOS 컴파일 1회)은 C27-07대로 총괄 푸시 뒤 사용자 'Run workflow'로 확인하고 2차 완료를 막지 않는다.

### 통합 순서 (계약 7.7.1)

| 단계 | 병합 | 통합 작업(커밋) | 그 단계 확인 |
|---|---|---|---|
| 1 | CORE | `1523f3a`(C26-03 구 강조)·`820449d`(`content_rev` 경합)·`dcbb7e3`(기록) | `ws check` 0, VM 1203·Chrome 115, V7 VM·Chrome, V10 CORE 몫(C25-01 예산) |
| 2 | INK | `526c894`(실제 CORE판 인계 18), 후속 `55bf85a`(웹 `Int64List` 제거) | VM 1318(골든 24장 불변)·Chrome 374, K-1·K-6~K-9, 벤치 27 중 26(B12는 기록만) |
| 3 | SYNC | `04602cc`(H3·R1 시험 가정, `TestDevice.renameRecording`) | T16-v2 `integration` 66, VM 1008·Chrome 70, `functions` 248, V13 에뮬레이터(SYNC 10 + LIBRARY Dart 9) |
| 4 | PDF(`pdf_io` + `media_io`) | `48168da`(탐침 제거·V10·V11·C26-01·02·04)·`e57a675`·`6a4c8ac`(재확인) | 4-a `integration` 26 · 4-b Chrome 2 · 4-c `media` 11(V8·V16) · 4-d 5, pdf_io VM 821·Chrome 119 |
| 5 | LIBRARY(`feature_library` + `ink_recognition`) | `92ac338`(L2-I2 실제 CORE = 가짜, 기록) | L2-I1 2·L2-I2 11·L2-I3 6·L2-I6 9, V9 다시 통과, VM 681 + 489 |
| 6 | EDITOR | `311e209`(E2-21·E2-21b, C25-02, 외곽선 적중 시험 4개) | VM 1497·`integration` 4·Chrome 4 |
| 7 | INFRA | `c5c1333`·`e276677`(V5 v2·V5b·V15·V12·H7·유휴 실행기·C26-02·C24-01·CI 도구 시험) | `integration` 14(주입·`--dart-define` 두 방식), V6 v2는 INK 후속 뒤 통과 |
| 8 | 통합 태그 전체 | 영역별로 실행(위), 총괄 일괄 실행은 이 문서 커밋 뒤 검증 단계 | `-t integration`·`-t media`·`-t emulator` 영역 몫 모두 통과 |
| 9 | 릴리스 웹 빌드 Playwright(H7) | — | 통과(첫 프레임 1,580 ms, 콘솔 오류 0). 미리보기 배포·iPad·APK·iOS 컴파일은 아래 '남은 일' |

### 통합 검증 기준 (계약 7.7.2 V1~V16)

| # | 결과 | 근거 |
|---|---|---|
| V1 | 통과 | 병합마다 `pub get --enforce-lockfile`, `ws check`(R1~R16) 0 — 총괄 병합 직후·각 영역 통합 끝(INFRA H1) |
| V2 | 통과 | 루트 `flutter analyze --fatal-infos` 0, `dart format` 바뀜 0 |
| V3 | 통과 | 병합 직후 VM 기준선(`r2-merge-vm.log`)의 실패 3멤버(pdf_io 1 — C26-03 기대값, feature_editor 4 — 빈 도형 적중, noteapp 1 — 실제 이미지 소스)를 모두 고친 뒤 영역별 VM·Chrome·`integration` 전부 통과(위 표). `dart test tool/test` 550. Chrome은 `useInkTestFonts`로 멈춤 없음 |
| V4 | **대기**(C27-01 결정, INFRA 반영 전) | 릴리스 빌드·`web-assets verify` 통과, 시작 글꼴 385,521 B(KaTeX 371,014·아이콘 14,507 — C24-01 한도 안). `main.dart.js`는 통합 끝 `42b01c7`에서 gzip 1,902,969 B / 원본 6,477,160 B(INFRA 통합 실측 1,902,938 B는 INK `55bf85a` 전 빌드 — 31 B 차). 총괄 결정으로 기준을 이 빌드로 옮기고 한도 2,000,000 B로 정했지만 `tool/web_budget.yaml`은 아직 1차 기준·한도 1,666,038 B라 `ws web-budget check` = 1(위반 2: 한도·증가). INFRA 반영 뒤 check 0이면 통과 |
| V5 | 통과 | `app_smoke_v2_test`(VM): 9.1 2~8·10단계를 실제 화면으로, override 출처·횟수, 자리 4곳(INFRA H3) |
| V5b | 통과 | `app_smoke_shape_assist_test`(VM) — P-B 작업 모두 병합(7.7.2 v2.7 표) |
| V6 | 통과 | `app_smoke_v2_browser_test`(Chrome) — INK `55bf85a` 뒤 재생 단계 포함 통과(FlutterError 0) |
| V7 | 통과 | `v1_fixture_migration_test` VM 파일 DB·Chrome 웹 워커: 행·필드 버전·outbox 유지, v1 사본 해시 = manifest. 웹 PF-8 첫 실행(DDC 2,149 ms)은 기록만 — 1 s 예산은 VM 몫, 릴리스 웹은 iPad B-1에서 |
| V8 | 통과 | `media`(Chrome 가짜 마이크): 파일 1,978 ms·시계 2,008 ms, C26-01 한계 안, 2배속 기울기 1.960 |
| V9 | 통과 | `groupIntoLines` 100 %, 도형 합성 1,400개 모든 종류 문턱 위(잘못 바꿈 ≤ 6 %) |
| V10 | 통과 | 질의 VM = Chrome, 5,000쪽 예산(C25-01), PDF 사각형 pt(C26-03 — 낱말마다 첫 일치), PF-10 DB 증가 8.31/6.15/3.62 MiB·PF-10w +133 ms |
| V11 | 통과 | 실제 PDFium VM·Chrome: 텍스트 상자 한글 추출, 이미지·수식 래스터, 점선 = 한 모양 58 하위 경로(C27-02) |
| V12 | 통과 | `native_config_test`·`native_reqs_test` 89, `ws native-reqs` 0, CocoaPods 전용 = ML Kit 둘 |
| V13 | 통과 | `functions` 248, 에뮬레이터 SYNC 10 + LIBRARY Dart 9(한 실행), GitHub `functions.yml` 2회 성공 |
| V14 | 컨테이너 몫 통과 · GitHub 실행 **사용자 확인 대기** | `workflows_test` 서명 분기·아티팩트 이름 사례 통과. `android.yml`·`ios-compile.yml`은 이 단계에 돌지 않음(수동 — C27-07) |
| V15 | 통과 | `feature_switch_test` 주입·`--dart-define` 두 방식, 끔에서 녹음 버튼·인식 메뉴·수식 엔진·자동 도형 토글만 사라지고 이미지 삽입은 남음 |
| V16 | 통과 | 실제 웹 저장소에서 탭 닫힘 흉내 → `pendingDrafts` 1 → 복구, `recordingId` 유지, 녹음 중 초안은 내지 않음 |

### 영역별 결과

| 영역 | 동시 개발 | 통합 단계에서 한 일 | 결함·변경 요청 |
|---|---|---|---|
| CORE | T20a~T37 완료 | C26-03 구 강조(실제·가짜 같은 내부 함수), 세션 로컬 쓰기 `content_rev` 경합 수정, V7·V10, 다른 영역 통합 시험을 실제 CORE에서 | CORE 결함 1(`content_rev` — 고침). [SYNC] 2·[PDF] 2·[INFRA] 1 보냄 → 모두 처리 |
| INK | T24~T43 완료, T44 미룸(C25-04) | 인계 시험 18개를 실제 CORE판으로도, README v2 | 웹 `Int64List`(INFRA V6 — `55bf85a` 고침). [PDF] V11·[EDITOR] 빈 도형 적중·[LIBRARY]·[EDITOR]·[INFRA] P-B 재실행 요청 → 모두 처리 |
| SYNC | S2-1~S2-15 완료 | T16-v2 실제 CORE 2개, V13 | 시험 가정 2(H3·R1)·가짜 1(`TestDevice`) 고침. 요청 보냄 없음 |
| PDF | T21~T41 완료 | 탐침·정적 skip 모두 제거, V10·V11 기대값을 계약 의미로, C26-01·02·04 | 결함 0. [INFRA] C26-02 연결 요청 → 처리 |
| LIBRARY | L2-01~L2-22 완료 | L2-I1·I2·I3·I6, V9 다시, `lib/` 변경 없음 | 없음. L2-I4 나머지(V5 2~8단계 인식 자리)는 INFRA V5 v2가 덮음, L2-I5 실기기 |
| EDITOR | E2-00~E2-22 완료, E2-11 미룸(P-C) | E2-21·E2-21b, C25-02 개발자 표시 값, 외곽선 적중 시험 4개 | 없음(CORE·INK 결함 못 찾음). E2-24는 실기기 뒤 |
| INFRA | J1~J22 완료(J0 ④·J15 제한은 푸시 뒤) | V5 v2·V5b·V15·V12·H7, C26-02·C24-01, 유휴 작업 실행기 헛돌기 수정, CI 도구 시험 수정 | [INK] `Int64List` → 처리, [총괄] V4 → C27-01 결정, `web_budget.yaml` 반영은 대기 |

### 통합에서 나온 문제와 처리

| # | 문제 | 원인 | 처리 | 계약 |
|---|---|---|---|---|
| 1 | EDITOR VM 시험 4개 실패(빈 도형 안쪽 탭·지우개) | 기반 단계 INK의 경계 상자 적중을 전제 | 외곽선에서 탭·지우개 경로가 변을 지나게(단언은 그대로 — `311e209`) | C27-03 |
| 2 | PDF V11 점선 조각 = 1 | 조각을 `InkFillShape` 수로 셈. INK는 한 모양의 하위 경로로 냄 | `moveTo` 수로 세고 PDF `m` 수와 맞춤(`48168da`) | C27-02 |
| 3 | PDF V10 실제 저장소 변형이 시작 전에 죽음 | 탐침 키 `probe#0`이 CORE 키 검증(`ArgumentError`)에 걸림 | 탐침 제거 — 실제 변형이 늘 돈다 | C27-05 |
| 4 | PDF 'second lecture' 사각형 1 → 2 | C26-03(낱말마다 첫 일치) 뒤 기대값이 옛 규칙 | 1차 낱말 사각형 둘(±0.5 pt)·합 = 1차 구 사각형·역순 질의 | C26-03 |
| 5 | SYNC H3 널 검사·R1 삭제된 녹음 이름 바꾸기 | 시험이 계약 읽기 규칙과 다름, 시험용 가짜가 삭제된 녹음도 이름을 바꿈 | 시험·가짜를 계약 문장대로(`04602cc`) | C27-04 |
| 6 | V6 v2 재생 단계에서 FlutterError 4 | INK `PlaybackTrack`의 `Int64List` — dart2js·DDC 미지원 | `List<int>` + Chrome 재생 칠하기 시험(`55bf85a`) | C27-06 |
| 7 | V5 v2가 되돌리기 중 RSS 2.6 GB로 죽음, V6 v2 'did not complete' | 유휴 작업 실행기가 `scheduleTask(Priority.idle)`를 기다려 애니메이션 중 0초 타이머가 끝없이 생김 | 시작 조건을 '프레임 끝 + 애니메이션 없음'으로(계약 7.3.3 '첫 프레임 3초 뒤·보일 때' 뜻은 같음 — 01-infra 6.5.1) | — |
| 8 | noteapp VM 실패 1·1차 `app_smoke_test` override 집합 | 기반 단계의 '이미지 소스 없음' 전제, 1차 V5 집합에 `editorImageImporterProvider` 없음 | 실제 `supportedImageSources()`로·집합에 행 추가 | — |
| 9 | CORE 세션 쓰기와 원격 쓰기가 겹치면 변경이 한 번만 오름 | 세션 `content_rev`가 못 본 원격 커밋 | `MAX(content_rev + 1, 세션 값)`(`820449d`) | — |
| 10 | `main.dart.js` 예산 초과(+236,931 B) | 2차 영역 코드(녹음·인식·수식·PDF 객체 내보내기) | 기준 이동 + 한도 2,000,000 B(결정), `tool/web_budget.yaml` 반영은 INFRA 대기, `deferred`는 3라운드 후보 | C27-01 |
| 11 | GitHub `ci.yml` 실행 11~13이 `check`에서 실패 | `workflows_test`가 러너의 `TEST_SCOPE`를 물려받음(컨테이너엔 없음) | `includeParentEnvironment: false` 6곳 — 다음 푸시에서 다섯 잡 실측 | — |

알려진 한계(결함 아님): INK B12(1000점) 디버그 VM 여유가 작음(0.5 ms / 0.6 ms — 기록만), 헤드리스 Chrome 적재 멈춤은 1차처럼 `ws`가 한 번 다시 돌려 통과, 실제 저장소 작업을 fake-async 영역에서 시작한 위젯 시험은 `runAsync(store.close)`가 끝나지 않음(EDITOR 하네스 메모 — 시험 쪽에서 피함).

### 남은 일

컨테이너 몫:

- **INFRA(V4 — 2차 통합 완료를 막음)**: C27-01 값을 `tool/web_budget.yaml`(기준 gzip 1,902,969 / 원본 6,477,160 B — 통합 끝 `42b01c7` 실측, `main_dart_js_gzip_max` 2,000,000)과 01-infra 6.15 표(지금 1,902,938 / 6,476,935 B — INK `55bf85a` 전 값)에 반영 → `ws web-budget check` 0. 그 뒤 총괄이 이 문서·00-overview·PLAN.md의 V4를 '통과'로, 상태를 '2차 통합 완료'로 바꾼다.
- 총괄: 이 문서 커밋 뒤 7.7.1 8단계 일괄 실행(`ws test --run-skipped -t integration`, `-t media`, `firebase emulators:exec … -t emulator` — 전역 잠금으로 하나씩)과 통합 브랜치 푸시 → INFRA가 `ci.yml` 다섯 잡 실측으로 J15 잡별 제한·월 분을 정함.
- 3라운드 후보: `deferred` import(C27-01), `Int64List` 금지의 `ws check` 규칙화(C27-06), INK T44, 실연결 미니 라운드(INFRA + SYNC — 07-sync 6.10 SC-1~SC-8).

사용자 행동(위에서부터 중요한 순서):

1. **Firebase Hosting(Spark·무료)** 프로젝트 만들기 — U24, [안내서 01](../../guides/01-firebase-project.md)·[02](../../guides/02-github-secrets.md) → 총괄이 **미리보기 채널** 배포 → **iPad 웹 확인(7.8 B)**. B-1(1차 노트가 있는 live 채널)은 배포 전에 백업 내보내기.
2. **Android APK**: 고정 서명 키 등록(U20 — [안내서 07](../../guides/07-android-signing.md)) → GitHub Actions에서 `android.yml` **Run workflow**(V14) → APK 설치([안내서 05](../../guides/05-android-apk.md)) → **7.8 A**(S펜 태블릿이 있을 때 — U2).
3. **iOS 컴파일 1회**(U19 — `ios-compile.yml` Run workflow, 무료 macOS 시간 약 150분). 거절이면 '미확인'으로 두고 첫 TestFlight 빌드 전에 한다.
4. **수식 엔진 계정**(U6 — Mathpix·Anthropic API 등)과 외부 전송 동의·비용 확인 → Firebase **Blaze**·함수 배포·엔진 비밀값(`functions/README.md`) → `npm run eval:math`. 실연결(동기화·로그인)도 Blaze 뒤(U3).
5. Apple 유료 계정(TestFlight) 뒤 7.8 C.

### 실기기 체크리스트 위치

- **2차 통합 체크리스트**: [docs/guides/08-device-checklist.md](../../guides/08-device-checklist.md) — A(안드로이드 APK)·B(iPad 웹 — B-1~B-16)·C(TestFlight 뒤), 결과 보고 양식 포함. 원본은 [00-overview.md 7.8](00-overview.md#78-실기기-체크리스트).
- 영역별 상세: 01-infra 9.3, 02-core 9.5(A-1·A-c1·A-c2·B-1·B-10·B-13·B-14·B-c1·B-c2·C-c1), 03-ink 9.6(I-A1·I-A2·I-B1~I-B14 — B14·B17 릴리스 빌드 실측), 04-editor 9.4(B-2·B-3·B-5·B-7·B-8·B-15 필수, A-2, E2-24), 05-library 9.4(A-4·A-L3·B-4·B-10·B-11), 06-pdf 9.6(A-3 'native: FGS failed' 줄 없음), 07-sync 9.3(실기기 항목 없음 — 실연결 뒤 SC-1~SC-8).
- 1차 체크리스트(아직 판정 전): [안내서 04](../../guides/04-ipad-web-test.md), [plans/00-review.md '1차 통합 결과'](../00-review.md#1차-통합-결과).
- 결과는 각 영역 진행 기록 '## 2차' > '### 통합 단계'에 적고(CORE I-7 등), 불합격 항목은 조정 작업으로 연다(INK `PenProfile`·`InkTuning`, LIBRARY 문턱, EDITOR `webTextInput`).
