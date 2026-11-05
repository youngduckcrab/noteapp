import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'src/bootstrap/foundation_bootstrap.dart';

/// Foundation step B8 entry point: tries CORE openNoteStore and shows the
/// minimal router with the placeholder screens, or a notice when the store
/// cannot be opened (docs/plans/01-infra.md 8.1 B8-1).
///
/// I5 replaces the body with `runNoteApp()` (bootstrap, modules, error
/// handling — 4.5.4, 6.4).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  runApp(await buildFoundationRoot());
}
