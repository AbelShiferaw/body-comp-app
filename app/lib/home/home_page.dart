import 'dart:async';

import 'package:app_body/app_body.dart';
import 'package:app_core/app_core.dart';
import 'package:app_scans/app_scans.dart';
import 'package:app_ui/app_ui.dart';
import 'package:body_comp/home/home_summary.dart';
import 'package:body_comp/l10n/l10n.dart';
import 'package:body_comp/profile/domain/profile.dart';
import 'package:body_comp/profile/presentation/profile_providers.dart';
import 'package:body_comp/router/router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Home: the user's 3D body as the hero, with the level badge, the latest
/// scan's headline numbers and their change since the first scan above it.
///
/// Layout follows the launch design ("Launch mix · Home" on the canvas):
/// clean screen, game-style level badge, the body filling the rest.
class HomePage extends ConsumerStatefulWidget {
  const new({super.key, this.clock = DateTime.now});

  /// Injected so tests can pin "today" for the next-scan bar.
  final DateTime Function() clock;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      ref
        ..invalidate(scansProvider)
        ..invalidate(currentMeasurementsProvider);
      await ref.read(bodyScansProvider.future);
    } on AppException catch (e) {
      if (!mounted) return;
      final l10n = context.l10n;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is NetworkException ? l10n.errorNetwork : l10n.errorGeneric,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scans = ref.watch(bodyScansProvider);
    final units = ref.watch(profileProvider).value?.units ?? Units.metric;
    final summary = switch (scans.value) {
      final s? => HomeSummary.of(s, now: widget.clock()),
      null => null,
    };
    final empty = scans.hasValue && summary == null && !scans.hasError;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              summary: summary,
              refreshing: _refreshing,
              onRefresh: () => unawaited(_refresh()),
            ),
            if (summary != null) _Headline(summary: summary, units: units),
            Expanded(
              child: empty
                  ? const _EmptyState()
                  : const Padding(
                      padding: EdgeInsets.only(top: AppSpacing.sm),
                      child: BodyView(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const new({
    required this.summary,
    required this.refreshing,
    required this.onRefresh,
  });

  final HomeSummary? summary;
  final bool refreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    final s = summary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        0,
      ),
      child: Row(
        children: [
          if (s != null) ...[
            LevelBadge(level: s.level),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.appTitle.toUpperCase(),
                    maxLines: 1,
                    style: textTheme.titleSmall?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                    ),
                  ),
                ),
                if (s != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  _NextScanBar(progress: s.nextScanProgress),
                ],
              ],
            ),
          ),
          if (s != null) Flexible(child: _ScanChip(scan: s)),
          IconButton(
            key: const Key('home_refresh'),
            tooltip: l10n.homeRefresh,
            onPressed: refreshing ? null : onRefresh,
            icon: refreshing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          IconButton(
            key: const Key('home_settings'),
            tooltip: l10n.settingsTitle,
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.push(Routes.settings),
          ),
        ],
      ),
    );
  }
}

/// The avatar's level (one per DEXA scan) in a hex badge.
class LevelBadge extends StatelessWidget {
  const new({required this.level, super.key});

  final int level;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      label: context.l10n.homeLevel(level),
      excludeSemantics: true,
      child: CustomPaint(
        key: const Key('home_level'),
        painter: _HexPainter(fill: tokens.surface, edge: tokens.lean),
        child: SizedBox(
          width: 40,
          height: 36,
          child: Center(
            child: Text(
              '$level',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(color: tokens.lean, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
    );
  }
}

class _HexPainter extends CustomPainter {
  const new({required this.fill, required this.edge});

  final Color fill;
  final Color edge;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.25, 0.5)
      ..lineTo(w * 0.75, 0.5)
      ..lineTo(w - 0.5, h / 2)
      ..lineTo(w * 0.75, h - 0.5)
      ..lineTo(w * 0.25, h - 0.5)
      ..lineTo(0.5, h / 2)
      ..close();
    canvas
      ..drawPath(path, Paint()..color = fill)
      ..drawPath(
        path,
        Paint()
          ..color = edge
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
  }

  @override
  bool shouldRepaint(_HexPainter old) => old.fill != fill || old.edge != edge;
}

class _NextScanBar extends StatelessWidget {
  const new({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      label: context.l10n.homeNextScan((progress * 100).round()),
      excludeSemantics: true,
      child: SizedBox(
        width: 92,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: LinearProgressIndicator(
            key: const Key('home_nextScan'),
            value: progress,
            minHeight: 4,
            color: tokens.lean,
            backgroundColor: tokens.surfaceRaised,
          ),
        ),
      ),
    );
  }
}

class _ScanChip extends StatelessWidget {
  const new({required this.scan});

  final HomeSummary scan;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.tokens;
    final latest = scan.latest;
    return Container(
      key: const Key('home_scanChip'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        latest.isEstimate
            ? l10n.homeScanEstimate(latest.scannedAt)
            : l10n.homeScanDexa(latest.scannedAt),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: tokens.textSecondary),
      ),
    );
  }
}

/// Body fat, lean mass and visceral fat of the latest scan, each with its
/// change since the first scan, colored by meaning.
class _Headline extends StatelessWidget {
  const new({required this.summary, required this.units});

  final HomeSummary summary;
  final Units units;

  static const _lbPerKg = 2.20462;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final s = summary;
    final imperial = units == Units.imperial;
    final mass = imperial ? _lbPerKg : 1.0;
    final massUnit = imperial ? l10n.unitLb : l10n.unitKg;
    final visceral = imperial ? _lbPerKg / 1000 : 1.0;
    final visceralUnit = imperial ? l10n.unitLb : l10n.unitG;

    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          0,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Stat(
                key: const Key('home_bodyFat'),
                label: l10n.metricBodyFat,
                stat: s.bodyFat,
                digits: 1,
                unit: l10n.unitPercent,
                changeUnit: l10n.unitPoints,
                since: s.first.scannedAt,
                compare: s.hasComparison,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _Stat(
                key: const Key('home_lean'),
                label: l10n.metricLeanMass,
                stat: s.leanKg,
                scale: mass,
                digits: 1,
                unit: massUnit,
                changeUnit: massUnit,
                since: s.first.scannedAt,
                compare: s.hasComparison,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _Stat(
                key: const Key('home_visceral'),
                label: l10n.metricVisceralShort,
                stat: s.visceralG,
                scale: visceral,
                digits: imperial ? 2 : 0,
                unit: visceralUnit,
                changeUnit: visceralUnit,
                since: s.first.scannedAt,
                compare: s.hasComparison,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const new({
    required this.label,
    required this.stat,
    required this.digits,
    required this.unit,
    required this.changeUnit,
    required this.since,
    required this.compare,
    this.scale = 1,
    super.key,
  });

  final String label;
  final HeadlineStat stat;
  final int digits;
  final double scale;
  final String unit;
  final String changeUnit;
  final DateTime since;
  final bool compare;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    final value = stat.value;
    final change = stat.change;

    final String? changeText;
    if (change != null) {
      changeText = stat.trend == Trend.flat
          ? l10n.homeNoChange(since)
          : '${change < 0 ? '▼' : '▲'} '
                '${(change.abs() * scale).toStringAsFixed(digits)} '
                '$changeUnit ${l10n.homeSince(since)}';
    } else {
      changeText = compare ? null : l10n.homeFirstScan;
    }
    final changeColor = switch (stat.trend) {
      Trend.better => tokens.lean,
      Trend.worse => tokens.fat,
      Trend.flat => tokens.textSecondary,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.labelSmall?.copyWith(
            color: tokens.textSecondary,
            letterSpacing: 0.8,
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(
              text: value == null
                  ? '–'
                  : (value * scale).toStringAsFixed(digits),
              style: textTheme.headlineMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
              children: [
                if (value != null)
                  TextSpan(
                    text: unit,
                    style: textTheme.titleSmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (changeText != null)
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              changeText,
              maxLines: 1,
              style: textTheme.labelSmall?.copyWith(color: changeColor),
            ),
          ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.accessibility_new, size: 72, color: tokens.lean),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.homeEmptyTitle,
              textAlign: TextAlign.center,
              style: textTheme.titleLarge?.copyWith(color: tokens.textPrimary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.homeEmptyBody,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              key: const Key('home_connect'),
              label: l10n.homeEmptyAction,
              onPressed: () => context.push(Routes.onboarding),
            ),
          ],
        ),
      ),
    );
  }
}
