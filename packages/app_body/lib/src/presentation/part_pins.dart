import 'dart:math' as math;

import 'package:app_body/src/domain/body_renderer.dart';
import 'package:app_body/src/domain/body_view_state.dart';
import 'package:app_body/src/presentation/body_strings.dart';
import 'package:app_ui/app_ui.dart';
import 'package:body_mapping/body_mapping.dart';
import 'package:material_ui/material_ui.dart';

// TODO(body): move strings to localization once modules share l10n.

/// One pin: a body part, where it is on screen and what its label says.
typedef PartPin = ({BodyPart part, Offset point, PinText text});

/// A pin's two lines: the part's name and its number.
typedef PinText = ({String name, String value});

/// The parts that get a pin. The trunk and hips stay tap-only: they sit
/// under the belly and the legs, and their pins would crowd them.
const List<BodyPart> pinnedParts = [
  BodyPart.leftArm,
  BodyPart.rightArm,
  BodyPart.belly,
  BodyPart.leftLeg,
  BodyPart.rightLeg,
];

/// The pin text for [part] in the current view: lean mass in Shape, fat %
/// in Fat, and the change between the compared scans in Change. Masses
/// use one decimal, like the headline numbers.
PinText pinLabel(
  BodyPart part,
  BodyViewState view,
  ScanPair pair,
  MassUnit unit,
) {
  RegionMass? mass(BodyScan s) =>
      part.region != null ? s.regions[part.region] : s.bands[part.band];
  final a = mass(pair.from);
  final b = mass(pair.to);
  final name = partName(part);
  if (a == null || b == null) return (name: name, value: '–');
  double lerp(double x, double y) => x + (y - x) * view.t;
  String kg(double v, {bool sign = false}) {
    final shown = unit.of(v);
    return '${sign ? signed(shown) : shown.toStringAsFixed(1)} '
        '${unit.name}';
  }

  final value = switch (view.mode) {
    BodyViewMode.body => '${kg(lerp(a.leanKg, b.leanKg))} lean',
    BodyViewMode.fat => '${lerp(a.fatPct, b.fatPct).toStringAsFixed(1)}% fat',
    BodyViewMode.change => switch (view.changeMetric) {
      ChangeMetric.fat => '${kg(b.fatKg - a.fatKg, sign: true)} fat',
      ChangeMetric.lean => '${kg(b.leanKg - a.leanKg, sign: true)} lean',
    },
  };
  return (name: name, value: value);
}

/// Draws [pins] as a dot on each part with a small label beside it. Each
/// label tries, in order: outside its dot, inside it, above, below; it takes
/// the first spot that stays on screen and clear of other labels and dots.
/// If none is free it moves down, with a leader line back to its dot.
/// Tapping a label opens that part.
class PartPins extends StatelessWidget {
  const new({required this.pins, required this.onTap, super.key});

  final List<PartPin> pins;
  final ValueChanged<BodyPart> onTap;

  static const _dot = 10.0;
  static const _gap = 6.0;
  static const double _padX = AppSpacing.sm;
  static const double _padY = AppSpacing.xs;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    final nameStyle = textTheme.labelSmall?.copyWith(
      color: tokens.onAction.withValues(alpha: 0.72),
    );
    final valueStyle = textTheme.labelMedium?.copyWith(color: tokens.onAction);
    final scale = MediaQuery.textScalerOf(context);
    Size measure(String text, TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scale,
        maxLines: 1,
      )..layout();
      final size = painter.size;
      painter.dispose();
      return size;
    }

    return LayoutBuilder(
      builder: (context, c) {
        final bounds = Offset.zero & c.biggest;
        final dots = [
          for (final pin in pins)
            Rect.fromCircle(center: pin.point, radius: _dot / 2 + 2),
        ];
        bool free(Rect r, List<Rect> placed) =>
            r.left >= bounds.left + _gap &&
            r.right <= bounds.right - _gap &&
            r.top >= bounds.top &&
            r.bottom <= bounds.bottom &&
            !placed.any((o) => o.inflate(2).overlaps(r)) &&
            !dots.any((d) => d.overlaps(r));

        final placed = <Rect>[];
        final children = <Widget>[];
        final lines = <(Offset, Offset)>[];
        final sorted = [...pins]
          ..sort((a, b) => a.point.dy.compareTo(b.point.dy));
        for (final pin in sorted) {
          final name = measure(pin.text.name, nameStyle);
          final value = measure(pin.text.value, valueStyle);
          final size = Size(
            math.min(
              math.max(name.width, value.width) + 2 * _padX,
              bounds.width - 2 * _gap,
            ),
            name.height + value.height + 2 * _padY,
          );
          final p = pin.point;
          const r = _dot / 2 + _gap;
          Rect at(double left, double top) =>
              Rect.fromLTWH(left, top, size.width, size.height);
          final leftOf = at(p.dx - r - size.width, p.dy - size.height / 2);
          final rightOf = at(p.dx + r, p.dy - size.height / 2);
          final outerFirst = p.dx < bounds.center.dx
              ? [leftOf, rightOf]
              : [rightOf, leftOf];
          final candidates = [
            ...outerFirst,
            at(p.dx - size.width / 2, p.dy - r - size.height),
            at(p.dx - size.width / 2, p.dy + r),
          ];
          var rect = candidates.firstWhere(
            (c) => free(c, placed),
            orElse: () => Rect.zero,
          );
          if (rect == Rect.zero) {
            final first = outerFirst.first;
            rect = first.translate(
              (first.left.clamp(_gap, bounds.right - _gap - size.width)) -
                  first.left,
              0,
            );
            for (var i = 0; i < placed.length; i++) {
              if (rect.overlaps(placed[i].inflate(2))) {
                rect = rect.translate(0, placed[i].bottom + 4 - rect.top);
                i = -1; // Check again against every placed label.
              }
            }
            final edge = Offset(
              p.dx < rect.center.dx ? rect.left : rect.right,
              rect.center.dy,
            );
            lines.add((p, edge));
          }
          placed.add(rect);
          children.add(
            Positioned.fromRect(
              rect: rect,
              child: Semantics(
                button: true,
                child: GestureDetector(
                  key: Key('body_pin_${pin.part.name}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(pin.part),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.action,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: _padX,
                        vertical: _padY,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pin.text.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: nameStyle,
                          ),
                          Text(
                            pin.text.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: valueStyle,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _LeaderPainter(lines, tokens.action),
                ),
              ),
            ),
            ...children,
            for (final pin in pins)
              Positioned(
                left: pin.point.dx - _dot / 2,
                top: pin.point.dy - _dot / 2,
                width: _dot,
                height: _dot,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: tokens.surface, width: 2),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LeaderPainter extends CustomPainter {
  new(this.lines, this.color);

  final List<(Offset, Offset)> lines;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (final (a, b) in lines) {
      canvas.drawLine(a, b, paint);
    }
  }

  @override
  bool shouldRepaint(_LeaderPainter old) => true;
}
