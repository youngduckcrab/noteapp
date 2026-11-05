import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../providers.dart';
import 'strings.dart';
import 'theme.dart';

/// MaterialApp.router (material_ui) with routerConfig = appRouterProvider,
/// theme = buildAppTheme(), locale ko, builder: (context, child) =>
/// UpdateBanner(child: child!). No MaterialUiCompatibilityBridge (D2).
///
/// The UpdateBanner builder comes with I8 (update detection).
class NoteApp extends ConsumerWidget {
  const NoteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('ko'),
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
