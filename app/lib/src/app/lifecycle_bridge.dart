import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../web/web_platform.dart';

/// Listens to AppLifecycleListener (onHide / onPause / onDetach) and
/// WebPlatform.visibilityChanges (hidden), debounced to 1 call per second,
/// then calls AppBootstrapper.notifyAppHidden() (→ CoreModule: store.flush()).
///
/// The first signal calls at once; signals in the next second are dropped
/// (going to the background fires hide and pause back to back, and the web
/// also sends visibilitychange / pagehide).
class AppLifecycleBridge extends ConsumerStatefulWidget {
  const AppLifecycleBridge({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppLifecycleBridge> createState() => _AppLifecycleBridgeState();
}

class _AppLifecycleBridgeState extends ConsumerState<AppLifecycleBridge> {
  static const Duration _quietPeriod = Duration(seconds: 1);

  late final AppLifecycleListener _lifecycle;
  StreamSubscription<WebVisibility>? _visibility;
  Timer? _quiet;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: _onHidden,
      onPause: _onHidden,
      onDetach: _onHidden,
    );
    _visibility = ref.read(webPlatformProvider).visibilityChanges.listen((
      visibility,
    ) {
      if (visibility == WebVisibility.hidden) _onHidden();
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_visibility?.cancel());
    _quiet?.cancel();
    super.dispose();
  }

  void _onHidden() {
    if (_quiet?.isActive ?? false) return;
    _quiet = Timer(_quietPeriod, () {});
    // notifyAppHidden never throws: module failures go to the error log.
    unawaited(ref.read(appBootstrapperProvider).notifyAppHidden());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
