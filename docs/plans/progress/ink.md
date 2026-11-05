# INK 진행 기록

## 요약

- 마지막 세션: 1 (동시 개발 단계)
- 다음 할 일: T05 중심선 처리·굵기 계수 굽기 → T06 `StrokeBuilder`(라이브·완료, T04 필터 연결) → T07 외곽선·K-1 (계획서 8장 순서)

## 작업 표

| ID | 상태 | 커밋 | 비고 — 완료 조건 테스트 파일 |
|---|---|---|---|
| T00 | 기반 단계에서 완료 | 955931c | `foundation/b3_smoke_test.dart`, `foundation/b3_behaviour_test.dart`, `unit/api_surface_test.dart`, `unit/export_list_test.dart`, `unit/no_platform_imports_test.dart`, (웹) `web/smoke_web_test.dart` |
| T01 | 완료 | 7c74b7c | `unit/smoke_test.dart`, `unit/tuning_test.dart`, (웹) `web/smoke_web_test.dart`(B3). `dart_test.yaml`(golden·bench), `test/flutter_test_config.dart` + `test/support/golden_tolerance{,_native,_browser}.dart`(0.5% 비교기, 브라우저는 아무것도 안 함), `THIRD_PARTY_NOTICES.md`. `tuning.dart`는 B3에 이미 있음 |
| T02 | 완료 | d1dd4ba | `unit/model/ink_points_test.dart`, `unit/model/ink_stroke_test.dart`, `unit/pen/style_ink_test.dart`, `unit/pen/pen_profile_test.dart`. 구현은 B3 본문이 이미 4.1·4.2·6.9대로라 테스트만 추가 |
| T03 | 완료 | 1489bbf | `unit/input/sample_adapter_test.dart`, `unit/input/pressure_detector_test.dart`, `unit/input/pressure_mode_test.dart`. `PressureDetector`를 6.4 전체 규칙으로 교체(관찰·12개 고정값·재보고), 결정은 detector가 store에 바로 보고(컨트롤러의 B3 보고 블록 삭제). `unit/api_surface_test`의 첫 스타일러스 획 기대값 real → pending(6.4) |
| T04 | 완료 | (이 커밋) | `unit/input/simulated_pressure_test.dart`, `unit/input/one_euro_filter_test.dart`. 내부 `src/input/simulated_pressure.dart`(`SimulatedPressure`, `RealPressureSmoother`, `smoothstep`, `sampleDtMs`)·`src/input/one_euro_filter.dart`(`OneEuroFilter`). 아직 `StrokeBuilder`에 연결하지 않음 — T05·T06에서 파이프라인에 넣는다. 실측: 500 px/s 지연 4.8 ms(60/120/240 Hz), 같은 궤적 Hz별 차 ≤ 0.008 |
| T05 | 남음 | | `unit/stroke/{subdivide,hook,dot,width_factor,taper,straighten,simplify}_test.dart` |
| T06 | 남음 | | `unit/stroke/stroke_builder_test.dart`, `unit/stroke/finish_data_test.dart`, (웹) `web/determinism_test.dart` |
| T07 | 남음 | | `unit/geometry/{outline,outline_parity,vector_path}_test.dart`, `unit/model/bounds_invariant_test.dart`, (웹) `web/geometry_on_web_test.dart` |
| T08 | 남음 | | `widget/pixel/{highlighter_overlap,self_overlap}_test.dart`, `unit/render/pencil_grain_test.dart`, (웹) `web/grain_checksum_test.dart`, `goldens/pens_golden_test.dart` |
| T09 | 남음 | | `unit/interop/core_interop_test.dart`, `unit/edit/ink_edit_test.dart`, `unit/interop/fake_store_handoff_test.dart` |
| T10 | 남음 | | `widget/{ink_page_view,viewport_report,handoff,highlighter_active}_test.dart`, `unit/render/{content_diff,session_rules}_test.dart` |
| T11 | 남음 | | `unit/diagnostics/latency_test.dart`, (웹) `web/ink_clock_test.dart` |
| T12 | 남음 | | `unit/{providers,testing_helpers,dev_tools}_test.dart`, (웹) `web/dev_tools_web_test.dart`, `widget/m0_scenario_test.dart` — INK-α 완료 |
| T23 | 남음 | | (선택, INK-α 직후) `example/` ink lab — `flutter build web`, `example/test/smoke_test.dart` |
| T13 | 남음 | | `unit/background/{template_vectors,template_defaults,background_spec}_test.dart`, `widget/{background_builder,template_still}_test.dart`, `goldens/templates_golden_test.dart` |
| T13b | 남음 | | `template_vectors_test` 확장(악보·플래너), `goldens/templates_music_planner_golden_test.dart` |
| T14 | 남음 | | `unit/edit/spatial_index_test.dart`, `unit/edit/hit_test_test.dart` |
| T15 | 남음 | | `unit/edit/stroke_eraser_test.dart`, `widget/eraser_preview_test.dart` |
| T16 | 남음 | | `unit/edit/partial_eraser_test.dart`, `unit/edit/partial_eraser_property_test.dart`, (웹) `web/partial_eraser_web_test.dart`, `goldens/partial_erase_golden_test.dart` |
| T17 | 남음 | | `unit/edit/lasso_test.dart`, `widget/lasso_preview_test.dart` |
| T18 | 남음 | | `unit/edit/selection_geometry_test.dart`, `unit/edit/selection_test.dart`, `widget/selection_preview_test.dart` |
| T19 | 남음 | | `unit/render/{render_config,bucket,raster_lru}_test.dart`, (웹) `web/render_config_web_test.dart`, `widget/{raster_vs_vector,raster_schedule,progressive_load}_test.dart` |
| T20 | 남음 | | `widget/{thumbnail_renderer,thumbnail,pen_preview}_test.dart`, (웹) `web/thumbnail_png_web_test.dart`, `goldens/{thumbnail,pen_preview}_golden_test.dart` |
| T21 | 남음 | | `unit/export/vector_export_test.dart`, `unit/export/template_export_test.dart` |
| T22 | 남음 | | `benchmark/*_bench_test.dart`, `benchmark/README.md` (9.1 VM 기준값) |

통합 단계 몫: INK 자체 `integration` 테스트는 없다(계획서 3장 — 실제 INK + 실제 CORE 흐름은 EDITOR E-21). 9.3 iPad 확인은 사용자 몫.

## 변경 요청

- (없음 — 기반 단계의 `SelectionGeometry` 이름 겹침은 계약 v1.4 C14-01로 처리됨)

## 의존성 요청

- (없음)

## 계획과 다르게 한 점

동시 개발 단계:

- T03: 내부 `PressureDetector` 생성자에 선택 인자 `store`(`PressureCapabilityStore?`)를 더했다(4.3 내부 시그니처는 kind·mode·prior). 6.4의 '결정이 나면 report'를 획 도중(`observe`)에 하려면 detector가 store를 알아야 해서다. `buildStroke`(오프라인)는 store 없이 쓴다.
- T03: `prior == supported`인데 고정값 12개가 나오면(펜슬 교체) capability만 `unsupported`로 재보고하고, **쓰는 중인 획의 source는 real 그대로** 둔다(다음 획부터 simulated). 획 도중 real → simulated 전환은 앞 점 굵기를 다시 계산해야 해 6.4 규칙 6(pending → real, 최대 11점)의 범위를 넘기 때문. 강제 모드(alwaysReal·alwaysSimulated)는 관찰·보고를 하지 않는다.

기반 단계 B3에서 (인수인계 메모 `/home/user/wt/notes/foundation-ink.md` 요약):

- `PencilGrain`은 생성자에서 바로 만들지 않고 첫 사용(첫 리스너·`ready`·`value`) 때 비동기로 한 번 만든다. 웹에서 `ui.decodeImageFromPixels`가 엔진 `Timer.run`을 걸어 0초 `pump()`로는 끝나지 않아 'A Timer is still pending'이 나기 때문(4.9 주석은 '즉시 시작').
- `InkDiagnostics`는 아직 `SchedulerBinding.addTimingsCallback`을 붙이지 않는다(T11에서).
- 지우개는 샘플 사이를 쓴 원(swept circle)으로 검사한다. 썸네일 렌더러·`InkPageThumbnail`은 종이 위에 폴리라인을 그린다.
- B3의 `test/web/smoke_web_test.dart`는 T01보다 먼저 만들었다.
- 내보내지 않는 내부 배관: `InkPageHost`, `InkPageRender`·`inkPageRenderOf`, 세션·선택·`LiveStrokeGeometry`의 `@internal` 팩토리, `src/background/builder_choice.dart`.

## 다음 세션 메모

- T02 `ink_points_test`: 계획의 `identical(InkPoints.of(p).raw, p.rawData)`는 디버그·테스트 실행에서 성립하지 않는다. CORE `rawData`가 디버그에서 호출마다 새 수정 불가 뷰(`asUnmodifiableView()`)를 주기 때문(CORE 6.2.4). 대신 `fromRaw`의 identical, `of(p).raw`가 수정 불가 뷰(쓰기 → UnsupportedError = INK가 복사하지 않음), 같은 값·같은 바이트 길이, `InkStroke.points.raw`가 늘 같은 객체임을 확인한다.

- 문서 C13-05(상태 줄 '승인', 계약 v1.4 인용, INK-4-1·4-2, 13.4)와 C14-01 README 한 줄은 세션 1에서 끝냈다.
- B3 본문은 단순 구현이다(4.15 표). 각 T 작업이 해당 파일 본문을 교체한다.
