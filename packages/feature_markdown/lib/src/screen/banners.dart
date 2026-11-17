// The banners under the top bar (08-markdown 8.4, 8.7; B-10): read-only reasons, save
// failures with [다시 시도], conflict copies, unsaved text kept on this device.
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

enum MdBannerTone { info, warning, error }

class MdBanner extends StatelessWidget {
  const MdBanner({
    super.key,
    required this.text,
    this.tone = MdBannerTone.info,
    this.actions = const [],
  });

  final String text;
  final MdBannerTone tone;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = StyleTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (tone) {
      MdBannerTone.info => (t.card, t.textPrimary),
      MdBannerTone.warning => (t.accentSoft, t.onAccentSoft),
      MdBannerTone.error => (scheme.errorContainer, scheme.onErrorContainer),
    };
    final icon = switch (tone) {
      MdBannerTone.info => AppIconKind.info,
      MdBannerTone.warning => AppIconKind.warning,
      MdBannerTone.error => AppIconKind.error,
    };
    return Material(
      color: bg,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.hairline)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Row(
            children: [
              AppIcon(icon, size: 20, color: fg),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    text,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: fg),
                  ),
                ),
              ),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}
