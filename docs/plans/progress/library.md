# LIBRARY 진행 기록

## 요약

- 마지막 세션: 4 (동시 개발 단계) — L11·L12 완료(세션 1: C13-05·L0·L1·L3·L4, 세션 2: L5~L8, 세션 3: L9·L10, L2는 기반 단계 B6에서 완료)
- 다음 할 일: L13 (항목 동작) → L14~L18 → L19 → L20
- 기준: 계획서 `docs/plans/05-library.md` 8장(작업 분해), 통합 계약 00-overview 7장 v1.4

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
| L13 | 남음 | | `widget/item_actions_test.dart`, `widget/folder_picker_test.dart` |
| L14 | 남음 | | `widget/multi_select_test.dart` |
| L15 | 남음 | | `unit/drop_decision_test.dart`, `unit/drag_handle_test.dart`, `unit/auto_scroll_test.dart`, `widget/drag_drop_test.dart`, `widget/auto_scroll_widget_test.dart` |
| L16 | 남음 | | `widget/trash_view_test.dart` |
| L17 | 남음 | | `widget/recent_favorites_test.dart`, `widget/search_test.dart` |
| L18 | 남음 | | `widget/integration_slots_test.dart`, `widget/storage_banner_test.dart`, `widget/settings_section_test.dart` |
| L19 | 남음 | | `goldens/library_golden_test.dart`, `widget/performance_test.dart`, `widget/a11y_test.dart` |
| L20 | 남음 | | `web/library_browser_test.dart` (+ L3 `web/new_note_options_browser_test.dart`) |
| L21 | 통합 단계 | | `integration/core_contract_test.dart` (`@Tags(['integration'])`, 미리 써 둬도 됨) |

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
- L0 공유 시나리오 목록에는 지금 하네스 시나리오 1건('a route change keeps the LibraryScreen State')만 있다. L21의 8건은 해당 화면 작업(L10~L18) 때 추가한다.

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
- 세션 4 L11: 표지는 `NoteCoverView`(4가지 + 예약기 요청), 예약기는 `coverThumbnailSchedulerProvider`, 에셋 표지는 `assetCoverBytesProvider`(`providers.dart`). 테스트 기본은 렌더러 자리 `null`(예약기 꺼짐, 자리표시) — 표지를 그려 보려면 `pageThumbnailRendererProvider.overrideWithValue(FakeThumbnailRenderer())`. L13의 '표지 변경'(`setCover`)은 `CoverPalette`·`ColorCoverCard`를 미리보기로 쓸 수 있다.
- L13 시작점: ⋯ 자리는 타일 `Stack`(`note_tile.dart`·`folder_tile.dart`의 'L13' 주석)과 리스트 행(`item_list.dart`의 `SizedBox(52)`). 대화상자 틀은 `LibraryDialogFrame`·`DialogNameField`(L12), 꾸미기는 `FolderColorPicker`·`FolderIconPicker`, 표지 변경은 `CoverPicker`(+ `ColorCoverCard` 미리보기), 실행 취소 스낵바는 `showLibrarySnackBarOn`(L8), 변경은 `libraryActionsProvider`(`move`→`MoveReceipt`/`undoMove`, `trash`→`restore`). 사이드바 줄 메뉴의 '새 하위 폴더'는 `runNewFolderFlow(context, parentId: 그 폴더)`.
- 화면 테스트 도우미 관례: provider 오류 보고 횟수는 `FlutterError.onError`를 try/finally로 잠시 바꿔 센다(`widget/sidebar_test.dart`·`widget/listing_test.dart`의 `collectReports`). 정렬 메뉴는 `find.byTooltip(LibraryStrings.sort)` → `find.widgetWithText(MenuItemButton, …)`.
- 위젯 테스트에서 provider 컨테이너는 `ProviderScope.containerOf(tester.element(find.byType(LibraryTopBar)))`로 얻을 수 있다(`widget/layout_test.dart`).
