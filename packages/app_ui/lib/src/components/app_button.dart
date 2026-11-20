import 'package:app_ui/src/theme/app_tokens.dart';
import 'package:material_ui/material_ui.dart';

/// The app's full-width action button: primary (near white on graphite) or
/// [secondary] (outlined surface). Shows a spinner and ignores taps while
/// [loading], so callers never double-submit.
class AppButton extends StatelessWidget {
  const new({
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.secondary = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final child = loading
        ? SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: secondary ? t.textPrimary : t.onAction,
            ),
          )
        : Text(label);
    final onTap = loading ? null : onPressed;
    return SizedBox(
      width: double.infinity,
      child: secondary
          ? OutlinedButton(onPressed: onTap, child: child)
          : FilledButton(
              onPressed: onTap,
              // Keep the primary look while loading, not the disabled grey.
              style: loading
                  ? FilledButton.styleFrom(
                      disabledBackgroundColor: t.action,
                      disabledForegroundColor: t.onAction,
                    )
                  : null,
              child: child,
            ),
    );
  }
}
