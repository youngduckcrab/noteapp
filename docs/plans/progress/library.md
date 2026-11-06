# LIBRARY 진행 기록

## 요약

- 마지막 세션: 통합 단계 1차(CORE → INK → EDITOR·LIBRARY 병합 뒤) — L21 실제 CORE로 통과('통합 단계' 절). 동시 개발 단계 몫(L0~L20)은 세션 8까지 끝(세션 1: C13-05·L0·L1·L3·L4, 세션 2: L5~L8, 세션 3: L9·L10, 세션 4: L11·L12, 세션 5: L13·L14, 세션 6: L15·L16, 세션 7: L17·L18, 세션 8: L19·L20, L2는 기반 단계 B6에서 완료)
- 다음 할 일: INFRA·PDF 병합 뒤 남은 통합 확인('통합 단계' › 남은 것 — V5 배너 문구, 앱 웹 빌드에서 9.2 준비, 사용자 iPad 확인)
- 기준: 계획서 `docs/plans/05-library.md` 8장(작업 분해), 통합 계약 00-overview 7장 v1.4
- (2차) 기반 단계 R2-B6 완료 — `99cdeef`(아래 '## 2차'). 기준: 계획서 `docs/plans/m5-7/05-library.md` 8.1, 통합 계약 m5-7/00-overview 7장 v2.2(7.2.11, 7.6.2 R2-B6 행, 7.6 시험 도우미)

## 작업 표

| ID | 상태 | 커밋 | 비고 — 완료 조건 테스트 파일 |
|---|---|---|---|
| B6 | 기반 단계에서 완료 | 676d241 | `test/feature_library_smoke_test.dart`, `unit/api_surface_test.dart` |
| C13-05 | 완료 | 307bd78 | 계획서 상태 줄 '승인'·계약 v1.4 인용·13.3 최종 승인 표(LIBRARY-3-1~3-3, 4-1, C14-01·02) |
| L0 | 완료 | 1d25517 | `unit/fake_library_backend_test.dart`, `widget/scenarios_on_fake_test.dart` — `test/support/`(TestClock, FakeLibraryBackend, FakeThumbnailRenderer, TestSizes, fixtures, pump_library, LibraryTestHarness), `test/shared/library_scenarios.dart` |
| L1 | 완료 | c2a55ea | `unit/date_format_test.dart`, `unit/josa_test.dart`, `unit/names_test.dart`, `unit/strings_contract_test.dart` |
| L2 | 기반 단계에서 완료 | 676d241 | `unit/appearance_test.dart` (B6에서 4.4 실제 값·L2 검사 전부) |
| L3 | 완료 | 9c8ebc2 | `unit/sort_test.dart`, `unit/prefs_notifier_test.dart`, `unit/settings_keys_test.dart`, `unit/page_size_mm_test.dart`, `unit/new_note_options_test.dart`, `shared/new_note_options_cases.dart`, `web/new_note_options_browser_test.dart` |
| L4 | 완료 | 9deed79 | `unit/section_test.dart`, `unit/selection_test.dart` |
| L5 | 완료 | d12ef32 | `unit/tree_flatten_test.dart`, `unit/breadcrumb_test.dart`, `unit/location_label_test.dart` |
| L6 | 완료 | 8dd7f5f | `unit/content_provider_test.dart`, `unit/expansion_test.dart` |
| L7 | 완료 | 6e936b5 | `unit/actions_test.dart` |
| L8 | 완료 | 58eb35c | `unit/grid_metrics_test.dart`, `widget/layout_test.dart` |
| L9 | 완료 | 80b8ddd | `unit/sync_badge_look_test.dart`, `widget/sidebar_test.dart` |
| L10 | 완료 | 581329e | `widget/listing_test.dart`, `widget/breadcrumb_bar_test.dart`, `widget/folder_missing_test.dart` (+ B6 `feature_library_smoke_test.dart` 갱신) |
| L11 | 완료 | bd43eaf | `unit/cover_scheduler_test.dart`, `widget/cover_view_test.dart` (+ `support/recording_thumbnail_io.dart`) |
| L12 | 완료 | ade94c3 | `widget/new_note_dialog_test.dart`, `widget/new_folder_dialog_test.dart` (+ B6 `feature_library_smoke_test.dart`·L10 `widget/listing_test.dart` 갱신) |
| L13 | 완료 | 7be0606 | `widget/item_actions_test.dart`, `widget/folder_picker_test.dart` (+ 공유 시나리오 2건 `shared/library_scenarios.dart` → `widget/scenarios_on_fake_test.dart`) |
| L14 | 완료 | c979633 | `widget/multi_select_test.dart` |
| L15 | 완료 | d4a2f20 | `unit/drop_decision_test.dart`, `unit/drag_handle_test.dart`, `unit/auto_scroll_test.dart`, `widget/drag_drop_test.dart`(touch·stylus 각 12건), `widget/auto_scroll_widget_test.dart` (+ 공유 시나리오 1건 `shared/library_scenarios.dart`) |
| L16 | 완료 | 82509da | `widget/trash_view_test.dart` (+ 공유 시나리오 1건 `shared/library_scenarios.dart`) |
| L17 | 완료 | b4581da | `widget/recent_favorites_test.dart`, `widget/search_test.dart`, `unit/search_match_test.dart` (+ 공유 시나리오 2건 `shared/library_scenarios.dart`, L13 `widget/item_actions_test.dart` 갱신) |
| L18 | 완료 | ccdc941 | `widget/integration_slots_test.dart`, `widget/storage_banner_test.dart`, `widget/settings_section_test.dart` (+ 공유 시나리오 2건 `shared/library_scenarios.dart`, B6 `feature_library_smoke_test.dart` 갱신) |
| L19 | 완료 | dd82973 | `goldens/library_golden_test.dart`(+ PNG 4장, `goldens/flutter_test_config.dart`), `widget/performance_test.dart`, `widget/a11y_test.dart` |
| L20 | 완료 | 6b2567c | `web/library_browser_test.dart`, `web/scenarios_browser_test.dart` (+ L3 `web/new_note_options_browser_test.dart`) — `flutter test --platform chrome test/web` 17개, `ws test --platform chrome --package feature_library` 통과 |
| L21 | 완료(통합 단계) | 4450eaa (미리 작성), aabcabe (통합) | `integration/core_contract_test.dart` (`@Tags(['integration'])` + `@TestOn('vm')`) — 세션 8에 미리 썼고, 1차 통합에서 실제 CORE로 10건 통과(닫기 방식만 고침 — '통합 단계' 절). 기본 실행은 skip(`~1`) 그대로 |

## 변경 요청

- 없음

## 의존성 요청

- 없음

## 계획과 다르게 한 점

- L0 `FakeLibraryBackend`: 5.7 시그니처에 더해 `queries`(래퍼를 거친 읽기 호출 기록 — 예: `'watchListing LibraryQuery(folder: null, updatedAt, desc)'`, `"searchLibrary '<q>' limit:50"`)를 두었다. `folderTreeProvider`가 래퍼를 거치는지(L0 완료 조건), 정렬이 `LibraryQuery`로 전달되는지(L10), 검색 디바운스 횟수(L17)를 확인하는 데 쓴다. `library`·`trash`의 정적 타입은 `RecordingLibraryRepository`·`RecordingTrashRepository`(각각 CORE 인터페이스 구현).
- L0 `calls` 형식은 `fake_library_backend.dart` 클래스 주석에 표로 적었다(예: `moveItems [n:<id>, f:<id>] -> f:<id>`, 대상 `null`은 `home`). 기록은 지연·실패 주입보다 먼저 남는다(실패한 호출도 기록). 씨앗 도우미(`seed*`)·`remoteChange`는 래퍼를 거치지 않아 기록·주입이 없다.
- L0 `seedOpened`는 `openSession` → `close()` 뒤 `store.flush()`까지 기다린다(가짜의 `markOpened`는 커밋을 기다리지 않음 — N-6). `seedNote(favorite: true)`는 만든 뒤 `setFavorite`하고 다시 읽은 값을 돌려준다.
- L0 `FakeThumbnailRenderer`: `failFor`·`nullFor`는 호출이 시작될 때 판정한다(`delay` 동안 테스트가 집합을 바꿔도 진행 중인 렌더 결과는 그대로 — L11 경합 테스트용).
- L1 `LibraryStrings`: 6.18 주요 문구 표 + 6.16.1 동기화 툴팁 문구 + `close`('닫기')·`loadFailed`('불러오지 못했어요', 6.19)를 넣었다. 동기화 중 문구는 상수 `syncInProgress`와 함수 `syncInProgressCount(n)`로 나눴다(이름이 같은 상수·함수를 둘 수 없음). 조사 문장 도우미 `quotedWithObject`·`quotedWithDirection`(`'<이름>'을` 형태)을 더했다. 한 화면 부분에서만 쓰는 문구는 그 작업(L8~L18) 때 추가한다.
- L1 `KoreanJosa`: 끝 공백은 무시, 빈 문자열·기호·한글 자모(완성형 음절이 아닌 것)는 '을(를)'·'(으)로'. `names.dart`에 `kMaxUniqueNameNumber = 999` 상수를 더했다.
- L3 `NewNoteOptions.fromJson`: `"template": null`(키 있음)은 빈 페이지, 키가 없거나 모르는 값이면 기본값(`lined`) — `toJson`이 빈 페이지를 `null`로 쓰므로 왕복을 위해 둘을 구분했다. `paper`는 정수로 표현되는 수(웹 `int`/VM `double` 정수값)만 받고 `PaperColors.all` 밖이면 흰색. `isCustom` getter와 `NewNoteSpec`(6.12, `toPageDraft`)·값 동등도 L3에서 같이 만들었다.
- L3 `LibraryPrefsNotifier.selectSort`: `sortField`·`sortDescending` 두 쓰기를 기다리지 않고 연달아 넣어 한 커밋으로 묶는다(중간 스냅숏에 한쪽만 바뀐 값이 오지 않게). 쓰기 실패는 `reportLibraryError`(`lib/src/common/report_error.dart`, `library: 'feature_library'`)로 보고하고 낙관적 상태는 유지.
- L3 `providers.dart`에는 지금 `libraryPrefsProvider`·`newNoteDefaultsProvider`만 있다. 나머지 provider는 해당 작업 때 같은 파일에 더한다.
- L4 `LibrarySelection`: 계획의 private 생성자 대신 공개 팩터리 `LibrarySelection.activeWith(keys)`(중복 제거, 첫 순서 유지)를 두었다 — 알림자 파일에서 만들 수 있어야 해서. `contains`용 `Set`을 함께 들고 있다(1,000개 타일에서 O(n²) 방지). `isEmpty`, `keyOfRef(LibraryItemRef)` 도우미를 더했다. `begin(first)`는 이미 선택된 키를 유지하고 `first`를 덧붙인다. 같은 섹션 값을 다시 넣으면(`showRouteFolder` 등) 선택은 유지되고, 검색어가 바뀌면 다른 섹션이라 선택이 비워진다.
- L5 `flattenFolderTree` 5단계(순환 폴더): '방문하지 않은 폴더'를 '보인 행'이 아니라 '어느 루트에서도 닿지 않는 폴더'(펼침과 무관한 도달 집합)로 읽었다 — 그대로 읽으면 접힌 폴더의 자식까지 최상위에 나오기 때문. 닿지 않는 폴더를 이름순으로 보며, 아직 덮이지 않은 것만 최상위처럼 내보내고 그 하위 전체를 덮음으로 표시한다(순환 x↔y는 한 줄 x로 보이고 펼치면 y가 그 아래). 도달 집합 계산 때문에 비용은 O(전체 폴더 수)(2,000개 테스트 통과).
- L5 `breadcrumb.dart`에 `breadcrumbPath(tree, folderId)`(= `[홈, ...tree.pathTo(id)]`, 트리에 없으면 `[홈]`) 도우미와 세 슬롯 타입의 값 동등을 더했다. `compressBreadcrumb`는 `maxVisible >= 2`를 assert. 크기 등급별 칸 수(4·3·2)는 L8/L10의 상단 막대에서 정한다.
- L5 `LibraryStrings`에 `pathSeparator`(' › ')·`ellipsis`('…')를 더했고 `locationLabel`이 쓴다. `kLocationLabelMaxNames = 3` 상수.
- L6 `libraryContentProvider`·`sidebarRowsProvider`: 보기 설정이 로드되기 전에는 `AsyncLoading`(휴지통 섹션 포함 모든 섹션). 단 `settingsSnapshotProvider`가 오류면 기본 정렬로 로드된 것으로 본다(설정 스트림 오류로 화면이 영원히 로딩에 머무르지 않게). 사이드바 행도 정렬(이름/사용자 지정)에 따라 순서가 바뀌므로 같은 규칙으로 기다린다. 검색 상한 50은 `kLibrarySearchLimit` 상수(`providers.dart`).
- L6 `folderLookupProvider`: `folderTreeProvider.future`에 더해 `trashItemsProvider`도 watch한다 — 휴지통에 있는 폴더를 다른 기기가 영구 삭제하면 트리는 바뀌지 않아(값 동등) 다시 계산되지 않기 때문. 트리에 없고 `getFolder`가 휴지통 아닌 폴더를 주면(트리 갱신 직전 경합) `active`.
- L6 `trashCountProvider`: 오류면 이전 값이 있어도 0.
- L6 `FolderExpansionNotifier`: 상태 `Set`은 펼친 순서(오래된 것 → 최근)로 순회한다. 이미 펼친 id를 다시 펼치면 자리 그대로(`expandAll`이 아무것도 바꾸지 않으면 같은 상태 객체·저장 없음). 저장된 목록이 오기 전에 접은 id는 복원하지 않고, 그 전에 디바운스가 끝나면 쓰지 않고 로드 뒤 500ms에 쓴다(저장된 id를 덮어쓰지 않게). 트리는 `ref.listen(folderTreeProvider)`로 따라가며 마지막 값으로 거른다(트리가 아직 없으면 거르지 않음). `ref.onDispose`에서는 `state`를 읽을 수 없어(Riverpod 3 생명주기 규칙) 사본 `_current`를 쓴다. 로드 실패는 `reportLibraryError` 1회 후 빈 상태.
- L7 `LibraryActions` 생성자는 private 이름 붙은 초기화 형식(`{required this._library, ...}`)으로 썼다 — 호출 쪽 이름은 계획 그대로 `library:`·`trash:`·`report:`(린트 `prefer_initializing_formals`).
- L7 `move`의 영수증(`MoveReceipt`)에는 `originalParents` 중 원래 부모가 대상과 다른 항목만 넣는다(이미 대상에 있던 항목은 CORE가 무시하므로 되돌릴 것도 없음, C-4). `undoMove`는 원래 부모별로 묶어 영수증 순서대로 부모마다 `moveItems` 1회, 첫 실패에서 멈춘다. `MoveReceipt`에 값 동등·`isEmpty`를 더했다.
- L7 `reorder`: 항목이 0개면 아무것도 부르지 않는다. CORE `reorderItems`는 넘긴 순서가 아니라 항목들의 **현재 상대 순서**를 유지한다(가짜에서 확인: `[c, a] after d` → `… d, a, c`). 화면은 어차피 표시 순서로 넘긴다.
- L7 `rename`은 이름을 미리 검사하지 않고 CORE에 넘긴다(대화상자가 미리 막음 — 6.11). CORE `ArgumentError` → `invalidName`. `ArgumentError`의 하위 타입(`RangeError`)도 `invalidName`.
- L7 `locate`·`uniqueNoteTitle`은 `ActionOutcome`이 아니라 값을 돌려주므로 읽기 실패는 보고 후 각각 `null`·기본 이름. `uniqueNoteTitle`은 `watchListing(LibraryQuery(folderId, name, asc)).first`로 노트 제목을 읽는다. `locate`는 휴지통에 있어도 부모를 돌려준다(없을 때만 `null`).
- L7 `lib/src/model/folder_appearance_value.dart`(`FolderAppearance`, `NewFolderSpec`, 값 동등)를 L7에서 만들었다. `libraryActionsProvider`의 `report`는 `reportLibraryError`(문맥 `'library action: <메서드>'`).
- L8 화면 구조: `LibraryScreen`(State) → `LibraryScope`(내부 InheritedWidget, `lib/src/ui/library_scope.dart` — `routeFolderId`·`sizeClass`·`openFolder`(6.4: 서랍 닫기 → 라우트 폴더면 `showRouteFolder()`, 아니면 `onOpenFolder`)·`openNote`·`openSettings`·`openDrawer`, 이벤트 처리기용 `LibraryScope.read`) → `Scaffold(key, drawer: expanded가 아니면 Drawer(320, LibrarySidebar(inDrawer: true)))` → `SafeArea` → `LibraryLayout`(expanded + `sidebarVisible`이면 `Row[사이드바 280, VerticalDivider(1), Expanded(ContentPane)]`) → `ContentPane`(`Column[LibraryTopBar 64, Divider, Expanded(ContentBody)]`). 크기 등급은 `MediaQuery.sizeOf(context).width`로 정한다(서랍 여부를 Scaffold 전에 알아야 해서 — 6.1 그림의 LayoutBuilder 대신). `LibraryDragScope`(L15)·`StorageWarningBanner`(L18)·`SelectionBar`(L14) 자리는 주석으로만 있다.
- L8 `LibrarySidebar`는 틀만: 앱 이름 줄(56, `LibraryStrings.appTitle` '노트') · 빈 본문 · 구분선 · 설정 버튼 줄(56, 툴팁 '설정' → `openSettings`). 내비 줄·트리·휴지통·동기화 표시는 L9. 배경 `surfaceContainerLow`.
- L8 `LibraryTopBar`: expanded는 ☰ = 사이드바 접기/펴기(툴팁 `hideSidebar` '사이드바 숨기기'/`showSidebar` '사이드바 보기', `setSidebarVisible`), medium/compact는 ☰ = 서랍(툴팁 `openMenu` '메뉴 열기'). 가운데는 섹션 제목(폴더는 트리의 폴더 이름 — L10에서 브레드크럼으로 바뀜, 홈은 '홈', 검색은 `searchResultsTitle(q)` = '"q" 검색 결과'). 오른쪽 버튼 자리는 비어 있다(L10·L12·L14·L17·L18).
- L8 `ContentBody`: 폴더 섹션은 **임시 본문**(B6의 '새 노트' 버튼 — 이제 `libraryActionsProvider.createNote(NewNoteSpec('제목 없는 노트', newNoteDefaults), folderId: 섹션 폴더)`, 실패 시 `showLibrarySnackBar(libraryFailureMessage(kind))`, 진행 중 비활성), 나머지 섹션은 빈 본문. **L10이 목록으로 바꿀 때 `test/feature_library_smoke_test.dart`도 고쳐야 한다**(지금은 이 임시 버튼의 '새 노트' 글자를 누름, '홈' 글자가 1개라고 확인 — L9가 사이드바 '홈' 줄을 넣으면 그 확인도 바뀜).
- L8 `lib/src/ui/feedback/library_snack_bar.dart`: `showLibrarySnackBar`(floating, expanded 폭 480, 동작 있으면 6초·없으면 4초, `hideCurrentSnackBar` 후 표시)와 `libraryFailureMessage(kind)`(6.19)를 L8에서 만들었다(L13에서 실행 취소 스낵바가 쓴다).
- L8 `size_class.dart`에 `breadcrumbMaxVisibleFor(sizeClass)`(4·3·2), `grid_metrics.dart`에 `libraryContentWidth(screenWidth, sizeClass:, sidebarVisible:)`(expanded + 표시 중이면 −281)를 더했다. `LibraryMetrics`에 `sidebarEdgeRowHeight = 56`(사이드바 머리·바닥 줄, 6.5)을 더했다. `GridMetrics`는 값 동등.
- L9 사이드바: 내비 줄 아이콘은 계획에 없어 `Icons.home_outlined`·`schedule`·`star_outline`·`delete_outline`으로 정했다. 줄은 좌우 8 안쪽 여백 + 선택 시 `secondaryContainer`(모서리 12) `Material`, 아니면 `MaterialType.transparency`(색 하드코딩 없음). '폴더' 머리줄의 '+'(새 폴더)는 대화상자가 생기는 L12에서 붙인다. 트리 줄 ▸/▾는 44×44 `IconButton`(툴팁 `LibraryStrings.expandFolder` '펼치기'·`collapseFolder` '접기'), 들여쓰기 `SidebarTreeRow.indentFor(depth)`. 트리 영역 오류(6.19)는 '불러오지 못했어요' + [다시 시도](`ref.invalidate(folderTreeProvider)`), 로딩 중에는 빈 칸. 파일: `ui/sidebar/sidebar_rows.dart`(`SidebarNavRow`, `SidebarTreeRow`), `ui/sidebar/sidebar_folder_tree.dart`, `ui/sidebar/sync_badge_indicator.dart`.
- L9 '보고 1회'(6.16.1·6.19): `lib/src/common/report_error.dart`에 `reportLibraryErrorOnce(owner, error, stack, context)`를 더했다 — `Expando`로 `ProviderContainer`마다 이미 보고한 오류 객체(identity)를 기억한다. 서랍은 열 때마다 사이드바를 새로 만들고, `WidgetRef.listen`에는 `fireImmediately`가 없어(빌드 중 listen) 위젯 State로는 '한 번'을 지킬 수 없기 때문. 빌드에서 provider 값이 오류면 이 함수를 부른다(동기화 표시·사이드바 트리). L10 목록 오류 보고도 이것을 쓰면 된다.
- L9 `LibraryScope`에 `closeDrawer`를 더했다(사이드바 최근·즐겨찾기·휴지통이 섹션을 바꾸기 전에 서랍을 닫음). 현재 폴더 드러내기는 `LibraryScreen` State의 `_scheduleReveal`(initState·folderId가 바뀐 didUpdateWidget → post-frame → `tree.pathTo(id)`의 마지막을 뺀 조상 `expandAll`, 트리가 없으면 `listenManual` 첫 값에서 한 번).
- L9 `SyncBadgeLook`에 값 동등을 더했고, 음수 `pendingChanges`는 0으로 본다. `SyncBadgeIndicator`는 오류·로딩이면 `SyncBadge.off`, 시각은 `clockProvider.now()`.
- L9 B6 스모크 테스트의 '홈' 글자 확인을 `findsNWidgets(2)`(상단 막대 + 사이드바 홈 줄)로 바꿨다.
- L9 사이드바 파일 이름은 3장 구조(`sidebar_nav_row.dart`·`folder_tree_view.dart`·`folder_tree_row_tile.dart`)와 다르다: `sidebar_rows.dart`(`SidebarNavRow`·`SidebarTreeRow`)·`sidebar_folder_tree.dart`(`SidebarFolderTree`). L13(줄 메뉴)·L15(놓기 대상)은 이 파일들을 고친다.
- L10 '새 노트'(그리드 첫 칸 `NewNoteTile`, 빈 상태 버튼)는 `ui/content/new_note_trigger.dart`의 `NewNoteTrigger(folderId:, builder: (context, onPressed) => …)`를 거친다. 지금은 B6처럼 '제목 없는 노트'를 바로 만들고 연다(진행 중 `onPressed == null`). **L12는 이 위젯 안만 바꿔 새 노트 대화상자를 열면 된다**(컨트롤은 그대로). 빈 상태에는 지금 [새 노트]만 있고 [새 폴더]는 L12가 더한다(`empty_state.dart` 주석).
- L10 비동기 결과 규칙: 새 노트가 나타나면 빈 상태가 그리드로 바뀌어 버튼 위젯이 사라지므로, 동작 시작 위젯이 살아 있는지에 기대지 않는다 — `LibraryScope` 콜백(`openNote` 등)은 `LibraryScreen` State가 `mounted`일 때만 동작하고, 스낵바는 await 전에 잡은 messenger로 `showLibrarySnackBarOn(messenger, …)`(`library_snack_bar.dart`). L12~L18의 대화상자·동작도 이 방식을 쓰면 된다.
- L10 `NoteCoverView`(`ui/content/note_cover_view.dart`)는 지금 모든 표지를 자리표시(`CoverPlaceholder`: `surfaceContainerHigh` + `Icons.description_outlined`)로 그리는 `StatelessWidget`이다. L11이 4가지 표지·예약기와 함께 `ConsumerStatefulWidget`으로 바꾼다(생성자 그대로).
- L10 타일(`note_tile.dart`·`folder_tile.dart`): `RepaintBoundary` → `Stack[Positioned.fill(Semantics(container, button, label: noteSemantics/folderSemantics, excludeSemantics, onTap) → InkWell → Column[표지 TileCoverBox, 8, TileFooterText])]`. ⋯(44×44) 자리는 제목 줄 오른쪽에 비워 두었고(`EdgeInsetsDirectional.only(end: 44)`) L13이 `Stack`에 `Positioned`로 넣는다. 리스트 행(`item_list.dart`의 `NoteListRow`·`FolderListRow`)도 ⋯ 자리 `SizedBox(52)`. 리스트 행의 ☆/★는 L10에서 `setFavorite` 토글까지 했다. 공통 조각은 `tile_parts.dart`(`openLibraryNote` — `requiresNewerApp`이면 열지 않고 스낵바, `FolderPicture`, `TileCoverBox`, `TileFooterText`(글자 배율 1.3 제한), `CoverCornerBadge`). `requiresNewerApp` 배지는 표지 왼쪽 아래 `Icons.upgrade`(primary), 메타는 '새 버전 앱에서 열 수 있어요'.
- L10 `ContentBody`: 폴더 섹션은 `_FolderBody`(트리가 로드됐는데 id가 없으면 `folderLookupProvider` → trashed/missing이면 `FolderMissingView`, 판정 중이면 `DelayedSpinner`, 오류·active면 목록). 최근·즐겨찾기·검색도 지금은 같은 `ContentListing`(폴더 먼저 → 노트)으로 보인다 — L17이 검색 결과 보기(묶음·위치·강조)로 바꾸고 최근·즐겨찾기를 테스트한다. 휴지통은 빈 본문(L16). `ContentListing`은 같은 섹션의 다른 질의(정렬 변경 = 새 family 인스턴스)가 로딩되는 동안 마지막 내용을 그대로 보여 준다(`_last`). 목록이 바뀌면 `selection.retainVisible`(6.7)도 L10에서 연결했다. 오류 [다시 시도]는 섹션별 CORE provider를 `invalidate`(폴더는 `libraryListingProvider` family 전체).
- L10 상단 막대: 폴더 섹션은 `BreadcrumbBar`(트리 로딩 중엔 빈 칸, 현재 칸 굵게 w700·버튼 아님, 조상 칸 `TextButton` 44, '…'은 `IconButton(Icons.more_horiz, 툴팁 LibraryStrings.hiddenPath '숨은 경로')` + `MenuAnchor`의 `MenuItemButton`들). 오른쪽은 expanded·medium이면 `SortMenuButton`(폴더 섹션만 활성, 아니면 비활성 + 툴팁 `sortFixed`) · `ViewModeButton`(휴지통 제외), compact면 `CompactListingMenu`(⋯ '더 보기' — '정렬' 하위 메뉴 + 보기 전환; **L14가 '선택'을 여기에 더한다**). 파일 `ui/top_bar/breadcrumb_bar.dart`, `ui/top_bar/sort_menu_button.dart`.
- L10 문구 추가: `sort`, `sortFixed`, `viewAsList`/`viewAsGrid`, `moreActions`, `hiddenPath`, `pageCount(n)`, `noteListMeta(date, n)`, `noteSemantics`/`folderSemantics`, `requiresNewerApp`, 빈 상태 5종(`emptyHome`…`emptySearch(q)`), `listLoadFailed`, `folderInTrash`·`folderNotFound`·`showTrash`·`goHome`.
- L10 B6 스모크 테스트: 이제 빈 홈의 [새 노트]를 누른다(`pumpAndSettle`로 목록 로드 후). '실패' 테스트는 목록이 뜬 뒤 저장소를 닫고 누른다.
- L11 `CoverThumbnailScheduler`(`lib/src/thumbnails/cover_thumbnail_scheduler.dart`): 렌더러가 `null`이면(꺼짐) `assetArrivals`·`changes`를 아예 구독하지 않는다. `startDelay`는 처음 한 번만이고, 대기열이 비어 작업자가 쉰 뒤의 요청은 `Timer(Duration.zero)`로 바로 시작한다(작업 사이는 `gap`). `request`가 FirstPageCover가 아니거나 `firstPageId == null`인 노트를 받으면 무시하면서 그 노트의 `_visible`·대기열·`_rerun` 항목도 지운다(타일의 최신 판이 표지 썸네일을 쓰지 않는데 예전 판이 에셋·원격 재시도로 그려지지 않게). `remoteSettle` 타이머는 `_remoteTimer ??=`로 한 창에 하나만(취소로 `_remoteDirty`가 비었다가 다시 채워져도 타이머가 둘이 되지 않게). `cancel`은 `_remoteDirty`에서도 뺀다. `null` 결과의 대기 에셋은 `content.page.background.referencedAssets`(작업이 읽은 페이지)로 정한다. `idle()`은 `dispose`에서도 완료된다. 실패 보고 문맥은 `'library cover thumbnail'`.
- L11 `NoteCoverView`: `initState`에서 `ref.listenManual(coverThumbnailSchedulerProvider, fireImmediately: true)`로 예약기를 받아 `request`(렌더러 자리가 바뀌어 예약기가 다시 만들어지면 새 예약기에 다시 요청). `didUpdateWidget`은 계획의 세 필드(`updatedAt`·`firstPageId`·`cover`)에 더해 **노트 id가 바뀐 경우**(키 없는 요소 재사용)도 옛 id `cancel` + 새 노트 `request`. 이미지는 `errorBuilder` → 자리표시(디코드 실패). 첫 페이지 썸네일은 `pageThumbnailProvider(id).value`(다시 읽는 동안에도 이전 값 유지).
- L11 색 표지 카드 `ColorCoverCard`(같은 파일): 띠 색은 `cover_palette.dart`의 `coverSpineColorFor(argb)`(= `Color.lerp(c, 검정, 0.2)`, 상수 `_spineShade`·`_spineShadeAmount` — 색 규칙 7.4.11). 제목은 띠 뒤 12·오른쪽 12 안쪽, 글자 배율 1.3 제한. **폭이 `LibraryMetrics.coverTitleMinWidth`(96)보다 좁으면(리스트 행 썸네일 40×52) 제목을 그리지 않는다**(제목이 바로 옆에 있음 — 계획에 없는 규칙).
- L11 `assetCoverBytesProvider`: `readBytes`에 더해 `bytesArrived`가 그 id를 내면 `invalidateSelf`(동기화로 나중에 내려온 표지 그림이 저절로 보이게).
- L11 테스트: 예약기 단위 테스트의 원격 내용 변경은 세션 `AddStrokes`에 `StrokeFixtures.synthetic(pointCount: 8)`을 썼다(5.1.1의 '쓰지 않는 것'에 있지만 테스트에서 획 하나를 만드는 데만 씀). 원격 batch·에셋 도착은 주입한 `StreamController`, provider 연결 테스트 1건은 가짜 저장소의 실제 `bytesArrived`(다른 가짜 저장소에서 같은 바이트를 `put`해 에셋 id(SHA-256)를 미리 얻음). 호출 기록 래퍼 `RecordingContentReader`·`RecordingThumbnailCache`는 `test/support/recording_thumbnail_io.dart`.
- L11 위젯 테스트 주의: `tester.pump(duration)`은 시간을 먼저 흘리고 프레임을 그리므로, 위젯을 바꾼 뒤(`didUpdateWidget → request`) 예약기 작업을 보려면 `pump()`로 먼저 빌드하고 `pump(1s)`.
- L12 피커(`lib/src/ui/pickers/`): 3장 목록의 6개 파일(`page_size_picker.dart`·`template_picker.dart`·`template_pictogram.dart`·`paper_color_picker.dart`·`cover_picker.dart`·`folder_appearance_picker.dart`)에 공용 `swatch_button.dart`(`SwatchButton` — 44×44 터치 영역, 원/둥근 사각 견본, 선택 시 primary 2px 고리, 툴팁 = 이름)를 더했다. `PageSizePicker`가 방향(`SegmentedButton<PageOrientationChoice>`, 사용자 지정이면 `onSelectionChanged: null`)까지 맡고 `onValidityChanged`로 mm 칸 유효 여부를 알린다(L18 설정 섹션도 같은 위젯을 쓰면 된다). 크기 `SegmentedButton`은 좁은 화면에서 넘치지 않게 가로 `SingleChildScrollView` 안에 있다. mm 칸 입력은 숫자 4자리 + 소수 1자리로 거르고(`FilteringTextInputFormatter`), 바깥에서 값이 바뀌면(`didUpdateWidget`, 이전 값과 다를 때만) 칸을 다시 채운다. `FolderIconPicker`는 기본 키(`folder`)를 고르면 `null`을 넘긴다(저장 안 함 = 기본). `TemplatePicker.choices`(빈 페이지 + 6종)는 테스트도 쓴다. `TemplatePictogram`의 종이 바탕은 `surfaceContainerLowest`(종이 색과 무관한 도식).
- L12 대화상자(`lib/src/ui/dialogs/`): `dialog_frame.dart`(`LibraryDialogFrame` — `Dialog` + 최대 폭 560 + 제목·스크롤 본문·버튼 줄, `DialogSection`, `DialogLocationRow`, `DialogNameField` — 자동 포커스, 전체 선택은 컨트롤러 쪽, `maxLength` 200·카운터 숨김)를 L13 대화상자도 쓰면 된다. **새 폴더도 빈 이름이면 기본 이름**(계획은 새 노트만 명시). 이름 칸은 200자에서 입력이 막히므로 `tooLong` 오류 문구는 두지 않았다.
- L12 흐름(`ui/dialogs/create_flows.dart`): `runNewNoteFlow(context, folderId:)`(= `uniqueNoteTitle` → 대화상자(기본값 `newNoteDefaultsProvider`, 위치 `locationLabel`, 트리가 아직 없으면 '홈') → `createNote` → `openNote`, 실패는 스낵바)·`runNewFolderFlow(context, parentId:)`(= `uniqueFolderName` → 대화상자 → `createFolder` → **부모와 그 조상 전부** `expandAll`, 이동 없음). 컨테이너마다 한 번에 흐름 하나(`Expando` — 기본 이름 읽기·CORE 쓰기 중 두 번째 탭은 무시). 컨테이너·`LibraryScope`·messenger는 첫 await 전에 잡는다(메뉴가 닫혀도 동작). `NewNoteTrigger`는 이제 이 흐름을 부르는 `StatefulWidget`(흐름이 끝날 때까지 `onPressed == null`).
- L12 진입점: 상단 막대 `NewMenuButton`(`ui/top_bar/new_menu_button.dart` — expanded·medium은 `FilledButton.tonalIcon(+, '새로 만들기')`, compact는 `IconButton(+, 툴팁 '새로 만들기')`, 메뉴 = 새 노트·새 폴더; 대상 = 폴더 섹션의 폴더, 그 외 홈). **휴지통 섹션에서는 숨김**(계획에 없음 — 보기 전환과 같은 규칙). **L18은 `NewMenuButton`의 `menuChildren`에 'PDF 가져오기'를 더한다.** 사이드바 '폴더' 머리줄 '+'(툴팁 '새 폴더', 폴더 섹션이면 그 폴더, 아니면 홈 — 서랍 안에서도 서랍을 닫지 않고 대화상자를 띄움), 빈 상태 [새 노트](FilledButton)·[새 폴더](OutlinedButton).
- L12 문구 추가: `fieldTitle`·`fieldName`·`fieldLocation`·`fieldPageSize`·`fieldOrientation`·`fieldTemplate`·`fieldPaperColor`·`fieldCover`·`fieldColor`·`fieldIcon`, `pageSizeA4`·`pageSizeLetter`·`pageSize16x9`·`pageSizeCustom`, `portrait`·`landscape`, `customWidth`·`customHeight`·`millimeters`, `coverFirstPage`, `colorNone`, `templateName(kind?)`, `paperColorName(argb)`.
- L12 B6 스모크·L10 목록 테스트: '새 노트'를 누른 뒤 대화상자의 [만들기]를 누르도록 바꿨다. 스모크의 '두 번째 탭' 테스트는 [만들기] 뒤 `createNote`가 대기 중일 때 빈 상태 [새 노트]가 비활성이고 눌러도 대화상자가 다시 뜨지 않음을 본다. '실패' 테스트는 대화상자를 연 뒤 저장소를 닫고 [만들기].
- L13 메뉴(`lib/src/ui/menus/item_context_menu.dart`): `itemMenuEntries(context, note:/folder:, sidebar:)`가 6.8·6.5 표의 항목을 만든다(노트: 이름 변경·표지 변경·즐겨찾기/해제·복사·이동…·휴지통으로 이동, 폴더: 이름 변경·꾸미기·복사·이동…·휴지통으로 이동, 사이드바 줄: 복사 대신 '새 하위 폴더'). 'PDF로 내보내기'는 L18이 노트 목록의 '이동…' 뒤에 넣는다(주석 자리). 타일·리스트 행의 ⋯는 `ItemMenuButton`(44×44, `MenuAnchor`) — **툴팁은 '더 보기'가 아니라 `LibraryStrings.itemMenu(이름)` = '<이름> 메뉴'**(compact 상단 막대 ⋯ '더 보기'와 구분, 스크린 리더가 어느 항목인지 읽음). 타일에서는 `PositionedDirectional(end: 0, top: 표지 높이 + LibraryMetrics.tileMenuTopGap(4))`.
- L13 사이드바 줄 메뉴 `SidebarRowMenu`(같은 파일, `SidebarFolderTree`가 각 `SidebarTreeRow`를 감쌈): `RawGestureDetector` — `LongPressGestureRecognizer(duration: LibraryMetrics.longPressDelay 400ms)`의 `onLongPressEnd`에서 누른 점과의 거리가 `kTouchSlop` 미만이면 누른 자리에 메뉴(`MenuController.open(position:)`), `TapGestureRecognizer.onSecondaryTapUp`(오른쪽 클릭)도 같은 메뉴. `excludeFromSemantics: true`(없으면 줄의 라벨·탭 노드와 갈라져 `labeledTapTargetGuideline` 실패) — 스크린 리더는 목록의 폴더 ⋯로 같은 동작을 쓴다. **L15는 길게 누르기 부분을 `LibraryDraggable.onLongPressReleased`로 바꾼다**(오른쪽 클릭은 그대로).
- L13 흐름(`lib/src/ui/menus/item_action_flows.dart`): `runRenameFlow`·`runFolderAppearanceFlow`·`runCoverFlow`·`runFavoriteFlow(ids:, favorite:, onDone:)`·`runCopyHereFlow(item:, parentId:)`·`runMoveFlow(items:, parents:, onDone:)`·`runTrashFlow(items:, singleName:, onDone:)`. create_flows와 같은 규칙(컨테이너·scope·messenger를 첫 await 전에 잡음). '같은 항목의 같은 동작 진행 중에는 그 진입점만 비활성'(6.11)은 **메뉴 항목을 비활성으로 그리지 않고, 진행 중인 같은 동작·같은 항목 반복을 무시**하는 것으로 했다(컨테이너별 `Expando<Set<String>>` — 메뉴는 열 때마다 닫히므로 눈에 보이는 차이 없음). 이동: 피커 초기 선택 = 항목들의 공통 부모(다르면 홈), `noOpTargets` = 그 공통 부모, `disabled` = 옮기는 폴더 + `tree.descendantsOf`. 결과 문구는 6.10.3 표(`movedTo`/`movedCountTo` — "'<대상>'(으)로 옮겼어요", 홈이면 "'홈'으로"), 대상 이름은 이동 뒤 최신 트리에서 읽음(피커 안에서 만든 폴더). 영수증이 비면 [실행 취소] 없음. 이름 변경은 바뀌지 않았으면 CORE를 부르지 않고, 꾸미기·표지 변경도 같은 값이면 부르지 않는다.
- L13 대화상자: `rename_dialog.dart`(필드 라벨은 노트·폴더 모두 '이름', `DialogNameField(counterFrom: 180)` — `DialogNameField`에 `counterFrom`을 더함, [저장]은 빈 값·같은 값·`String.length` 200 초과(이모지 등 C-6)면 비활성, 다듬은 이름을 돌려줌), `folder_appearance_dialog.dart`(미리보기 96×72 — `tile_parts.dart`에 `FolderGlyph(colorArgb, icon, …)`를 새로 두고 `FolderPicture`가 그것을 씀, `folderIconColor` 대신 `folderColorOr(argb, scheme)`; 저장된 모르는 아이콘 키는 사용자가 아이콘을 고르기 전까지 유지; 바뀌기 전엔 [저장] 비활성), `cover_dialog.dart`(미리보기 없음 — `CoverPicker`만, 같은 표지면 [저장] 비활성). `showConfirmDialog`는 아직 없다 — 쓰는 곳(영구 삭제·비우기)이 L16이라 그때 만든다.
- L13 폴더 선택 대화상자(`folder_picker_dialog.dart`, `FolderPickerDialog`·`FolderPickerRow`·`FolderPickerResult`(값 동등)): 트리 줄은 홈 아래 한 단계 들여쓴다(`depth + 1`), 처음 펼침 = `initialFolderId`까지의 경로 **그 폴더 포함**(하위 폴더로 옮기기 쉽게), 순서는 사이드바와 같은 `folderTreeOrderFor(prefs.sort)`. 비활성 줄은 ▸도 없다(하위도 모두 비활성이라). 확인 버튼은 고른 줄이 비활성·트리에 없음·`noOpTargets`면 비활성. [새 폴더]는 새 폴더 대화상자(이름·색·아이콘)를 띄워 고른 폴더 안에 만들고 그 폴더를 고른다(피커 안의 펼침만 바꾸고 사이드바 펼침은 건드리지 않음), 고른 줄이 비활성이면 비활성. compact는 `Dialog.fullscreen` + `SafeArea`.
- L13 문구 추가: `itemMenu(name)`, `newSubfolder`, `moveDestination`·`copyDestination`, `moveHere`·`copyHere`, `preview`, `characterCount(n, max)`, `copied`·`copiedCount(n)`, `movedTo(target)`·`movedCountTo(n, target)`, `trashedOne(name)`·`trashedCount(n)`.
- L13 `NoteListRow`의 ☆/★도 `runFavoriteFlow`를 거친다(L10의 자체 토글 코드 삭제).
- L14 선택 모드 진입·표시: 상단 막대 '선택'(expanded·medium은 보기 전환 뒤 `TextButton`, compact는 ⋯ 메뉴 마지막 `MenuItemButton` — `CompactListingMenu(onSelect:)`, 이제 휴지통에서도 ⋯가 보임) → `begin()`(빈 선택), 타일·행 길게 누르기 → `add(key)`(InkWell `onLongPress` + `Semantics(onLongPress)` — **L15가 `LibraryDraggable.onDragStarted`로 옮긴다**, `tile_parts.dart`의 `addItemToSelection`). 탭은 선택 모드면 `toggle`(`toggleItemSelection`), 아니면 열기. 타일 `Semantics(selected: 선택 모드일 때만 값, 아니면 null)`. 그리드: 표지 왼쪽 위 `SelectionCheckBadge`(44×44 영역, `IgnorePointer`+`ExcludeSemantics` 장식), 선택되면 `TileCoverBox(selected: true)` = 테두리 3 primary. 리스트 행: 앞쪽 `Checkbox`(장식 — 누르기·의미는 행이 맡음, 들여쓰기 16→4). ⋯는 선택 모드에서 숨김(행은 44 빈 칸으로 정렬 유지), 리스트 ☆/★는 그대로 둠. '새 노트' 타일은 선택 모드에서도 그대로(계획에 없음). 선택 상태는 `watchItemSelection(ref, context, key)`(`select`로 (active, selected)만 구독).
- L14 선택 막대(`ui/top_bar/selection_bar.dart`, `ContentPane`이 `librarySelectionProvider(route).select(active)`로 `LibraryTopBar`와 바꿈): 버튼 모양은 **크기 등급이 아니라 막대 폭**으로 정한다 — 900 이상은 `TextButton.icon`(라벨), 520 이상은 `IconButton`(툴팁 = 라벨, 비활성 내보내기는 툴팁 '노트를 선택하세요'), 그보다 좁으면(compact) 이동·휴지통만 아이콘, 모두 선택/해제·즐겨찾기·복사·PDF 내보내기는 ⋯(툴팁 '더 보기') 메뉴로(splitHalf 683·ipad11 세로 834에서 라벨 버튼 5개가 넘쳐서). 막대 라벨: 즐겨찾기/즐겨찾기 해제·복사·**'이동'(새 문구 `LibraryStrings.move`, 메뉴는 '이동…')**·PDF 내보내기·**'휴지통'**(`trash`). 'n개 선택됨'은 `Semantics(liveRegion)`. 휴지통 섹션은 ✕·개수·모두 선택만(복원·영구 삭제는 L16 — `actions` 목록 자리 주석).
- L14 일괄 동작: 대상 = `selection.inDisplayOrder(content.orderedKeys)`, 부모 = 콘텐츠의 `folder.parentId`/`note.folderId`. 이동·휴지통·즐겨찾기는 L13 흐름에 `onDone: end`, 복사는 새 `runCopyToFlow`(피커 '복사할 위치'·'여기에 복사', 시작 = 폴더 섹션의 폴더, 그 외 홈, **접미사는 대상이 선택 항목 중 하나라도 그 부모면 ' 사본', 아니면 ''** — 최근·즐겨찾기·검색처럼 부모가 섞인 경우의 해석, `copiedCount(n)`). 성공하면 선택 종료, 취소·실패면 선택 유지. `end`는 컨테이너에서 다시 읽은 notifier로(흐름 끝에 막대가 없어도 동작).
- L14 PDF 내보내기(`lib/src/integration/pdf_flows.dart` 새 파일 — 3장 구조의 파일, L18이 가져오기·⋯ 내보내기를 더한다): `runLibraryPdfExport(context, action:, noteIds:)`는 **`LibraryScope.screenContext`(새 필드 — `LibraryScreen` State의 `context`)**를 슬롯에 넘기고, 컨테이너별 `Expando`로 한 번에 하나(진행 중이면 `false`를 바로 돌려줌, `isLibraryPdfExportRunning(context)`), 예외는 `reportLibraryError(…, 'library pdf export')` + `errorGeneric`. 막대 버튼은 자체 `_exporting`으로 누르는 즉시 비활성(같은 프레임 두 번째 탭도 무시), 슬롯이 끝나면(정상·예외 모두) 선택 종료.
- 공유 시나리오(L0 틀): 하네스 1건 + **L13에서 2건** — 'folders: create, move through the picker, no move into the own subtree'(빈 상태 [새 폴더] A → 사이드바 줄 메뉴 '새 하위 폴더' B → 새로 만들기 C, A 이동 피커에서 A 비활성·홈 확인 비활성, 래퍼 `moveItems(A → B)`가 `FolderCycleException`·변화 없음(C-4), A → C 이동 후 [실행 취소]), "copy: ' 사본' of a 200-character title stays 200 characters"(C-5). 나머지(사용자 지정 재정렬 다중, 휴지통 → 복원 위치, 제목 검색 NFD, '최근'은 openSession 뒤에만, 새 노트 기본값 왕복, 원격 삭제 → 폴더 없음 보기)는 L15~L18 때 추가한다. 시나리오 본문의 CORE 직접 호출·읽기는 `tester.runAsync`로 감싼다(`runAsync`는 콜백 오류를 다시 던지지 않으므로 오류를 기대하면 콜백 안에서 잡아 값으로 돌려줌).
- L15 파일: 3장의 `dnd/` 5개 파일에 더해 **`dnd/library_drop_zone.dart`**(`LibraryDropZone` — `DragTarget<LibraryDragHandle>` 하나: `onWillAcceptWithDetails` 항상 true, `onMove`에서 `decideDrop`(트리 = `folderTreeProvider`, 사용자 지정 여부 = 섹션이 폴더 + `prefs.sort.field == custom`, 위치 = 자기 `RenderBox.globalToLocal(details.offset)`), `builder(context, decision)`로 강조, 놓으면 같은 위치로 다시 판정해 `runDropFlow`. `onHold`(700ms, `holdNeedsDrop`이면 `DropInto`일 때만) — 접힌 트리 줄 펼침·'…' 메뉴 열기, `onDropped`)를 두었다. 실행은 `item_action_flows.dart`의 **`runDropFlow(context, payload, decision)`**(이동·휴지통은 L13 흐름과 같은 결과 문구·[실행 취소] 코드를 `_moveAndReport`·`_trashAndReport`로 나눠 공유).
- L15 `LibraryDragHandle`에 `dropped`/`markDropped()`(놓기 대상이 판정을 실행했는지 — `onLongPressReleased` 판단용)를 더했다. 콘텐츠 페이로드는 순수 함수 `contentDragPayload(pressed:, pressedParent:, selection:, content:)`(drag_payload.dart, 단위 테스트 대상): 선택 모드면 선택 ∪ 누른 항목을 `content`의 화면 순서(폴더 → 노트)로, 더는 안 보이는 선택 항목은 빼고, 누른 항목은 항상(콘텐츠에 없으면 끝에) 넣는다. `parents`는 콘텐츠의 `folder.parentId`/`note.folderId`.
- L15 `LibraryDraggable`: `childWhenDragging`을 따로 두지 않고 같은 자식을 `Opacity(끄는 중 0.4)`로 감싼다(위젯 종류가 바뀌어 표지 등 하위 State가 다시 만들어지지 않게). `AutomaticKeepAliveClientMixin`으로 끄는 동안 지연 목록에서 살아 있게 한다(자동 스크롤로 화면 밖에 나가도). 끝은 `onDragEnd`가 아니라 `onDragCompleted`·`onDraggableCanceled`로 받는다(Flutter는 원본이 사라지면 `onDragEnd`를 부르지 않음). `onLongPressReleased`는 끄는 동안 누른 점에서 가장 멀어진 거리 < `kTouchSlop`이고 `handle.dropped`가 아닐 때. `maxSimultaneousDrags: 1`.
- L15 끄는 모양 위치: 6.10.1의 '(−24, −28)'을 **카드 왼쪽 아래 모서리가 포인터에서 왼쪽 24·위 28**로 읽었다(카드 전체가 포인터 위 — 손가락에 가리지 않게. 왼쪽 위 모서리를 (−24, −28)에 두면 포인터가 카드 안에 들어가 아이콘이 가림). 치수는 `LibraryMetrics.dragFeedback*`.
- L15 **끄는 동안 상단 막대 유지**: 콘텐츠 끌기는 시작할 때 선택 모드를 켜는데(6.10.1) 선택 모드에서는 선택 막대가 상단 막대를 대신해(6.9) 브레드크럼 놓기 대상(6.6)이 사라진다. 그래서 `LibraryDragScopeState.dragging`(`ValueListenable<bool>`, `dragStart()`~`dragEnd()`)이 true인 동안 `ContentPane`은 `LibraryTopBar`를, 그리드는 '새 노트' 타일을 그대로 둔다(끌기 시작 때 타일이 한 칸씩 밀려 포인터 아래가 바뀌지 않게). 끌기가 끝나면 선택 막대가 나온다. 계획 6.9 표현과 다른 점.
- L15 `LibraryDragScope`: 계획 API에 `maybeOf`, `draggingOf(context)`, `dragStart()`, `dragging`을 더했다. 자동 스크롤 영역 고르기: 포인터를 담은 영역 중 나중에 등록된 것(서랍 트리가 콘텐츠보다 우선), 어느 영역에도 없으면 마지막 영역의 가로 범위 안일 때만 그 영역이 계속(위·아래 밖 → 최대 속도), 아니면 모두 정지. 서랍 가장자리는 스코프 자신의 상자 기준 x < 24. `EdgeAutoScroller`는 `Ticker`(시작 시 `_last = 0`, 끝·범위 밖이면 정지), `velocityFor`는 가까운 가장자리 기준(영역이 112보다 낮으면 위·아래 중 가까운 쪽).
- L15 '…'(숨은 경로) 자체는 판정이 없는 놓기 영역(`target: null`) — 700ms 머물면 메뉴만 연다. 메뉴 항목이 `FolderDropTarget`이고 놓으면 메뉴를 닫는다. 메뉴 항목의 탭은 버튼 State의 `context`로 폴더를 연다(메뉴 항목 context는 메뉴가 닫히면 비활성 — 기존 L10 테스트가 잡음).
- L15 휴지통 놓기 문구: 1개 = `LibraryStrings.droppedInTrash`('휴지통으로 옮겼어요', 6.10.3 그대로), 여러 개 = `trashedCount(n)`. 끄는 카드 '항목 n개' = `itemCount(n)`. `runDropFlow`는 **콘텐츠에서 시작한 끌기만, 성공했을 때만** `selection.end()`(실패·사이드바 끌기는 선택 유지 — L14 일괄 동작과 같은 규칙).
- L15 강조: 그리드 폴더 타일 into = `TileCoverBox(dropInto)` 테두리 2 primary + `FolderPicture(dropInto)` 배경 primaryContainer, 재정렬 = `DropInsertionBar.forTile`(gap 가운데 폭 3, 타일 `Stack(clipBehavior: Clip.none)`), 리스트 행 into = 뒤에 primaryContainer, 재정렬 = `DropInsertionBar.forRow`(행 위·아래 가장자리 안쪽 높이 3), 사이드바 줄 = `SidebarDropLook`(`folder` → primaryContainer/onPrimaryContainer, `trash` → errorContainer/onErrorContainer — `sidebar_rows.dart`의 `_rowColors`), 브레드크럼 칸·메뉴 항목 = 모서리 8 primaryContainer 배경.
- L15 `SidebarRowMenu` API를 `SidebarRowMenu(folder:, builder: (context, openMenu) => …)`로 바꿨다(길게 누르기 인식기를 없애고, `Listener`로 마지막 누른 점을 기억해 `LibraryDraggable.onLongPressReleased` = `openMenu`가 그 자리에 연다. 오른쪽 클릭은 그대로). 트리 줄 조립은 `sidebar_folder_tree.dart`의 `_TreeItem`(메뉴 → 놓기 영역 → 끌기 원본 → `SidebarTreeRow(drop:)`).
- L15 그리드·리스트·사이드바 트리에 `findChildIndexCallback`(키 → 인덱스)을 넣었다 — 항목이 앞에서 생기거나 사라져도(접힌 폴더 자동 펼침, 선택 모드의 '새 노트' 타일) 끄는 중인 원본 State가 유지되게. 세 목록은 각각 `ScrollController`를 가진 State가 되어 `AutoScrollRegion`으로 감쌌다.
- L15 타일·행의 `InkWell.onLongPress`는 없앴다(길게 누르기 = 끌기 시작, `onDragStarted` = `addItemToSelection`). `Semantics(onLongPress)`는 스크린 리더용으로 그대로 선택에 추가한다.
- L15 공유 시나리오 1건 추가: 'custom order: two selected notes dragged after a third move together'(사용자 지정 정렬 설정 저장 → 노트 1 길게 누르기·노트 2 탭 → 노트 2를 노트 4의 90% 지점에 놓기 → `reorderItems [1, 2] after:4` 1회, 목록 3·4·1·2).
- L16 파일: `ui/trash/trash_view.dart`(`TrashView` — `trashItemsProvider` 직접: 로딩 `DelayedSpinner`, 오류 `ListLoadError`(+ `reportLibraryErrorOnce`, [다시 시도] = `invalidate(trashItemsProvider)`), 비면 `EmptyState(TrashSection)`('휴지통이 비어 있어요'), 아니면 `Column[안내 줄(최소 56, ⓘ + 문구 + [휴지통 비우기]), Divider, ListView(72)]`; 목록이 바뀌면 `selection.retainVisible`), `ui/trash/trash_row.dart`(`TrashRow`, `TrashDaysChip`, `kTrashWarnDays = 3`), `ui/dialogs/confirm_dialog.dart`(`showConfirmDialog`/`ConfirmDialog` — `AlertDialog` 최대 폭 560, [취소] `TextButton`, 확인 `FilledButton`, `destructive`면 error/onError; 바깥 탭 = false). 흐름은 `item_action_flows.dart`의 `runRestoreFlow`·`runPurgeFlow`·`runEmptyTrashFlow`.
- L16 행: 탭(선택 모드 아님) = 행에 붙은 메뉴 [복원] [영구 삭제](⋯와 같은 `MenuController`), 선택 모드면 토글. **길게 누르기 = 선택 모드 시작**(`InkWell.onLongPress` — 휴지통 행은 끌지 않으므로 L14 방식 그대로, 계획 6.13에는 '상단 선택'만 있음). 행 폭 < 600(compact 등)이면 지운 날짜를 설명 줄에 붙인다(`'<설명> · <날짜> 삭제'`, 계획에 없는 배치 규칙 — 375에서 넘침 방지). 지운 날짜 = `formatLibraryDate(deletedAt)` + ' 삭제'(오늘이면 '오늘 오후 2:05 삭제'). 표지는 `NoteCoverView`(40×52), 폴더는 `FolderPicture`(32, 배경 없음).
- L16 복원 [보기]: `locate(첫 항목)` → `LibraryScope.openFolder(parentId)` — 라우트 폴더와 같으면(휴지통이 그 라우트의 섹션) `showRouteFolder()`로 섹션만 돌아가고 `onOpenFolder`는 부르지 않는다(6.4 규칙). 영구 삭제·비우기 성공 시 스낵바 없음(계획에 문구 없음). 비우기 확인 버튼 라벨 = '휴지통 비우기'(계획은 확인 제목·본문만 지정), 성공하면 선택 모드도 끝낸다. 비우기 메시지의 n = 휴지통 최상위 항목 수.
- L16 선택 막대(휴지통): 대상 순서·이름은 `libraryContentProvider`가 아니라 `trashItemsProvider`(지운 시각 최신순)에서 — '모두 선택'도 그 키들. 동작 [복원](`Icons.restore_from_trash_outlined`) [영구 삭제](`Icons.delete_forever_outlined`), 성공하면 `end()`.
- L16 문구 추가: `trashNotice`, `emptyTrash`, `emptyTrashView`, `restore`, `purge`, `purgeTitle`, `emptyTrashTitle`, `purgeMessageOne(name)`·`purgeMessageCount(n)`, `emptyTrashMessage(n)`, `restoredOne(name)`·`restoredCount(n)`, `trashedFolderInfo(noteCount:, folderCount:)`, `trashedNoteInfo(pages)`, `deletedOn(date)`, `trashRowSemantics`.
- L16 공유 시나리오 1건 추가: 'trash: a note trashed in a folder is restored there; [보기] opens it'(영어 안 노트 ⋯ › 휴지통으로 이동 → 사이드바 휴지통 → ⋯ › 복원 → CORE `getNote`가 `deletedAt == null`·`folderId == 영어`, [보기] → 영어 목록에 노트).
- L17 메타 줄: `ui/content/note_meta.dart`의 `NoteMetaStyle`(`of(section)` — 폴더·휴지통 `modified`, 최근 `recent`, 즐겨찾기 `favorite`, 검색 `location`)과 `watchNoteMeta(ref, note, style, listRow:)`. 최근 = `recentNoteMeta(위치, lastOpenedAt 날짜)`(리스트 행도 같음 — 페이지 수 없음, `lastOpenedAt`이 없으면 수정 날짜), 즐겨찾기 = `favoriteNoteMeta(위치, 수정 날짜)`('<위치> · 수정 <날짜>'), 검색 = 위치. 위치는 `watchLocationLabel`(`folderTreeProvider.select`로 라벨이 바뀔 때만 다시 빌드) — 트리가 아직 없으면 위치 부분을 빼고 날짜만. `requiresNewerApp`이면 어느 섹션이든 그 문구. 타일 의미 라벨(`noteSemantics`)은 그대로 수정 날짜. `NoteTile`·`NoteListRow`에 `metaStyle`·`highlight`, `FolderListRow`에 `showLocation`·`highlight`, `TileFooterText`에 `highlight`를 더했다(기본값은 기존 표시 그대로).
- L17 강조: `lib/src/model/search_match.dart`의 `searchMatchRange(title, query)`(6.14의 `toLowerCase().indexOf`) — 소문자로 바꿔 길이가 달라지면(브라우저의 'İ' 등) 강조하지 않는다(인덱스가 제목을 가리키지 않음). 그리는 쪽은 `highlightedTitleSpan`(note_meta.dart, w700 + `primary`) → 제목은 `Text.rich`(`find.text`는 그대로 찾음).
- L17 **검색 다시 질의**: 계획은 '결과에서 동작하면 `ref.invalidate(librarySearchProvider(q))`'인데, 동작 흐름마다 넣는 대신 `libraryContentProvider(SearchSection)`이 `noteStoreProvider`의 `changes`를 구독해 폴더·노트 `EntityChange`가 든 batch마다 `librarySearchProvider(q)`를 invalidate한다(결과의 ⋯·선택 막대·끌어 놓기·다른 기기 변경 모두). 획·페이지 변경(`stroke`·`page` 등)만 든 batch는 무시. 구독은 provider `onDispose`에서 취소.
- L17 검색 입력 `LibrarySearchField(routeFolderId:, autofocus:)`(`ui/top_bar/library_search_field.dart`): 디바운스는 State의 `Timer(LibraryMetrics.searchDebounce)` → `section.search(controller.text)`(조합 중 글자 포함 — `onChanged`가 조합 중에도 불림), Enter(`onSubmitted`) = 즉시, 지우기 버튼(툴팁 `clearSearch` '검색어 지우기', 값이 있을 때만) = 디바운스 취소 + 비움 + `exitSearch()`. `ref.listen(section)`이 검색이 아닌 섹션을 받으면 디바운스 취소 + 비움. 상단 막대가 **라우트 폴더로 key**를 줘 라우트가 바뀌면 새 State(빈 입력), `initState`에서 지금 섹션이 검색이면 그 검색어로 시작(선택 모드가 끝나 상단 막대가 다시 생길 때·크기 등급이 바뀔 때). 휴지통 섹션에도 검색 입력이 있다(검색을 비우면 휴지통으로 돌아감). 폭은 expanded 240 · medium 200(정렬 버튼 앞).
- L17 compact 검색(6.2 '막대 전체가 검색 입력으로'): 상단 막대(`LibraryTopBar`가 `ConsumerStatefulWidget`이 됨)에 검색 아이콘(툴팁 `LibraryStrings.search` '검색') → `_compactSearchOpen` → 막대 = `[← 툴팁 closeSearch '검색 닫기'][검색 입력(autofocus)]`. 섹션이 검색이면 플래그와 무관하게 이 막대. ← = 닫기 + `exitSearch()`. 라우트가 바뀌면 닫힘, 섹션이 검색이 아닌 다른 곳으로 바뀌면 닫힘(단 입력이 비워져 검색 전 섹션(`returnTo`)으로 돌아간 것은 열린 채 유지 — 지우기 버튼 뒤에도 입력이 남음).
- L17 결과 보기 `SearchResultsView`(`ui/content/search_results_view.dart`): `ContentListing`이 로딩·오류·빈 상태를 그대로 맡고, 내용이 있는 검색 섹션만 이 보기에 넘긴다. `CustomScrollView`(+ `AutoScrollRegion`): `SearchGroupHeader`('폴더 (n)' — `Semantics(header)`) + `SliverFixedExtentList`(64) `FolderListRow(showLocation: true)` / '노트 (n)' + 그리드(`SliverGrid`, `GridMetrics`, 타일 `NoteTile(metaStyle: location)`) 또는 리스트(`NoteListRow`) / `truncated`면 맨 아래 `searchTruncated`. 각 목록에 `findChildIndexCallback`. 새 노트는 검색 중이면 홈(`NewMenuButton.targetOf` 그대로).
- L17 문구 추가: `search`, `closeSearch`, `clearSearch`, `searchFolderGroup(n)`·`searchNoteGroup(n)`, `searchTruncated`, `recentNoteMeta(location, opened)`, `favoriteNoteMeta(location, modified)`, `modifiedOn(date)`.
- L17 테스트: 상단 막대에 `TextField`가 생겨 L13 `widget/item_actions_test.dart`의 `find.byType(TextField)`를 대화상자 안(`dialogField`)으로 좁혔다. 공유 시나리오 2건 추가: 'search: decomposed (NFD) titles and queries match composed ones'(NFD 제목을 NFC 검색어로, NFC 제목을 NFD 검색어로 — 폴더 묶음·노트 묶음, `searchLibrary '수학' limit:50`), 'recent: a note shows only after openSession (no markOpened here)'(라이브러리에서 탭 = `onOpenNote`만·`calls` 비어 있음·최근 빈 상태 → `seedOpened` 뒤 최근에 나타남).
- L18 PDF 자리(`lib/src/integration/pdf_flows.dart`): 진행 중 표시를 `Expando<bool>`에서 컨테이너별 `ValueNotifier<bool>`(`libraryPdfExportRunning(context)`·`libraryPdfImportRunning(context)` → `ValueListenable<bool>`)로 바꿨다 — 메뉴 항목이 `ValueListenableBuilder`로 진행 중에 비활성. 공통 `_guarded`(진행 중이면 아무것도 안 함, `LibraryScope.screenContext`를 슬롯에 넘김, await 전에 messenger를 잡고 예외 → `reportLibraryError` + `errorGeneric`). 쓰이지 않던 `isLibraryPdfExportRunning`은 지웠다. `runLibraryPdfImport(context, action:, folderId:)`: 반환 id → `LibraryScope.openNote`(State가 mounted일 때만), `null` → 아무것도 안 함.
- L18 'PDF 가져오기'(`NewMenuButton`, 이제 `ConsumerWidget`): 새 노트 · 새 폴더 다음 세 번째 항목(`Icons.picture_as_pdf_outlined`). 자리 `null`이면 비활성 + 라벨 아래 '준비 중'(`bodySmall`) 두 줄. 대상 = `NewMenuButton.targetOf(section)`(폴더 섹션의 폴더, 그 외 `null`). 휴지통 섹션에는 새로 만들기 버튼 자체가 없다(L12 그대로).
- L18 노트 ⋯ 'PDF로 내보내기': `ItemMenuButton`이 `ConsumerWidget`이 되어 노트일 때만 `libraryPdfExportActionProvider`를 watch해 `itemMenuEntries(exportPdf:)`로 넘긴다(새 선택 인자, `null`이면 항목 없음). 위치는 '이동…'과 '휴지통으로 이동' 사이(6.8 표 순서). 폴더 메뉴·사이드바 줄 메뉴에는 없다.
- L18 `StorageWarningBanner`(`lib/src/ui/banners/storage_warning_banner.dart`): `ContentPane`의 `Divider` 아래·본문 위. 6.16.2 주석 그대로(`storageWarningOf(storageInfo, persistenceStatusProvider.value ?? store.persistenceStatus)`), 경고 없음·닫힘 = `SizedBox.shrink`(높이 0). 모양 = `Material(색) + ConstrainedBox(minHeight 48) + Row[아이콘 20, 문구(줄바꿈), [닫기](notDurable만, `TextButton` foreground = on…Container)]`, `Semantics(liveRegion)`. 닫음은 State에만(`_notDurableDismissed`) — writeFailing은 닫았어도 보이고, 다시 notDurable로 돌아오면 닫힌 채.
- L18 `LibrarySettingsSection`: 계약대로 `ConsumerWidget`이고, 안에서 `IgnorePointer`+`Opacity 0.38`(설정 로딩 중 — `settingsSnapshotProvider`에 값이 없으면) → 내부 `_NewNoteDefaultsForm`(`ConsumerStatefulWidget`): 표시 값 `_value`를 State에 두고 바꾸면 즉시 반영 + `settings.set(newNoteDefaults, toJson())`(await하지 않음 — 쓰기 Future 규칙, 실패는 보고). `ref.listen(newNoteDefaultsProvider)`로 다른 기기 값·첫 로드를 반영(연속 변경이 늦게 오는 스냅숏 위에 쌓이지 않게). 피커는 새 노트 대화상자의 `PageSizePicker`·`TemplatePicker`·`PaperColorPicker` + `DialogSection` 라벨(제목·표지 없음). 사용자 지정 범위 밖 값은 `PageSizePicker`가 `onChanged`를 부르지 않으므로 저장되지 않는다.
- L18 B6 스모크의 `LibrarySettingsSection` 테스트: 'Column 정확히 1개'(자리표시용 단언)를 `findsWidgets`로 바꾸고 `SingleChildScrollView` 안에 넣었다(설정 틀이 스크롤함 — 800×600 기본 테스트 화면에서 넘침 방지).
- L18 테스트: `widget/integration_slots_test.dart`(가져오기 6건·내보내기 2건·`featureLibraryOverrides()` 빈 목록), `widget/storage_banner_test.dart`(4건 — 계획의 3가지 + 'notDurable을 닫아도 writeFailing은 보임'), `widget/settings_section_test.dart`(5건). 공유 시나리오 2건 추가: 'new note defaults: the stored JSON comes back in the dialog and the page'(사용자 지정 148×210mm·점 속지·아이보리를 `settings.set` → 대화상자 칸 '148.0'·'210.0' → [만들기] → 첫 페이지 크기·배경, 설정을 다시 읽어 같은 값), 'remote delete: the shown folder trashed / purged elsewhere → missing view'(`remoteChange`로 휴지통 → '이 폴더는 휴지통에 있어요', 영구 삭제 → '폴더를 찾을 수 없어요…'). 이로써 L21 ① 목록의 시나리오(8 L21)가 모두 들어갔다.
- L19 골든(`test/goldens/library_golden_test.dart`, `@Tags(['golden'])` + `@TestOn('vm')`): 4장 `library_13_landscape.png`·`library_13_portrait.png`(서랍 닫힘 확인)·`library_13_landscape_list.png`·`library_trash.png`. 씨앗은 `seedSampleLibrary`에 ★(아이디어)·색 표지(일기, `CoverPalette.colors[0]`)·폴더 꾸미기(영어, `FolderPalette.colors[3]`·`FolderIcons.keys[5]`)를 더했다 — ★·색 카드·폴더 색/아이콘 배치까지 보이게. 휴지통은 30·27·10·0일 전 항목 4개. DPR 2(하네스 그대로), PNG는 각 16~22KB. 글자와 아이콘은 테스트 글꼴의 네모(배치만 비교). 처음 만든 골든이라 L19 커밋에 같이 넣었다(갱신은 별도 커밋 — 계약 7.4.8). 갱신 명령: 패키지에서 `flutter test --update-goldens --tags golden test/goldens`.
- L19 허용 오차 비교기는 계약 7.4.8이 말하는 `test/flutter_test_config.dart`가 아니라 **`test/goldens/flutter_test_config.dart`**에 두었다(같은 디렉터리 아래 테스트에만 적용 — 다른 VM 테스트와 `test/web` 브라우저 실행에는 영향 없음). `LocalFileComparator`를 상속해 `diffPercent ≤ 0.005`(0.5 %)면 통과. 패키지 `.gitignore`에 `test/goldens/failures/`(실패 때 생기는 비교 이미지)를 넣었다. 확인: 가로 골든을 리스트 골든으로 바꿔치기하면 26 % 차이로 실패(되돌림).
- L19 성능(`widget/performance_test.dart`): '큰 폴더'에 노트 1,000개(1분 간격, `tester.runAsync` 안에서 CORE로 생성). 6.21 '스트림 첫 값 뒤 다음 프레임'은 시간 없이 `pump()`를 하며 `libraryContentProvider(FolderSection(id))`에 값이 생길 때까지(보기 설정 값 → 목록 값, 3프레임 이내) 기다린 뒤 **바로 다음 프레임**에 사이드바 줄·타일이 있고 스피너가 없는지로 확인한다(지금 구현은 설정 첫 값을 기다린 뒤 목록 쿼리를 구독하므로 pumpWidget 뒤 두 번째 프레임에 보임). 생성된 `NoteTile`(`skipOffstage: false`) 9~35개(실제 19개), 끝까지 스크롤해도 ≤ 35이고 맨 앞 노트는 해제됨, 리스트 보기 행 ≤ 30, 타일마다 `RepaintBoundary`·높이 하나.
- L19 접근성(`widget/a11y_test.dart`): 13" 가로·세로 각 12상태(홈 격자·리스트, 깊은 폴더 + 브레드크럼, 빈 폴더, 휴지통, 검색 결과 + 지우기 버튼, 새로 만들기 메뉴('PDF 가져오기' 준비 중), ⋯ 메뉴, 선택 모드, 저장 경고 배너 [닫기], 새 노트·새 폴더 대화상자) + 세로 서랍 = 25건에 세 지침(`iOSTapTargetGuideline`·`labeledTapTargetGuideline`·`textContrastGuideline`). `SemanticsHandle`은 `addTearDown`이 아니라 본문 `finally`에서 닫는다(핸들 검사가 tearDown보다 먼저 돎).
- L19 lib 수정 1건: `LibraryDialogFrame` 제목의 `Semantics(header: true)`에 `container: true`를 더했다. 없으면 제목 라벨·header 표시가 대화상자의 전체 화면 경로 노드(`role: dialog`)로 합쳐져, 대화상자 전체가 '머리글'로 읽히고 `textContrastGuideline`이 화면 전체(어두운 장벽)의 색으로 대비 1.77을 보고했다(새 폴더 대화상자).
- L20 브라우저 스모크(`test/web/library_browser_test.dart`, `@TestOn('browser')`): 노트 2개(홈) → 새로 만들기 › 새 폴더 '프로젝트'(이름 칸 입력 → [만들기], `createFolder home '프로젝트'`) → '회의록'을 **stylus**로 폴더 타일에 끌어 놓기(9.1 순서, `moveItems [n:…] -> f:…`, '…로 옮겼어요', CORE에서 `folderId` 확인) → 폴더 ⋯ › 휴지통으로 이동(`trashItems [f:…]`) → 사이드바 휴지통 → 행 ⋯ › 복원(`restore [f:…]`, '…복원했어요') → 홈에 폴더가 있고 열면 노트가 안에 있음. 계획에 없던 1건을 더했다: 리스트 보기 설정이 웹에서 써지고(`'list'`) 새 화면이 그 값으로 시작.
- L20 추가 파일 `test/web/scenarios_browser_test.dart`: 공유 시나리오(`libraryScenarios` 9건 — VM의 `widget/scenarios_on_fake_test.dart`와 같은 목록)를 dart2js에서도 돌린다. 새 노트 기본값(사용자 지정 148×210mm) 설정 왕복이 웹 숫자 타입(148.0도 `int`)으로 지나가고, 사용자 지정 순서·200자 사본 이름·NFD 검색도 웹에서 확인된다. 계획 8 L20 표에는 없는 파일이지만 소유 경로 안 테스트 추가라 그대로 두었다.

## 다음 세션 메모

- 기반 단계 인수인계: `/home/user/wt/notes/foundation-library.md`. B6에서 L2 외형 레지스트리(4.4 실제 값)와 그 테스트가 이미 끝났다.
- 테스트 기반(L0): 위젯 테스트는 `LibraryTestHarness(FakeLibraryBackend(), size: …, extraOverrides: …)` → `h.pump(tester, folderId: …)`, `h.goToFolder`, `h.log.entries`, `h.backend.calls`/`queries`. 씨앗은 `seedSampleLibrary(backend)`(홈 폴더 3·노트 4, 수학 › 미적분 › 극한 › 연습 문제 + '극한 정리'). 시간 흐름이 있는 단위 테스트는 `fakeAsync` 안에서 백엔드를 만든다(가짜의 커밋 재시도·`latency`가 Timer).
- L1 이후 `LibraryStrings`에 6.18 주요 표가 있다. 새 화면 문구는 그 작업에서 이 파일에 더한다(위젯에 한국어 리터럴 금지).
- provider는 모두 `lib/src/state/providers.dart`에 모은다(지금: `libraryPrefsProvider`, `newNoteDefaultsProvider`, `librarySectionProvider`, `librarySelectionProvider`). `selection_notifier.dart`가 `providers.dart`를 import한다(순환 import, Dart에서 허용).
- 오류 보고는 `reportLibraryError(error, stack, context)`(`lib/src/common/report_error.dart`).
- 세션 1 끝 확인: `ws check` 0, 루트 `flutter analyze --fatal-infos` 0, 패키지 VM 테스트 175개 통과, `flutter test --platform chrome test/web` 6개 통과(L3 브라우저 파일).
- 세션 2 끝 확인: `ws check` 0, 루트 `flutter analyze --fatal-infos` 0, 패키지 VM 테스트 293개 통과, `flutter test --platform chrome test/web` 6개 통과.
- L9·L10 시작점: 화면 부분은 `LibraryScope.of(context)`(빌드)/`LibraryScope.read(context)`(이벤트)로 `openFolder`·`openNote`·`openSettings`·`sizeClass`·`routeFolderId`를 얻는다. 섹션은 `ref.watch(librarySectionProvider(scope.routeFolderId))`. 사이드바 행은 `sidebarRowsProvider`, 펼침은 `folderExpansionProvider`, 휴지통 개수는 `trashCountProvider`, 목록은 `libraryContentProvider(section)`, 폴더 없음 판정은 `folderLookupProvider(id)`, 변경은 `libraryActionsProvider`, 스낵바는 `showLibrarySnackBar`. 브레드크럼은 `breadcrumbPath(tree, id)` + `compressBreadcrumb(maxVisible: breadcrumbMaxVisibleFor(sizeClass))`, 그리드 치수는 `GridMetrics.forWidth(LayoutBuilder 폭, sizeClass:, textScale:)`.
- 세션 3 끝 확인: `ws check` 0, 루트 `flutter analyze --fatal-infos` 0, 패키지 VM 테스트 352개 통과, `flutter test --platform chrome test/web` 6개 통과.
- 세션 4 끝 확인: `ws check` 0, 루트 `flutter analyze --fatal-infos` 0, 패키지 VM 테스트 415개 통과, `flutter test --platform chrome test/web` 6개 통과.
- 세션 5 끝 확인: `ws check` 0, 루트 `flutter analyze --fatal-infos` 0, 패키지 VM 테스트 471개 통과, `flutter test --platform chrome test/web` 6개 통과.
- 세션 6 끝 확인: `ws check` 0, 루트 `flutter analyze --fatal-infos` 0, 패키지 VM 테스트 539개 통과, `flutter test --platform chrome test/web` 6개 통과.
- 세션 7 끝 확인: `ws check` 0, 루트 `flutter analyze --fatal-infos` 0, 패키지 VM 테스트 594개 통과, `flutter test --platform chrome test/web` 6개 통과.
- 세션 8 끝 확인: `ws check` 0, 루트 `flutter analyze --fatal-infos` 0, 패키지 VM 테스트 626개 통과 + 1 skip(L21 `integration`), `flutter test --platform chrome test/web` 17개 통과(`ws test --platform chrome --package feature_library`도 통과), `dart format` 변경 없음.
- (L17 완료) 공유 시나리오는 L18까지 8 L21 ① 목록을 모두 담았다(9건 — 세션 8에서 다시 셈). 검색 화면 테스트 도우미: `widget/search_test.dart`의 `search(tester, text)`(enterText → `pump(300ms)` → `pumpAndSettle`), `searchInput`(`LibrarySearchField` 안의 `TextField`), `boldParts`(제목 `Text.rich`의 w700 조각). **`enterText` 뒤에는 `pump()`를 해야** 대화상자의 [저장] 등 활성 상태가 다시 그려진다(`enterText`는 프레임을 그리지 않음).
- 끌기 테스트 도우미: `widget/drag_drop_test.dart`의 `startDrag`(down → 450ms → moveBy(0, 20)) / `moveTo` / `drop`(up + pumpAndSettle). 끄는 동안에도 상단 막대가 남아 있고 선택 막대는 끌기가 끝난 뒤 나온다.
- 세션 4 L11: 표지는 `NoteCoverView`(4가지 + 예약기 요청), 예약기는 `coverThumbnailSchedulerProvider`, 에셋 표지는 `assetCoverBytesProvider`(`providers.dart`). 테스트 기본은 렌더러 자리 `null`(예약기 꺼짐, 자리표시) — 표지를 그려 보려면 `pageThumbnailRendererProvider.overrideWithValue(FakeThumbnailRenderer())`. L13의 '표지 변경'(`setCover`)은 `CoverPalette`·`ColorCoverCard`를 미리보기로 쓸 수 있다.
- L13 시작점: ⋯ 자리는 타일 `Stack`(`note_tile.dart`·`folder_tile.dart`의 'L13' 주석)과 리스트 행(`item_list.dart`의 `SizedBox(52)`). 대화상자 틀은 `LibraryDialogFrame`·`DialogNameField`(L12), 꾸미기는 `FolderColorPicker`·`FolderIconPicker`, 표지 변경은 `CoverPicker`(+ `ColorCoverCard` 미리보기), 실행 취소 스낵바는 `showLibrarySnackBarOn`(L8), 변경은 `libraryActionsProvider`(`move`→`MoveReceipt`/`undoMove`, `trash`→`restore`). 사이드바 줄 메뉴의 '새 하위 폴더'는 `runNewFolderFlow(context, parentId: 그 폴더)`.
- 화면 테스트 도우미 관례: provider 오류 보고 횟수는 `FlutterError.onError`를 try/finally로 잠시 바꿔 센다(`widget/sidebar_test.dart`·`widget/listing_test.dart`의 `collectReports`). 정렬 메뉴는 `find.byTooltip(LibraryStrings.sort)` → `find.widgetWithText(MenuItemButton, …)`.
- 위젯 테스트에서 provider 컨테이너는 `ProviderScope.containerOf(tester.element(find.byType(LibraryTopBar)))`로 얻을 수 있다(`widget/layout_test.dart`).
- L15 시작점: 끌기는 `LongPressDraggable`(400ms) — 지금 타일·행의 `InkWell.onLongPress`(→ `addItemToSelection`)와 사이드바 줄의 `SidebarRowMenu` 길게 누르기(`RawGestureDetector`)를 `LibraryDraggable`로 바꾼다(타일: `onDragStarted` = `selection.add`, `onLongPressReleased` = 아무것도 안 함, 사이드바 줄: `onLongPressReleased` = 줄 메뉴 — `SidebarRowMenu`의 `_openAt`). 페이로드의 부모는 선택 막대와 같은 방식(`folder.parentId`/`note.folderId`). 놓은 뒤 이동·휴지통 결과 스낵바는 L13 흐름 문구(`movedTo`/`movedCountTo`, 휴지통은 6.10.3의 '휴지통으로 옮겼어요' — 아직 상수 없음)와 `showLibrarySnackBarOn` + 실행 취소(`undoMove`/`restore`)를 쓰면 된다. 테스트에서 ⋯는 `find.byTooltip(LibraryStrings.itemMenu('<이름>'))`, 선택 막대 버튼은 `find.descendant(of: find.byType(SelectionBar), matching: find.text(라벨))`.
- (L19 완료) 골든 갱신은 패키지에서 `flutter test --update-goldens --tags golden test/goldens` 뒤 **별도 커밋**(계약 7.4.8). 화면 배치를 바꾸는 작업(L20 이후·통합 단계)에서 골든이 깨지면 갱신 커밋을 따로 만든다. 접근성 검사는 `widget/a11y_test.dart`의 `check(설명, 상태를 만드는 본문)`에 상태를 더하면 세 지침이 자동으로 붙는다.
- (L20 완료) 브라우저 테스트는 패키지에서 `flutter test --platform chrome test/web`(3파일 17건, 컨테이너에서 약 25~75초). 화면 흐름을 더 웹에서 보려면 `test/shared/library_scenarios.dart`에 시나리오를 더하면 VM·Chrome(`web/scenarios_browser_test.dart`)·통합(L21) 세 곳에서 같이 돈다(웹 안전 import만).
- L21(통합 단계) 시작점: `test/integration/core_contract_test.dart`를 세션 8에 미리 썼다(계획 8 L21 그대로). ① `libraryScenarios.where((s) => !s.needsFaults)`(지금 9건 모두)를 `open(tester, storageInfo: nativeFile)` = `tester.runAsync(() => FakeLibraryBackend.overStore((c) => openTestNoteStore(clock: c, storageInfo: …)))` 위에서 돌리고, 끝에 `close` = `pumpWidget(SizedBox)` → `runAsync(backend.dispose)` ② 기본 `openTestNoteStore()`(메모리 = nativeMemory) → `pump` 두 번 뒤 쓰기 없이 `LibraryStrings.storageNotDurable` 배너. **실제 drift로는 한 번도 돌려 보지 않았다** — 통합 단계에서 CORE T6 병합 뒤 `ws test --run-skipped -t integration`으로 돌리고, 'A Timer is still pending'·스트림 첫 값이 안 오는 경우는 그 시나리오의 CORE 호출이나 대기를 `runAsync`로 감싼다(11절, LIBRARY-2-6). 시나리오 본문(`shared/library_scenarios.dart`)의 씨앗은 이미 `tester.runAsync` 안에서 CORE를 부른다.

## 통합 단계

1차 통합(계약 7.7 순서 CORE → INK → EDITOR·LIBRARY 병합 뒤, 통합 브랜치 `claude/note-app-planning-bk29xb`, 기준 1582ec2, 통합 커밋 aabcabe). PDF·SYNC·INFRA는 아직 동시 개발 중이라 이 브랜치의 `pdf_io`·`sync_engine`·`app`은 기반 단계 자리표시다(단 `app`의 기반 라우터는 이미 실제 `LibraryScreen`을 띄운다). LIBRARY `lib/`는 바꾸지 않았다 — L21 테스트 파일, 계획서 8 L21 행·11절 리스크 행, 이 기록만.

### L21 — `integration/core_contract_test.dart`를 실제 CORE로 (계약 7.7 5단계)

- 첫 실행: 시나리오 1·2 통과, 3번째("copy: ' 사본' of a 200-character title …")에서 **멈춤** — CPU 거의 0, 10분 넘게 출력 없음(testWidgets 시간 초과도 걸리지 않음).
- 원인(추적 안 한 임시 진단 테스트 `test/integration/zz_debug_test.dart`로 확인하고 지움 — EDITOR 기록의 '루트 analyze 10건'은 이 임시 파일의 `avoid_print`였고 지금 루트 analyze는 0건): 시나리오 단언은 모두 통과했고 멈춘 곳은 끝의 닫기 `tester.runAsync(backend.dispose)`. `store.close()`는 `ThumbnailCacheImpl.close()`에서 진행 중인 캐시 작업(`_tail`)을 기다리는데, 그 작업은 화면의 표지(`NoteCoverView` → CORE `pageThumbnailProvider` → `ThumbnailCache.read`)가 **가짜 시간 영역에서** 시작한 블롭 IndexedDB 읽기다. `openTestNoteStore`의 블롭 저장소는 idb_shim(sembast 메모리)라 트랜잭션 시작(`TransactionSembast` `_delayedInit` — 0ms 타이머)과 sembast `Cooperator` 쉼(0.1ms 타이머 — 실제 시간 4ms마다)이 그 영역의 타이머가 된다. `pumpAndSettle`은 마지막 프레임에서 생긴 이 타이머를 진행하지 않고 끝나고(프레임 예약이 없으면 멈춤), `runAsync` 안에서는 가짜 시간이 흐르지 않으므로 닫기가 영원히 기다린다. `pumpAndSettle` 뒤 `pump(1ms)` 한 번이면 풀리는 것도 확인. 폴더만 다루는 2번은 표지가 없어서, 1번은 마지막이 `pump()`라 우연히 통과했다.
- CORE 결함 아님(변경 요청 없음): 닫기가 남은 캐시 작업을 기다리는 것은 맞는 동작이고, idb_shim 타이머 때문에 fake_async 안에서는 시간을 진행해야 한다는 점은 CORE 기록(core.md '통합 단계' — 에셋 `put`·썸네일 쓰기)에 이미 있다. 읽기도 같고 `close()`가 그것을 기다린다는 점을 아래 '메모'에 더해 둔다.
- 고침(테스트 파일 `close()`만): 화면을 내린 뒤 `backend.dispose()`(= `store.close()`)를 **테스트 영역에서 시작**하고 `pump(1ms)`와 `runAsync(Future.delayed(1ms))`를 번갈아 끝날 때까지 진행한다(상한 500번 — 넘으면 `store.close() did not finish`로 실패, 닫기 오류는 그대로 다시 던짐). EDITOR E-21과 같은 방식. 끝까지 진행하므로 가짜 타이머도 남지 않는다(flutter_test의 'A Timer is still pending' 검사 통과). 시나리오 본문(`shared/library_scenarios.dart`)·`FakeLibraryBackend`·`lib/`는 그대로 — 본문의 `runAsync` CORE 호출(drift: 씨앗·`watchFolderTree().first`·`watchListing().first`·`getNote`·`pagesOf`·설정·`openSession`)과 화면 조작이 일으킨 가짜 영역의 drift 쓰기는 실제 CORE에서 그대로 통과했다(drift `NativeDatabase`는 테스트 isolate에서 마이크로태스크만 씀).
- 결과: **10건 모두 통과**. ① 공유 시나리오 9건(`needsFaults == false` — 지금 전부, `storageInfo: nativeFile`): 경로 변경에도 State 유지, 폴더 만들기·피커 이동·순환 거부(실제 CORE `FolderCycleException`, 아무것도 안 바뀜)·실행 취소, 200자 제목 사본 = 200자, 사용자 지정 순서에서 두 노트를 셋째 뒤로(`reorderItems` 1회, 3·4·1·2), 폴더 안 노트 휴지통 → 제자리 복원·[보기], NFD 제목·질의 검색, '최근'은 `openSession` 뒤에만(`markOpened` 호출 없음), 새 노트 기본값 JSON 왕복(148×210mm·점·아이보리 → 대화상자 칸·첫 페이지 크기·배경), 원격 휴지통·영구 삭제 → 폴더 없음 보기. ② 기본 `openTestNoteStore()`(메모리 = `nativeMemory`) → 쓰기 없이 `LibraryStrings.storageNotDurable` 배너(계약 7.2.12·7.6 C11-12). 가짜와 실제 CORE의 결과 차이 없음.
- 실행: 패키지에서 `flutter test --run-skipped -t integration` → 10개 통과(약 25초, 대부분 컴파일). 루트 `dart run tool/ws.dart test --run-skipped -t integration --package feature_library` → `feature_library vm 10 passed 0 failed 30.6s ok`.

### 실제 CORE·INK 합류 뒤 패키지 테스트

| 검사 | 결과 |
|---|---|
| 패키지 `flutter test` (VM, 골든 4장 포함) | 626개 통과 + 1 skip(L21 `integration`), 태그 경고 없음 — 세션 8과 같은 수 |
| 패키지 `flutter test --platform chrome test/web` | 17개 통과(3파일) |
| 루트 `flutter analyze --fatal-infos` | 0건 |
| `ws check` | 위반 0(R1·R2·R3·R7·R8·R9·R15) |
| `dart format` (`packages/feature_library`) | 변경 없음 |

LIBRARY의 VM·Chrome 테스트는 CORE 공용 가짜(`createFakeNoteStore`) 위에서 돌고 INK를 import하지 않으므로(R8) 실제 CORE·INK 합류로 바뀐 것이 없다 — 예상대로 같은 수로 통과.

### 실제 INK 썸네일 렌더러와의 접점 (계획 5.3 K-1·K-4, 6.15)

LIBRARY 패키지는 `ink_engine`을 import할 수 없어 패키지 테스트로는 볼 수 없다. 그래서 모든 패키지에 의존하는 `app` 디렉터리에서 **저장소 밖 임시 테스트**(scratchpad 파일을 `flutter test <절대 경로>`로 — 커밋하지 않음, `app/`에는 아무것도 쓰지 않음)로 확인했다: 실제 CORE(`openTestNoteStore(storageInfo: nativeFile)`) + `pageThumbnailRendererProvider.overrideWith((ref) => ref.watch(inkPageThumbnailRendererProvider))`(INFRA 7.3.3 연결과 같은 모양) + `featureLibraryOverrides()` + `LibraryScreen`, 줄 속지 A4 세로 노트 1개.

- 표지 예약기(800ms 시작 지연) → INK 렌더 → `ThumbnailCache.write` → 표지가 `Image`로 바뀜. 결과 PNG 362×512(긴 변 = `maxSidePx` 512, 짧은 변 = 512 × 595.28/841.89 반올림), `pageId`·`contentRevision`(0)이 페이지 값과 같음(K-1).
- 세션으로 획 1개(`AddStrokes`, 페이지 `contentRevision` 1) → 노트 `updatedAt`이 바뀌어 타일이 다시 요청 → 캐시가 오래됨(`isStaleFor`) → 다시 렌더, 캐시 `contentRevision` 1·PNG 바이트가 달라짐, 표지는 `Image` 그대로.
- 어긋남 없음 → LIBRARY 변경 없음. K-3(획 2,000개 512px ≤ 150ms, iPad Safari)은 기기 측정이라 9.2 확인 때. 이 확인을 저장소에 남기려면 INFRA 앱 테스트(V5 스모크 등)가 맡을 수 있다(LIBRARY 소유 경로에는 둘 수 없음).

### 계획 8 L21 · 10절 통합 단계 완료 조건 — 지금(PDF·INFRA 연결 전) 확인한 것

| 조건 | 상태 |
|---|---|
| L21 `ws test --run-skipped -t integration` 통과 (V3의 LIBRARY 몫) | 통과 |
| 실행 뒤 남은 타이머·열린 저장소 없음 | 통과 — 테스트마다 `store.close()` 완료를 단언, flutter_test 가짜 타이머 검사 통과 |
| 루트 `flutter analyze`·전체 테스트(LIBRARY VM·골든·Chrome) | 통과(위 표) |
| 10절 1~4(작업 완료 조건, analyze·format·`ws check`, 공개 API 11개·`markOpened` 없음, 다른 영역 없이 통과) | 유지 — `unit/api_surface_test`·`unit/actions_test`·전체 테스트 통과 |
| 앱 `flutter build web` | `cd app && flutter build web --release` 통과(91.6초, `✓ Built build/web`) — 지금 앱은 INFRA 기반 라우터(B8)지만 실제 LIBRARY 코드(`LibraryScreen`)를 dart2js로 함께 빌드한다. INFRA 실제 연결 뒤 V4(`web-assets verify` 포함)에서 다시 |
| INFRA V5 스모크의 라이브러리 배너 문구 = 계약 7.4.5 (10절 5) | INFRA 병합 뒤 |
| 9.2 사용자 iPad 확인 → M2 '폴더로 노트를 정리할 수 있음' | 미리보기 배포 뒤 |

### 메모 — 다른 영역 통합 담당에게 (INFRA V5·V6 스모크, PDF `integration`)

- 실제 CORE(`openTestNoteStore`)로 `LibraryScreen`을 `testWidgets`에서 띄우면, 첫 페이지 표지 노트 타일마다 CORE `pageThumbnailProvider`가 썸네일 캐시를 **가짜 시간 영역에서** 읽는다(블롭 IndexedDB의 0·0.1ms 타이머). `pumpAndSettle` 뒤에도 그 타이머가 남을 수 있어 `tester.runAsync(store.close)`는 멈춘다(시간 초과 없음). 화면을 내린 뒤 `store.close()`를 테스트 영역에서 시작하고 `pump(1ms)`·`runAsync(() => Future.delayed(1ms))`를 번갈아 끝날 때까지 진행하면 된다(L21 `close()`). 같은 이유로 썸네일 캐시를 `runAsync` 안에서 읽거나 기다리지 않는다(가짜 영역 읽기가 앞에 있으면 함께 멈춤).
- 실제 렌더러를 붙이면 `Picture.toImage`·`toByteData`도 실제 이벤트 루프가 필요하다 — 같은 번갈아 진행(위 INK 확인은 `pump(50ms)`·`runAsync(5ms)` 번갈아 최대 400번).

### 남은 것

- INFRA 병합 뒤: V5 스모크의 라이브러리 화면 배너 문구 = 계약 7.4.5 고정 문장(10절 5), 앱 웹 빌드(V4)에서 9.2 준비(폴더 5개·노트 30개 — 개발자 메뉴 등, 9.2 머리말), 미리보기 배포 → 9.2 사용자 iPad 확인(6·17·24 제외 전 항목 합격 → PLAN M2).
- PDF 병합·INFRA 연결 뒤: 9.2 #28(선택 막대 'PDF 내보내기'·노트 ⋯ 'PDF로 내보내기')과 'PDF 가져오기'가 실제 함수로 — 자리 provider(`libraryPdfImportActionProvider`·`libraryPdfExportActionProvider`)는 L14·L18에서 준비됨, INFRA가 7.3.3 표대로 override.
- 9.2 #6(썸네일)·#24(스크롤 느낌)·K-3(렌더 시간): 기기에서.
- 변경 요청: 없음. 의존성 요청: 없음(`pubspec.lock` 변경 없음). 공개 API 변경 없음.

## 2차

계획 docs/plans/m5-7/05-library.md(승인 · 계약 v2.2 — 7.6.2 R2-B6 행, 7.6 시험 도우미 블록의 `ink_recognition/testing.dart`, 05-library 8.1 B6-a·B6-b). 바탕: `main` `c824a37`(1차 통합 HEAD `b6c9d0a` + 계획 + R2-B1 `3c77de3` + R2-B7b `9cdd3fb` + R2-B2·B7a·B2i 묶음 + R2-B3 INK T24 `fd3370f` + R2-B5 `78d7f25` + R2-B4 `5636d4e`).

### 작업 표 (2차)

| ID | 상태 | 커밋 | 비고 — 완료 조건 |
|---|---|---|---|
| B6-a | 완료 | 99cdeef | `feature_library`: `LibraryOpenNoteAt`·`LibraryScreen.onOpenNoteAt`(받기만 — 필드 저장, 화면 동작 없음), 내보내기 12개. `test/feature_library_smoke_test.dart`(기존 6개 + `onOpenNoteAt`을 넘겨 띄우고 새 노트는 여전히 `onOpenNote` 1회·`onOpenNoteAt` 0회), `unit/api_surface_test.dart`(12개 이름 — `LibraryOpenNoteAt` 함수형·생성자 인자·기본 null) |
| B6-b | 완료 | 99cdeef | `ink_recognition`: 7.2.11 공개 표면 35개 이름(05-library 4.2 목록) + `testing.dart` 4개. `test/ink_recognition_smoke_test.dart`(새로 씀 — `recognitionOverrides()` + 가짜 저장소로 provider 전부 읽기, 저장소 override 없이도 예외 없음, 쓸 수 있는 엔진 → 색인기·컨테이너 dispose, 설정 섹션 빌드), `unit/api_surface_test.dart`(진입점 두 개의 `show` 목록 = 4.2 목록·4.3 목록, 계약 블록 호출 모양 전부 — `HandwritingIndexer(store:, recognizer:, enabled:, foreground:)` 포함, 4.4.2 기본 엔진, 4.4.5 기본값·`==`·`copyWith`, 6.19 `toString`), `unit/handwriting_trace_test.dart`(본문 `shared/trace_cases.dart` — Chrome에서도), `unit/fakes_test.dart`('줄 1'·'줄 2'·변형 2개, `failNext` 한 번, `failWith` 매번, `fake_async` 지연, 취소, CP-L4 멤버, `SyntheticHandwriting` id 형식·결정성), `unit/synthetic_shapes_test.dart`(B6 몫: 4n+1점·윗변 가운데 시작·정확히 닫힘·시계 방향·변마다 n점 고른 간격·`ArgumentError` — 판정 단언은 L2-06), `unit/group_into_lines_test.dart`(B6 몫 — 아래 3), `web/recognition_browser_test.dart`(B6 몫: 진입점 import, `recognitionOverrides()` → 지원 안 함·직접 입력만·`NoShapeFitter`·색인기 null, 쓸 수 있는 가짜 엔진이어도 웹은 색인기 null, 공유 본문). 패키지에서 `flutter test` 태그 경고 없음(`dart_test.yaml`은 R2-B1 그대로) |

확인(2026-11-06, 커밋 전 작업 트리): `flutter analyze --fatal-infos` 두 패키지 0건, `dart format` 변경 없음, `ws test --package feature_library --package ink_recognition --platform vm` **feature_library 628 통과·1 skip(integration), ink_recognition 57 통과**, `ws test --package ink_recognition --platform chrome` **9 통과**, `ws test --package feature_library --platform chrome` **17 통과**, `ws check`(R1~R16, R14 포함) 위반 0·경고 0.

### 7.6.2 R2-B6 행 대비 동작 (기반 단계 — 동시 개발에서 교체)

- **최종**: 모델·실패 타입·포트, `HandwritingTrace.fromStroke`(`ts = createdAt + t(i)`, `Float64List`), `UnsupportedHandwritingRecognizer`·`ManualOnlyMathRecognizer`(4.4.2 — provider 기본값), `ShapeFitTuning`(4.4.5), `RecognitionConfig`, provider 4개의 이름·타입, `RecognitionTarget`·`RecognitionAction`, `HandwritingIndexerStatus`·`HandwritingIndexerPhase`(+ 6.19 `toString`), `testing.dart`의 가짜 엔진 두 개와 `SyntheticShapes.rectanglePath`(INFRA V5b가 기반 단계 뒤 바로 씀).
- **단순**: `recognitionOverrides()`는 `[ink.inkShapeFitterProvider.overrideWithValue(const NoShapeFitter())]` 하나(계약 7.6.2 — `config`는 아직 읽지 않음, 엔진 두 개·`GeometricShapeFitter`는 L2-07), `GeometricShapeFitter.fit` → 늘 null(L2-06), `groupIntoLines`는 획마다 한 줄(L2-05), 동작 목록 둘 다 빈 목록(L2-12), `HandwritingIndexer.start()` 아무것도 안 함·`dispose()` 멱등·`status` = `off`(L2-10a·L2-10b), `handwritingIndexerProvider`는 웹이거나 엔진을 쓸 수 없으면 null이고 그 밖에는 `enabled`가 늘 거짓인 색인기(L2-11에서 `recog.autoIndex`를 따름 — 설정 키는 L2-07), `recognitionDevOverlayLinesProvider`는 `['손글씨 색인 없음 (이 기기에서 인식 불가)']` 고정(L2-11), `RecognitionSettingsSection`은 빈 `Column`(L2-18), `SyntheticHandwriting`은 계약 id 형식·6.6 틀만 맞춘 단순 생성(L2-05가 E-L5 시제품으로 교체).

### 계획·계약과 다르게 한 점 (2차 R2-B6)

1. **고르기(`createPlatformHandwritingRecognizer` 조건부 export)를 만들지 않았다** — 8.2 L2-07 작업이다. 8.1 B6-b의 브라우저 시험 '`stub 선택`'은 '`recognitionOverrides()`를 넣은 웹 컨테이너에서 손글씨 엔진이 `UnsupportedHandwritingRecognizer`'로 확인했다(B6의 `recognitionOverrides()`는 손글씨 provider를 override하지 않으므로 지금은 기본값). 조건부 export와 '웹은 stub 파일·VM은 native 파일' 확인은 L2-07·L2-20에서. `RecognitionStrings`·설정 키(`RecognitionSettingsKeys`)도 L2-07이라 개발자 줄 문장은 `providers.dart`의 private 상수로 두었다.
2. `HandwritingIndexer`는 계약 생성자 인자를 아직 **보관하지 않는다**(쓰지 않는 private 필드는 analyze 경고). `dispose()` 뒤에도 `status`의 `ValueNotifier`는 닫지 않는다(provider·개발자 표시가 dispose 뒤에 읽어도 안전 — L2-10a에서 수명 규칙을 정함).
3. `groupIntoLines`(B6 몫): 점 없는 획을 버리고, 줄 = 획 하나, 순서 = 획 상자 윗변 → 왼쪽 → 첫 시각 → 입력 순서(4.4.6 출력 규칙만 지킴). 8.1 표에 시험 파일이 없어 `unit/group_into_lines_test.dart`를 B6 몫으로 더했다(L2-05가 6.5·V9 사례로 바꿈).
4. 가짜 엔진의 세부(4.3이 정하지 않은 것): `FakeHandwritingRecognizer(isAvailable: false)` → `modelState` = `unsupported`, `ensureModel`·`recognizeLine` → `RecognizerUnsupported`(호출은 먼저 기록). `ensureModel`은 횟수를 세고 그 언어를 `ready`로. 기본 답의 n은 실패한 호출도 센다. `FakeMathRecognizer`: 호출 기록 → `isAvailable` 거짓이면 `RecognizerUnsupported` → `failWith`(매번) → 지연. 지연 중에 `cancel`이 끝나면 `RecognizerCancelled`(지연 0이면 취소를 보지 않고 바로 답). `confidence`는 null(4.3 그대로). `FakeHandwritingRecognizer`의 내부 `RecognizerModelAdmin` 구현은 그 인터페이스가 생기는 L2-08에서.
5. 가짜 두 개의 생성자는 Dart의 private named parameter(`this._answer` 등 — 부르는 쪽 이름은 `answer:`·`isAvailable:`·`latency:`·`latex:`·`failWith:`)로 썼다. 호출 모양은 계약과 같다(`api_surface_test`가 계약 인자 이름으로 부름). 1차 EDITOR 코드도 같은 문법을 쓴다.
6. `SyntheticHandwriting.lines`(B6 몫): 줄 번호는 0부터, `<n>`은 페이지 안 획 번호(0부터, 쓴 순서) — E-L5 시제품 `synth.dart`와 같다. 획은 글자마다 지그재그 하나(6~12점, 8 ms 간격), 줄 간격·글자 높이는 6.6 범위. `lineCount`가 0~99 밖이면 `ArgumentError`(id의 줄 자리가 두 자리).
7. `SyntheticShapes.rectanglePath`: 점 수 = 4 × `pointsPerSide` + 1(마지막 = 처음). 윗변은 가운데에서 나눠 앞쪽 ⌈n/2⌉점(가운데 → 오른쪽 위 모서리 전)과 뒤쪽 ⌊n/2⌋점(왼쪽 위 모서리 → 가운데 전)이라 n이 홀수면 두 반쪽의 간격이 조금 다르다(n 짝수 — 기본 24 — 면 윗변 전체가 w/n 간격). 크기 규칙은 '두 변 모두 ≥ 48 pt'로 검사한다(정규화된 rect에서 `shortestSide ≥ 48`과 같고, 폭·높이가 음수인 rect도 거절).
8. 공개 이름을 더하지 않고 값 타입에 `==`·`hashCode`·`toString`을 더했다: `TextCandidate`, `MathResult`, `RecognitionConfig`(`==`·`toString`), 실패 7종(`toString`), `HandwritingTrace`·`HandwritingLineInput`·`MathInput`(`toString`).
9. `unit/api_surface_test.dart`는 진입점 파일의 `show` 목록을 읽어 4.2·4.3 목록과 맞춰 보므로 `@TestOn('vm')`이다(Chrome 몫은 `web/recognition_browser_test.dart`).
10. 이 진행 기록(`docs/plans/progress/library.md`)은 이 단계 경로 목록 밖이지만 영역 자기 진행 파일이다(계약 2차 2.2).

### 다른 영역에 알림

- INFRA(R2-B8a `RecognitionModule`): 지금 `recognitionOverrides()`는 override 1개(`inkShapeFitterProvider` → `NoShapeFitter`)다. L2-07 병합 뒤 정확히 3개(4.4.8)가 된다 — V5의 'provider 출처·횟수' 단언은 그때의 3개 기준으로. `handwritingIndexerProvider`는 웹·지원 안 함에서 null이고, 만들어진 색인기의 `start()`는 L2-10a까지 아무것도 하지 않는다(유휴 작업 `recognition.indexer`가 불러도 안전).
- INFRA V5b·LIBRARY L2-I3: `SyntheticShapes.rectanglePath`는 이 커밋부터 최종 모양이다. '기본 판정기가 늘 사각형으로 판정'은 L2-06(P-B)이 `GeometricShapeFitter`를 넣을 때 켠다.
- EDITOR·INFRA: `recognitionSelectionActions()`·`recognitionInsertActions()`는 L2-12까지 빈 목록이다.


### 동시 개발

바탕: `area2/library` = `main` `5843ec3`(기반 단계 R2-B1~R2-B6 + R2-final + 계약 v2.3). 다른 영역 2차 구현은 이 작업 트리에서 기반 단계 표면 — CORE 가짜 저장소 v2(B2-β T23b: 손글씨 `update`·`stalePages`·`notesWithStalePages` 동작), INK R2-B3(T24~T26b: `MathPreview` 실제, `useInkTestFonts`, `createTestPageController(shapeFitter:)`).

착수 정리(세션 1): 계획서 상태 줄 '승인 · 계약 v2.3', 5.8 '가정' → 실제 타입, v2.2(C22-07 V5 → V5b)·v2.3(C23-07 `FakeInkShapeFitter.result`·`useInkTestFonts`·WidgetsBinding) 인용 맞춤. 00-review '최종 승인' LIBRARY-F1(P-B 미루면 `미룸`) · F2(`ShapeFitTuning` 기본값을 바꾸는 커밋은 `synthetic_shapes_test` 같이) · F3(에뮬레이터 uid·`npx --prefix functions firebase …`)은 계획서 8.2·8.3·9.3에 이미 있어 그대로 따른다. 다른 영역이 보낸 [LIBRARY] 표시: INK(`FakeInkShapeFitter`는 `result` 필드, Chrome 시험의 `useInkTestFonts`, `InkMathRenderer.layout`의 WidgetsBinding) — L2-13·14·17a·20·I3 시험을 쓸 때 지킨다. INFRA(`ink_recognition` 골격 준비) — 할 일 없음.

#### 작업 표

| ID | 상태 | 커밋 | 완료 조건 시험 파일 |
|---|---|---|---|
| B6-a | 기반 단계에서 완료 | 99cdeef | `feature_library_smoke_test.dart`, `unit/api_surface_test.dart` |
| B6-b | 기반 단계에서 완료 | 99cdeef | `ink_recognition_smoke_test.dart`, `unit/api_surface_test.dart`·`handwriting_trace_test.dart`·`fakes_test.dart`·`synthetic_shapes_test.dart`·`group_into_lines_test.dart`, `web/recognition_browser_test.dart` |
| L2-01 | 남음 | | feature_library `unit/content_hits_test.dart`, `unit/content_provider_test.dart` |
| L2-02 | 남음 | | `widget/content_search_test.dart`, `unit/strings_contract_test.dart` |
| L2-03 | 남음 | | `widget/content_search_test.dart` |
| L2-04 | 남음 | | `goldens/library_golden_test.dart`, `widget/a11y_test.dart`, `shared/library_scenarios.dart` → `widget/scenarios_on_fake_test.dart`·`web/scenarios_browser_test.dart` |
| L2-05 | 남음 | | ink_recognition `unit/group_into_lines_test.dart`, `unit/synthetic_handwriting_test.dart`, `shared/line_cases.dart` |
| L2-06 (P-B) | 남음 | | `unit/shape_fitter_test.dart`, `unit/shape_geometry_test.dart`, `unit/synthetic_shapes_test.dart`, `unit/shape_real_samples_test.dart`, `shared/shape_cases.dart` |
| L2-07 | 남음 | | `unit/recognition_overrides_test.dart`, `unit/settings_keys_test.dart`, `unit/strings_contract_test.dart` |
| L2-08 (P-B, ML Kit) | 남음 | | `native/mlkit_adapter_test.dart`, `unit/mlkit_errors_test.dart` |
| L2-09 (P-B) | 남음 | | `unit/mixed_language_test.dart` |
| L2-10a | 남음 | | `unit/indexer_test.dart` |
| L2-10b | 남음 | | `unit/line_reuse_test.dart`, `unit/indexer_merge_test.dart`, `unit/indexer_test.dart`, `unit/catch_up_test.dart` |
| L2-11 | 남음 | | `unit/indexer_provider_test.dart` |
| L2-12 | 남음 | | `unit/recognition_actions_test.dart`, `unit/object_builders_test.dart` |
| L2-13 | 남음 | | `widget/latex_editor_sheet_test.dart`, `unit/recognition_actions_test.dart` |
| L2-14 | 남음 | | `widget/math_pad_manual_test.dart`, `widget/sheet_rules_test.dart` |
| L2-15 (P-B) | 남음 | | `widget/conversion_sheet_test.dart`, `widget/sheet_rules_test.dart` |
| L2-16 (P-B) | 남음 | | `unit/callable_math_recognizer_test.dart`, `unit/math_payload_test.dart` (+ `emulator/callable_emulator_test.dart` 기본 skip — L2-I6) |
| L2-17a (P-B) | 남음 | | `widget/math_pad_engine_test.dart` |
| L2-17b (P-B) | 남음 | | `widget/to_math_test.dart` |
| L2-18 (P-A / P-B) | 남음 | | `widget/settings_section_test.dart` |
| L2-19 (P-B, A-4 실험 창) | 남음 | | `unit/char_error_rate_test.dart`, `widget/recognition_lab_test.dart` |
| L2-20 | 남음 | | `ink_recognition/test/web/recognition_browser_test.dart`, `feature_library/test/web/scenarios_browser_test.dart` |
| L2-22 (P-C) | 남음 | | `unit/math_fixture_export_test.dart`, `widget/math_pad_engine_test.dart` |
| L2-I1 | 통합 단계 | | `ink_recognition/test/integration/real_core_indexer_test.dart`(`integration` — 미리 써 둠) |
| L2-I2 | 통합 단계 | | `feature_library/test/integration/core_contract_test.dart` |
| L2-I3 | 통합 단계 | | `ink_recognition/test/integration/shape_assist_flow_test.dart`(`integration` — 미리 써 둠) |
| L2-I4 | 통합 단계 | | INFRA `app_smoke_v2_test.dart`·`feature_switch_test.dart` |
| L2-I5 | 통합 단계 | | 실기기 결과 → 진행 기록 |
| L2-I6 | 통합 단계 | | `emulator/callable_emulator_test.dart`(`emulator` — L2-16과 함께 써 둠) |

#### 변경 요청

- 없음

#### 의존성 요청

- 없음

#### 계획과 다르게 한 점

- 없음

#### 이정표 커밋

- 없음

#### 다음 세션 메모

- 순서(8.2 권장 — P-A 먼저): L2-01 → 02 → 03 → 04 / L2-05 → 07 → 10a → 10b → 11 → 12 → 13 → 14 → 18(P-A) → 20, 그다음 P-B(06·08·09·15·16·17a·17b·18 나머지·19), 마지막 P-C(22).
