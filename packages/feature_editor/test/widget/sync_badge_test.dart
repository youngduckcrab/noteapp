// E-13: the toolbar sync icon (04-editor 6.9.1, contract 7.2.13): hidden
// while off (the default), else icon + semantics label.
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/toolbar/sync_badge_icon.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';

Future<void> _pumpWith(WidgetTester tester, core.SyncBadge badge) async {
  await pumpEditor(
    tester,
    overrides: [
      core.syncBadgeProvider.overrideWith((ref) => Stream.value(badge)),
    ],
  );
  await tester.pump();
}

Icon _icon(WidgetTester tester) => tester.widget<Icon>(
  find.descendant(
    of: find.byKey(EditorSyncBadgeIcon.iconKey),
    matching: find.byType(Icon),
  ),
);

void main() {
  testWidgets('default (off) → no icon, no space', (tester) async {
    await pumpEditor(tester);
    await tester.pump();
    expect(find.byKey(EditorSyncBadgeIcon.iconKey), findsNothing);
    for (final label in [
      EditorStrings.syncDone,
      EditorStrings.syncInProgress,
      EditorStrings.syncOffline,
      EditorStrings.syncError,
    ]) {
      expect(find.bySemanticsLabel(label), findsNothing);
    }
  });

  testWidgets('done', (tester) async {
    await _pumpWith(
      tester,
      const core.SyncBadge(display: core.SyncDisplayState.done),
    );
    expect(_icon(tester).icon, Icons.cloud_done);
    expect(find.bySemanticsLabel(EditorStrings.syncDone), findsOneWidget);
  });

  testWidgets('inProgress with 3 pending changes → a 3 badge', (tester) async {
    await _pumpWith(
      tester,
      const core.SyncBadge(
        display: core.SyncDisplayState.inProgress,
        pendingChanges: 3,
      ),
    );
    expect(_icon(tester).icon, Icons.cloud_sync);
    expect(
      find.descendant(
        of: find.byKey(EditorSyncBadgeIcon.iconKey),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(EditorStrings.syncInProgress), findsOneWidget);
  });

  testWidgets('offline', (tester) async {
    await _pumpWith(
      tester,
      const core.SyncBadge(display: core.SyncDisplayState.offline),
    );
    expect(_icon(tester).icon, Icons.cloud_off);
    expect(find.bySemanticsLabel(EditorStrings.syncOffline), findsOneWidget);
  });

  testWidgets('error → sync_problem in colorScheme.error', (tester) async {
    await _pumpWith(
      tester,
      const core.SyncBadge(display: core.SyncDisplayState.error),
    );
    final icon = _icon(tester);
    expect(icon.icon, Icons.sync_problem);
    final scheme = Theme.of(
      tester.element(find.byKey(EditorSyncBadgeIcon.iconKey)),
    ).colorScheme;
    expect(icon.color, scheme.error);
    expect(find.bySemanticsLabel(EditorStrings.syncError), findsOneWidget);
  });

  testWidgets('a failing badge stream → hidden', (tester) async {
    await pumpEditor(
      tester,
      overrides: [
        core.syncBadgeProvider.overrideWith(
          (ref) => Stream<core.SyncBadge>.error(StateError('sync')),
        ),
      ],
    );
    await tester.pump();
    expect(find.byKey(EditorSyncBadgeIcon.iconKey), findsNothing);
  });
}
