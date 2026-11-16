import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../providers.dart';
import '../update/update_banner.dart';
import 'appearance.dart';
import 'strings.dart';
import 'theme.dart';

/// MaterialApp.router (material_ui) with routerConfig = appRouterProvider,
/// theme / darkTheme = buildAppTheme(style, light / dark) and themeMode from
/// appAppearanceProvider ('화면' settings — a change applies live, 01-infra
/// 18.3), locale ko, builder: (context, child) => UpdateBanner(child:
/// child!). No MaterialUiCompatibilityBridge (D2).
class NoteApp extends ConsumerWidget {
  const NoteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appAppearanceProvider);
    return MaterialApp.router(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(style: appearance.style),
      darkTheme: buildAppTheme(
        style: appearance.style,
        brightness: Brightness.dark,
      ),
      themeMode: appearance.themeMode,
      locale: const Locale('ko'),
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) => UpdateBanner(child: child!),
    );
  }
}
