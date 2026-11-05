# PDF 진행 기록

## 요약

- 마지막 세션: 1/10 (동시 개발 단계)
- 다음 할 일: T1 공통(오류·문구, 취소 신호, 페이지 범위, 크기 정책, 파일 이름, 자모, 제목) → T2 픽스처 · 테스트 환경

## 작업 표

| ID | 상태 | 커밋 | 비고 — 완료 조건 테스트 파일 |
|---|---|---|---|
| T0 | 기반 단계에서 완료 | 783a5ba | B4: contract/api_surface_test, unit/init_test(B4 판), unit/value_equality_test(B4 몫), unit/page_size_policy_test(PdfPageFit), web/foundation_browser_test, dart_test.yaml |
| T1 | 남음 | | unit/page_range_test, unit/page_size_policy_test, unit/file_naming_test, unit/hangul_jamo_test, unit/title_policy_test, unit/cancel_signal_test, unit/value_equality_test, unit/error_messages_test, unit/no_platform_imports_test |
| T2 | 남음 | | pdfium/fixture_builder_test, tool/prepare_web_test.dart, web/pdfrx_smoke_browser_test |
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

- 없음

## 다음 세션 메모

- 계획서 상단 상태 줄·계약 인용(v1.4)·13.4(PDF-4-1~4-3, C14-01·02)는 세션 1에서 반영했다.
- PDF-4-2: T8 커밋 때 `pdfRenderStatsProvider`가 `core.noteStoreProvider`를 필요로 하게 됨을 결과 보고 메모에 적어 INFRA에 공지한다.
