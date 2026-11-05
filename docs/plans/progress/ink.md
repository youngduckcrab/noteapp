# INK 진행 기록

## 요약

- 마지막 세션: 2 (동시 개발 단계) — T05·T06 완료(세션 1: T01~T04)
- 다음 할 일: T07 외곽선(O1–O9)·K-1 불변식 → T08 펜 렌더러 (계획서 8장 순서)

## 작업 표

| ID | 상태 | 커밋 | 비고 — 완료 조건 테스트 파일 |
|---|---|---|---|
| T00 | 기반 단계에서 완료 | 955931c | `foundation/b3_smoke_test.dart`, `foundation/b3_behaviour_test.dart`, `unit/api_surface_test.dart`, `unit/export_list_test.dart`, `unit/no_platform_imports_test.dart`, (웹) `web/smoke_web_test.dart` |
| T01 | 완료 | 7c74b7c | `unit/smoke_test.dart`, `unit/tuning_test.dart`, (웹) `web/smoke_web_test.dart`(B3). `dart_test.yaml`(golden·bench), `test/flutter_test_config.dart` + `test/support/golden_tolerance{,_native,_browser}.dart`(0.5% 비교기, 브라우저는 아무것도 안 함), `THIRD_PARTY_NOTICES.md`. `tuning.dart`는 B3에 이미 있음 |
| T02 | 완료 | d1dd4ba | `unit/model/ink_points_test.dart`, `unit/model/ink_stroke_test.dart`, `unit/pen/style_ink_test.dart`, `unit/pen/pen_profile_test.dart`. 구현은 B3 본문이 이미 4.1·4.2·6.9대로라 테스트만 추가 |
| T03 | 완료 | 1489bbf | `unit/input/sample_adapter_test.dart`, `unit/input/pressure_detector_test.dart`, `unit/input/pressure_mode_test.dart`. `PressureDetector`를 6.4 전체 규칙으로 교체(관찰·12개 고정값·재보고), 결정은 detector가 store에 바로 보고(컨트롤러의 B3 보고 블록 삭제). `unit/api_surface_test`의 첫 스타일러스 획 기대값 real → pending(6.4) |
| T04 | 완료 | bd6875e | `unit/input/simulated_pressure_test.dart`, `unit/input/one_euro_filter_test.dart`. 내부 `src/input/simulated_pressure.dart`(`SimulatedPressure`, `RealPressureSmoother`, `smoothstep`, `sampleDtMs`)·`src/input/one_euro_filter.dart`(`OneEuroFilter`). 아직 `StrokeBuilder`에 연결하지 않음 — T05·T06에서 파이프라인에 넣는다. 실측: 500 px/s 지연 4.8 ms(60/120/240 Hz), 같은 궤적 Hz별 차 ≤ 0.008 |
| T05 | 완료 | fc236cf | `unit/stroke/{subdivide,hook,dot,width_factor,taper,straighten,simplify}_test.dart`. 내부 `src/stroke/centerline.dart`(`CenterPoint`, 중복 판정 `isDuplicateSample`, F2 `subdivide`·`subdivideSegment`, F3 `removeHooks`, F4 `isDotStroke`·`dotOf`), `width_factor.dart`(K1 `bakedPressure`, K2–K4 `widthFactor`, K6 `widthQForFactor`, `radiusForFactor`), `taper.dart`(F5), `straighten.dart`(F6, 라이브용 `straightLine`), `simplify.dart`(F7, `simplifyStrokeData`), `geometry/rdp.dart`(공용 RDP). 아직 `StrokeBuilder`에 연결하지 않음(T06) |
| T06 | 완료 | 6f67596 | `unit/stroke/stroke_builder_test.dart`, `unit/stroke/finish_data_test.dart`, (웹) `web/determinism_test.dart`. `StrokeBuilder` 본문 교체(6.3 중복 병합·시간 역전 → 6.4 관찰 → 6.5 가상 필압 → 6.6 1€·실제 필압 평활 → K1–K4 → 라이브 청크, `finish` = F1→F3→F4→F6→F2→F5→F8→F7, 롤오버 `rolledOver`), `LiveStrokeGeometry` 내부(안정 점 append-only, 64점 청크 `frozenPath`, 열린 청크 + 원시 꼬리 `tailPath`, 형광펜 polyline·alwaysStraight 직선), `StrokeSession.end`가 롤오버 조각을 한 `InkEdit`에 담음, `newCoreStroke`의 `createdAt += FinishedStroke.createdAtOffsetMs`. 공용 스크립트·체크섬 `test/support/stroke_scripts.dart`(VM 기록값 283364609 = Chrome) |
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
- T06: 청크 고정은 필압 판정이 난 뒤에만 한다(pending 동안은 열린 청크에 둠). 6.4 규칙 6의 '최대 11점'은 미지원 판정 기준이고, 지원 판정('첫 값과 0.02 넘게 다른 값')은 12번째보다 늦게 올 수 있다(기본값이 아닌 고정값을 한동안 내다가 변하는 펜). 이렇게 하면 pending → real 재계산이 고정된 청크를 건드리지 않아 `frozenPath` append-only가 늘 성립하고, 재계산은 그 시점까지의 현재 조각 점 전부(보통 ≤ 11점)를 원시 필압 기록으로 다시 돌린다 — 결과는 처음부터 `alwaysReal`이었던 것과 같다(`stroke_builder_test`).
- T06: 내부 `FinishedStroke`에 `createdAtOffsetMs`(롤오버 조각의 Σ⌊t_b⌋), `StrokeBuilder`에 `rolledOver`(롤오버로 끝난 조각 목록)를 더했다(4.4 내부 시그니처에 없는 멤버 — 공개 표면 변화 없음). `buildStroke`는 4.4대로 마지막 조각(`finish()` 결과)만 돌려준다. 롤오버 때 라이브 형상은 그대로 이어지고(이음점은 필터된 b), 저장되는 두 획은 원시 b에서 만난다.
- T06: 라이브 시작 taper의 Ls는 `taperStart · width`(0.4·S 상한 없음 — S를 아직 모름). 아주 짧은 획(S < 2.5·Ls)은 펜을 뗄 때 시작 쪽 굵기도 조금 바뀐다. 라이브 형상은 아직 B3 렌더러(`paintLivePolyline` — 폴리라인)가 그린다. `frozenPath`·`tailPath`는 B3 외곽선 생성기(`OutlineGenerator.outlineOf`)로 만들며 T07이 생성기를 교체하면 그대로 따라간다. 채움 렌더·활성 레이어 연결은 T08·T10.
- T05: F3 갈고리 제거를 F2 보간 **앞**(안정 점 + 끝점 단계)에서 한다. 6.7 표 순서는 F2 → F3이지만 '창 안의 점 ≤ 4개'는 샘플 수여야 의미가 있다(보간 뒤에는 굵은 펜의 창에 점이 늘 4개를 넘어 규칙이 꺼진다). '창 앞 길이 3W 미만이면 적용 안 함'은 S − W ≥ 3W로 읽었다.
- T05: F7 RDP는 1024점 창마다 따로 돌린다(창 끝점은 항상 유지). RDP는 운 나쁜 입력(같은 높이 톱니)에서 O(n²)이고 `finish`는 펜을 뗄 때 UI 스레드에서 돌기 때문 — 1024점 이하 획(거의 전부)은 한 번에 처리돼 결과가 같다. widthQ 규칙은 '현의 widthQ 선형 보간(호 길이 기준)과의 차 > 0.004이면 유지'로 구현했고, 재단순화 때는 x·y 허용과 widthQ 허용을 함께 2배로 늘린다.
- T05: 연필 K2 최대값은 `pressureGain` 0.45라 1.45이고(`maxFactor` 1.6에는 닿지 않음) 최대 기울기와 곱하면 f = 4.06이다. 6.7 K4의 4.48은 `maxFactor` 기준 상한이다. 둘 다 `kMaxWidthFactor` 4를 넘어 widthQ 1로 포화하므로 결론(K6·K-1)은 같다 — `width_factor_test`가 두 값을 모두 확인.
- T05: F6 축 맞춤은 시작점을 두고 끝점을 시작점을 지나는 축 위로 옮긴다(수평이면 끝 y = 시작 y). F4 점 획의 tilt·azimuth는 굵기 계수가 가장 큰 샘플 값. K3 속도 범위(0.3, 2.0)·K4 기울기 범위(0.35, 1.15)·갈고리 창 최소값(1.5 / 1.0pt, 0.75·width)은 6.28 표에 없어 `InkTuning`(공개)에 더하지 않고 각 파일의 비공개 상수로 두었다.
- T03: `prior == supported`인데 고정값 12개가 나오면(펜슬 교체) capability만 `unsupported`로 재보고하고, **쓰는 중인 획의 source는 real 그대로** 둔다(다음 획부터 simulated). 획 도중 real → simulated 전환은 앞 점 굵기를 다시 계산해야 해 6.4 규칙 6(pending → real, 최대 11점)의 범위를 넘기 때문. 강제 모드(alwaysReal·alwaysSimulated)는 관찰·보고를 하지 않는다.

기반 단계 B3에서 (인수인계 메모 `/home/user/wt/notes/foundation-ink.md` 요약):

- `PencilGrain`은 생성자에서 바로 만들지 않고 첫 사용(첫 리스너·`ready`·`value`) 때 비동기로 한 번 만든다. 웹에서 `ui.decodeImageFromPixels`가 엔진 `Timer.run`을 걸어 0초 `pump()`로는 끝나지 않아 'A Timer is still pending'이 나기 때문(4.9 주석은 '즉시 시작').
- `InkDiagnostics`는 아직 `SchedulerBinding.addTimingsCallback`을 붙이지 않는다(T11에서).
- 지우개는 샘플 사이를 쓴 원(swept circle)으로 검사한다. 썸네일 렌더러·`InkPageThumbnail`은 종이 위에 폴리라인을 그린다.
- B3의 `test/web/smoke_web_test.dart`는 T01보다 먼저 만들었다.
- 내보내지 않는 내부 배관: `InkPageHost`, `InkPageRender`·`inkPageRenderOf`, 세션·선택·`LiveStrokeGeometry`의 `@internal` 팩토리, `src/background/builder_choice.dart`.

## 다음 세션 메모

- T02 `ink_points_test`: 계획의 `identical(InkPoints.of(p).raw, p.rawData)`는 디버그·테스트 실행에서 성립하지 않는다. CORE `rawData`가 디버그에서 호출마다 새 수정 불가 뷰(`asUnmodifiableView()`)를 주기 때문(CORE 6.2.4). 대신 `fromRaw`의 identical, `of(p).raw`가 수정 불가 뷰(쓰기 → UnsupportedError = INK가 복사하지 않음), 같은 값·같은 바이트 길이, `InkStroke.points.raw`가 늘 같은 객체임을 확인한다.

- 문서 C13-05(상태 줄 '승인', 계약 v1.4 인용, INK-4-1·4-2, 13.4)와 C14-01 README 한 줄은 세션 1에서 끝냈다(커밋 551bdea).
- 세션 1 끝 확인: `ws check` 0, 루트 `flutter analyze --fatal-infos` 0, 패키지 VM 113개·Chrome 3개 통과.
- 세션 2 끝 확인: `ws check` 0, 루트 `flutter analyze --fatal-infos` 0, 패키지 VM 177개·Chrome 5개 통과(`web/determinism_test` 체크섬 = VM).
- T07 시작점: 계획서 6.8(O1–O9 표 — `grep -n '^### 6.8'`), 6.7 끝의 K-1 증명. 교체할 파일은 `src/geometry/outline_generator.dart`(지금 B3 — 좌우 오프셋만, 캡·꺾임 분할 없음)·`stroke_outline.dart`(`toPath(smooth:)`가 아직 직선 — O7 2차 베지어로)·`vector_path.dart`. 공용 RDP는 `src/geometry/rdp.dart`(`rdpMark`, `segmentDistance` — T05에서 만듦, O8 외곽선 단순화에 그대로 쓰면 된다). `LiveStrokeGeometry`의 `frozenPath`·`tailPath`도 `OutlineGenerator.outlineOf`를 부르므로 T07 교체가 라이브에도 그대로 반영된다. `bounds_invariant_test`는 `buildStroke` → `interop.newCoreStroke`(롤오버 없는 획은 `createdAtOffsetMs` 0)로 만든다.
- 파이프라인 내부 이름: `src/stroke/centerline.dart`(`CenterPoint` — 가변 점, `factor` = taper 전 f), `width_factor.dart`, `taper.dart`, `straighten.dart`, `simplify.dart`. 라이브 형상 조작 함수는 `src/render/sessions.dart`의 `@internal` `liveAddStable`·`liveFreezeChunk`·`liveSetOpen`·`liveClear`·`livePoints`·`liveFrozenChunks`.
- 결정성 테스트: `test/support/stroke_scripts.dart`의 `recordedScriptChecksum`(283364609)은 파이프라인 수치를 바꾸면(T07은 외곽선만이라 영향 없음) VM에서 다시 기록하고 Chrome(`web/determinism_test.dart`)에서 같은지 확인한다. 체크섬은 CORE 양자화 격자에서 산술로만 계산(비트 연산 없음).
- 테스트 도우미 파일은 `test/support/`(골든 허용 오차 비교기 3개 + `stroke_scripts.dart`).
- B3 본문은 단순 구현이다(4.15 표). 각 T 작업이 해당 파일 본문을 교체한다.
