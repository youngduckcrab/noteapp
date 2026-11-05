# PDF 진행 기록

## 요약

- 마지막 세션: 2/10 (동시 개발 단계)
- 다음 할 일: T8 렌더 캐시·큐·타일 수학(+ `pdfRenderStatsProvider` 본문 교체, PDF-4-2 공지) → T9 배경 위젯·INK 어댑터

## 작업 표

| ID | 상태 | 커밋 | 비고 — 완료 조건 테스트 파일 |
|---|---|---|---|
| T0 | 기반 단계에서 완료 | 783a5ba | B4: contract/api_surface_test, unit/init_test(B4 판), unit/value_equality_test(B4 몫), unit/page_size_policy_test(PdfPageFit), web/foundation_browser_test, dart_test.yaml |
| T1 | 완료 | 73d6ee1 | unit/page_range_test, unit/page_size_policy_test, unit/file_naming_test, unit/hangul_jamo_test, unit/title_policy_test, unit/cancel_signal_test, unit/value_equality_test, unit/error_messages_test, unit/no_platform_imports_test |
| T2 | 완료 | 00ff451 | pdfium/fixture_builder_test, unit/fixture_builder_bytes_test, tool/prepare_web_test.dart(4개 파일·sha256), web/pdfrx_smoke_browser_test, web/pure_logic_browser_test, support/pdfium_env.dart, 패키지 .gitignore |
| T3 | 완료 | bd58dde | pdfium/pdfrx_engine_test, web/pdfrx_engine_browser_test |
| T4 | 완료 | 009a832 | unit/fake_gateway_test, unit/core_gateway_fake_store_test. integration/core_gateway_test는 작성만 함(통합 단계에서 실행 — 현재 `openTestNoteStore`는 CORE T6 전 자리표시) |
| T5 | 완료 | a160abb | unit/import_service_test, pdfium/import_real_test (+ test/support/render_doubles.dart) |
| T6 | 완료 | ad78e51 | widget/import_flow_test, web/file_source_browser_test (+ unit/file_source_test, support/fake_file_picker.dart) |
| T7 | 완료 | (이 커밋 — 다음 커밋에서 해시 기록) | unit/document_pool_test |
| T8 | 남음 | | unit/tile_math_test, unit/render_scheduler_test, unit/render_cache_test, unit/render_stats_provider_test |
| T9 | 남음 | | widget/page_background_view_test, widget/ink_builder_adapter_test, goldens/background_states_golden_test, pdfium/background_real_test |
| T10 | 남음 | | unit/thumbnail_test, unit/cover_thumbnail_test (integration/ink_thumbnail_test는 미리 작성 — 통합 단계) |
| T11 | 남음 | | unit/text_normalizer_test, unit/search_service_test, unit/search_equality_test, pdfium/search_real_test, widget/search_panel_test |
| T12 | 남음 | | unit/compose_encoder_test, unit/vectorizer_box_test, unit/template_underlay_test (integration/ink_vectorizer_test는 미리 작성 — 통합 단계) |
| T13 | 남음 | | pdfium/compose_native_test |
| T14 | 남음 | | web/compose_browser_test |
| T15 | 남음 | | unit/export_service_test, pdfium/export_e2e_test |
| T15b | 남음 | | unit/batch_export_test, widget/batch_export_flow_test |
| T16 | 남음 | | widget/export_flow_test, web/output_sink_browser_test |
| T17 | 남음 | | unit/providers_test, unit/init_test(실제 판), widget/menu_actions_test |
| T18 | 남음 | | perf/import_500_test, perf/compose_500_native_test, web/perf_compose_500_test, perf/render_scroll_sim_test (perf 태그) |
| T19 | 남음 | | README, THIRD_PARTY_NOTICES.md, licenses/, unit/licenses_test |

## 변경 요청

- 없음

## 의존성 요청

- 없음

## 계획과 다르게 한 점

- T1 `PdfIoException.userMessage`: 6.14의 `{max}`(tooLarge·tooManyPages)는 예외에 담기지 않으므로 `PdfIoRuntime.config.limits`(initializePdfIo에 준 설정)에서 읽는다. 내부 `PdfStringsKo.errorMessage(code, detail:, limits:)`는 limits를 직접 받는다. assetMissing의 `{detail}`은 쪽 목록 문자열이며 없으면 괄호를 뺀다.
- T1 진행 단계 문구(4.2·6.3): 파일 읽는 중 / PDF 여는 중 / 저장 중 / 페이지 만드는 중 / 표지 만드는 중 / 내보낼 준비 중 / 페이지 합성 중 / PDF 마무리 중, `total > 0`이면 ' (done/total)'. 내보내기 3단계 문구는 계획서에 없어 정했다.
- T1 결과 시트 쪽 목록: 연속 구간을 한 항목으로 세어 10개(`missingPagesListMax`)까지 보이고 나머지는 ' 외 n쪽'(n = 빠진 쪽 수). 잘린 목록은 '…외 n쪽은 원본이 없어…'로 '쪽'을 겹치지 않는다.
- T1 `PdfPageRange`: `resolve`는 쪽 오름차순(입력 순서가 아님 — 4.6 주석 'ascending'), 구분자 ','(전각 '，'·'、'도), 범위 기호 '-'·'–'·'~', 빈 조각은 건너뜀, 조각이 하나도 없으면 오류. `all().format()` = '1-', `parse('1-')`도 `isAll`. 값 동등(`format()` 기준)을 더했다(공개 이름 추가 없음).
- T1 `PdfPageSizePolicy.toNotePageSize`: 크기가 양수·유한이 아니면 ArgumentError. 배율을 곱한 뒤 다시 0.001pt로 반올림.
- T2 `PdfFixtureBuilder`: 매핑 텍스트(`mapped: true`)는 문서 전체가 공유하는 두 번째 Helvetica(WinAnsi + ToUnicode) 하나로 그린다. 코드는 인쇄 가능한 WinAnsi 바이트(0x21–0x7E, 0xA1–0xFF, 0xAD 제외 — 188개)라 글자마다 실제 글리프·글자 상자가 있다(PDFium `FPDFText_GetCharBox`는 글리프 상자를 씀). 서로 다른 코드 단위가 188개를 넘으면 StateError. 매핑 없는 텍스트는 Latin-1만(넘으면 ArgumentError). 권한 암호(사용자 암호 '')는 `/P -44`, 사용자 암호는 `/P -4`. RC4·바이트 변환은 비트 연산 없이 산술로(웹 안전). 출력은 결정적이라 VM·dart2js 바이트가 같은지 sha256으로 확인한다(test/support/fixture_digest.dart).
- T2 `web/pdf_io_compose_ext.js`는 준비 스크립트가 4개 파일을 복사하도록 자리 파일만 만들었다(명령은 T14). pubspec `flutter: assets:` 선언은 아직 하지 않았다(T14·T19에서 필요할 때).
- T2 `web/pure_logic_browser_test.dart`(9.1)를 이 작업에서 만들었다(T1 순수 로직 + 픽스처 바이트). T11·T12가 항목을 더한다.
- T3 `PdfDocumentInfo.isEncrypted`: pdfrx 2.11.0 웹은 `/P`가 음수(실제 PDF는 거의 항상 음수)면 `FPDF_GetDocPermissions`를 부호 있는 정수로 읽어 `isEncrypted == false`를 준다. 그래서 pdfrx 값 || `usedPassword` || 앞·뒤 64KiB에 `/Encrypt` 키가 있음으로 판단한다(정보용 값 — 저장 결정은 `usedPassword`만 씀).
- T3 렌더 취소: `PdfRenderCancelToken`에 내부 함수 `whenRenderCancelled(token, listener)`(page_info.dart, barrel 비공개)를 두어 pdfrx 취소 토큰으로 넘긴다. 렌더는 pdfrx `renderForDisplay`(웹은 워커 ImageBitmap)로 `ui.Image`를 만든다. 해제된 문서의 `render`는 null, `loadText`·`encodeWithoutSecurity`는 StateError.
- T3 `%PDF-` 검사는 내부 함수 `hasPdfMagic`(pdf_engine.dart, barrel 비공개) — T5 가져오기 서비스도 같은 함수를 쓴다.
- T4 `CorePdfNoteGateway`: `putPdf`는 `put`이 내는 모든 오류를 `storageFailed`(cause 보존)로 바꾼다 — 재시도 없이 끝나는 경로는 청크 쓰기 실패뿐이고 그 오류 타입은 blob 저장소 몫이라서. 다른 메서드는 CORE 예외만 바꾸고(EntityNotFound → noteNotFound, ReadOnly → readOnlyNote, 그 밖의 NoteCoreException → storageFailed) ArgumentError 같은 프로그램 오류는 그대로 던진다. `insertPages`의 `receipt.persisted`는 `.ignore()`(기다리지 않고, 나중 오류도 처리되지 않은 오류가 되지 않게).
- T4 `FakePdfNoteGateway`: lib/testing.dart는 `package:note_core/testing.dart`를 import할 수 없어(R4 test_only_entrypoints) CORE 가짜 저장소를 감싸지 않고 자체 메모리 구현으로 만들었다. 4.14에 없는 테스트용 멤버: `calls`(포트 호출 기록), `thumbnails`, `assets`, `heldWriteCount`, `addRemoteAsset`, `dropAssetBytes`, `addStrokes`, `trashNote`, `purgeNote`(공개 최상위 이름 추가 없음). 보류된 쓰기는 `releaseWrites()` 때 호출 순서대로 적용된다.
- T5 내부 이름(공개 아님): `PdfImportSessionImpl`(import/import_session.dart), `renderImportCover`(import/cover_thumbnail.dart — T10 표지 테스트도 이 함수), `reportPdfError`(common/error_report.dart — 6.13의 보고 함수).
- T5 `FakePdfEngine`(4.14는 모양을 정하지 않음): 생성자 `pages`(없으면 `pageCount`×`pageSize`, 기본 A4 1쪽)·`texts`(쪽 번호 → `PdfPageTextData`)·`userPassword`·`ownerPasswordOnly`·`imageArgb`. 시험 조절: `initError`·`openError`·`renderError`, 기다리게 하는 훅 `beforeOpen`·`beforeRender`·`beforeLoadText`, 기록 `ensureInitializedCalls`·`openCalls`(sourceName·fileName·transferOwnership)·`passwordRequests`·`renderRequests`·`loadTextCalls`·`encodeCalls`·`documents`·`openDocumentCount`. `encodeWithoutSecurity`는 원본 뒤에 `FakePdfEngine.noSecurityMarker`를 붙인 바이트를 주고, 그 바이트는 암호 없이 열린다. 렌더 이미지는 `Picture.toImageSync`(fake_async에서도 동작).
- T5 가져오기 세부: 쪽이 0개인 문서는 `corrupt`. `PdfImportAsNewNote.title`이 공백뿐이면 `suggestedTitle`. `encodeWithoutSecurity` 실패는 `corrupt`(cause 보존). 진행률 `creatingPages`는 호출 전 (0/n)·끝난 뒤 (n/n) 두 번. `refuse` 정책은 엔진이 암호를 물으면(=사용자 암호 필요) 콜백이 null을 돌려주고 그 `passwordCancelled`를 `userPasswordRefused`로 바꾼다(묻지 않음). `open`의 파일 읽기·엔진 초기화·열기는 `raceCancel` — 열기 중 취소하면 늦게 열린 문서를 닫는다. 암호 창이 떠 있을 때 취소해도 바로 `cancelled`. 커밋 중 `dispose()`는 커밋이 끝날 때 문서를 닫는다(풀에 넘기지 않음). 커밋이 오류(`readOnlyNote` 등)로 끝나면 세션은 그대로라 다시 `commit`하거나 `dispose`할 수 있다. 같은 세션의 두 번째 성공 `commit`·dispose 뒤 `commit`은 StateError.
- T5 테스트 더블 `test/support/render_doubles.dart`: `RecordingDocumentPool`(adopt 기록), `SolidThumbnailRenderer`(renderThumbnail만), `ScriptedThumbnailRenderer`(core.PageThumbnailRenderer) — 실제 풀(T7)·렌더러(T8) 전까지 T5·T6 테스트가 쓴다.
- T6 `FilePickerPdfSource`: 한 파일만 고르므로 `FilePicker.pickFile`(`pickFiles`와 같은 옵션 — `FileType.custom`, `['pdf']`)을 쓴다. 웹·네이티브 같은 API(6.15)라 분기 없음. 파일 변환은 내부 함수 `pickedPdfFileFrom(PlatformFile)`(크기 = `lengthSync()`, 바이트는 `readAsBytes`를 가져오기가 부를 때). 웹에서 file_picker 기본값(`withData: true`)은 고를 때 바이트를 미리 읽는다 — 끄는 옵션 `FilePickerWebOptions`는 `file_picker_web`에만 있어(직접 의존성 아님, 사용 중단 예정 표시) 그대로 둔다. 그래서 웹에서는 6.3 1단계 '읽기 전 크기 거부'가 메모리를 아끼지 못한다(거부는 그대로 됨).
- T6 `web/file_source_browser_test`: 계획의 'web.File → PickedPdfFile'은 file_picker가 web.File을 감싸는 몫이라, 실제 `web.File`을 file_picker 웹 구현처럼 감싼 테스트용 `PlatformFile`(크기 = `File.size`, 바이트 = `arrayBuffer`)을 `ScriptedFilePicker`(test/support/fake_file_picker.dart, `FilePickerPlatform.instance` 교체)로 돌려주고 `FilePickerPdfSource.pickPdf()` 결과의 이름·크기·바이트를 확인한다. VM에서도 같은 방식(unit/file_source_test).
- T6 `FakePdfFileSource`(4.14는 모양을 정하지 않음): 생성자 `files`(대기열)·`supported`, `enqueue(file|null)`·`enqueueError(e)`, `beforePick` 훅, `pickCalls`·`queued`. 대기열이 비면 null(사용자 취소).
- T6 흐름 세부: 시트에서 파일 선택이 취소되면(첫 선택) 시트를 닫고 흐름은 null. 열기 오류(notPdf·passwordCancelled 등)는 시트 안에 문구 + '다른 파일 선택'. 시트에서 세션을 열어 두고(암호 창 포함) 범위를 받는다 — 빈 칸 = 전체, 잘못된 범위는 입력란 오류 문구. 큰 파일 확인 창은 시트를 닫은 뒤(`isLargeFile`, 세션 열린 뒤). 진행 창은 `DialogRoute`를 흐름이 직접 넣고 뺀다. 성공은 스낵바 '{n}쪽을 가져왔어요', 실패는 스낵바 `userMessage`, 취소는 문구 없음. '취소' 버튼은 진행 단계가 `creatingPages` 전일 때만 보인다. 문구는 strings_ko.dart(가져오기 시트·암호 창·큰 파일 확인 — 계획 6.14에 없던 문구를 정함).
- T6 `PdfImportJobNotifier`: busy = 자기 가져오기 또는 내보내기·일괄 내보내기 상태가 Running. 자기 가져오기가 도는 중의 두 번째 `run`은 상태를 바꾸지 않고 null(돌고 있는 작업의 Running을 덮지 않음), 다른 작업이 도는 중이면 `PdfJobFailed(busy)`. 진행률은 `PdfTuning.jobProgressInterval`(100ms, 4.13에 새로 추가)마다 묶어 상태에 반영. 예상 밖 예외는 보고 후 `PdfJobFailed(storageFailed, cause)`. '닫기' 뒤 작업이 실패하면 `reportPdfError`.
- T6 `api_surface_test`의 B4 몫 'importPdfAsNewNote → null'은 지웠다(실제 흐름 — widget/import_flow_test).
- T7 `DefaultPdfDocumentPool`: 생성 때 `gateway.bytesArrived`를 구독한다(문서는 열지 않음). 실패 기억(2초)은 모든 열기 실패(assetMissing 포함)에 적용하되, 열기를 시작한 뒤 그 id의 원본이 도착했으면 기억하지 않는다. 엔진·게이트웨이의 PdfIoException이 아닌 오류는 `corrupt`(cause 보존). `adopt`: 이미 열린 문서가 있으면 넘겨받은 문서를 닫고(같은 파일 재가져오기), 아니면 참조 0 유휴로 넣고 그 id의 실패 기억을 지운다. 열기 중에 `adopt`가 먼저 넣으면 열린 문서를 닫고 adopt한 것을 쓴다. `dispose`는 빌려 간 문서까지 모두 닫고 이후 `acquire`는 StateError, 진행 중이던 열기는 끝나면 닫는다. `requestRemote`의 `ensureLocal` 예외·`watch` 오류는 보고 후 공유 스트림에 `RemoteAssetProgress(failed)`를 내고 요청 기록을 지운다. 공유 watch는 `Stream.multi`(새 구독자에게 마지막 값을 먼저 줌), 구독자가 0이면 fetcher 구독 해제. `bytesArrived`와 `ensureLocal == true`가 겹치면 `assetArrived`가 두 번 나온다(6.6대로 — `acquire`가 중복 열기를 막음).
- T7 `FakeRemoteAssetFetcher`: 4.14 멤버 + `failEnsureLocal(id, error)`·`watchListenerCount(id)`. 같은 id의 동시 `ensureLocal`은 한 Future를 공유.
- fake_async 주의: `StreamSubscription.cancel()`이 돌려주는 Future는 루트 존에서 끝날 수 있어 fake_async 안에서 기다리면 끝나지 않는다 — lib 코드는 cancel을 기다리지 않는다(`unawaited`).
- T1 `no_platform_imports_test`: 색 리터럴 검사 범위를 render/·ui/에 ink_adapter/까지 넓히고 `Color.fromARGB(`·`Color.fromRGBO(`·`Colors.`도 잡는다. `package:flutter/material.dart` 금지, 조건부 export는 두 factory 파일에만 있음도 검사.

## 다음 세션 메모

- 세션 1 결과: T1·T2·T3·T4 완료.
- 세션 2 결과: T5(`FakePdfEngine` 포함)·T6 완료. 가져오기 서비스 provider는 `pdfDocumentPoolProvider`(T7)·`pdfPageRendererProvider`(T8)를 watch하므로 지금 위젯 테스트는 둘을 `test/support/render_doubles.dart`로 override한다(T7·T8 뒤에도 그대로 둬도 된다). 다음은 T7(문서 풀·`FakeRemoteAssetFetcher`) — `adopt`는 같은 id 문서가 이미 열려 있으면 넘겨받은 문서를 닫아야 한다(같은 파일 재가져오기). 그다음 T8.
- 위젯 테스트에서 가져오기 진행 창·시트의 진행 막대는 값이 없으면 계속 움직이므로 `pumpAndSettle` 대신 `pump(100ms)` 반복(import_flow_test `_settle`). 표지는 `toByteData`(엔진 비동기)라 위젯 테스트에서는 `core.pageThumbnailRendererProvider`를 `ScriptedThumbnailRenderer`로 override해 자체 PNG 경로를 피한다.
- Chrome 테스트: `dart run tool/ws.dart test --platform chrome --package pdf_io`(준비 스크립트 포함, 약 70초). 한 번 `flutter test --platform chrome test/web`가 900초 시간 초과로 끊겼고 다시 돌리니 59초에 통과했다(다른 영역 부하로 보임).
- 실 PDFium VM 테스트는 `test/pdfium/`(`@Tags(['pdfium'])`, `setUpAll(initPdfiumForTests)`). 이 작업 트리에는 `build/native_assets/linux/libpdfium.so`가 이미 있다.

- 계획서 상단 상태 줄·계약 인용(v1.4)·13.4(PDF-4-1~4-3, C14-01·02)는 세션 1에서 반영했다.
- T4 테스트의 CORE 쪽 가정: `createFakeNoteStore(faults:)`의 `failNextCommits(3)`이면 1초 시점 미완료·`writeFailing`, 6초 시점 완료(100ms·400ms·1.6s 재시도). 실제 CORE(T6)로 바뀌면 integration/core_gateway_test를 돌려 확인한다.
- PDF-4-2: T8 커밋 때 `pdfRenderStatsProvider`가 `core.noteStoreProvider`를 필요로 하게 됨을 결과 보고 메모에 적어 INFRA에 공지한다.
