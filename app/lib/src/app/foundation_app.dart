import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../routing/app_routes.dart';
import '../routing/foundation_router.dart';
import 'strings.dart';

/// Root widget of foundation step B8: material_ui MaterialApp.router over
/// [createFoundationRouter]. It owns the router and disposes it.
///
/// I7 replaces it with NoteApp (theme, UpdateBanner, router provider —
/// docs/plans/01-infra.md 4.5.6). Must sit below a ProviderScope that
/// overrides CORE's noteStoreProvider (contract 7.3.3).
class FoundationApp extends StatefulWidget {
  const FoundationApp({super.key, this.initialLocation = AppRoutes.library});

  /// First location (tests start on deep links such as `/notes/n1`).
  final String initialLocation;

  @override
  State<FoundationApp> createState() => _FoundationAppState();
}

class _FoundationAppState extends State<FoundationApp> {
  late final GoRouter _router = createFoundationRouter(
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

/// Shown instead of the app when openNoteStore fails (B8: always until CORE
/// T6, whose openNoteStore is UnimplementedError in B2). I5 replaces it with
/// StartupErrorScreen (retry, reset, diagnostics).
class FoundationStartupNotice extends StatelessWidget {
  const FoundationStartupNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: AppStrings.appName,
      locale: Locale('ko'),
      home: Scaffold(body: _NoticeBody()),
    );
  }
}

class _NoticeBody extends StatelessWidget {
  const _NoticeBody();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppStrings.storeOpenFailed,
              style: textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              AppStrings.storeOpenFailedDetail,
              style: textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
