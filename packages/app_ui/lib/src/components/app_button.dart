import 'package:app_ui/src/theme/app_tokens.dart';
import 'package:material_ui/material_ui.dart';

/// The app's primary action button. Shows a spinner and ignores taps while
/// [loading], so callers never double-submit.
class AppButton extends StatelessWidget {
  const new({
    required this.label,
    required this.onPressed,
    this.loading = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
        child: loading
            ? SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.tokens.onAccent,
                ),
              )
            : Text(label),
      ),
    );
  }
}
