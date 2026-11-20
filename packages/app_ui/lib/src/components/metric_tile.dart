import 'package:app_ui/src/theme/app_theme.dart';
import 'package:app_ui/src/theme/app_tokens.dart';
import 'package:material_ui/material_ui.dart';

/// A labelled number, such as "Body fat 18.2 %", on a card. [valueColor]
/// tints the number (lean or fat). An optional [delta] shows the change since
/// the last scan; [deltaIsGood] colors it by meaning, never as an alarm:
/// progress is lean (Ice), a step back is fat (Ember).
class MetricTile extends StatelessWidget {
  const new({
    required this.label,
    required this.value,
    this.unit,
    this.valueColor,
    this.delta,
    this.deltaIsGood,
    super.key,
  });

  final String label;
  final String value;
  final String? unit;
  final Color? valueColor;
  final String? delta;
  final bool? deltaIsGood;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final deltaColor = switch (deltaIsGood) {
      true => t.lean,
      false => t.fat,
      null => t.textFaint,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.smd + 2,
        vertical: AppSpacing.smd,
      ),
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(
              text: value,
              style: AppTheme.display(size: 22)
                  .copyWith(color: valueColor ?? t.textPrimary),
              children: [
                if (unit != null)
                  TextSpan(
                    text: ' $unit',
                    style: text.bodySmall?.copyWith(color: t.textSecondary),
                  ),
              ],
            ),
          ),
          if (delta != null) ...[
            const SizedBox(height: 2),
            Text(delta!, style: text.bodySmall?.copyWith(color: deltaColor)),
          ],
        ],
      ),
    );
  }
}
