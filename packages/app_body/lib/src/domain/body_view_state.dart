import 'package:body_mapping/body_mapping.dart';
import 'package:meta/meta.dart';

/// What the body shows.
enum BodyViewMode {
  /// The plain body in the current style.
  body,

  /// Fat % per region.
  fat,

  /// Change between the two compared scans ([ChangeMetric]).
  change,
}

/// Which change the Change view colors.
enum ChangeMetric { fat, lean }

/// UI state of the body screen: which two scans are compared and how.
@immutable
class BodyViewState {
  const new({
    this.fromId,
    this.toId,
    this.t = 1,
    this.mode = BodyViewMode.body,
    this.changeMetric = ChangeMetric.fat,
    this.exaggerate = false,
    this.selected,
  });

  /// Compared scans by id. Null means the defaults: previous and latest.
  final String? fromId;
  final String? toId;

  /// Blend between the two scans: 0 is [fromId], 1 is [toId].
  final double t;
  final BodyViewMode mode;
  final ChangeMetric changeMetric;

  /// Multiplies the shape change by [exaggerateGain]. Off by default, and
  /// the body carries a visible "x3" badge while on.
  final bool exaggerate;
  final BodyPart? selected;

  static const exaggerateGain = 3.0;

  HeatMetric? get heatMetric => switch (mode) {
    BodyViewMode.body => null,
    BodyViewMode.fat => HeatMetric.fatPct,
    BodyViewMode.change => switch (changeMetric) {
      ChangeMetric.fat => HeatMetric.fatChange,
      ChangeMetric.lean => HeatMetric.leanChange,
    },
  };

  BodyViewState copyWith({
    String? fromId,
    String? toId,
    double? t,
    BodyViewMode? mode,
    ChangeMetric? changeMetric,
    bool? exaggerate,
    BodyPart? Function()? selected,
  }) => BodyViewState(
    fromId: fromId ?? this.fromId,
    toId: toId ?? this.toId,
    t: t ?? this.t,
    mode: mode ?? this.mode,
    changeMetric: changeMetric ?? this.changeMetric,
    exaggerate: exaggerate ?? this.exaggerate,
    selected: selected == null ? this.selected : selected(),
  );
}

/// The two scans being compared, resolved from the state and the scan list.
typedef ScanPair = ({BodyScan from, BodyScan to});

/// Resolves [state]'s scan ids against [scans] (sorted oldest first). Falls
/// back to previous and latest; a single scan is compared with itself.
ScanPair? resolvePair(List<BodyScan> scans, BodyViewState state) {
  if (scans.isEmpty) return null;
  BodyScan? byId(String? id) {
    for (final s in scans) {
      if (s.id == id) return s;
    }
    return null;
  }

  final to = byId(state.toId) ?? scans.last;
  final toIndex = scans.indexOf(to);
  final from = byId(state.fromId) ?? scans[toIndex > 0 ? toIndex - 1 : toIndex];
  return (from: from, to: to);
}
