# LIBRARY 2차 계획서 검토 — `05-library.md`

> 검토자: 총괄 대리 검토자 · 검토일 2026-11-05
> 대상: [05-library.md](../05-library.md)(2,309줄, 초안) — 라이브러리 화면 · 인식(LIBRARY), 소유 경로 `packages/feature_library/`, `packages/ink_recognition/`(새)
> 기준: 개요 [00-overview.md](../00-overview.md) 7장 통합 계약 v2.0 초안, 조사 01~04(특히 [03-recognition](../research/03-recognition.md)·[04-native](../research/04-native.md) 6절), PLAN.md(F-10·F-11·F-14, 5.1·5.2, 10장 M5·M7), 1차 LIBRARY 작업 트리 `/home/user/wt/library`(`ec403be`), 1차 CORE `/home/user/wt/core`(`4336967`), 1차 INK `/home/user/wt/ink`, 1차 EDITOR `/home/user/wt/editor`, 다른 영역 계획서 01·02·03·04·06·07(맞닿은 절만), 이미 나온 검토 [core.md](core.md)·[editor.md](editor.md)·[infra.md](infra.md)
> 확인 방법: 계획서 전 절을 읽었다. 4.1·4.2·4.3의 '계약 원문' 블록을 개요 7.2.11·7.6과 `diff`로 대조했다(글자까지 같음 — 차이는 코드 울타리·머리줄뿐). pub 캐시의 `google_mlkit_digital_ink_recognition 0.16.1`·`google_mlkit_commons 0.13.0`·`http 1.6.0`·`flutter_riverpod 3.4.3`·`material_ui 1.10.0` 소스와 pub.dev API(게시일)를 다시 봤다. LIBRARY 실험 폴더 `/tmp/claude-0/plan57-scratch/library57/`의 도형 판정 평가(`shape/bin/eval.dart`, 시드 20261105)를 한 번 다시 돌려 6.17.3 표와 같은 수를 얻었다. 줄 나누기 합성 자료는 단순 모형으로 따로 셈했다(M-2 — 스크래치 `lines_sim.py`). 무거운 시험은 돌리지 않았다.

---

## 총평

계약 7.2.11을 글자 그대로 옮기고(대조 차이 0), 계약이 이름만 둔 곳(4.4)과 계약을 바꾸고 싶은 곳(12.1 CP-L1~L10)을 깔끔하게 나눈 계획서다. 좋은 점:

- **외부 사실 확인이 탄탄하다.** 내가 다시 본 것 — ML Kit 채널 이름 `google_mlkit_digital_ink_recognizer`, `StrokePoint.t`가 `int`, `DigitalInkRecognitionContext(preContext:, writingArea:)`, 오류 문자열(안드로이드 `'Model Error'`·`'Failed to create model identifier'`·`'Model Identifier error'`·`'recognition Error'`, iOS `'invalid_model'`·`'Error Model has not been downloaded yet'`, commons iOS `'download_in_progress'`), 점수 없음 → 플러그인이 `0.0`을 채움, 안드로이드 `digital-ink-recognition:19.0.0`·iOS pod `~> 9.0.0`·15.5, 0.16.1·0.13.0 게시일 2026-08-17, `http 1.6.0`(2025-11-10)의 `AbortableRequest`·`RequestAbortedException`, Riverpod `ProviderScope.containerOf(context, listen:)`, `material_ui` `showModalBottomSheet(constraints:, useSafeArea:)` — 모두 맞다.
- **도형 판정기는 실험으로 V9를 미리 넘겼다**(E-L3). 시드 20261105 재실행: 직선 100%·원 100%·타원 93.5%(잘못 4.0%)·삼각형 87.5%(3.0%)·사각형 96.0%(0%)·오각형 97.0%·낙서 거부 96.0%, 획당 111 µs — 6.17.3 표와 같다.
- 1차 코드 근거가 대부분 맞다 — `LibraryScreen` 생성자·내보내기 11개(`feature_library.dart`), `libraryContentProvider`의 `SearchSection` 즉시 무효화(`state/providers.dart` 103·135–139행), `SearchResultsView`의 `CustomScrollView`·`SearchGroupHeader`, CORE `SettingsRepository.get`이 `Future<T>`(그래서 `consent: () => settings.get(...)`가 `Future<bool> Function()`과 맞음), `settingsSnapshotProvider`가 `StreamProvider<SettingsSnapshot>`, `NoteContentReader.loadPage`·`pagesOf`, `ChangeOrigin`, `PageThumbnailRenderer.render(content, {maxSidePx})`, INK `inkPageControllerProvider`가 `autoDispose.family`(임시 페이지 id가 새지 않음), `SelectionGeometry.snapAngle`이 `ink_engine.dart`에서 내보내짐.
- 웹 경계(조건부 export 하나 + ML Kit import 파일 하나), 동의 게이트를 네트워크 전에 두고 `MockClient` 0회로 단언, 수식 패드 '손으로 고친 값 우선', SYNC와 맞춘 callable 형식·오류 표(07-sync 5.3과 대조해 어긋남 없음)가 좋다.

그러나 **그대로 승인할 수 없다(revise)**. ① 색인기가 작업을 시작할 때 읽은 결과로 `put`하므로, 같은 페이지에 변환 창의 '복사'(확정 줄)나 원격 결과가 그 사이 들어오면 **사용자가 고친 글을 조용히 덮어쓴다**(데이터 손실). ② P-A 완료 조건인 줄 나누기 V9(획 정확도 ≥ 95%·페이지마다 줄 수 차 ≤ 1)가 **실험 근거 없이** 정해졌고, 합성 생성기 명세가 이웃 줄이 서로 반대로 기울어 겹치는 자료를 만들 수 있어 알고리즘이 아니라 자료 때문에 떨어질 수 있다. 그 밖에 색인기의 UI 스레드 비용, 확정 줄을 너무 쉽게 버리는 규칙, 기기 간 엔진 id 비교, `loadPage` 전 `flush`, 휴지통 노트 판정, 에뮬레이터 시험 시점·장소, INK 통합 시험 위치, 작업 분해 크기, 실기기 항목 몇 개를 고쳐야 한다.

---

## 반드시 고칠 것

### M-1. 색인기가 낡은 결과 위에 `put`해 확정 줄(사용자가 고친 글)을 덮어쓴다 (데이터 손실)

- **위치**: 6.9.2 입력(1480행 — `kind == stroke`·`kind == page`만 구독), 6.9.3 작업(1487–1508행 — `existing = forPage(pageId)`를 작업 **시작 때** 한 번 읽고, 줄을 다 인식한 뒤 `put`), `gate()`(1500행 — '이 페이지가 작업 시작 뒤 다시 바뀌지 않음'은 획 변경만 봄), 6.13.5 복사·확정 줄(1734–1741행), 4.4.7 표(706–707행).
- **문제**:
  - 자동 인식을 켠 사용자가 다섯 줄을 쓰고 올가미로 고른 뒤 '텍스트 복사' 창을 연다. 올가미 선택은 획을 바꾸지 않으므로 마지막 획 3초 뒤 색인기 작업이 시작된다(`existing == null`을 읽음). 창과 색인기는 같은 ML Kit FIFO를 번갈아 쓰며 둘 다 진행한다. 사용자가 2줄을 고치고 [복사] → 창이 `userConfirmed: true` 줄로 `put` → 몇 백 ms 뒤 색인기가 자기 결과(확정 표시 없음, 엔진 글)로 `put` → **고친 글이 사라지고** A-L2('고친 낱말로 검색')가 실패한다. 창을 여는 데 3초 넘게 걸리므로 드문 일이 아니라 자동 인식을 켠 사람에게는 거의 늘 겹친다.
  - `handwriting` 변경(CORE `put`은 `ChangeBatch(local)`에 `handwriting` 변경을 낸다 — 02-core 6.9.4)은 색인기 입력이 아니므로 `gate()`가 알아채지 못한다. 실연결 뒤 다른 기기의 결과(원격 `handwriting`)도 같은 길로 덮인다.
  - 계약 7.2.5 `userConfirmed` 주석('set by the conversion UI; auto re-recognition keeps it')과 02-core 5.5('그 병합은 색인기 몫')를 어긴다. 9.3·8.2 L2-10 시험 목록에 이 경우가 없다.
- **고칠 방향**(둘 다):
  1. 색인기가 `EntityKind.handwriting` 변경도 구독한다. 작업 중인 페이지의 `handwriting` 변경이 오면 그 작업을 버리고 대기열 앞으로 되돌린다(획 변경과 같은 처리, 다만 조용해질 때를 다시 기다리지 않아도 됨).
  2. `put` 직전에 `forPage(pageId)`를 다시 읽어 시작 때 값과 다르면(`==` 또는 `updatedAt`) 6.9.4 병합을 **새 값에 대해 다시** 한다 — 새 값의 확정 줄은 획 집합이 같은 한 그대로 둔다. 변환 창의 복사 경로(6.13.5 2단계)도 `put` 직전에 같은 재읽기·병합을 한다.
  - 시험: `unit/indexer_test.dart`에 '작업 도중 확정 줄 `put`이 들어옴 → 확정 줄 유지·쓰기 1회', '작업 도중 원격 `handwriting` → 작업 버림·재시도', `widget/conversion_sheet_test.dart`에 '색인기 진행 중 복사 → 확정 줄 유지'를 더한다. C-3에도 적는다.

### M-2. 줄 나누기 V9 완료 조건에 실험 근거가 없고, 합성 생성기가 이웃 줄이 겹치는 자료를 만들 수 있다

- **위치**: 6.5 끝 '완료 판정(V9)'(1370행 — 시드 1~20 × 줄 3~12에서 획 정확도 ≥ 95% + **페이지마다** 줄 수 차 ≤ 1), 6.6 생성기(1375행 — '줄마다 기울기 ∈ [−4°, +4°]', 줄 간격 ∈ [1.6, 2.4]·H, 글자 크기 ±15%·세로 흔들림 ±0.08·H), 8.2 L2-05(2056행, **P-A**), 7.3 실험 표(줄 나누기 실험 없음).
- **문제**:
  - 도형 판정기(E-L2·E-L3)와 달리 줄 나누기는 알고리즘도 생성기도 실험하지 않았다. 그런데 P-A 작업이고 계약 V9 문턱을 그대로 완료 조건으로 삼았다.
  - 생성기는 줄마다 기울기를 **따로** 뽑고 회전 중심을 정하지 않았다. 이웃 두 줄이 반대로 기울면 줄 끝에서 서로 다가온다. 단순 모형(줄 길이는 6.6의 낱말·글자 분포, 폭 515 pt에서 자름, 글자 상자 높이 최대 1.31·H)으로 이웃 줄 쌍 2만 개를 셈하니, 글자 상자가 닿을 만큼 가까워지는 쌍이 11~15%, 알고리즘 4단계의 '세로 겹침 ≥ 0.5'를 넘는(= 두 줄이 합쳐질) 쌍이 회전 중심을 줄 가운데에 두면 0.3%, 줄 시작에 두면 3.4%였다 [추정 — 단순 모형]. 뒤쪽이면 12줄 페이지에서 합쳐짐이 한 번 이상 날 확률이 약 30%이고, 200쪽 중 한 쪽이라도 두 번 합쳐지면 '페이지마다 줄 수 차 ≤ 1'이 깨진다. 실제 필기는 한 페이지 안의 줄이 대개 비슷하게 기운다.
  - 그래서 지금 명세로는 (a) 알고리즘이 맞아도 생성기 탓에 떨어지거나, (b) 생성기 특성에 맞춘 문턱 조정이 일어나 실기기에서 나빠질 수 있다. '획 단위 정확도'의 정의(다수 정답 줄)도 줄이 합쳐졌을 때 어느 쪽을 정답으로 보는지 정하지 않았다.
- **고칠 방향**:
  1. 생성기 명세를 좁힌다 — 페이지 공통 기울기 θ_p ∈ [−4°, +4°] + 줄마다 ±1° 정도, 회전 중심은 줄 가운데, 이웃 줄 글자 상자 사이 세로 틈 ≥ 0.25·H를 보장(어기면 그 줄을 다시 뽑음). '촘촘한 줄 간격'·'서로 다른 기울기'는 경계 사례(손으로 만든 고정 자료)로 따로 둔다.
  2. 기반 단계 R2-B6 전(또는 L2-05 첫 단계)에 도형처럼 컨테이너 실험(`library57/lines/`)으로 정확도·줄 수 차 분포를 재고 7.3에 E-L5로 남긴다. 결과가 95%에 못 미치면 문턱 조정 근거와 함께 V9 문구 변경을 12.1에 올린다.
  3. 정확도 정의를 '정답 줄마다 그 줄 획이 가장 많이 간 출력 줄 = 그 줄의 짝(일대일), 짝이 아닌 줄로 간 획 = 틀림'처럼 계산법까지 적는다.

---

## 권장 (고치면 좋은 것)

### S-1. 색인기 페이지 작업의 UI 스레드 비용 — G-2 '방해하지 않음'

- **위치**: 6.9.3(1490행 `loadPage` → 모든 획 점 디코드 → `sourceRevOf` → `groupIntoLines`), 6.9.7(1544행 '1,000획 ≤ 60 ms'), 6.24.
- **문제**: 사용자가 3초 쉴 때마다 지금 페이지에서 이 작업이 돈다. 60 ms(VM 목표 — 태블릿에서는 더 김)는 UI 아이솔레이트에서 3~4프레임이고, 바로 그때 다시 쓰기 시작하면 첫 획이 늦는다(PLAN 5.4 지연 20 ms). 또 '신선한지'를 알려고 매번 전체를 디코드한다.
- **고칠 방향**: ① 먼저 `stalePages(noteId)`(점 디코드 없음 — 02-core 6.9.3)로 그 페이지가 낡았을 때만 `loadPage`, ② 줄 나누기·`HandwritingTrace` 변환을 줄 단위로 쪼개 사이마다 양보하거나 네이티브에서 `compute`로(웹에서는 색인기가 돌지 않으니 문제없음), ③ A-L3에 '3초 쉰 직후 다시 쓸 때 끊김 없음'을 명시하고 개발자 표시에 작업 시간(ms)을 넣는다.

### S-2. 확정 줄을 너무 쉽게 버린다

- **위치**: 6.9.4 표 둘째 행(1518행 — 획 집합이 조금이라도 다르면 확정 줄을 버림).
- **문제**: 마침표 하나, i의 점 하나를 더 찍거나 부분 지우개로 한 획을 다듬어도 사용자가 고친 글이 사라지고 엔진 글로 바뀐다. 계약 주석('auto re-recognition keeps it')보다 훨씬 좁다.
- **고칠 방향**: 옛 획 id의 대부분(예: ≥ 80%)이 새 줄에 남고 새 획이 작은 상자뿐이면 확정 글을 유지하되 `userConfirmed`는 그대로, 그보다 많이 바뀌면 엔진 글로 바꾸되 옛 확정 글을 `alternatives` 맨 앞에 둔다(검색에는 남지 않지만 변환 창에서 되살릴 수 있음). 규칙을 계약 주석으로 올린다(C-3).

### S-3. 엔진 id가 다르면 다시 인식하는 규칙 — 기기 간 이중 인식

- **위치**: 6.9.3 `existing.engineId == engine`(1496행), 6.7.2 엔진 id(안드로이드 `'mlkit-digital-ink/19.0.0'`, iOS `'mlkit-digital-ink-ios/9.0.0'`, 1401행).
- **문제**: `HandwritingText`는 동기화 엔티티다. 실연결 뒤 안드로이드와 iPad 네이티브가 모두 자동 인식을 켜면, 한 기기가 쓴 페이지마다 다른 기기가 '엔진이 다르다'며 다시 인식해 덮어쓴다(획마다 두 번 인식·두 번 업로드, 마지막에 쓴 기기가 이김). 지금은 영향이 없지만 형식·규칙은 실연결 전에 정하는 것이 싸다(계약 3.3 3번과 같은 이유).
- **고칠 방향**: '신선함'을 `sourceRev`와 **언어 꼬리(`:ko`)**로만 판정하고 엔진 판·기기 차이는 무시한다(다른 기기 결과도 신선). 사용자가 언어를 바꾼 경우만 다시 인식. SYNC에 알린다(X-3).

### S-4. 복사 경로·색인기가 커밋 전 획을 못 본다 — `flush` 먼저

- **위치**: 6.13.5 2~3단계(1737–1738행 '그 페이지의 현재 입력 획과 기존 결과를 읽어'), 6.9.3 `loadPage`.
- **문제**: `NoteContentReader.loadPage`는 '커밋된 상태(먼저 `NoteStore.flush()`)'다(1차 `content_reader.dart` 9행). 방금 쓴 획을 고르고 바로 '텍스트 복사'를 누르면 선택 획(세션 메모리)은 있는데 `loadPage`에는 없어 '변환한 획이 입력 획 전부인가'를 틀리게 판정하고 `sourceRev`를 잘못 넣는다.
- **고칠 방향**: 복사 경로는 `await store.flush()` 뒤 `loadPage`. 색인기는 3초 조용해진 뒤라 대개 커밋돼 있지만 같은 한 줄을 넣는다. 시험: '쓰자마자 복사 → `sourceRev` 맞음'.

### S-5. '노트 내용' 묶음의 휴지통 판정이 1차 코드와 다르다

- **위치**: 6.1.3 노트 머리(1244행 '`noteProvider(noteId)`가 `null`(그 사이 휴지통·영구 삭제)이면 묶음 전체를 숨긴다'), 8.2 L2-02 '노트가 휴지통으로 → 묶음 숨김'(2053행).
- **문제**: 1차 `watchNote`는 휴지통 노트도 `deletedAt`이 찬 채로 돌려준다(`fake_note_store.dart` 635–638행, `drift_library_repository.dart` 292–298행 — `null`은 행이 없을 때뿐). 그래서 휴지통으로 간 노트는 숨겨지지 않는다(`note` 변경의 즉시 재질의가 곧 지우긴 하지만 시험 문장과 다르다).
- **고칠 방향**: `note == null || note.isDeleted`로 숨기고, 휴지통에 든 폴더 안의 노트는 CORE 재질의에 맡긴다고 적는다.

### S-6. 에뮬레이터 시험(L2-21) — 장소·시점·단언

- **위치**: 6.11.7(1664–1669행), 8.2 L2-21(2072행 '완료 판정은 CI `functions` 잡 통과', 선행 'SYNC `functions/` 골격'), 5.6 끝 '[추측]'(1162행).
- **문제**:
  - 이 컨테이너에서 Functions + Auth 에뮬레이터와 Dart `package:http` 호출이 실제로 돌았다(조사 04 6.4, 07-sync 6.8.11 [확인]). 계약 7.7.2 V13은 '컨테이너 검증 기준'이고 7.7.1 8단계도 `-t emulator`를 컨테이너에서 돌린다. 완료 판정을 CI에만 두면 원칙('컨테이너에서 실행 가능한 시험으로 완료 판정')과 어긋난다(계약 자체도 7.4.6과 다름 — C-1).
  - 기반 단계 R2-B7의 `functions/` 골격은 '가짜 엔진·단위 시험 1개'뿐이고, 로그인 필수·`OWNER_UIDS`·오류 표는 SYNC 동시 개발 몫이다. LIBRARY 작업 트리에는 통합 3단계(SYNC 병합) 전까지 시험할 함수가 없다 — '골격 뒤 언제든'이 아니다.
  - SYNC는 가짜 엔진 출력을 결정적으로 정했고(07-sync D-S7·6.8.5 — 획 2개·점 5개 → `\frac{2}{5}`, PNG만 → `\sqrt{B}`, `engine: 'gemini'` → `UNAVAILABLE`) 'LIBRARY Dart 시험이 같은 값을 단언한다'고 적었다. 6.11.7 경우 목록에는 값이 없다.
  - callable 오류 형식은 조사 04(Dart 클라이언트로 `{error: {… UNAUTHENTICATED}}` 확인)와 07-sync 6.8.11에서 확인됐다 — '[추측]' 표시를 '확인'으로 바꿔도 된다.
- **고칠 방향**: L2-21을 8.3 통합 몫(L2-I6, 3단계 뒤)으로 옮기고, 완료 조건을 '컨테이너에서 `firebase emulators:exec --only functions,auth --project demo-noteapp "dart run tool/ws.dart test --run-skipped -t emulator"`(전역 잠금) 통과 + CI 반복'으로 한다. 경우 목록에 07-sync E1~E9 값(특히 E5·E6·E7·E8)을 그대로 적는다.

### S-7. L2-I3 'INK 시험이 `GeometricShapeFitter`를 override'는 의존 방향상 쓸 수 없다

- **위치**: 8.3 L2-I3(2082행).
- **문제**: `ink_recognition` → `ink_engine` 의존이므로 INK 패키지 시험이 `ink_recognition`을 import할 수 없다(계약 7.1·INFRA R8). 03-ink I-4도 같은 흐름을 기대하는데 둘 다 상대에게 미루고 있다.
- **고칠 방향**: LIBRARY가 `ink_recognition/test/integration/shape_assist_flow_test.dart`를 쓴다 — INK `testing.dart` v2의 `createTestPageController(shapeFitter: const GeometricShapeFitter())`(03-ink 4.12)로 합성 사각형·원 획을 500 ms 멈춤과 함께 넣어 `shapePreview` → `end()` → `InkEdit(addShape)`·`kind`를 단언. INK에 알린다(X-2).

### S-8. 작업 분해 — 한 세션에 넘치는 작업

- **위치**: 8.2 L2-10(2061행 — 일정·페이지 작업·줄 재사용·확정 줄·따라잡기·수명주기·오류 + 시험 3파일, 단언 20여 개), L2-17(2068행 — 임시 페이지 캔버스·포인터·지우개·되돌리기·1초 타이머·취소·동의 카드 + `recog.toMath` 전부), L2-15(2066행).
- **고칠 방향**: L2-10을 (a) 일정·페이지 작업·오류·`status`와 (b) 줄 재사용·확정 줄(M-1 포함)·따라잡기·수명주기로, L2-17을 (a) 패드 손글씨 칸·1초 멈춤·취소·동의 카드와 (b) `recog.toMath`로 나눈다. 의존 사슬(8.2 끝 문단)도 그에 맞춘다.

### S-9. 안드로이드 'Wi-Fi에서만'에서 셀룰러면 '받는 중…'이 끝나지 않는다

- **위치**: 6.7.4(1439행), 6.13.1 모델 카드(1695행), 6.18 모델 행.
- **문제**: commons 플러그인은 `DownloadConditions.requireWifi()`로 받기를 걸고(`GenericModelManager.kt` 41행) Task가 Wi-Fi가 될 때까지 끝나지 않는다. 색인기에는 의도대로지만, 사용자가 변환 창·설정에서 [받기]를 누르면 이유 없이 '받는 중…'이 이어진다.
- **고칠 방향**: 사용자가 누른 받기는 '와이파이에 연결되면 받아요' 안내 + [지금 셀룰러로 받기](두 번 누르기, 6.12 규칙)로 `wifiOnly: false` 경로를 준다. 색인기의 `waitingModel`에도 이유(Wi-Fi 대기)를 상태에 남긴다.

### S-10. A-4는 영어 모델도 있어야 한다

- **위치**: 6.20(1924행 — 같은 획을 `ko`·`en`·전략 B로 인식), 9.4 A-4(2157행 — '한국어 모델 [받기]'만).
- **고칠 방향**: 실험 창이 열릴 때 `ko`·`en` 모델 상태를 보이고 없으면 받게 한다. A-4 절차에 'English 모델도 받기(크기 기록)'를 더한다. 그렇지 않으면 첫 실험에서 `en`·B 열이 전부 `ModelNotReady`가 된다.

### S-11. 취소가 '오프라인'으로 바뀔 수 있다 — 예외 잡는 순서

- **위치**: 6.11.2 끝(1617행), 6.11.4 표(1647행 '연결 실패(`http.ClientException`) → `RecognizerOffline`').
- **문제**: `RequestAbortedException extends ClientException`이다(`http-1.6.0/lib/src/abortable.dart` 40행). `ClientException`을 먼저 잡으면 패드에서 펜을 다시 댈 때마다 '서버에 연결할 수 없어요'가 뜬다.
- **고칠 방향**: `RequestAbortedException` → `RecognizerCancelled`를 먼저 잡는다고 6.11.4에 적고, `callable_math_recognizer_test`에 '실제 `AbortableRequest` 취소 → `RecognizerCancelled`(오프라인 아님)'를 더한다.

### S-12. iPad Safari 클립보드 — 선택 메뉴에서 바로 복사

- **위치**: 6.13.6(1745행 — 획 없이 수식·텍스트 상자 하나면 시트 없이 바로 `Clipboard.setData`), 11절 위험 14(2211행 '단추 누름 처리 안에서 바로 부름'), 9.4 B-11(2169행 '텍스트 복사(LaTeX) → 메모에 붙여넣기').
- **문제**: 이 경로의 `run`은 EDITOR `ExtensionRunner`가 **메뉴가 닫힌 뒤** `await`로 부른다(04-editor 4.3.1). LIBRARY가 '단추 누름 안'을 보장할 수 없다. Safari의 `navigator.clipboard.writeText`가 사용자 동작 활성화를 잃으면 실패한다 [추측 — editor 검토 S-6이 이미지 선택에 같은 우려].
- **고칠 방향**: (a) EDITOR와 '확장 항목 `onSelected`는 누름 처리에서 동기적으로 시작'을 합의하거나(X-1), (b) 웹에서는 바로 복사 대신 LaTeX 편집 창을 열고 창 안 [LaTeX 복사] 단추로 복사한다(창 안 누름이라 활성화가 확실). B-11에 '선택 메뉴 경로로 복사 → 붙여넣기 됨'을 명시해 확인한다.

### S-13. 검색 재질의 디바운스 의미

- **위치**: 6.1.6(1279행 '1초 디바운스 … 몰려도 질의 1회').
- **문제**: 따라잡기 중 색인기가 1초보다 자주 `put`하면, 타이머를 매번 다시 거는 디바운스는 따라잡기가 끝날 때까지 결과를 안 바꾸고, 고정 주기면 매초 다시 묻는다. 어느 쪽인지, 다시 묻는 동안 이전 결과를 유지하는지(깜빡임·스크롤 위치·펼친 노트) 적혀 있지 않다.
- **고칠 방향**: '마지막 변경 1초 뒤, 최대 대기 5초'처럼 상한을 두고, 다시 묻는 동안 이전 결과·스크롤·펼침을 유지한다고 적고 시험에 넣는다.

### S-14. 작은 것들

- 5.8 INK 행(1178행) 'R2-B3 `MathPreview`는 래스터 없이 상자' → 03-ink 4.13 표는 R2-B3에서 `MathPreview`를 **실제 동작**(`Math.tex`)으로 둔다(상자는 페이지 위 `MathObject` 렌더). 패드 시험에서 미리보기를 실제로 단언할 수 있다.
- 계약은 `RecognitionSettingsSection extends ConsumerWidget`(const)이다. 두 번 누르기·받기 진행 같은 상태는 내부 private `StatefulWidget`에 둔다고 6.18에 적는다.
- `unit/shape_real_samples_test.dart`(279행)는 파일을 읽으므로 `@TestOn('vm')`을 단다.
- 10절 6번 '실기기 … (완료 판정)'은 계약 5장('완료 판정은 컨테이너 시험, 실기기는 합격 판정')과 표현이 다르다 — '합격 확인'으로.
- 6.7.3 표에 안드로이드 `'Model download check failed'`(인식 전 모델 확인 실패, `DigitalInkRecognizer.kt` 68행)를 행으로 더한다(지금은 '그 밖'으로 감).
- ML Kit 점수는 플러그인이 없으면 `0.0`을 채운다 — `TextCandidate.score`를 그대로 넘기되 '0.0은 없음일 수 있음'을 주석으로.
- 6.4·6.7.2 `writingAreaPt`(페이지 폭 × 줄 높이 1.5)와 획 좌표(페이지 절대 pt, 예 y=700)의 기준이 다르다. ML Kit이 쓰기 영역을 크기 추정에만 쓰는지 확인되지 않았으므로 [추측], 줄 획을 줄 상자 왼쪽 위 기준으로 옮겨 보내는 쪽이 안전하다(A-4에서 두 방식을 비교해도 좋다).
- 엔진 id 문자열(`19.0.0`·`9.0.0`)은 플러그인 판을 올릴 때 함께 바꿔야 한다 — 상수 한 곳 + README 한 줄.

---

## 다른 영역과 걸리는 것

### X-1. EDITOR — 넘기는 `context`, 사용자 동작 활성화, 도형 표본 형식

- `RecognitionAction.run(context, …)`은 그 `context`로 `ProviderScope.containerOf`·`showModalBottomSheet`·`ScaffoldMessenger.maybeOf`를 부른다(6.3·6.12·6.13.6). 04-editor는 어느 `BuildContext`를 넘기는지 적지 않았다 — 메뉴 항목 context는 메뉴가 닫히면 unmounted다. '에디터 본문(`EditorBody`)의 context'라고 EDITOR 4.3.1에 적어 달라고 요청한다(editor 검토 S-6·X-5와 같은 결론).
- S-12: 확장 항목을 누름 처리에서 동기적으로 시작하는지 합의.
- 도형 표본: EDITOR 개발자 메뉴의 `Stroke.toJson()`(점은 base64 — `stroke.dart` 149행, `kind`·`viewScale` 없음)과 LIBRARY 형식 `{kind, points, viewScale}`(6.17.3 끝)이 다르고, 자동 보정으로 바뀐 획은 저장되지 않는다. editor 검토 S-5·X-6대로 EDITOR가 링 버퍼 → LIBRARY 형식으로 내도록 맞춘다(12.2 Q7의 답).
- CP-L3·CP-L5는 04-editor 6.7.4와 같은 내용이라 EDITOR가 지지할 것이다.

### X-2. INK — 통합 시험 위치, `MathPreview` 상태

S-7: 도형 보정 흐름 시험은 `ink_recognition` 쪽에 둔다(INK `createTestPageController(shapeFitter:)` 사용). 03-ink I-4 문구를 'LIBRARY 시험이 INK 시험 도우미로'로 고치게 알린다. S-14 첫 항목(`MathPreview`는 R2-B3 실제 동작)도 확인 차 알린다.

### X-3. SYNC — 가짜 엔진 값, 에뮬레이터 시점, 기기 간 결과

- S-6: Dart 에뮬레이터 시험이 07-sync E1~E9의 값을 그대로 단언한다. L2-21은 SYNC 병합(통합 3단계) 뒤에 돈다.
- S-3: 손글씨 결과는 노트 범위 동기화 기록이고 '병합 단위 하나 `{engineId, sourceRev, lines}`'(02-core 5.6 표)라 마지막 쓰기가 이긴다. 엔진 id가 다른 기기 결과를 '신선'으로 보는 규칙에 SYNC가 동의하는지 확인한다(실연결 미니 라운드 전).

### X-4. CORE — 명령 모양, 낡은 노트 질의, `flush`

- CP-1: core 검토 C-1이 '`RemoveElements.elementIds`는 `Set` 유지'를 권했다. LIBRARY는 `object_builders.dart` 한 곳에서만 명령을 만들므로 어느 쪽이든 고칠 곳이 하나다 — 그대로 좋다.
- 12.2 Q8 `notesWithStalePages()`: core 검토 X-2·S-10이 '`pages.ink_rev` 캐시로 한 질의'가 가능하다고 했다. 폴더 2,000개 따라잡기(6.9.5) 비용을 생각하면 이번 라운드 '추가'로 요청할 가치가 있다(INFRA 유휴 시간에 도는 일이라 첫 실행이 짧을수록 좋다).
- S-4: `NoteStore.flush()` 뒤 `loadPage` — CORE 변경 없음, 확인만.

### X-5. INFRA — 색인기 시험 이음새, 스모크의 자동 도형 획

- infra 검토 M-2: `HandwritingIndexer`가 `final class`라 INFRA는 provider override로 가짜 색인기를 넣을 수 없다. LIBRARY는 계약 그대로 두고, INFRA 이음새(유휴 작업에 주입하는 `start`/`dispose` 함수)를 받아들인다고 5.9에 적는다. LIBRARY 쪽 '두 번 `dispose` 안전'(R-3) 시험은 그대로.
- V5 2단계 '합성 멈춤으로 자동 도형'은 실제 `GeometricShapeFitter`를 거친다. INFRA가 쓸 '반드시 사각형으로 판정되는' 합성 획을 `testing.dart`에 `SyntheticShapes.rectangle(...)`(추가 — CP-L4와 같은 묶음)으로 주면 스모크가 문턱값 조정(U18)에 흔들리지 않는다.

---

## 계약 문제

- **C-1** (7.4.6 vs 7.7.1·7.7.2 V13): 7.4.6은 `emulator` 태그를 'CI `functions` 잡에서만'이라 하고, 7.7.1 8단계·V13은 컨테이너 검증 기준으로 `-t emulator`를 돌린다. 조사 04 6.4·07-sync 6.8.11이 컨테이너 실행을 확인했으므로 '컨테이너에서 전역 잠금으로 돌리고 CI에서 반복'으로 맞춘다(S-6).
- **C-2** (7.4.6 '플러그인 가짜' 행): 'LIBRARY 시험은 … 플러그인 채널을 건드리지 않음'인데 ML Kit 어댑터 자체 시험(`test/native/mlkit_adapter_test.dart`)은 메서드 채널 가짜를 건다. 어댑터를 시험할 다른 길이 없으므로 '서비스 패키지의 플러그인 어댑터 자체 시험은 메서드 채널 가짜 허용'을 예외로 적는다.
- **C-3** (7.2.5 `userConfirmed` 주석 · G-2): '자동 재인식이 유지한다'의 구체 규칙(S-2)과 '색인기는 `put` 직전 최신 값과 병합한다(작업 중 들어온 `handwriting` 쓰기를 덮지 않음)'(M-1)을 계약 문장으로 넣는다. 변환 창·색인기·원격 적용 세 쓰기 주체가 같은 엔티티를 쓴다.
- **C-4** (7.2.11 `HandwritingIndexer` 주석): '3 s'만 있고 원격 30 s·엔진 id 비교(S-3)는 LIBRARY 세부다. 기기 간 동작에 영향이 있으므로 신선함 판정(`sourceRev` + 언어)을 주석에 올린다.
- **C-5** (7.2.11 `ensureModel` 주석 'iOS: app checks connectivity itself'): 계획은 연결 확인 대신 '두 번 누르기 경고'다(12.2 Q2). Q2가 승인되면 주석을 'iOS: app asks before downloading (plugin ignores wifiOnly)'로 고친다.
- **C-6** (7.4.4): '인식 켜기(synced)' 키가 이름 없이 scope만 있다 — CP-L9(키 4개 확정, 별도 '인식 켜기' 없음)를 받아들인다.
- **C-7** (7.6 `SyntheticHandwriting` 주석 'lines / words'): 시그니처는 `lines`뿐이다. 'words'를 지우거나 `words(...)` 시그니처를 더한다.
- **C-8** (7.2.10 / X30): `EditorSelectionMenuItem.onSelected`·`EditorInsertMenuItem.onSelected`에 넘기는 `context`의 수명이 계약에 없다(X-1). '항목이 끝날 때까지 mounted인 에디터 본문 context'를 한 줄 넣는다.
- 12.1 제안에 대한 의견: CP-L1·L2·L3·L4·L5·L7·L8·L9 지지(SYNC는 CP-L8을, INFRA는 CP-L1~L3을 이미 받아들임). CP-L6은 S-12 (b)를 택하면 '웹에서는 창 경유'를 덧붙인다. CP-L10(`foreground` 주입)은 G-2 시험을 순수 단위 시험으로 만들어 주므로 받아들이기를 권한다 — '추가'이고 소비자가 없다.

---

## 질문

1. M-1에서 '작업 중 `handwriting` 변경 → 작업 버림'과 '`put` 직전 재읽기·재병합' 중 하나만 한다면 어느 쪽인가? (검토자는 둘 다 권한다 — 앞의 것만으로는 `put` 직전 경합이 남는다.)
2. S-3: 다른 기기·다른 엔진 판의 결과를 신선하게 볼 것인가, 아니면 '내 기기 엔진이 낫다'는 가정으로 다시 인식할 것인가? 후자라면 실연결 뒤 이중 인식을 받아들이는 것이다.
3. S-12: 웹에서 수식·텍스트 상자 '텍스트 복사'를 창 경유(b)로 바꿔도 되는가? 그러면 B-11 절차가 '선택 › 텍스트 복사 → 창의 [LaTeX 복사]'로 한 단계 는다.
4. M-2의 실험 결과가 95%에 못 미치면 V9 줄 나누기 문턱(계약)을 낮출 것인가, 생성기를 더 좁힐 것인가?
