// lib/src/settings/recognition_settings_section.dart — contract
// m5-7/00-overview 7.2.11 (m5-7/05-library 6.18).
//
// The settings screen's '인식' section body (1차 7.4.11 section rules: a
// Column only — no Scaffold, title or scroll; the parent gives the width).
// 2차 foundation step R2-B6 (contract 7.6.2): a placeholder — an empty
// Column. LIBRARY L2-18 adds the rows of 6.18 (language, models, Wi-Fi only,
// automatic indexing + status, math consent, lab entries).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class RecognitionSettingsSection extends ConsumerWidget {
  const RecognitionSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => const Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
  );
}
