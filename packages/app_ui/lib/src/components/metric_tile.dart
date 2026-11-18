import 'package:app_ui/src/theme/app_tokens.dart';
import 'package:material_ui/material_ui.dart';

/// A labelled number, such as "Body fat 18.2 %". Optionally shows a change
/// since the last scan; [deltaIsGood] decides whether it is colored as
/// progress (lean) or a regression (danger).
class MetricTile extends StatelessWidget {
  const new({
    required this.label,
    required this.value,
    this.unit,
    this.delta,
    this.deltaIsGood,
    super.key,
  });

  final String label;
  final String value;
  final String? unit;
  final String? delta;
  final bool? deltaIsGood;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final deltaColor = switch (deltaIsGood) {
      true => t.lean,
      false => t.danger,
      null => t.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: text.labelMedium?.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text.rich(
            TextSpan(
              text: value,
              style: text.headlineSmall?.copyWith(color: t.textPrimary),
              children: [
                if (unit != null)
                  TextSpan(
                    text: ' $unit',
                    style: text.bodyMedium?.copyWith(color: t.textSecondary),
                  ),
              ],
            ),
          ),
          if (delta != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(delta!, style: text.labelMedium?.copyWith(color: deltaColor)),
          ],
        ],
      ),
    );
  }
}
