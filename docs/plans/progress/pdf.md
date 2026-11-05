# PDF 진행 기록

## 요약

- 마지막 세션: 3/10 (동시 개발 단계)
- 다음 할 일: T11 텍스트·검색(정규화·검색 서비스·검색 패널) → T12 벡터화·인코더

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
| T7 | 완료 | da17026 | unit/document_pool_test |
| T8 | 완료 | 3829a68 | unit/tile_math_test, unit/render_scheduler_test, unit/render_cache_test, unit/render_stats_provider_test (+ widget/render_handle_test — 핸들 동작) |
| T9 | 완료 | ac4fe3c | widget/page_background_view_test, widget/ink_builder_adapter_test, goldens/background_states_golden_test(+ goldens/background_states/*.png 6장), pdfium/background_real_test |
| T10 | 완료 | 6962562 | unit/thumbnail_test, unit/cover_thumbnail_test. integration/ink_thumbnail_test는 작성함(통합 단계 판정 — 지금 INK B3 구현 + 실 PDFium으로 `--run-skipped -t integration` 수동 실행 시 통과) |
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
- T8 내부 이름(공개 아님): render/tile_math.dart(`bucketScale`·`previewScale`·`thumbnailScale`·`scaleForLongSide`·`needsTiles`·`PdfTileGrid`·`PdfTileRef`·`tilesFor`·`PdfRenderPlan`·`PdfRenderKind`·`PdfRenderClass`·`opaquePaperArgb`), render/render_scheduler.dart(`PdfRenderScheduler`·`PdfRenderJob`), render/render_cache.dart(`PdfRenderCache`·`PdfCacheLease`·`PdfRenderKey`). 3장 트리의 `render_stats.dart`는 만들지 않았다 — `PdfRenderStats`는 B4대로 render_service.dart에 있다(barrel 그대로).
- T8 캐시 키: 6.7.4의 (assetId, pageIndex, kind, scale, tileX, tileY)에 렌더 배경색(불투명 종이 색)을 더했다 — 같은 PDF 쪽이 다른 종이 색 노트에 쓰이면 다른 이미지라서. 미리보기 키의 scale은 버킷이 아니라 실제 배율 pv(긴 변 1024 상한이 걸리면 버킷과 다름).
- T8 `PdfRenderService`의 `AppLifecycleListener(onHide: trimMemory)`는 생성자가 아니라 첫 `attach`·`renderThumbnail` 때 등록한다(그 전에는 캐시가 비어 있음). 그래서 `pdfRenderStatsProvider` read(서비스 생성)는 바인딩이 없어도 된다 — INFRA가 바인딩 없는 `test()`에서 읽어도 안전.
- T8 `statsListenable`: 캐시·큐 변화를 마이크로태스크 하나로 모아 갱신한다(핸들을 attach·update하는 위젯 build 안에서 리스너가 불리지 않게). `stats` 게터는 그때그때 계산. `openDocuments` = `pool.openCount`(풀은 알리지 않으므로 다음 갱신 때 반영).
- T8 핸들: `update()`는 리스너를 부르지 않는다(호출자 didUpdateWidget 뒤 build가 `snapshot`을 읽음). 이미지 도착·상태 변화만 알린다. 스냅숏에서 빠진 이미지는 `SchedulerBinding.addPostFrameCallback` + `ensureVisualUpdate`로 다음 프레임 뒤 참조를 내린다(핸들은 위젯 아래에서만 쓰임). `dispose`는 대기·진행 렌더 취소, 타일은 바로 `release(dropIfUnused: true)`(다른 핸들이 안 쓰면 즉시 dispose), 미리보기·썸네일은 LRU에 남김. 서비스 `dispose`는 살아 있는 핸들도 정리하고 캐시·통계 노티파이어를 해제한다.
- T8 그릴 것 결정 세부: 보이는 사각형이 있으면 25% 여백 포함 목록을 보이는 타일 먼저(보이는 영역 중심에서 가까운 순)·여백 타일 다음 순으로 만들고 64개에서 자른다(`visiblePageRect == null`이고 64 초과면 계획대로 타일 없음). 보이는 사각형이 비면(화면 밖) 타일 없음. 핀치 중(`isScaling`)·끝난 뒤 120ms 동안 새 요청 없음 — 단 아직 base가 하나도 없는 핸들(핀치 중 마운트된 페이지)은 base(미리보기·썸네일)만 요청한다. base가 바뀌면(버킷·모드) 새 base가 올 때까지 이전 base를 스냅숏에 둔다. 이전 버킷 타일은 현재 버킷의 보이는 타일이 모두 도착(또는 최종 실패)하면 내리고, 타일이 필요 없어지면(축소·썸네일 모드) 바로 내린다(프레임 뒤).
- T8 오류: 문서 열기의 엔진 오류(`corrupt`·`engineUnavailable` 등)는 풀의 실패 기억(2초) 뒤 한 번 다시 열고, 또 실패하면 보고 + `failed`. `assetMissing` → `assetMissing`, `passwordCancelled` → `needsPassword`(보고 없음 — 원격 요청은 T9). 쪽 번호가 범위 밖이면 `corrupt` 보고 + `failed`. 렌더 오류는 이미지마다 즉시 1회 재시도, 또 실패하면 보고하고 base면 `failed`(이전 base가 보이고 있으면 `ready` 유지), 타일이면 그 타일만 건너뜀(미리보기는 그대로). 같은 이미지를 두 핸들이 동시에 렌더하면 합치지 않는다(나중 `put`이 중복 이미지를 dispose).
- T8 `renderThumbnail`: 큐의 썸네일 클래스로 렌더, 캐시에 넣지 않는다(호출자 소유). `assetMissing`·`passwordCancelled` → null(보고 없음), 그 밖의 예외 → null + 보고. 배경색은 받은 값 그대로.
- T8 긴 변 맞춤 배율(`scaleForLongSide`): `(긴 변 px − 0.001) / 긴 변 pt` — 엔진 `fullPixelSize`의 올림이 부동소수 오차로 1px 더 커지지 않게(미리보기 1024·썸네일 256·`renderThumbnail`의 `longSidePx`가 정확히 나옴).
- T8 `PdfTuning.renderTimingSamples = 100`(p95 창)을 새로 두고 4.13에 적었다.
- T8 `unit/init_test`(B4 판)에서 `pdfRenderStatsProvider` read를 지웠다(4.12대로 `unit/render_stats_provider_test`로 옮김). `web/foundation_browser_test`는 통계 read에 CORE 가짜 저장소를 더했다. `web/pure_logic_browser_test`에 타일 수학을 더했다.
- T9 원격 원본(6.7.7)은 3장 트리의 `remote_asset_watch.dart` 대신 핸들(render_service.dart) 안에 두었다: 핸들은 생성 때 `pool.assetArrived`를 구독하고, `acquire`가 `assetMissing`이면 `pool.requestRemote`를 구독(썸네일 모드 포함)해 `downloading`·`waiting` → `downloading`, `offline`·`failed`·`unavailable` → `assetMissing` + `remote`, `local` → 다시 열기. 공유 watch가 새 구독자에게 마지막 값을 다시 주므로 `local`로 다시 연 뒤에도 원본을 못 읽으면 다음 `assetArrived`까지는 `local`로 또 열지 않는다(무한 반복 방지). 풀의 실패 기억(2초) 안에서는 다시 열어도 같은 오류가 바로 온다 — 실제로는 `bytesArrived`/`ensureLocal == true`가 기억을 지우고 `assetArrived`를 낸다. 해제·다른 페이지로 바뀔 때 두 구독을 끊는다(cancel은 기다리지 않음).
- T9 배경 위젯: 상태 표시(6.8 ⑤)는 painter가 아니라 `CustomPaint`의 child 위젯(논리 px 고정 — 아이콘 32/썸네일 20, 문구 14, 진행 막대). 색은 `Theme.of(context).colorScheme.onSurfaceVariant`. 아이콘: assetMissing `description_outlined`, downloading `cloud_download_outlined`, needsPassword `lock_outline`, failed `warning_amber`. 진행률 %는 내림. painter는 render/page_background_painter.dart의 내부 클래스 `PdfPageBackgroundPainter`(종이 → base → 타일 → 하이라이트, 페이지 상자로 clip). 위젯은 `renderer`가 바뀌면(identical 아님) 핸들을 다시 attach한다.
- T9 `PdfSearchState.rectsFor`·`currentRectsFor`·`currentFocusRect`(4.8, 원래 T11 몫)를 painter가 읽어야 해서 지금 구현했다(hits 중 그 pageId의 rects 이어 붙임 / 현재 결과가 그 페이지면 그 rects / 현재 결과 rects 합집합, 없으면 null). T11은 검색 서비스·패널만 남는다.
- T9 `renderStill`: `renderThumbnail(longSidePx: ceil(max(pixelSize)), backgroundArgb: 불투명 종이 색)` → PDF 표시 크기 대신 받은 이미지 크기로 `PdfPageFit`(상자는 비율에만 의존) → `PictureRecorder`로 종이 + 이미지 → `toImageSync`(위젯 테스트 fake async에서도 끝남). 예외는 보고 후 null(원본 없음·암호는 `renderThumbnail`이 이미 null — 보고 없음).
- T9 `pdfBackgroundLayerBuilderProvider` 본문 = 4.12 T9 판(`renderer: () => ref.read(pdfPageRendererProvider)`, `highlights: ref.watch(pdfSearchHighlightsProvider)`). `unit/init_test`(B4 판)는 첫 빌더 `isPaperOnly == false`로 바꾸고 paperOnly 묶음은 자리표시를 직접 만든다. `web/foundation_browser_test`도 `isPaperOnly == false`.
- T9 골든은 썸네일 모드(아이콘만)·고정 스냅숏 렌더러 더블로 6장을 만들었다(`flutter test --update-goldens test/goldens/`). 테스트 글꼴이라 아이콘은 사각형으로 그려진다.
- T10 썸네일 경로는 T8 `renderThumbnail`·썸네일 모드 그대로(새 lib 코드 없음). 표지 자체 경로(`renderImportCover`)는 종이 색을 불투명으로 바꿔 칠하고 같은 색으로 렌더를 요청하도록 고쳤다(배경 위젯·`renderStill`과 같은 규칙). 자체 경로 표지 크기는 노트 페이지 비율로 긴 변 512(반올림 — A4 362×512), 썸네일 모드 이미지는 엔진 `fullPixelSize` 올림(A4 182×256).
- fake_async 주의: `StreamSubscription.cancel()`이 돌려주는 Future는 루트 존에서 끝날 수 있어 fake_async 안에서 기다리면 끝나지 않는다 — lib 코드는 cancel을 기다리지 않는다(`unawaited`).
- T1 `no_platform_imports_test`: 색 리터럴 검사 범위를 render/·ui/에 ink_adapter/까지 넓히고 `Color.fromARGB(`·`Color.fromRGBO(`·`Colors.`도 잡는다. `package:flutter/material.dart` 금지, 조건부 export는 두 factory 파일에만 있음도 검사.

## 다음 세션 메모

- 세션 1 결과: T1·T2·T3·T4 완료.
- 세션 2 결과: T5(`FakePdfEngine` 포함)·T6·T7 완료. 가져오기 서비스 provider는 `pdfDocumentPoolProvider`(T7)·`pdfPageRendererProvider`(T8)를 watch하므로 지금 위젯 테스트는 둘을 `test/support/render_doubles.dart`로 override한다(T7·T8 뒤에도 그대로 둬도 된다). 다음은 T8(렌더 캐시·큐·타일 수학, `pdfRenderStatsProvider` 본문을 `ref.watch(pdfPageRendererProvider).statsListenable`로 — 커밋 때 결과 보고 메모에 PDF-4-2 공지: INFRA 컨테이너에 `core.noteStoreProvider` 필요) → T9 → T10(`renderThumbnail` 구현 뒤 표지 자체 경로 테스트 `unit/cover_thumbnail_test`는 `renderImportCover`를 직접 부른다).
- 위젯 테스트에서 가져오기 진행 창·시트의 진행 막대는 값이 없으면 계속 움직이므로 `pumpAndSettle` 대신 `pump(100ms)` 반복(import_flow_test `_settle`). 표지는 `toByteData`(엔진 비동기)라 위젯 테스트에서는 `core.pageThumbnailRendererProvider`를 `ScriptedThumbnailRenderer`로 override해 자체 PNG 경로를 피한다.
- Chrome 테스트: `dart run tool/ws.dart test --platform chrome --package pdf_io`(준비 스크립트 포함, 약 70초). 한 번 `flutter test --platform chrome test/web`가 900초 시간 초과로 끊겼고 다시 돌리니 59초에 통과했다(다른 영역 부하로 보임).
- 실 PDFium VM 테스트는 `test/pdfium/`(`@Tags(['pdfium'])`, `setUpAll(initPdfiumForTests)`). 이 작업 트리에는 `build/native_assets/linux/libpdfium.so`가 이미 있다.

- 계획서 상단 상태 줄·계약 인용(v1.4)·13.4(PDF-4-1~4-3, C14-01·02)는 세션 1에서 반영했다.
- T4 테스트의 CORE 쪽 가정: `createFakeNoteStore(faults:)`의 `failNextCommits(3)`이면 1초 시점 미완료·`writeFailing`, 6초 시점 완료(100ms·400ms·1.6s 재시도). 실제 CORE(T6)로 바뀌면 integration/core_gateway_test를 돌려 확인한다.
- PDF-4-2: T8에서 `pdfRenderStatsProvider` 본문을 `ref.watch(pdfPageRendererProvider).statsListenable`로 바꿨다 — 이제 읽는 컨테이너에 `core.noteStoreProvider`가 있어야 한다(세션 3 결과 보고 메모로 INFRA에 공지함). 바인딩은 필요 없다(수명 주기 리스너는 첫 렌더 때 등록).
- 세션 3 결과: T8·T9·T10 완료. 핸들 동작 테스트는 `test/widget/render_handle_test.dart`(가짜 엔진 `beforeRender`로 렌더를 붙잡는 `_World`), 위젯은 `test/widget/page_background_view_test.dart`. 다음 T11: `PdfSearchState.rectsFor`·`currentRectsFor`·`currentFocusRect`는 T9에서 이미 구현함 — T11은 `PdfTextNormalizer`·`DefaultPdfTextService.searchNote`·`PdfSearchNotifier`·검색 패널(`showPdfSearchPanel`)과 그 테스트(unit/text_normalizer_test, unit/search_service_test, unit/search_equality_test, pdfium/search_real_test, widget/search_panel_test). 검색 하이라이트는 배경 위젯이 `highlights`로 이미 그린다(widget/page_background_view_test 'search highlights').
