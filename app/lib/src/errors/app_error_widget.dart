/// Release-mode error box (docs/plans/01-infra.md 4.5.3, 6.7).
library;

import 'package:material_ui/material_ui.dart';

import '../app/strings.dart';

/// Release-mode replacement for the red error box: grey box + icon +
/// "이 부분을 표시하지 못했어요".
Widget appErrorWidgetBuilder(FlutterErrorDetails details) =>
    const _AppErrorBox();

class _AppErrorBox extends StatelessWidget {
  const _AppErrorBox();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // An error can be shown above MaterialApp (no Directionality there).
    return Directionality(
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      child: ColoredBox(
        color: colors.surfaceContainerHighest,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.broken_image_outlined,
                  color: colors.onSurfaceVariant,
                  size: 24,
                ),
                const SizedBox(height: 4),
                Text(
                  AppStrings.errorWidgetMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
