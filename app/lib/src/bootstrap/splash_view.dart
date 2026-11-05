import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../app/strings.dart';

/// First frame of the app (6.4): app name, the current startup stage and,
/// once the stage is slow, "시간이 걸리고 있어요… (n초)" where n counts the
/// seconds of the current stage.
///
/// Needs a Directionality / MaterialApp above it (BootstrapApp provides one).
class SplashView extends StatelessWidget {
  const SplashView({super.key, required this.stageLabel, required this.isSlow});
  final ValueListenable<String> stageLabel;
  final ValueListenable<bool> isSlow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(AppStrings.appName, style: theme.textTheme.headlineMedium),
              const SizedBox(height: 24),
              const SizedBox.square(
                dimension: 32,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 16),
              _StageText(stageLabel: stageLabel, isSlow: isSlow),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stage label plus the slow notice. Counts whole seconds since the label
/// last changed with a 1 s periodic timer (fake-time friendly in tests).
class _StageText extends StatefulWidget {
  const _StageText({required this.stageLabel, required this.isSlow});

  final ValueListenable<String> stageLabel;
  final ValueListenable<bool> isSlow;

  @override
  State<_StageText> createState() => _StageTextState();
}

class _StageTextState extends State<_StageText> {
  Timer? _ticker;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    widget.stageLabel.addListener(_onStage);
    widget.isSlow.addListener(_onChanged);
    _restartCount();
  }

  @override
  void didUpdateWidget(_StageText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stageLabel != widget.stageLabel) {
      oldWidget.stageLabel.removeListener(_onStage);
      widget.stageLabel.addListener(_onStage);
      _restartCount();
    }
    if (oldWidget.isSlow != widget.isSlow) {
      oldWidget.isSlow.removeListener(_onChanged);
      widget.isSlow.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    widget.stageLabel.removeListener(_onStage);
    widget.isSlow.removeListener(_onChanged);
    super.dispose();
  }

  void _restartCount() {
    _ticker?.cancel();
    _seconds = 0;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _seconds++;
      if (widget.isSlow.value) setState(() {});
    });
  }

  void _onStage() => setState(_restartCount);

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = widget.stageLabel.value;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label.isNotEmpty)
          Text(
            label,
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        if (widget.isSlow.value) ...[
          const SizedBox(height: 8),
          Text(
            AppStrings.splashSlow(_seconds),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
