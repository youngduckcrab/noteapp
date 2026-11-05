import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../routing/app_router.dart';
import '../routing/app_routes.dart';
import '../routing/screen_builders.dart';
import 'strings.dart';

/// Root widget of foundation step B8: material_ui MaterialApp.router over
/// [createAppRouter] with the production screens. It owns the router and
/// disposes it.
///
/// BootstrapApp shows it after a successful start until I7 replaces it with
/// NoteApp (theme, UpdateBanner, router provider — docs/plans/01-infra.md
/// 4.5.6). Must sit below a ProviderScope that overrides CORE's
/// noteStoreProvider (contract 7.3.3).
class FoundationApp extends StatefulWidget {
  const FoundationApp({super.key, this.initialLocation = AppRoutes.library});

  /// First location (tests start on deep links such as `/notes/n1`).
  final String initialLocation;

  @override
  State<FoundationApp> createState() => _FoundationAppState();
}

class _FoundationAppState extends State<FoundationApp> {
  late final GoRouter _router = createAppRouter(
    screens: AppScreenBuilders.production(),
    initialLocation: widget.initialLocation,
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppStrings.appName,
      locale: const Locale('ko'),
      routerConfig: _router,
    );
  }
}
