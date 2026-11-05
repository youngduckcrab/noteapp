# PDF 2차 계획서 검토 — `06-pdf.md`

> 검토자: 총괄 대리 검토자 · 검토일 2026-11-05
> 대상: [06-pdf.md](../06-pdf.md)(2,513줄, 초안) — PDF · 미디어 입출력 (`pdf_io` 확장 + `media_io` 새 패키지)
> 기준: 개요 [00-overview.md](../00-overview.md) 7장 통합 계약 v2.0 초안, 조사 01~04, PLAN.md(F-13·F-15·F-16, 5.1·5.2, 10장 M5~M7), 1차 PDF 작업 트리 `/home/user/wt/pdf`(`98c193c`)와 1차 통합이 들어간 `/home/user/noteapp`(`9305235` pdf 통합 커밋 포함), 다른 영역 계획서 01~05·07의 맞닿은 절(grep)
> 확인 방법: 계획서 전 절을 읽고, 계약 블록을 개요 원문과 `diff`로 대조하고(7.2.4·7.2.9·7.2.12 — 글자 그대로 맞음), 1차 코드·pub 캐시(`record 7.1.2`·`record_platform_interface 2.1.0`·`record_web 2.1.3`·`just_audio 0.10.6`·`audio_session 0.2.4`·`flutter_foreground_task 11.0.3`·`plugin_platform_interface 2.1.8`)·pub.dev API로 사실을 확인했다. 분석기 동작 하나는 `/tmp/claude-0/plan57-scratch/rv-pdf/vft/`에서 작은 패키지로 실험했다. 무거운 시험은 돌리지 않았다.

---

## 총평

계약 7.2.12를 정확히 옮기고(원문 대조 결과 차이 없음), 1차 코드와 PDFium 동작을 실험으로 먼저 확인한 뒤 설계한 좋은 계획서다. 특히 좋은 점:

- **사전 검증이 실제로 되어 있다**: CID 글꼴 넣기 후 한글 텍스트 추출, 부분 집합 밖 글자가 조용히 빠지는 현상(E2 — 래스터 대체 규칙의 근거), JPEG inline·BGRA 알파 SMask, 같은 페이지 두 번 덧붙이기(E4), pdfrx 워커의 `addFunction`·wasm export 표(E5·E6). 1차 코드 이름(`pdfImportJobProvider`·`pdfRenderStatsProvider.queued/inflight`·`PdfEngineDocument.loadText`·`PdfPageTextData.charRects`·`PdfNoteGateway.readAssetBytes`·`AssetStore.bytesArrived`·`listAssets(hasLocalBytes:)`·`debugNativeComposeJobCount`·`PdfComposeOpcodes` 8·9 미사용)도 내가 다시 본 것이 모두 맞았다.
- **외부 패키지 API가 정확하다**: `RecordConfig(audioInterruption: AudioInterruptionMode.pause)`, `IosAudioCategoryOption.allowBluetoothA2DP`, `AudioRecorder.ios?.manageAudioSession`, `setOnConfigChanged`, `ForegroundTaskOptions.stopWithTask`·`allowAutoRestart`, `startService(serviceTypes:, callback:)`, `AVAudioSessionCategoryOptions.allowBluetoothA2dp`, `RecordPluginWeb.registerWith`·`JustAudioPlugin.registerWith`를 pub 캐시에서 확인했다. 추가 직접 의존 7개의 판·게시일도 pub.dev와 같다.
- **녹음은 잃지 않는 것이 먼저**라는 원칙을 상태 기계·M-1 순서·저장 실패 시 초안 유지·`createRecording` 멱등 복구·'#0 마지막' 색인 완료 표시처럼 구체적인 규칙으로 내렸고, 플랫폼 코드를 `RecorderEngine` 포트 뒤로 모아 VM 가짜 엔진으로 상태 전이를 시험하는 구조가 깔끔하다.
- 계약 안의 문장 충돌(M-2 '묻는다' ↔ 7.2.12 '묻지 않고')을 스스로 찾아 CP-PDF-4로 올렸다.

그러나 **그대로 승인할 수 없다(revise)**. 가장 큰 문제는 ① `testing.dart`의 가짜 플랫폼 세 개가 `MockPlatformInterfaceMixin`을 `lib/`에서 써서 워크스페이스 분석기 설정상 **오류**(V2 실패)라는 점, ② 수식 래스터·INK 벡터 v2가 INK T36·T42 전에는 비어 있어 **T24·T25의 완료 조건을 동시 개발 중에 판정할 수 없다**는 점, ③ 텍스트·수식 래스터가 계약 메모리 예산(이미지 임시 16 MB)을 크게 넘을 수 있다는 점, ④ 재구축 도중 색인 중인 에셋이 '완료'로 표시되어 **검색 결과가 영구히 빠지는** 경로, ⑤ 두 번째 탭(또는 같은 기기의 다른 창)이 진행 중인 녹음 초안을 복구·삭제해 **녹음을 잃는** 경로, ⑥ Chrome WebM의 길이를 시계 값으로 패치해 R-3·V8이 **스스로를 재는 시험**이 된다는 점, ⑦ 긴 웹 녹음의 정지·복구 때 같은 바이트를 여러 벌 들고 있어 iPad Safari 예산을 넘고 복구가 매 실행 반복될 수 있다는 점, ⑧ 정지 직후·패널 열기 때 녹음을 열어 두는 동작이 EDITOR 기본 강조 방식과 만나 **방금 쓴 필기가 모두 흐려지는** 점이다.

---

## 반드시 고칠 것

### M-1. `testing.dart` 가짜 플랫폼이 `MockPlatformInterfaceMixin`을 써서 분석 오류가 난다

- **위치**: 4.3.2 `FakeRecordPlatform`·`FakeJustAudioPlatform`·`FakeImagePickerPlatform` 선언(747·758·768행), 3.4 pubspec `plugin_platform_interface: 2.1.8`(291행), 7.2 표·CP-PDF-9.
- **문제**: `MockPlatformInterfaceMixin`은 `plugin_platform_interface 2.1.8`에서 `@visibleForTesting`이다(pub 캐시 126행). `lib/testing.dart`는 시험 디렉터리가 아니므로 분석기가 `invalid_use_of_visible_for_testing_member`를 내고, 워크스페이스 `analysis_options.yaml`은 이 진단을 **`error`**로 올려 두었다(1차 모든 작업 트리 16행). 작은 패키지로 재현했다 — `class FakeA extends RecordPlatform with MockPlatformInterfaceMixin`이 `lib/`에서 경고(워크스페이스 설정이면 오류)를 낸다. `flutter analyze --fatal-infos`(V2)·T30 완료 조건이 막힌다.
- **고칠 방향**: 세 가짜는 `extends RecordPlatform`/`JustAudioPlatform`/`ImagePickerPlatform`만 한다 — 이 클래스들의 생성자가 `super(token: _token)`을 넘기므로 `instance` 설정의 토큰 검사를 그대로 통과한다(1차 `ScriptedFilePicker extends FilePickerPlatform`과 같은 방식). 믹스인과 `plugin_platform_interface` 직접 의존을 빼고 CP-PDF-9를 6개로 줄인다(X-2).

### M-2. INK 진행에 묶인 완료 조건 — 수식 래스터·벡터 v2가 동시 개발 중에 비어 있다

- **위치**: 5.2 '동시 개발 중 INK 가짜' 표(1369행 '`InkMathRenderer.rasterize`·`InkFonts`는 R2-B3부터 실제 동작'), 5.2 끝 문단(1373행), T24·T25 완료 조건(2232·2233행).
- **문제**:
  - 03-ink 4.13 기반 단계 표는 `InkMathRenderer.rasterize` = **`null`**(최종은 INK T36)이다(03-ink 780행, T26 '`rasterize` → `null`'). 계획서의 '`rasterize`는 R2-B3부터 실제'는 틀렸다. 그러면 T25의 `web/object_resolver_browser_test`('수식 래스터가 Chrome에서 비어 있지 않음')와 해석기 수식 경로 시험은 INK T36 전에는 통과할 수 없고, 모든 수식이 '그리지 못함' 경고로 빠진다.
  - `InkPageVectors.underlay/annotations/cover`는 INK T42까지 빈 목록이고, `InkFillShape`는 1차에서 `_` 생성자다(확인 — `vector_export.dart` 67행). 03-ink 4.12 `testing.dart` v2에도 벡터 값을 만드는 도우미가 없다. 그래서 T24 `object_vectorizer_test`의 '손으로 만든 v2 벡터' 길은 없고, `BoxInkVectorizer`로 바꾸면 T24가 만드는 코드(`InkEngineVectorizer.planPage`의 `InkPageVectors` → `PdfPagePlan` 변환)를 하나도 시험하지 않는다. INK T42는 INK 작업 순서의 끝 무리(03-ink 1801행)라 PDF 핵심 변환이 통합 직전까지 시험되지 않는다.
- **고칠 방향**: ① 해석기에 내부 포트 `PdfMathRasterizer`(기본 = `ink.InkMathRenderer`)와 `PdfTextRasterizer`를 두고, T25 단위·Chrome 시험은 가짜 래스터(단색 RGBA)로 판정한다. 실제 INK 래스터 단언은 `integration`(INK T36 뒤 켬)으로 옮긴다. ② T24는 `InkPageVectors`를 직접 받지 말고 PDF 쪽 중간 표현(층별 목록 — `underlay`·`highlighter`·`ink`·`annotations`·`cover`)으로 한 번 옮긴 뒤 `PdfPagePlan`을 만드는 순수 함수로 나눠, 순수 함수는 손으로 만든 중간 표현으로 VM에서 시험하고 INK 값 → 중간 표현 한 겹만 `integration`에 둔다. ③ 동시에 INK에 `testing.dart` v2 생성 도우미(`InkPageVectors`·`InkFillShape`·`InkImageVector`·`InkTextVector`·`InkTextLine`·`InkMathVector` 시험용 생성자)를 R2-B3에 넣어 달라고 요청한다(X-1). 5.2 표의 '실제 동작' 문구를 고친다.

### M-3. 텍스트·수식 래스터와 동기화로 온 큰 이미지가 '이미지 임시 16 MB' 예산을 넘는다

- **위치**: 4.5.1 `maxRasterLongSidePx 4096`·`exportImageTempBytes`, 6.2.4 표 `PdfAssetImageRef` '그 밖 → 엔진 디코드'(1542행)·`PdfMathRef`(1543행), 6.2.5 래스터 대체(1555행), 6.2.10 '이미지 임시 16 MB'(1603행).
- **문제**: 래스터 상한이 **긴 변 4096 px**뿐이다. 쪽 하나를 채우는 텍스트 상자(500 × 700 pt)를 300 dpi로 그리면 2083 × 2917 px ≈ 24 MiB, 정사각에 가까운 큰 수식 frame은 4096² ≈ 64 MiB RGBA다. 부분 집합 밖 글자 하나(한자 등 — E2)나 글꼴 적재 실패만으로 이 길에 들어선다. 또 `media_io`를 거치지 않고 동기화로 온 이미지(다른 기기·다른 판)는 크기 제한 없이 원본 해상도로 디코드한다(6000 × 4000 PNG ≈ 96 MiB). 계약 7.4.5의 '이미지 객체 임시 16 MB'와 계획서 6.2.10의 '하나가 최대 16 MiB'라는 전제가 깨지고, 웹 워커 wasm 메모리도 그만큼 커진다. T26의 '동시 디코드 ≤ 16 MiB 계측' 시험은 작은 표본만 써서 이를 잡지 못한다.
- **고칠 방향**: 래스터·디코드 모두 **픽셀 수 상한**(예: 4 Mpx = 16 MiB RGBA)으로 자른다 — 텍스트·수식은 dpi를 frame 크기에 따라 낮추고(300 dpi는 상한 안에서만), 엔진 디코드는 `instantiateImageCodec(targetWidth/targetHeight)`로 긴 변 2048(M-3 값)에 맞춘다. 상수는 `PdfTuning` 한 곳. T25·T26에 '쪽 크기 텍스트 상자 래스터', '6000 × 4000 PNG 에셋', '큰 수식 frame' 표본을 더해 16 MiB 계측 훅으로 단언한다. INK `rasterize`의 상한도 같은 규칙이어야 하므로 X-1·C-5로 올린다.

### M-4. 재구축 도중 색인 중인 에셋이 '완료'로 표시되어 결과가 영구히 빠진다

- **위치**: 6.4.2 의사 코드(1628·1643행)와 '#0 마지막' 문단(1652행), 4.1.1 `start()` 주석(402행), T27.
- **문제**: CORE `rebuild({pdf})`는 쓰기 큐 작업으로 pdf 단위·소유자를 **지우기만** 한다(02-core 6.10.5). 색인기가 에셋 A의 쪽 1..k를 쓴 뒤 재구축이 그것을 지우면, 색인기는 계획대로 k+1..n−1과 `#0`을 마저 쓴다. `rebuilding`이 false로 돌아와 따라잡기를 해도 `A#0`이 현재 `sourceRev`라 A를 건너뛴다 → 쪽 1..k는 **다시 색인되지 않는다**(조용한 검색 누락). 정규화 판이 바뀐 첫 실행에서는 재구축이 '예약'만 되고(열기를 막지 않음) 색인기가 3초 뒤 시작하므로 실제로 겹칠 수 있다.
- **고칠 방향**: 게이트 조건에 `!status.rebuilding`을 더하고, `rebuilding`이 true가 되는 순간 진행 중 작업을 멈추고 큐를 비운다. false가 되면 `sourceRevs`를 다시 읽어 `done`을 새로 계산한다(진행 중이던 에셋도 처음부터 판정). 시작 때 이미 `rebuilding`이면 끝날 때까지 기다린다. T27에 '에셋 중간에 재구축 → 끝난 뒤 모든 쪽 존재' 시험을 더한다.

### M-5. 다른 탭이 진행 중인 녹음 초안을 복구·삭제해 녹음을 잃는다

- **위치**: 4.2.3 `pendingDrafts()`(658행), 6.10 의사 코드(1937행), CP-PDF-3.
- **문제**: '지금 녹음 중인 초안을 뺀다'는 판정은 **이 JS 실행 문맥의 메모리 상태**로만 한다. 같은 출처를 Safari 탭 두 개로 열거나(1차 CORE가 '범위 밖 — 사용자 안내'로 둔 상황이지만 실수로 흔히 생긴다), 녹음 중인 탭을 둔 채 새로 고친 다른 탭이 시작하면, 두 번째 탭의 유휴 작업 `media.recoverDrafts`가 첫 탭이 1초마다 `append` 중인 초안을 녹음 행으로 만들고 `discard`한다. 첫 탭의 다음 `append`는 `StateError`(모르는 `draftId` — 02-core 6.7.2)가 되고 `DraftWriter`는 그 뒤 조각을 메모리(`unsaved`)에만 쌓는다 → 정지가 실패하거나 탭이 닫히면 그 뒤 녹음 전부를 잃는다. 1차의 '다중 탭 = DB는 일관, 세션만 어긋남'보다 훨씬 큰 손실이다.
- **고칠 방향**: 웹에서는 `RecordingDraft.updatedAt`이 `now − max(10 s, 5 × webDraftChunkMs)`보다 최근인 초안을 복구 대상에서 뺀다. 일시정지 동안에도 `updatedAt`이 갱신되도록 `DraftWriter`가 주기적으로 빈 조각 `append`(CORE가 `active_ms`만 갱신 — 02-core 6.7.2)를 보낸다. 가능하면 녹음하는 탭이 Web Locks(`navigator.locks`, Safari 15.4+)로 `noteapp-rec-<draftId>`를 쥐고 복구가 `ifAvailable: true`로 확인한다(없으면 시각 규칙만). VM `recorder_service_test`에 '같은 저장소를 쓰는 서비스 둘 — 한쪽 녹음 중, 다른 쪽 복구 → 건너뜀'을 더하고, `append` `StateError`를 받으면 녹음을 멈추고 '다른 창에서 이 녹음을 정리했어요' 같은 문구로 알린다.

### M-6. Chrome WebM 길이를 시계 값으로 패치해 R-3·V8이 자기 자신을 잰다

- **위치**: 6.6.3 의사 코드(1788·1789행), 6.8.7(1883·1885행), T39 V8 단언(2251행), 6.7 개발자 표시 `diff`.
- **문제**: 정지 때 `WebmDuration.patch(bytes, activeMs)`로 녹음 시계 값을 Duration에 넣고, 그 파일을 디코더로 재서 `durationMs`로 쓴다. 그러면 Chrome에서 '디코더 길이'(R-3)는 시계 값 그 자체이고, V8의 `|offset 누적 − 파일 길이| ≤ 50 ms`는 구조상 늘 0에 가깝다 — 계약 검증 기준이 아무것도 확인하지 않는다. 개발자 표시 `diff`(A-5 보정 판단 근거)도 웹 Chrome에서는 의미가 없다. (조사 02의 '+7 ms' 실측도 `record_web`이 자기 `Stopwatch` 값으로 패치한 파일을 잰 것이라 같은 성격이다 — `media_recorder_delegate.dart` 203행.)
- **고칠 방향**: `webm_duration.dart`가 Duration을 **파일 안의 오디오 타임라인**으로 계산한다 — 마지막 `Cluster`(0x1F43B675)의 `Timecode`(0xE7) + 마지막 `SimpleBlock`(0xA3)의 상대 타임코드 + 프레임 길이(Opus 20 ms 기본, `TimecodeScale` 반영). 그 값으로 패치하고, 시계와의 차이를 V8·개발자 표시에서 비교한다. 파싱이 실패할 때만 시계 값을 쓰고 개발자 표시에 'duration from clock'을 남긴다. 복구(잘린 마지막 조각)에서도 같은 계산이 초안 `activeMs`보다 정확하다. 시험: 손 표본에 클러스터·블록을 넣어 계산 값 단언, V8은 '타임코드 길이 vs 시계 ≤ 50 ms'.

### M-7. 긴 웹 녹음의 정지·복구가 같은 바이트를 여러 벌 들고, 복구가 매 실행 반복될 수 있다

- **위치**: 6.6.3(1786·1788행), 6.6.4 길이 재기(1805행), 6.10 복구, 6.13.3 '정지 → 재생기에 연다'(2082행), 6.17 메모리 행(2150·2157행).
- **문제**: 계획서 2장이 받아들인 '3시간 86 MB' 녹음을 웹에서 정지하면 `readAll`(86 MB) → `+ writer.unsaved` 이어 붙이기(복사) → WebM 패치(크기가 바뀌므로 전체 복사) → 길이 재기용 `Blob`(브라우저 쪽 복사) → `AssetStore.put` → 정지 직후 재생기 `open`의 `readBytes`(86 MB) + `Blob`(86 MB)이 짧은 시간에 겹친다. 앞의 버퍼가 GC되기 전이면 300 MB 예산(7.4.5)을 넘고, iPad Safari가 탭을 다시 읽으면 초안은 남아 있으므로 **다음 실행 3초 뒤 같은 복구가 같은 크기로 다시 돈다** — 매 실행 탭이 죽는 반복이 될 수 있다. 6.17은 30분(14 MB)만 계산했다.
- **고칠 방향**: ① 빈 `unsaved`면 이어 붙이지 않고, 패치는 머리 부분만 새로 만든 뒤 웹에서는 `Blob([새 머리, 원본 나머지 view])`로 합쳐 길이 재기·재생에 같은 `Blob`을 쓴다(전체 복사 없음). ② 단계마다 앞 버퍼 참조를 버린다. ③ 녹음 크기가 일정 이상(예: 32 MiB)이면 정지 직후 자동 `open`을 하지 않거나 바이트를 다시 읽지 않고 같은 `Blob`을 넘긴다. ④ 복구 시도 횟수를 기기 설정(`media.recoverAttempts` — 초안 id별)에 **시작 전에** 기록하고, 끝나지 않은 시도가 2번 쌓인 초안은 자동 복구에서 빼 개발자 표시·패널 한 줄('복구하지 못한 녹음이 있어요')로 알린다. 영구 실패(노트가 영구 삭제되어 `createRecording`이 `ArgumentError` 등)는 초안을 남겨 두지 말고 분류해 정리한다. ⑤ 6.17에 3시간 행을 더하고, Chrome perf 시험에 86 MB 합성 초안의 정지·복구 경로가 만드는 전체 크기 버퍼 수를 계측 훅으로 단언한다.

### M-8. 패널을 열거나 녹음을 정지하면 그 녹음의 필기가 모두 흐려진다 (EDITOR 강조 규칙과 충돌)

- **위치**: 6.13.3 '열 때 … 가장 최근 녹음을 재생하지 않고 `open`'(2080행)·'정지 → 돌려받은 녹음을 재생기에 연다'(2082행), 5.3 끝 문단(1409행).
- **문제**: EDITOR 6.15.2는 이 노트 녹음이 열려 있고 phase가 `ready`·`paused`·`completed`면 '지금 위치로 한 번' `setPlaybackFocus`를 넣고(04-editor 2123행), 기본 강조 방식은 `dimUnwritten`이다(04-editor 532행). 패널이 녹음을 위치 0으로 열면 그 녹음에 연결된 획이 전부 '아직 안 쓴 획'으로 흐려진다. 특히 **녹음을 정지하자마자 방금 쓴 필기가 모두 흐려진다.** 탭 재생 조건(04-editor 6.3.5 ③)을 맞추려고 넣은 동작이 기본 사용 흐름을 깨뜨린다.
- **고칠 방향**: EDITOR와 하나로 정한다(X-5). 권장: PDF는 열어 두기를 유지하되, EDITOR가 '이 열림 뒤 한 번이라도 `playing`이었거나 `seekMs`가 불린 뒤'에만 초점을 넣는다(`ready` 처음 상태는 초점 없음). 그게 어렵다면 PDF가 자동 `open`을 빼고 EDITOR 탭 재생 조건을 '열린 녹음이 없으면 탭한 획의 `recordingId`로 `open` 후 탐색'으로 바꾼다. 어느 쪽이든 `recording_panel_test`와 EDITOR `playback_highlight_test`에 '정지 직후 흐림 없음'을 넣는다.

---

## 권장

- **S-1 (CP-PDF-1을 피하는 길)**: `pool`·`gate`는 같은 패키지의 provider만 넣으므로 공개 생성자에 선택 인자를 더할 필요가 없다. `@internal`(meta) 팩토리나 `src/` 전용 구성 함수로 주입하면 원문 시그니처 그대로이고 `PdfIndexerGate`를 barrel에 내보낼 필요도 없다(C-2와 함께).
- **S-2 (조각 보내기 시점을 분명히)**: 6.2.2 의사 코드가 'parts → 1차 묶음 규칙으로 addPages'를 쪽 반복 **뒤**에 적어, 큰 PNG가 많은 쪽에서 조각이 쪽 끝까지(또는 16쪽 묶음까지) 쌓이는 것처럼 읽힌다. '대기 중인 조각 바이트가 `exportChunkMaxBytes`를 넘으면 항목 반복 안에서 바로 `await addPages`'를 의사 코드에 넣는다.
- **S-3 (`PdfObjectFixtures.jpeg({width, height, exifOrientation})`)**: `pdf_io`에는 `package:image`가 없고 `dart:ui`는 JPEG를 인코딩하지 못한다. 손으로 만든 바이트로 임의 크기의 올바른 JPEG를 만들기는 어렵다(SOF 크기만 바꾸면 엔트로피 자료와 어긋남). 고정 크기 상수 표본 몇 개(기준선·점진·EXIF 6 — APP1만 끼워 넣음)로 시그니처를 바꾼다.
- **S-4 (작업 크기)**: T25(이미지·수식·텍스트·헤더·래스터 + 시험 4개), T31(상태 기계·시계·`DraftWriter`·복구), T32(웹 녹음기 + WebM 패치 + 페이지 이벤트 + `media` 시험), T35(헤더·정규화·웹 코덱·클립보드·시트·문구 + 시험 5개), T36(패널 전부)은 한 세션을 넘기 쉽다. 순수 함수(`webm_duration`, `image_header`·`image_normalizer`, `RecordingClock`·`DraftWriter`)를 앞 작업으로 떼어 내면 병렬로 나아갈 수도 있다.
- **S-5 (`DraftWriter`의 `unsaved`가 끝없이 자람)**: `append` 예외 뒤 조각을 메모리에만 쌓고 다시 시도하지 않는다. 일시적 IndexedDB 오류에도 남은 녹음 전체가 메모리에 남는다. 다음 조각 때마다 `unsaved`를 먼저 다시 쓰도록 하고(조각 ≤ 4 MiB 유지), `unsaved`도 8 MiB 상한에 넣어 넘으면 `storageBacklog`로 멈춘다. 웹에서 정지 저장이 실패하면 '파일로 내려받기'(Blob 다운로드)를 마지막 수단으로 보이면 '잃지 않음' 원칙에 맞는다.
- **S-6 (iPad 앱 전환과 '마이크 끊김' 판정의 순서)**: iOS Safari는 앱이 뒤로 갈 때 캡처 트랙을 `mute`했다가 돌아오면 `unmute`하는 경우가 있다. 6.8.3의 '`mute`가 1초 넘게 → `microphoneLost`(이어서 녹음 불가)'가 가려짐 일시정지와 겹치면 **앱을 전환할 때마다 녹음을 새로 시작**해야 한다. `mute` 감시는 `recording`이고 보이는 동안만 켜고, 보이게 된 뒤 `unmute`를 몇 초 기다린 다음 판정하도록 순서를 적는다. B-9에 '앱 전환 → 돌아와 이어서 녹음 → 정지 → 한 파일로 재생'을 더한다.
- **S-7 (iOS Safari에서 `<audio>` 메타데이터 적재)**: 길이 재기(6.6.4)와 웹 `open`이 `setUrl(blob:)`의 길이를 기다린다. iOS Safari는 사용자 동작 없이 미디어를 미리 읽지 않는 경우가 있어, 시작 3초 뒤의 자동 복구(동작 없음)는 매번 5초 시간 초과로, `open`은 `loading`에 머물 수 있다 [추측]. 웹에서는 `preload: false`로 열고 길이는 `Recording.durationMs`·M-6의 계산 값을 쓰는 쪽을 기본으로 두고, B-8에 '패널 열기 직후 재생 바 길이 표시'를 확인 항목으로 넣는다.
- **S-8 (색인기 웹 메모리)**: 색인기는 에셋 하나를 끝낼 때까지 문서를 임대해 둔다(500쪽 ≈ 90초). 웹에서 사용자가 다른 큰 PDF를 보는 중이면 wasm에 큰 문서 두 개가 함께 있다. 웹 게이트에 '`openDocuments`가 0이거나 그 에셋이 이미 열려 있음'을 더하거나, 1차 웹 큰 원본 경고(150 MB) 이상인 에셋은 다른 문서가 열려 있을 때 미룬다. 휴지통·고아 에셋까지 색인하는 낭비(12.3 Q8)도 '활성 `PdfBackground` 쪽이 가리키는 에셋만'으로 줄일 수 있는지 CORE에 묻는다.
- **S-9 (JPEG 빠른 길 조건)**: `image_probe`·`image_header`의 빠른 길(바이트 그대로)을 성분 1(회색)·3(YCbCr)으로 한정한다. Adobe APP14 CMYK JPEG는 브라우저와 PDF 뷰어의 색 반전 처리가 다를 수 있으므로 느린 길(디코드 → RGB 재인코딩)로 보낸다.
- **S-10 (`BuildContext` 비동기 사용)**: `importImageForNote`·패널 시트가 `await` 뒤에 `context`를 쓴다(6.12.1). `use_build_context_synchronously`(flutter_lints)가 `--fatal-infos`에서 걸리므로 첫 `await` 전에 `ProviderScope.containerOf(context, listen: false)`·`ScaffoldMessenger.of`·`Navigator.of`를 잡고 `context.mounted`를 확인한다고 적는다. 준비 중 시트는 `enableDrag: false`도 함께.
- **S-11 (`installFakeMediaPlatforms`의 범위)**: '임시 디렉터리' 훅은 `dart:io`가 필요하므로 `testing.dart`(웹 안전) 안에서는 조건부 파일로 나눠야 하고, 웹에서는 녹음 엔진이 `record`가 아니라 자체 MediaRecorder라 `FakeRecordPlatform`이 효과가 없다. 'VM 전용 — Chrome(V6)에서는 CORE `FakeAudioRecorder`로 override'를 문서와 `assert`로 분명히 한다(X-3).
- **S-12 (글꼴 적재 실패 + 오프라인 웹)**: `fontsReady == false`이면 래스터 대체도 `NoteSans` 없이 Flutter 대체 글꼴을 쓰는데, 웹 오프라인에서는 한글 글리프를 받을 수 없어 두부(□)가 들어갈 수 있다. 이때는 '그림으로 넣음' 경고가 아니라 내보내기를 멈추고 '글꼴을 받지 못했어요 — 연결 뒤 다시' 문구로 알리는 편이 낫다(또는 그 상자만 빼고 경고).
- **S-13 (1차 통합 반영)**: `/home/user/noteapp`에 1차 PDF 통합 커밋 `9305235`(`integration/real_wiring_test.dart` 409줄, `template_underlay_test` 강화)가 이미 있다. 8.3·9.4의 '1차 `integration` 3개'는 4개이고, V11 객체 내보내기는 `real_wiring_test`의 구성(실제 CORE·INK·PDFium·앱과 같은 provider 그래프)을 넓히는 편이 새 하네스를 만드는 것보다 싸다. 1차 시험 수(VM 580·Chrome 54)도 통합 뒤 값으로 고친다.
- **S-14 (문서 손질)**: 1.5 C2-28 행의 '이 문서 5.7'은 5.6이다. 6.13.2 '녹음 동의 안내' 대기 줄은 매번 보이고 확인 창은 처음 한 번뿐인데, F-16 '녹음 시작 시 안내'에 맞는지는 Q5로 사용자 확인을 받는 것이 맞다(기본값 좋음).

---

## 다른 영역과 걸리는 것

- **X-1 (INK)**: M-2 — `InkMathRenderer.rasterize`가 INK T36까지 `null`, 벡터 v2가 T42까지 빈 목록이라 PDF 객체 내보내기가 통합 직전까지 실제 값으로 시험되지 않는다. ① `testing.dart` v2에 벡터 값 시험용 생성자(`InkPageVectors`·`InkFillShape`·`InkImageVector`·`InkTextVector`·`InkTextLine`·`InkMathVector`)를 R2-B3에 넣어 줄 것, ② 가능하면 T36(래스터)·T42(벡터 v2)를 앞당길 것. M-3 — `rasterize`의 상한을 긴 변이 아니라 픽셀 수(예: 4 Mpx)로 할 것. CP-INK-9(글꼴 미적재 → `lines` 빈 목록)와 CP-PDF-8은 짝이므로 함께 승인되어야 한다. CP-INK-6(지연 저장소)은 T20 ③ 시험의 전제다(INK 기반 단계 표에 '최종 구현'으로 있음 — 확인).
- **X-2 (INFRA)**: CP-PDF-9가 01-infra 3.3 `media_io` pubspec(R2-B1)에 없다. M-1에 따라 `plugin_platform_interface`를 뺀 6줄로 넣어야 T30(R2-B4)의 `testing.dart`가 컴파일된다. `plugin_packages`·`pinned_external` 목록도 함께(INFRA 검토 M-3과 같은 지점).
- **X-3 (INFRA)**: 8.3 '7(INFRA) V5·V6: `installFakeMediaPlatforms`로 실제 `mediaIoOverrides()`가 돈다'는 01-infra 5.8(모듈 주입 인자 — `imageSources`·`importer`·`recordingPanel` 가짜)과 다르다. 어느 방식으로 할지 정하고, Chrome V6에서는 가짜 플랫폼이 웹 녹음기에 효과가 없음(S-11)을 INFRA가 알게 한다. 또 01-infra 5.8의 '가짜 `PdfSearchIndexer` override'는 `final class`라 컴파일되지 않는다(INFRA 검토 M-2) — PDF가 시험 이음새(C-2)를 주면 INFRA가 쓰기 쉽다.
- **X-4 (INFRA)**: `FEATURE_MEDIA=false`가 이미지 삽입(P-A, M5-3·M5-4)까지 끄는 문제(INFRA 검토 M-4). PDF 쪽은 이미 `supportedImageSources()`·`importImageForNote`가 `initializeMediaIo` 없이 동작하게 설계했으므로(4.2.4), INFRA가 이미지 가져오기 자리를 녹음 스위치와 떼어 연결하면 된다. `media.recoverDrafts`(01-infra 6.5.2)는 M-5·M-7의 '최근 갱신 초안 제외'·'시도 횟수 상한'을 PDF가 서비스 안에서 지키므로 INFRA 코드는 그대로 둬도 되지만, '끝나지 않은 시도'를 INFRA가 따로 세지 않는다는 점을 서로 적는다.
- **X-5 (EDITOR)**: M-8 — 패널의 자동 `open`(정지 직후·패널 열기)과 EDITOR 6.15.2의 `ready` 초점·기본 `dimUnwritten`이 만나 필기가 흐려진다. 두 계획서 중 한쪽을 고쳐 하나로 정한다. CP-PDF-10(녹음 중 `play()` 무시)은 EDITOR 탭 재생 문서(6.15.3 '실패는 보고만')에 '녹음 중이면 소리 없음'으로 반영되어야 사용자 혼란이 없다.
- **X-6 (CORE)**: ① CORE `FakeAudioRecorder.start`는 지원 안 함일 때 `StateError`(02-core 6.8.3)인데 실제 녹음기(4.2.3·CP-PDF-5)와 CORE `UnsupportedAudioRecorder`는 `UnsupportedError`다 — 가짜를 실제에 맞춘다. ② V16·V8을 실제 웹 저장소(IndexedDB·drift 웹 워커)로 돌릴 도우미(12.3 Q2)가 02-core에 없다. D13이 P-A이고 주 기기가 iPad Safari이므로 `testing_web.dart`(브라우저 전용)로 `openWebTestNoteStore(name)`를 공개해 달라고 요청한다 — 없으면 V16은 메모리 저장소에서 늘 통과하는 시험이 된다. ③ M-5의 빈 조각 `append`가 `updated_at`도 갱신하는지 02-core 6.7.2에 명시해 달라. ④ CP-3·CP-7·CP-10에 PDF가 기대는 '승인 전 동작'이 있으므로 결정 시점을 R2-B2 전으로.
- **X-7 (LIBRARY·SYNC)**: 직접 접점 없음 확인. LIBRARY는 `source: pdf` 결과를 보이기만 하고(05-library 87·1166행), SYNC는 이미지·오디오를 1차 에셋 파이프라인(300 MiB 상한 — 07-sync 333행)으로 보낸다. 3시간 녹음 86 MB가 상한 안이라는 PDF 계산과 맞는다.

---

## 계약 문제

- **C-1 (7.3.2 M-2 ↔ 7.2.12)**: M-2의 '다음 실행 때 `pendingDrafts()`로 복구를 **묻는다**'와 7.2.12의 '**묻지 않고** 녹음으로 만든다'가 충돌한다(CP-PDF-4 = CORE CP-12 ② = INFRA 검토 C-8). 계약 문장을 '묻지 않고'로 정리한다. 7.4.2 표의 '돌아오면 이어서 녹음할까요? 안내'(가려짐)와 혼동되지 않게 문장을 나눈다.
- **C-2 (7.2.12 `PdfSearchIndexer`)**: `final class`라 앱 셸이 가짜를 넣을 수 없고(INFRA 검토 C-2), CP-PDF-1은 승인 전인데 T20이 '최종 시그니처'로 `PdfIndexerGate`까지 공개한다(7.4.9 '승인 전까지 원문대로'와 어긋남). 권장: 원문 생성자 그대로 두고 주입은 패키지 내부(S-1), 시험 이음새는 INFRA 쪽 주입 함수 또는 `pdf_io/testing.dart`의 카운터 훅으로. 계약에 '색인기 시작·종료 시험은 앱 셸 이음새로 한다'를 적는다.
- **C-3 (7.6 `media_io/testing.dart` 주석)**: 원문은 '가짜 record / just_audio 플랫폼은 `RecordingPanel`의 VM 위젯 시험용'이라 적었지만, PDF 설계는 패널 시험을 CORE 가짜로 하고 가짜 플랫폼은 서비스·앱 스모크용으로 쓴다(4.3.2 끝 문단). 또 원문에 이미지 선택기 가짜가 없어 V5 '이미지 선택기 … 가짜'와 맞지 않는다. CP-PDF-6과 함께 주석을 고친다(믹스인 없이 — M-1).
- **C-4 (7.2.4 `pendingDrafts` · `RecorderStatus.isActive`)**: CP-PDF-3 문장에 '이 실행의 활성 세션(`starting`·`recording`·`paused`·`finishing`)과 **최근 갱신된 초안(다른 창의 진행 중 녹음일 수 있음)**은 빼고 준다'를 넣는다(M-5). `isActive`(= `recording || paused`)를 쓰는 INFRA 유휴 작업은 `starting`·`finishing`을 놓치므로, 계약에 '복구 여부 판단은 `pendingDrafts()`에 맡긴다'를 적는다.
- **C-5 (7.4.5 메모리 예산 ↔ 7.2.9 `rasterize`)**: '이미지 객체 임시 16 MB'와 '래스터 긴 변 4096'(03-ink 4.10)이 양립하지 않는다(M-3). 예산 문장에 '래스터·디코드는 픽셀 수 상한으로 이 예산 안에 든다'를 더하고, INK `rasterize` 주석의 상한을 픽셀 수로 바꾼다.
- **C-6 (7.7 V8 · 7.2.4 R-3)**: V8의 '파일 길이'와 R-3의 '디코더 길이'가 녹음 시계로 패치된 값이면 시험이 성립하지 않는다(M-6). R-3에 '웹 WebM의 길이는 블록 타임코드에서 계산해 넣는다(시계 값 패치 금지)'를, V8에 '비교 대상 = 파일 안 타임라인 길이'를 적는다.

---

## 질문

- **Q-1**: 같은 기기에서 앱을 두 탭(또는 Safari 탭 + 홈 화면 앱 — iOS는 저장소가 따로라 해당 없음일 수 있음)으로 여는 경우를 2차에서도 '범위 밖'으로 둘 것인가? M-5의 최소 보호(최근 갱신 초안 제외)는 범위와 상관없이 넣기를 권한다.
- **Q-2**: 웹 녹음 정지 저장이 실패했을 때 '파일로 내려받기'를 마지막 수단으로 보여도 되는가(S-5)? 녹음 파일이 기기의 '다운로드'에 남는다.
- **Q-3**: M-8의 해결을 PDF(자동 `open` 제거) 쪽으로 할지 EDITOR(`ready` 처음 상태는 초점 없음) 쪽으로 할지 총괄이 정해 달라. 권장은 EDITOR 쪽(탭 재생 조건을 바꾸지 않아도 됨).
- **Q-4**: 3시간 이상 연속 녹음을 2차의 지원 범위로 볼 것인가? 그렇다면 M-7의 계측 시험을 P-A로, 아니면 패널에 '긴 녹음은 1시간마다 나눠 주세요' 같은 안내를 두고 P-C로 내린다.
