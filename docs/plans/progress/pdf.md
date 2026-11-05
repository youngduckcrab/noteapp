# PDF 진행 기록

## 요약

- 마지막 세션: 1/10 (동시 개발 단계)
- 다음 할 일: T3 엔진 어댑터(`PdfrxEngine`) → T4 게이트웨이

## 작업 표

| ID | 상태 | 커밋 | 비고 — 완료 조건 테스트 파일 |
|---|---|---|---|
| T0 | 기반 단계에서 완료 | 783a5ba | B4: contract/api_surface_test, unit/init_test(B4 판), unit/value_equality_test(B4 몫), unit/page_size_policy_test(PdfPageFit), web/foundation_browser_test, dart_test.yaml |
| T1 | 완료 | 73d6ee1 | unit/page_range_test, unit/page_size_policy_test, unit/file_naming_test, unit/hangul_jamo_test, unit/title_policy_test, unit/cancel_signal_test, unit/value_equality_test, unit/error_messages_test, unit/no_platform_imports_test |
| T2 | 완료 | (이 커밋) | pdfium/fixture_builder_test, unit/fixture_builder_bytes_test, tool/prepare_web_test.dart(4개 파일·sha256), web/pdfrx_smoke_browser_test, web/pure_logic_browser_test, support/pdfium_env.dart, 패키지 .gitignore |
| T3 | 남음 | | pdfium/pdfrx_engine_test, web/pdfrx_engine_browser_test |
| T4 | 남음 | | unit/fake_gateway_test, unit/core_gateway_fake_store_test (integration/core_gateway_test는 미리 작성 — 통합 단계) |
| T5 | 남음 | | unit/import_service_test, pdfium/import_real_test |
| T6 | 남음 | | widget/import_flow_test, web/file_source_browser_test |
| T7 | 남음 | | unit/document_pool_test |
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
- T1 `no_platform_imports_test`: 색 리터럴 검사 범위를 render/·ui/에 ink_adapter/까지 넓히고 `Color.fromARGB(`·`Color.fromRGBO(`·`Colors.`도 잡는다. `package:flutter/material.dart` 금지, 조건부 export는 두 factory 파일에만 있음도 검사.

## 다음 세션 메모

- 계획서 상단 상태 줄·계약 인용(v1.4)·13.4(PDF-4-1~4-3, C14-01·02)는 세션 1에서 반영했다.
- PDF-4-2: T8 커밋 때 `pdfRenderStatsProvider`가 `core.noteStoreProvider`를 필요로 하게 됨을 결과 보고 메모에 적어 INFRA에 공지한다.
