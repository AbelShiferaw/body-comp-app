import 'package:body_mapping/body_mapping.dart';

// TODO(body): move strings to localization once modules share l10n.

String partName(BodyPart p) => switch (p) {
  BodyPart.leftArm => 'Left arm',
  BodyPart.rightArm => 'Right arm',
  BodyPart.leftLeg => 'Left leg',
  BodyPart.rightLeg => 'Right leg',
  BodyPart.trunk => 'Trunk',
  BodyPart.belly => 'Belly',
  BodyPart.hips => 'Hips',
};

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String shortDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

String signed(double x, {int digits = 1}) =>
    '${x >= 0 ? '+' : '−'}${x.abs().toStringAsFixed(digits)}';

/// Legend label for one ramp stop.
String legendLabel(HeatMetric metric, double value, {required bool first}) =>
    switch (metric) {
      HeatMetric.fatPct => '${value.round()}%${first ? ' fat' : ''}',
      HeatMetric.fatChange || HeatMetric.leanChange =>
        value == 0
            ? 'no change'
            : '${signed(value * 100, digits: 0)}% '
                  '${metric == HeatMetric.fatChange ? 'fat' : 'lean'}',
    };
