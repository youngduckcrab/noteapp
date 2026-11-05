// lib/src/ui/settings/editor_settings_sections.dart — contract 00-overview
// 7.2.17 ('Settings sections (Column only, no Scaffold)'), 04-editor 4.9.
//
// INFRA's settings screen puts these inside its ListView, in the order
// editor.input → editor.pen → 일반 › editor.page → editor.developer, and draws
// the section titles itself (01-infra 4.5.8). Each widget is a Column without
// a Scaffold or its own scrolling.
//
// Foundation step B5 (contract 7.6): placeholders with an empty body. Task
// E-20 adds the controls described on each class.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// 입력: 입력 모드(자동/펜 전용/손가락 필기), 팜 리젝션(펜 직후 터치 무시 시간,
/// 펜 hover 중 터치 무시, 접촉 반경 — 지원 기기 안내 문구 포함),
/// 제스처(두 손가락 탭 되돌리기, 세 손가락 탭 다시 실행, 길게 누르기 메뉴 켜기/끄기,
/// 나머지 제스처는 읽기 전용 표).
class EditorInputSettingsSection extends ConsumerWidget {
  const EditorInputSettingsSection({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => const _PlaceholderBody();
}

/// 펜: 필압 사용(자동/항상 사용/사용 안 함 = ink.PressureMode, 현재 감지 상태는
/// ink.pressureCapabilityProvider), 그리고 현재 펜 종류(editorToolProvider.penType)의
/// 필압 곡선(부드럽게/보통/단단하게)·필압 감도·손떨림 보정·(형광펜일 때) 직선 보정,
/// '펜 종류별 기본값으로 초기화'(core.StrokeStyle.defaultsFor). 펜 종류 선택 칩으로
/// 다른 종류의 값도 편집할 수 있다(펜 팝업 '고급'과 같은 값 — 6.9.3).
class EditorPenSettingsSection extends ConsumerWidget {
  const EditorPenSettingsSection({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => const _PlaceholderBody();
}

/// 일반 › 페이지 넘김: 세로 스크롤 / 좌우 넘기기.
class EditorPageSettingsSection extends ConsumerWidget {
  const EditorPageSettingsSection({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => const _PlaceholderBody();
}

/// 개발자 표시 켜기/끄기, 켜는 다른 방법 안내, '합성 노트 만들기'(core seedSyntheticNote,
/// 6.12.4).
class EditorDeveloperSettingsSection extends ConsumerWidget {
  const EditorDeveloperSettingsSection({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => const _PlaceholderBody();
}

/// B5: an empty Column (no Scaffold, no scrolling — contract 7.2.17).
class _PlaceholderBody extends StatelessWidget {
  const _PlaceholderBody();

  @override
  Widget build(BuildContext context) => const Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[],
  );
}
