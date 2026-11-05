# INK 2차 계획서 검토 — `03-ink.md`

> 검토자: 총괄 대리 검토자 · 검토일 2026-11-05
> 대상: [03-ink.md](../03-ink.md)(2,034줄, 초안) — 필기 엔진 · 페이지 렌더, 소유 경로 `packages/ink_engine/`(새 `assets/fonts/`·`tool/fonts/`)
> 기준: 개요 [00-overview.md](../00-overview.md) 7장 통합 계약 v2.0 초안(7.0.1·7.2.2·7.2.3·7.2.9·7.3.1~7.3.3·7.4.5·7.4.6·7.4.10·7.5·7.6·7.7·7.8), 조사 01·02·03·04, PLAN.md(F-03·F-11·F-13·F-14·F-15·F-16, 5.1·5.2, 7.3, 10장), 1차 INK 작업 트리 `/home/user/wt/ink`(`17d19bb`), 1차 CORE 작업 트리 `/home/user/wt/core`, 다른 영역 계획서 01·02·04·05·06의 맞닿은 절
> 확인 방법: 계획서 전 절을 읽고 4장 계약 블록을 개요 7.2.9와 줄 단위로 대조했다(일치). 1차 코드 인용을 열어 봤고(아래 '확인한 것'), pub.dev API로 `flutter_math_fork`·`flutter_svg`·`vector_graphics(_compiler)` 와 간접 의존의 게시일, PyPI로 fonttools·brotli 게시일을 봤다. `flutter_math_fork 0.7.4`·`flutter_svg 2.3.0`·`vector_graphics 1.2.3` 소스(pub 캐시)를 읽었다. 무거운 시험은 돌리지 않았다. 임시 작업 `/tmp/claude-0/plan57-scratch/inkreview/`.

---

## 총평

계약 7.2.9를 글자 그대로 옮기고, 계약이 `/* INK */`로 남긴 자리만 4.10 'INK 확정 세부'에 모은 뒤 어긋나는 곳을 CP-INK-1~11로 올린 구조가 좋다. 새 펜 5종의 K-1 증명(펜촉 지지점이 `disk(p_i, a_i)` 안, 사각 캡 0.7071·w ≤ 0.75·w, 대시 = 원형 캡 채움 외곽선)과 도형 K-6 증명(화살표 머리 세 꼭짓점이 `E`에서 `L` 안)이 맞고, 1차 '미리보기 = 커밋' 원칙을 캘리그래피 회전에까지 적용한 판단(6.4)도 정확하다. 실험 근거도 많다: 웹에서 `ImageDescriptor.width`가 없다는 것, 화면 밖 `RenderView` 배치·래스터가 VM·Chrome에서 돈다는 것, Chrome 시험에서 `rootBundle`이 응답하지 않는다는 것, `NoteSans` 부분 집합 크기를 직접 확인했다. 외부 패키지 판(`flutter_math_fork 0.7.4` 2025-05-21, `flutter_svg 2.3.0` 2026-05-08, `vector_graphics 1.2.3` 2026-07-31, `vector_graphics_compiler 1.3.0` 2026-07-28, `xml <=7.0.1` 제약)은 pub.dev와 같다. 소유 경로 밖 수정은 없다(pubspec 의존 4줄은 INFRA CP3 A안으로 합의, `.gitattributes`는 Q6 요청).

그러나 **그대로 승인할 수 없다(revise)**. ① 재생 흐림·강조를 overlay(맨 위) 층에 그려 **암기 테이프 아래 글씨의 모양이 재생 중에 드러나고**(K-9 취지 위반) 텍스트 상자·수식까지 옅어진다. ② 도형 변형 미리보기가 CORE 해석기의 굵기 배율(`scaleStrokeWidth`)을 빠뜨려 **미리보기 ≠ 커밋**이다. ③ 수식 화면 밖 래스터가 `\sqrt`·`\vec`·늘어나는 괄호처럼 `flutter_svg`로 그리는 기호를 **비동기 적재 전에 찍어** 네이티브 release에서 루트 기호가 빠진다(화면·썸네일·PDF 모두 래스터를 씀 — 컨테이너 debug 시험으로는 드러나지 않음). ④ 이미지·수식 캐시 예산이 실제 메모리를 묶지 못하고, 작업 집합이 예산을 넘으면 다시 기록 ↔ 다시 디코드가 끝없이 돈다. 웹 메모리 합계도 300 MB를 넘는데 '안'이라고 적었다. 그 밖에 새 펜 미리보기(`PenPreviewPainter`) 누락, Chrome 시험에서 글꼴 적재가 멈추는 문제를 다른 영역에 넘기는 방법, 실기기 합격을 완료 기준에 넣은 것을 고쳐야 한다.

---

## 반드시 고칠 것

### M-1. 재생 흐림·강조를 overlay 층에 그려 테이프 아래 글씨가 드러나고 텍스트 상자·수식도 옅어진다

- **위치**: 6.19 '그리기 (overlay 층만 …)'(1599행~), 6.1 층 표 overlay 행(1226행), 4.1 L-1 표 7행(417행), 9.3 K-7·K-9 행, T40 완료 조건(1795행).
- **문제**:
  1. 흐림 베일(안 쓴 획 외곽선 위 종이 색 75%)과 강조 외곽(주황 2 px 테두리)을 **overlay**에 그린다. overlay는 annotation(텍스트 상자·수식)과 cover(테이프) **위**다(L-1). 그래서 테이프로 가린 자리 아래에 안 쓴 획이 있으면 베일이 테이프 위에 그 획 모양대로 종이 색을 칠해 **가린 글씨의 모양이 보인다**. 강조 외곽은 두 스타일(`dimUnwritten`·`highlightRecent`) 모두에서 테이프 위에 획 윤곽을 긋는다. 녹음하며 필기하고 테이프로 가린 뒤 재생하며 복습하는 흐름(PLAN 5.2 '학습용')에서 바로 걸린다.
  2. 같은 이유로 안 쓴 획 위에 놓인 텍스트 상자·수식의 글자가 획 모양으로 옅어진다. 6.19-4는 형광펜 위 베일이 '그 위 글씨까지 옅게 한다'는 같은 현상을 알고 형광펜만 뺐는데, 층 위치 자체가 원인이다.
  3. K-9(테이프는 썸네일·내보내기에서 항상 가림)는 '테이프 아래 내용이 새지 않는다'는 뜻인데, 화면 재생 중에 새는 경로를 시험이 보지 않는다(T40·T31 어디에도 '재생 중 테이프 픽셀 불변'이 없다).
- **고칠 방향**:
  - 베일과 강조 외곽을 **ink 위·annotation 아래**에서 그린다. 1차 `inkActive` 층(매 paint 다시 그리는 살아 있는 층, 기본 그림·타일과 무관)의 맨 앞 단계로 넣으면 K-7(기본 래스터를 다시 만들지 않음)도 그대로 지켜진다. overlay에는 레이저·올가미·선택·도형 보정 미리보기만 남긴다.
  - 6.1 층 표·6.19·T40을 고치고, 시험을 더한다: `widget/playback_focus_test` — (a) 안 쓴 획 위에 가린 테이프 → 재생 600프레임 동안 테이프 영역 픽셀이 재생 끔 상태와 같음(두 스타일 모두), (b) 안 쓴 획 위 텍스트 상자 글자 픽셀 불변.
  - L-1 표 7행 '재생 강조'를 'ink와 annotation 사이(살아 있는 층)'로 바꾸는 계약 문구 수정을 12.1에 올린다(C-1).

### M-2. 도형 변형 미리보기가 굵기 배율을 빠뜨려 '미리보기 = 커밋 결과'가 깨진다

- **위치**: 1.1 원칙 6(34행), 6.8.4 둘째 글머리(1354행), 6.14 `setPreviewTransform`(1534행), 6.16 대기 표시 '변형 대상은 `transformed(m)`'(1551행), 5.2 CP-2 동의 문장(1038행)·12.3(2000행), T37 `selection_test` v2(1792행).
- **문제**:
  1. 1차 `InkEdit.toCommand()`는 `TransformElements(…, scaleStrokeWidth: true)`를 낸다(`/home/user/wt/ink/packages/ink_engine/lib/src/edit/ink_edit.dart` 87–92). CORE 계획서는 `ShapeObject.transformed(m)`가 **스타일을 그대로** 두고 굵기 배율은 해석기가 `scaleStrokeWidth`로 따로 적용한다고 정했다(02-core 1429·1482행: '도형이고 `scaleStrokeWidth`면 `strokeWidth × s`([0.1, 30])').
  2. INK는 객체 미리보기·대기 표시를 `object.transformed(m)` 결과로 그린다 → 올가미로 도형을 2배로 키우는 동안 테두리 굵기는 그대로이고, 손을 떼면 2배 굵기로 바뀐다(1차 획은 굵기까지 배율 — 획과 도형이 섞이면 미리보기에서 둘이 다르게 보이다가 커밋에서 같아짐). '미리보기 = 커밋'을 근거로 든 CP-2 동의 문장도, CP-2가 `transformed` 안이 아니라 해석기 쪽에서 구현되면 같은 문제가 생긴다.
- **고칠 방향**:
  - 미리보기·대기 표시에서 CORE 해석기와 **같은 함수**로 객체를 바꾼다. CORE에 공개 도우미(예: `TransformElements.applyToObject(PageObject o)` 또는 `PageObject.transformedBy(Affine2 m, {required bool scaleStrokeWidth})`)를 두게 요청하고(X-1, C-6), 승인 전에는 INK 내부에서 같은 규칙(`strokeWidth × m.uniformScale`, [0.1, 30]으로 자름 — CORE 6.4.1)을 적용한다.
  - 원칙 6·6.8.4·6.14·5.2 문장을 '해석기와 같은 규칙'으로 고치고, T37 `selection_test` v2에 '도형 2배 배율 미리보기 굵기 = 커밋 뒤 `content.objects`의 굵기(가짜 저장소에서 `toCommand` 실행)', '텍스트 상자 배율 미리보기 = 커밋'(CP-2 결정 결과대로) 단언을 더한다.

### M-3. 수식 화면 밖 래스터가 `flutter_svg`로 그리는 기호(루트·벡터 화살표·늘어나는 괄호)를 비동기 적재 전에 찍는다

- **위치**: 6.12.2 파이프라인(1483–1500행 — `buildScope → … → flushPaint → toImage`를 한 번에), 6.12.3(화면 수식은 래스터로만 그림), 6.20 썸네일·5.7 PDF(같은 `rasterize`), T36 완료 조건(1791행), 11장 리스크 '화면 밖 RenderView'.
- **문제**:
  1. `flutter_math_fork 0.7.4`는 `\sqrt`(`ast/nodes/sqrt.dart` 349·377·406), `\vec`·`\overrightarrow`·`\xrightarrow`(`accent.dart`·`stretchy_op.dart`·`accent_under.dart`), `\oint` 계열(`nary_op.dart` 78)을 `SvgPicture.string`으로 그린다(`render/svg/svg_string.dart` 56). `flutter_svg 2.3.0`의 문자열 적재는 `compute(...)`를 거치고(`loaders.dart` 159), `vector_graphics 1.2.3`의 `VectorGraphic`은 `_loadAssetBytes()`에서 `await _loadPicture(...)` 뒤 `setState`로 그림을 붙인다(`vector_graphics.dart` 402–436). 첫 build·paint에는 자리 상자만 있다.
  2. `compute`는 debug·웹에서는 `SynchronousFuture`로 도는 시험용 구현이고(`utilities/compute.dart`), **네이티브 profile·release에서는 isolate를 띄운다**. 그래서 컨테이너의 `flutter test`(debug)로는 통과할 수 있어도 안드로이드 APK·TestFlight release에서 `rasterize`가 루트 기호 없는 수식을 내고, 그 래스터가 화면 수식(6.12.3)·썸네일·PDF 300 dpi 모두에 쓰인다. PLAN F-14 지원 범위(루트, 연립방정식의 `\left\{`)의 핵심 기호다.
  3. 계획서의 [확인] 실험은 `\sum_{k=1}^{n} k^2` 래스터와 `\frac{a}{b}+\sqrt{x^2}`의 **배치 크기**만 봤다(배치 크기는 `Container(width, height)`라 적재와 무관 — 래스터만 문제).
  4. 호스트가 isolate에 하나이고(1499행) 래스터 요청이 화면 캐시·썸네일·PDF에서 겹쳐 오는데, 적재를 기다리게 바꾸면 요청끼리 트리를 덮어쓴다(직렬화 규칙 없음).
- **고칠 방향**:
  - `OffscreenMathHost.rasterize`: build·layout 뒤 호스트 `BuildOwner(onBuildScheduled:)`로 다시 build 요청이 왔는지 보고, 왔으면 이벤트 루프를 양보(`await Future<void>.delayed(Duration.zero)`)하며 다시 `buildScope → flush`를 반복한 뒤(상한: 횟수·시간, `InkTuning.mathSvgSettleMs` 같은 상수) 찍는다. 상한을 넘으면 `null`(자리표시 + `mathRasterFailed`)로 두어 루트 없는 래스터가 캐시·PDF에 들어가지 않게 한다. 호스트 사용은 큐로 하나씩 처리한다.
  - T36 `math_render_test`에 `\sqrt{x}`·`\sqrt[3]{x}`·`\vec{v}`·`\xrightarrow{f}`·`\left\{\begin{array}{l}a\\b\end{array}\right.`를 넣어 '루트 기호 자리(배치 상자 왼쪽 위) 잉크 픽셀 > 0'을 단언하고, 시험 이음새(호스트에 '적재를 일부러 늦추는' 디버그 훅 또는 지연 `BytesLoader`)로 **비동기 적재 경로**를 컨테이너에서 재현한다. 웹 `offscreen_math_web_test`에도 같은 표본.
  - 11장에 '네이티브 release에서만 드러나는 경로'를 리스크로 적고, 9.6 I-A2·I-B8 확인 표본에 루트·연립방정식을 명시한다.

### M-4. 이미지·수식 캐시 예산이 실제 메모리를 묶지 못하고, 작업 집합이 예산을 넘으면 다시 기록 ↔ 다시 디코드가 끝없이 돈다

- **위치**: 4.10 `InkImageCache.peek`·`changes`(647–653행), 6.11.2 버킷, 6.11.3 핸들 규칙(1462행), 6.8.3 underlay·annotation 무효화 표(1345–1346행), 6.12.3 수식 캐시 8 MiB, 6.22 표·합계(1646–1658행), T35·T36 완료 조건.
- **문제**:
  1. 핸들 규칙상 painter가 이미지를 청크 `Picture`에 그리면 그 그림이 이미지를 붙잡는다(6.11.3 — '이미 기록된 Picture는 자기 참조로 계속 그린다'). 캐시가 LRU로 쫓아내 `dispose()`해도 **메모리는 그림이 사라질 때까지 남는다**. L2 청크 그림은 '개수 제한 없음'(6.22)이라, 예산 48 MB(웹)는 캐시 장부일 뿐 실제 사용량의 상한이 아니다.
  2. 반대로 보이는 작업 집합이 예산보다 크면 고장 난다. 예: 웹에서 사진 객체 20장(M-3 한도 긴 변 2048 px → 버킷 2048 = 16 MB씩)이 한 화면에 확대돼 있으면 320 MB > 48 MB. 디코드 A가 끝나 B를 쫓아냄 → `changes` → underlay 청크 다시 기록 → B가 `peek`에서 `null` → B 디코드 요청 → … 이 반복된다. 수식 8 MiB도 같다(200×50 pt 수식, 버킷 4 → 약 640 KB, 13개면 넘침).
  3. `changes`가 자산 id 없는 전역 `Listenable`이라 어느 페이지의 어느 디코드든 마운트된 모든 컨트롤러의 underlay 청크를 다시 기록하게 한다(S-6과 함께 보면 위 반복이 페이지 수만큼 커진다).
- **고칠 방향**:
  - 캐시 항목에 '살아 있는 그림이 쓰는 중' 참조 수를 두고 그 바이트를 예산에 센다(쫓아내지 않음). 예산을 넘는 요청은 쫓아내기 대신 **한 단계 낮은 버킷**으로 낮춰 받는다(작업 집합이 예산 안에 들어오게). 수식도 같은 규칙.
  - `changes`가 바뀐 `(assetId, bucket)`을 알려 주게 하고(내부 `Stream<String>` 또는 `ValueListenable`), 컨트롤러는 그 자산을 그리는 청크만 다시 기록한다.
  - T35·T36에 '작업 집합 > 예산(예산을 작게 준 캐시)일 때 청크 다시 기록 횟수가 유한(예: 자산 수 × 2 이하)하고 마지막에 모든 객체가 그려짐', '그림이 쓰는 중인 항목은 쫓겨나지 않음' 시험을 더한다. CP-INK-5(예산을 `InkRenderConfig`로)가 이 시험을 쉽게 하므로 R2-B3 전에 결정을 요청한다.

### M-5. 웹 메모리 합계가 300 MB를 넘는데 '7.4.5 합계 안'이라고 적었다

- **위치**: 6.22 마지막 글머리(1658행), 9.6 I-B11 합격 기준(1906행), 11장 '이미지 디코드 메모리' 행.
- **문제**: 300 MB는 1차 7.4.10의 'iPad Safari 한 탭' 예산이다. 웹 값으로 더하면 INK 184 MB(외곽선 32 + 타일 96 + 이미지 48 + 수식 8) + PDF 112 MB(미리보기 32·타일 64·썸네일 16 — 1차 표) + CORE 되돌리기 32 MiB = **328 MB**이고, 2차 7.4.5가 더한 PDF 내보내기 임시 16 MB·웹 녹음 조각 8 MB를 넣으면 352 MB다(재생 Blob은 별도 — 06-pdf 2157행). '나머지는 PDF·CORE·녹음'이라는 문장이 틀렸고, I-B11의 'INK ≤ 184 MB'만 보면 B-13의 '합계 ≤ 300 MB'가 실패할 수 있다. 위험 #10(탭 재로드)의 주 원인이 이 예산이다.
- **고칠 방향**: 계산을 바로잡고, INK가 줄일 수 있는 안을 총괄에게 제안한다 — 예: 웹 이미지 캐시를 타일 예산과 합쳐 '래스터 이미지 합계 96 + 48 → 112 MB' 공유 예산(타일과 이미지가 같은 LRU 장부), 또는 웹 이미지 32 MB. I-B11 기준을 '개발자 표시 앱 캐시 합계 ≤ 300 MB(B-13과 같은 값)'로 바꾼다. 계약 7.4.5 숫자 자체의 모순은 C-4로 올린다.

### M-6. 새 펜 5종의 펜 미리보기(`PenPreviewPainter`)가 계획에 없다 — 레이저는 지금 코드로 예외가 날 수 있다

- **위치**: 3장 트리(`render/pen_preview.dart` 변경 표시 없음), 6.2~6.7, 8.2 T27~T31 완료 조건.
- **문제**: EDITOR는 펜 선택기·고급 설정의 미리보기 획을 'INK `PenPreviewPainter`가 새 펜 모양을 그린다(INK 일)'로 넘겼다(04-editor 2086행). 1차 painter는 형광펜이 아니면 `paintFillStroke(canvas, stroke, sample.outline!)`로 그린다(`pen_preview.dart` 51–68). 레이저(`transientTrail`)는 채움 외곽선이 없으면 `outline!`에서 멈추고, 캘리그래피·점선·테이프는 외곽선 생성기가 렌더 방식별로 나뉘기 전에는 모양이 다르게 나온다. EDITOR 선택기 시험(E2-14)은 실제 INK를 쓴다.
- **고칠 방향**: 6.2에 '펜 미리보기' 줄(레이저는 빛 + 심 정지 그림, 테이프는 가림 모양·줄무늬, 캘리그래피는 `nibAngleDeg`·`nibAspect` 반영, 점선은 대시)을 더하고, T27~T31 각 완료 조건에 `widget/pen_preview_test` v2(펜마다 픽셀 > 0·예외 없음, 레이저 색 = `laserArgb`)와 `goldens/pens_p1_golden_test`의 미리보기 장을 넣는다. 트리의 `pen_preview.dart`에 `[바뀜]`.

### M-7. Chrome 시험에서 `rootBundle`이 응답하지 않는 문제를 INK 안에서만 풀어, 다른 영역의 Chrome 시험이 글꼴 적재에서 멈춘다

- **위치**: 6.23 '시험의 rootBundle' 행(1672행), 4.10 `InkFonts.ensureLoaded()` 규칙(690행), 4.12 `debugSetInkFontSource`·`test/support/note_sans_mini.dart`(741행·253행), 6.24 `fontLoadFailed` 행.
- **문제**:
  1. 계획서가 확인한 대로 `flutter test --platform chrome`에서 `rootBundle.load`는 **오류 없이 응답하지 않는다**(8초 시간 초과). `ensureLoaded`·`noteSansBytes`·`InkTextLayout.measure`(글꼴 적재를 기다림)에 시간 상한이 없어 그대로 멈춘다.
  2. 이 함수들을 부르는 다른 영역의 Chrome 시험이 이미 계획돼 있다: EDITOR `web/text_input_browser_test.dart`(세션 끝 → `measure`, E2-01), LIBRARY 변환 결과 상자 높이(`measure`), PDF 내보내기(`noteSansBytes`, V11 'VM·Chrome'). 01·04·05·06 어디에도 `debugSetInkFontSource`를 쓴다는 말이 없다(grep 결과 없음). 주입할 작은 글꼴도 INK `test/support/`에 있어 다른 패키지가 가져올 수 없다.
- **고칠 방향**: (a) `ensureLoaded`·`noteSansBytes`에 시간 상한(`InkTuning.fontLoadTimeoutMs`, 예 5,000)을 두고 넘으면 오류로 끝낸다(`measure`는 대체 글꼴 값). (b) 작은 시험 글꼴을 `testing.dart`(웹 안전, base64 상수)로 공개하고 `useInkTestFonts()` 같은 한 줄 도우미를 둔다. (c) 5.6~5.8에 'Chrome 시험에서 `InkFonts`·`InkTextLayout`을 쓰는 영역은 `setUpAll(useInkTestFonts)`'를 적고 EDITOR·LIBRARY·PDF에 알린다(X-3·X-5·X-6). KaTeX는 '적재 없이 단언'이 다른 영역에도 같다는 것도 함께 적는다.

### M-8. 완료 기준에 사용자 실기기 합격을 넣어 컨테이너에서 완료를 판정할 수 없다

- **위치**: 10장 7항(1934행).
- **문제**: '통합 뒤 9.6 B 표를 사용자가 확인하고 I-B1~I-B10 합격'을 INK 완료 기준으로 둬, 영역 완료가 사용자 기기 확인에 묶인다. 개요 5장은 '2차의 완료 판정은 언제나 컨테이너에서 도는 시험(7.7 V1~V16), 실기기 확인(7.8)은 합격 판정'으로 나눈다. I-B1('붓 끝이 자연스러움')처럼 주관 항목도 있다.
- **고칠 방향**: 10장은 1~6항(컨테이너)만 남기고, 7항은 9.6 머리에 '합격 판정(통합 뒤, 영역 완료 조건 아님) — 불합격 항목은 `PenProfile`·`InkTuning` 조정 작업으로 이어짐'으로 옮긴다.

---

## 권장

- **S-1. 웹 재생 중 매 프레임 베일 벡터 재생 비용**(6.19·6.25 B15): 웹 CanvasKit은 매 프레임 장면 전체를 다시 그린다(1차 6.14). 재생 중에는 Ticker로 매 프레임 프레임이 생기므로, 블록 베일 그림(안 쓴 획 외곽선 채움 수천 개)이 프레임마다 다시 래스터된다. B15는 VM의 기록 비용만 잰다. 개발자 표시 키 `playbackPaintUs`(p95)를 두고 I-B9에 기록 항목으로 넣고, 넘으면 블록 베일을 `toImageSync`로 래스터해 이미지로 그리는 대체 경로(타일과 같은 버킷 규칙)를 11장에 적는다.
- **S-2. 1차 코드에 이미 있는 사각 캡**(6.7-1 1319행, 3장 트리 175행, T27 `square_cap_test`[새]): 1차 채움 외곽선 생성기에 사각 캡이 이미 있다(`outline_generator.dart` 149·166–167·364–374 — `_cap(square:)`, 모서리 `r·√2`, `InkCap.square`도 이미 있음). '더한다'를 '1차 사각 캡을 쓰고 점 획(O1)만 정사각형으로 바꾼다'로 고치고 T27 작업량을 줄인다.
- **S-3. `InkLayer.cover` 추가 때 `== highlighter ? … : (ink)` 분기 점검 목록**(6.7-5): 1차 코드에는 '형광펜이 아니면 ink'로 처리하는 곳이 여럿 있다 — `sessions.dart` 208(`_layer` → `inkActive`), `vector_export.dart` 155(→ `inkShapes`), `ink_page_controller.dart` 687·701·719, `pen_preview.dart` 56, `thumbnail_renderer.dart` 120(`!= ink → continue`라 테이프를 건너뜀), `layer_painters.dart` 27–51(`switch`). 'INK 거르기가 그대로 뺀다'(1323행)는 887행 한 곳에만 맞다. T31에 이 목록을 적어 빠짐을 막는다.
- **S-4. 이미지 배경 첫 디코드를 원본 해상도로 하지 않아도 된다**(6.11.1 1452행): `instantiateImageCodec(targetWidth:)`만 주면 비율이 유지되고 `allowUpscaling: false`로 원본을 넘지 않으므로, 디코드 결과 크기에서 비율을 얻으면 된다. 또는 PNG IHDR·JPEG SOF 헤더를 Dart로 읽어 크기만 얻는다(PDF도 헤더로 읽는다 — 06-pdf 1356행). 이미지 페이지 50장 노트를 앱 시작 뒤 넘길 때 장마다 16 MB 일시 디코드가 반복되는 것을 없앤다.
- **S-5. 작업 크기**: T26(글꼴 생성 도구·부분 집합·범위표·`cmap` 대조·`InkFonts`·`InkTextLayout`·`validate`·`layout`·화면 밖 호스트·`MathPreview`·고지·Chrome 시험 2개)은 한 세션을 넘는다. R2-B3 임계 경로라 'T26a 글꼴·측정(EDITOR가 기다림)'·'T26b 수식 검증·배치·미리보기(recog가 기다림)'로 나누면 먼저 끝난 쪽을 알릴 수 있다. T32(1차 `InkChunkCache` 항목 타입 일반화 — 타일·appended·L1 경로를 다 건드림)와 T37(적중·올가미·선택·변형·지우개·대기 표시·인계 시험)도 둘로 나누기를 권한다.
- **S-6. `InkImageCache.changes`에 자산 id**(4.10 653행): M-4와 별개로도, 전역 알림 하나에 모든 컨트롤러가 underlay 청크를 다시 기록하는 것은 썸네일·여러 페이지 스크롤에서 불필요한 일이다.
- **S-7. 개발 도구 판**(7.1 1749행, 6.10.1): fonttools 4.68.0은 2026-10-27 게시(9일), brotli 1.2.1은 2026-10-22(14일 경계)다. pub 의존이 아니라 '게시 14일 규칙'(7.5)의 직접 대상은 아니지만 같은 취지로 4.67.0(2026-10-14)으로 고정하거나 '개발자 도구는 예외'라고 적는다. TTF만 만드므로 brotli(woff2용)는 필요 없을 수 있다. 원본 주소는 `main` 대신 커밋 해시가 든 주소로 적는다(sha256 대조는 이미 있음).
- **S-8. 시각 기준 문장**(6.6-2·6.18): 1차 `InkClock.alignedWithEventTimestamps`는 네이티브에서 false다(`diagnostics/ink_clock.dart` 13). 레이저 자취 수명은 `InkClock`만, 멈춤 감지는 샘플 시각(`InkSample.timeUs`)끼리 + 타이머만 비교하고 둘을 섞지 않는다는 규칙을 한 줄로 적는다(네이티브에서 이벤트 시각과 `nowUs()`를 빼면 틀림).
- **S-9. 수식 `layout`을 build·layout·paint 안에서 부르지 않는다**(6.12.2): 별도 `BuildOwner`·`PipelineOwner`라도 바깥 build 중에 `buildScope`를 돌리면 디버그 단언에 걸릴 수 있다. '프레임 단계 밖(이벤트 처리·Future)에서만' 규칙을 4.10에 적고, 바깥 build 안에서 부르면 `StateError`인지 허용인지 시험으로 정한다.
- **S-10. 화살표 머리와 선 끝의 겹침**(6.9.3): 선을 밑변 중점 `B`까지 둥근 캡으로 그으면 캡 반원(반지름 `w/2`)이 삼각형 안으로 들어가 `strokeOpacity < 1`일 때 겹친 곳이 진해진다(화면·PDF 모두 — 별도 `InkFillShape`). 선 끝을 버트 캡으로 하거나, 테두리와 머리를 한 경로(nonzero 합집합)로 만든다.
- **S-11. 자동 도형 미리보기 층**(6.18 1578행): overlay에 그린 미리보기가 텍스트 상자·테이프 위에 보이다가 커밋 뒤 ink 층(그 아래)으로 내려간다. M-1과 같이 `inkActive`에 그리면 미리보기 = 결과 층이 된다.
- **S-12. `inkPageControllerProvider`의 `ref.read`**(4.11 703행): provider 본문에서 `ref.read`로 한 번 읽으면 '바뀌면 다음 획부터'가 되지 않는다. 1차 `pressureMode: () => ref.read(...)`처럼 읽는 함수를 넘긴다.
- **S-13. 12.3 답 보충**: EDITOR CP-E3(R2-B3에 `setPreviewObjects`·`hitTestTape`·`hitTestRecorded`·레이저 `end() == null`)는 4.13 표로 이미 충족 — '동의(4.13)'로 적는다. PDF CP-PDF-7(`InkTextLayout.rasterize`)·CP-PDF-8에 답이 없다(X-6). Q9는 LIBRARY가 INK `MathPreview`를 쓴다고 적었으므로(05-library 152·1757행) 닫는다.
- **S-14. `InkSelection.recolor`가 바꿀 것이 없을 때**(6.14): 이미지·모르는 객체만 선택하면 `targetIds`가 비어 `isEmpty` 편집이 나온다(1차 `recolor`는 `InkEdit` 비-null 반환). EDITOR가 '색'을 숨기지만(04-editor E2-07), '빈 편집을 돌려주고 `toCommand`는 `StateError`'를 4.10 표에 적는다.
- **S-15. 썸네일이 웹에서 `NoteSans` 적재를 일으킨다**(6.20 3단계): 라이브러리 표지·페이지 패널 썸네일이 텍스트 상자 페이지를 만나면 430 KB를 받는다. 7.4.5 '텍스트 상자를 처음 그릴 때'와 같은 뜻인지(썸네일도 그리기) 한 줄로 밝히고, I-B6에 '라이브러리 첫 표시 지연'을 기록 항목으로 더한다.

---

## 다른 영역과 걸리는 것

- **X-1 (CORE)**: M-2 — 객체 변형의 단일 규칙. `TransformElements`가 객체에 적용하는 결과(도형 굵기 배율, 수식 글자 크기, CP-2 텍스트 글자 크기)를 INK가 미리보기에 그대로 쓸 수 있는 공개 함수로 CORE가 제공하도록 요청한다. CP-2를 `transformed` 안에 넣을지 해석기 쪽에 둘지도 이것과 같이 정한다.
- **X-2 (CORE)**: CORE CP-1(새 명령을 이름 있는 인자 + `const` + `label`로)은 INK `toCommand` 표(`core.AddObjects(pageId, addedObjects)` 등 위치 인자 표기)에 바로 걸린다. 4.6 표 아래에 'CP-1 결정대로 호출 모양을 따른다'를 적고, CP-1이 R2-B2 전에 정해지면 R2-B3의 `ink_edit_test`도 그 모양으로 쓴다.
- **X-3 (EDITOR)**: 텍스트 상자 편집기 글자 모양. INK는 `StrutStyle(forceStrutHeight: true, height: lineHeight)` + 안쪽 여백 0으로 그리는데(6.10.2), 04-editor는 `EditableText`의 `StrutStyle`·여백을 적지 않았고 CP-INK-3도 언급하지 않는다(grep 결과 없음). 같지 않으면 세션 끝에 글자 위치가 튄다(E-6). CP-INK-3을 EDITOR와 함께 결정하고, 승인 전에는 EDITOR가 6.10.2 표를 그대로 쓴다는 확인을 받는다. Chrome 시험 글꼴(M-7)도 함께 알린다.
- **X-4 (EDITOR)**: 시트(안 A) 입력 중 `setPreviewObjects([draft])`로 텍스트 상자를 미리 그리는데(04-editor 1993행), INK는 글자를 **frame으로 자른다**(K-6). 초안의 frame 높이가 입력 전 높이 그대로면 새 줄이 잘려 보이지 않는다. EDITOR가 초안 높이를 `measure`로 갱신하거나(비동기 — 키 입력마다 기다림), INK가 글꼴 적재 뒤 쓸 수 있는 동기 측정(`InkTextLayout.measureSync`, 적재 전 `null`)을 더하는 안 중 하나를 정한다.
- **X-5 (EDITOR)**: '빈 곳 끌기 → 끄는 동안 `setPreviewObjects`로 빈 상자 테두리'(04-editor 1923행) — INK의 텍스트 상자 그리기는 배경과 글자뿐이라(6.10.3) 빈 글·배경 없음 상자는 아무것도 그려지지 않는다. EDITOR가 overlay에 끌기 사각형을 직접 그리거나, INK가 미리보기 객체 중 빈 텍스트 상자에 점선 테두리를 그리는 규칙을 더한다(INK 쪽이면 4.10 표에 한 줄).
- **X-6 (EDITOR)**: 테이프 '모두 보이기'를 노트 단위로 들고 새로 마운트되는 페이지에도 적용한다(04-editor 1262행 I-10). INK `setAllTapesRevealed(true)`는 '지금 있는 테이프만' 드러내므로(4.10 684행), 마운트 직후 내용이 아직 오지 않은 컨트롤러에 부르면 아무것도 드러나지 않는다. (a) EDITOR가 첫 `updateContent` 뒤에 부르거나 (b) INK가 '모두 드러냄 모드(다음 `toggleTape`·`setAllTapesRevealed(false)` 전까지, 그 뒤 들어오는 테이프 포함)'로 의미를 바꾸는 것 중 하나로 맞춘다. 펜으로 새로 그린 테이프는 가린 채 시작해야 하므로 (b)면 '내용 갱신으로 들어온 테이프'와 '이 컨트롤러에서 방금 그린 테이프'를 구분하는 규칙이 필요하다.
- **X-7 (PDF)**: 06-pdf는 R2-B3~T42 동안 `InkPageVectors` v2 값을 손으로 만들어 시험한다고 적었다('INK 공개 생성자 — 없으면 …', 06-pdf 1369행). 1차 `InkPageVectors`·`InkFillShape`·`InkHighlighterGroup`은 비공개 생성자(`._`)이고 계약 블록에도 생성자가 없다. INK `testing.dart`에 시험용 생성 도우미(예: `testInkPageVectors({…})`, `testInkFillShape(…)`, `InkTextVector`·`InkMathVector`·`InkImageVector`)를 두는 것을 4.12에 더한다(C-5).
- **X-8 (PDF)**: CP-PDF-7(`InkTextLayout.rasterize(TextBoxObject, pixelsPerPt:)`)·CP-PDF-8에 INK 답이 없다. '그리는 의미는 INK' 원칙과 M-3의 래스터 호스트 정리를 생각하면 CP-INK-3보다 CP-PDF-7이 PDF 쪽에는 더 맞다(대체 글꼴·자르기까지 같은 코드). 12.3에 답을 적는다. PDF V11 Chrome의 한글 추출 확인은 M-7 (b) 도우미가 있어야 Chrome에서도 된다.
- **X-9 (LIBRARY)**: 05-library는 R2-B3 INK를 'MathPreview는 래스터 없이 상자'로 읽었다(1178행). INK 4.13은 `MathPreview`를 R2-B3부터 실제 동작으로 준다(개요 R2-B3 문장 '수식은 `MathPreview` 래스터 없이 상자'가 모호한 탓 — C-8). LIBRARY에 '패드 미리보기 시험을 기반 단계부터 실제로 돌려도 된다'고 알린다. Chrome 시험 글꼴(M-7)도 같다.
- **X-10 (INFRA)**: Q6의 `.gitattributes`(`*.ttf binary`)와 `assets/fonts/`의 `README.md`·`OFL.txt`가 웹 빌드 `assets/`에 함께 실린다는 것(웹 자산 검사 `web-assets verify`가 모르는 파일을 막는지)을 INFRA와 확인한다.

---

## 계약 문제

- **C-1. L-1 7행 '재생 강조'의 층**(7.2.9 L-1 표): M-1 — overlay에 두면 annotation·cover 위에 그려져 테이프 아래 글씨가 샌다. 'ink 위·annotation 아래(살아 있는 층), 기본 래스터 불변'으로 바꾸자고 제안한다. K-9 문장에 '화면 재생 강조도 가린 테이프를 바꾸지 않는다'를 더한다.
- **C-2. `StrokeSession` 선언**(7.2.9 `abstract class StrokeSession { /* v1.4 */ … }`): v1.4와 1차 코드는 `final class StrokeSession implements InkGestureSession`이다(`sessions.dart` 195, 1차 03-ink 1016행). 계약 문장대로 `abstract class`로 바꾸면 의미가 달라진다(외부 구현 허용). INK 계획서는 계약 블록을 글자 그대로 옮겨 같은 문장을 갖고 있다(484행). 계약을 `final class StrokeSession implements InkGestureSession { /* v1.4 */ ValueListenable<InkShapeFit?> get shapePreview; }`로 고치고, INK 4.10에 '`final` 유지'를 적는다.
- **C-3. `InkEdit`의 객체 id 구분**(7.2.9 `toCommand` 표): '획뿐이면 `RemoveStrokes`, 객체가 섞이면 `RemoveElements`'를 하려면 `removedIds` 가운데 어느 것이 객체인지 알아야 하는데 공개 필드가 없다. INK는 비공개 `_objectIds`로 풀었다(6.16 1549행). 그러면 같은 공개 필드의 두 `InkEdit`이 다른 명령을 내고(`==`도 다름), 공개 생성자로 만든 `eraseStrokes`/`deleteStrokes`에 도형 id를 넣으면 `RemoveStrokes`가 되어 **도형이 지워지지 않고 조용히 무시된다**(CORE `RemoveStrokes`는 모르는 id 무시). 공개 선택 인자 `Set<String> removedObjectIds = const {}`(또는 `objectIds`)를 계약에 더하자고 제안한다(추가 — 동시 개발 중 '추가만' 규칙 안).
- **C-4. 7.4.5 메모리 합계**: M-5 — 2차 표의 예산을 더하면 웹 300 MB를 넘는다(328~352 MB). 총괄이 영역별 웹 예산을 다시 나누거나 합계를 바꿔야 한다. INK 쪽 제안은 M-5.
- **C-5. 벡터 v2 값 타입의 생성 방법**(7.2.9 `InkPageVectors`·`InkImageVector`·`InkTextVector`·`InkTextLine`·`InkMathVector`): 계약에 생성자가 없고 1차 값 타입은 비공개 생성자다. PDF가 기반 단계부터 손으로 만든 값으로 시험하려면(06-pdf 1369행) 공개 생성자 또는 INK `testing.dart` 생성 도우미를 계약(7.6 시험 도우미 블록)에 적어야 한다.
- **C-6. 객체 변형 규칙의 단일 출처**(7.2.3 `TransformElements` 규칙 주석): '`PageObject.transformed`'와 '`scaleStrokeWidth also scales ShapeStyle.strokeWidth`'가 다른 자리에 있어, `transformed`만 부르는 소비자(INK 미리보기·대기 표시, EDITOR 클립보드 미리보기)가 해석기와 다른 결과를 그린다. CORE 공개 도우미를 계약에 올린다(X-1).
- **C-7. CP-INK-2의 결정 시점**: 계획서는 R2-B3 전 결정이 필요하다고 했고, 결정이 없으면 계약 표('그 밖 v1.4')와 **다른** `CompositeCommand`로 구현한다(6.15). '승인 전에는 계약 원문'이라는 4.0·10장 5항 원칙의 예외이므로 총괄이 R2-B3 전에 승인하거나 거절해야 한다. 같은 묶음으로 CP-INK-5(예산 위치 — M-4 시험에 필요)도 R2-B3 전에 정한다.
- **C-8. 7.6 R2-B3 문장의 모호함**: '수식은 `MathPreview` 래스터 없이 상자'는 'MathObject는 연한 상자, `MathPreview` 위젯은 실제 동작'으로 고친다(LIBRARY가 반대로 읽음 — X-9).

---

## 질문

1. (총괄) M-1의 층 이동(C-1)을 받아들이는가? 받아들이지 않으면 대안은 'overlay 베일·강조를 가린 테이프·annotation 영역으로 잘라 내기(clip)'인데, 테이프 수만큼 clip 경로가 생겨 프레임 비용이 커진다.
2. (총괄) 웹 메모리 예산(M-5·C-4)을 어떻게 다시 나눌 것인가? INK는 '타일 + 이미지 공유 112 MB' 또는 '이미지 32 MB'를 제안한다.
3. (총괄·EDITOR) 테이프 '모두 보이기'(X-6)를 INK 의미 변경(b)로 할 것인가, EDITOR 호출 시점(a)으로 할 것인가?
4. (총괄·PDF·EDITOR) 텍스트 문단 모양의 공유를 CP-INK-3(`textStyleOf`·`strutStyleOf`)과 CP-PDF-7(`InkTextLayout.rasterize`) 둘 다로 할 것인가? EDITOR 편집기는 `TextStyle`이 필요하고 PDF는 래스터가 필요하다.
5. (총괄) M-3의 비동기 SVG 적재를 컨테이너에서 재현할 시험 이음새(디버그 훅)를 INK 공개 표면(`testing.dart`)에 둘지, 내부 `@visibleForTesting`로 둘지?
6. (사용자·U7) 부분 집합 밖 한글(KS X 1001 밖 8,822자)이 든 텍스트 상자는 PDF에서 **상자 전체가** 래스터로 바뀌어 검색되지 않는다. 지금 기본값(2,350자)으로 가도 되는가, 상용 한글 전체(약 2 MB/굵기 — [추측])를 웹 지연 적재로 받을 것인가?

---

## 확인한 것 (요약)

- 계약 블록: 4.1~4.9의 Dart 블록이 개요 7.2.9와 줄 단위로 같다. 4.0 새 공개 이름 22개 수가 맞다.
- 1차 코드: `InkEdit`의 `const` 공개 생성자·`toCommand`의 `scaleStrokeWidth: true`(`edit/ink_edit.dart`), `InkFillShape._`·`InkPageVectors._` 비공개 생성자와 `exportStrokes(List<InkStroke>)`(`export/vector_export.dart` 67–137), `final class StrokeSession implements InkGestureSession`(`render/sessions.dart` 195), `select(Set<String>)`(`ink_page_controller.dart` 361), 컨트롤러·썸네일 렌더러·`InkPageThumbnail`이 `backgroundBuilders` 목록을 받음(CP-INK-6 근거 맞음), `inkPageControllerProvider`가 `pageBackgroundBuildersProvider`를 `watch`(`providers.dart` 97), 사각 캡·`InkCap.square`가 이미 있음(`outline_generator.dart` 149·364), `InkClock.alignedWithEventTimestamps`(네이티브 false), `onWarning(String code)`(문자열 키 — 새 키 추가가 다른 영역을 깨지 않음), INK 밖 INK enum 사용은 EDITOR의 값 비교 3곳뿐(C2-19 주장 맞음).
- CORE: `AssetStore` 멤버 9개(`bytesArrived` 포함 — 6.11.4 맞음), `ImageBackground.fit`·`ImageFit{contain, cover, fill}`, `noteStoreProvider` 기본 `UnimplementedError`(`providers.dart` 34), `Affine2.rotation = atan2(b, a)`(`geometry.dart` 164), `StrokeStyle.defaultsFor` P1 값(`pen_style.dart` 80–108)과 extras 깊은 비교(`_deep.equals`).
- 외부: pub.dev — `flutter_math_fork 0.7.4`(2025-05-21, `flutter_svg >=2.0.0+1 <3.0.0`), `flutter_svg 2.3.0`(2026-05-08)/2.3.2(2026-10-28), `vector_graphics 1.2.3`(2026-07-31)/1.2.6(2026-11-02), `vector_graphics_compiler 1.3.0`(2026-07-28, `xml >=6.3.0 <=7.0.1`), 간접 `vector_graphics_codec 1.1.13`·`path_parsing 1.1.0`·`provider 6.1.5+1`·`tuple 2.0.2`·`http 1.6.0`·`xml 7.0.1` 모두 14일 넘음. PyPI — fonttools 4.68.0(2026-10-27), brotli 1.2.1(2026-10-22).
- 다른 계획서: 01-infra(CP3·CP5·CP7·`forbidden_font_families` — INK 답과 맞음), 02-core(CP-1·CP-2·CP-5·CP-6·CP-9, `transformed` 굵기 규칙 1429·1482행), 04-editor(I-2~I-13, CP-E3, 시트 미리보기·빈 상자 테두리·테이프 노트 상태·펜 미리보기), 05-library(`GeometricShapeFitter`·수식 패드·`MathPreview`), 06-pdf(벡터 v2 사용 표·CP-PDF-7·8·CP-INK 답).
