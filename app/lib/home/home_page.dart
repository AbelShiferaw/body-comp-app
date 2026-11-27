import 'dart:async';

import 'package:app_body/app_body.dart';
import 'package:app_core/app_core.dart';
import 'package:app_dexa_sync/app_dexa_sync.dart';
import 'package:app_scans/app_scans.dart';
import 'package:app_ui/app_ui.dart';
import 'package:body_comp/home/home_summary.dart';
import 'package:body_comp/l10n/l10n.dart';
import 'package:body_comp/profile/domain/profile.dart';
import 'package:body_comp/profile/presentation/profile_providers.dart';
import 'package:body_comp/router/router.dart';
import 'package:body_mapping/body_mapping.dart' show Mass;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// Home: the user's 3D body as the hero, with the latest scan's headline
/// numbers and their change since the first scan above it.
///
/// Layout follows the basic look ("2 · Home" on the design canvas). Game
/// mode, a Settings switch, adds the level badge and the next-scan bar.
class HomePage extends ConsumerStatefulWidget {
  const new({super.key, this.clock = DateTime.now});

  /// Injected so tests can pin "today" for the next-scan bar.
  final DateTime Function() clock;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _refreshing = false;

  /// Imports new scans from the linked DEXA provider when this phone can,
  /// then reloads. Without a link it just reloads what is stored.
  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    void say(String text, {SnackBarAction? action}) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action));
    try {
      final link = await ref.read(dexaSyncProvider.future);
      if (link.canRefresh) {
        // A run that changed scans reloads them app-wide (sync wiring).
        final result = await ref.read(dexaSyncProvider.notifier).refresh();
        say(
          result.added > 0
              ? l10n.homeNewScans(result.added)
              : l10n.homeNoNewScans,
        );
      } else {
        ref
          ..invalidate(scansProvider)
          ..invalidate(currentMeasurementsProvider);
      }
      await ref.read(bodyScansProvider.future);
    } on AppException catch (e) {
      if (!mounted) return;
      final signIn =
          e.code == SyncErrorCodes.providerReauth ||
          e.code == SyncErrorCodes.notLinkedOnThisPhone;
      if (signIn) {
        say(
          l10n.homeSignInAgain,
          action: SnackBarAction(
            label: l10n.homeSignInAction,
            onPressed: () => context.push(Routes.onboarding),
          ),
        );
      } else {
        say(e is NetworkException ? l10n.errorNetwork : l10n.errorGeneric);
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Kept alive so Refresh knows at once whether this phone can sync.
    ref.watch(dexaSyncProvider);
    final scans = ref.watch(bodyScansProvider);
    final units = ref.watch(unitsProvider);
    final now = widget.clock();
    final summary = switch (scans.value) {
      final s? => HomeSummary.of(s, now: now),
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
              gameMode: ref.watch(gameModeProvider),
              refreshing:
                  _refreshing || ref.watch(syncRunProvider) is SyncRunning,
              onRefresh: () => unawaited(_refresh()),
            ),
            if (summary != null)
              _Headline(summary: summary, units: units, now: now),
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
    required this.gameMode,
    required this.refreshing,
    required this.onRefresh,
  });

  final HomeSummary? summary;

  /// Shows the level badge and the next-scan bar.
  final bool gameMode;
  final bool refreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.tokens;
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
          if (s != null && gameMode) ...[
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
                    style: AppTheme.wordmark.copyWith(
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
                if (s != null && gameMode) ...[
                  const SizedBox(height: AppSpacing.xs),
                  _NextScanBar(progress: s.nextScanProgress),
                ],
              ],
            ),
          ),
          if (s != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Flexible(child: _ScanChip(scan: s)),
          ],
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
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(color: tokens.lean),
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
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(AppRadius.pill),
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
  const new({required this.summary, required this.units, required this.now});

  final HomeSummary summary;
  final Units units;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final s = summary;
    final imperial = units == Units.imperial;
    final massUnit = imperial ? l10n.unitLb : l10n.unitKg;
    final since = _monthOf(context, s.first.scannedAt, now: now);

    Widget stat(
      String key,
      String label,
      HeadlineStat stat, {
      required int digits,
      required String unit,
      String? changeUnit,
      double scale = 1,
    }) => Expanded(
      child: _Stat(
        key: Key(key),
        label: label,
        stat: stat,
        digits: digits,
        scale: scale,
        unit: unit,
        changeUnit: changeUnit ?? unit,
        since: since,
      ),
    );

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
          spacing: AppSpacing.sm,
          children: [
            stat(
              'home_bodyFat',
              l10n.metricBodyFat,
              s.bodyFat,
              digits: 1,
              unit: l10n.unitPercent,
              changeUnit: l10n.unitPoints,
            ),
            stat(
              'home_lean',
              l10n.metricLeanMass,
              s.leanKg,
              digits: 1,
              scale: imperial ? Mass.lbPerKg : 1,
              unit: massUnit,
            ),
            stat(
              'home_visceral',
              l10n.metricVisceralShort,
              s.visceralG,
              digits: imperial ? 2 : 0,
              scale: imperial ? Mass.lbPerKg / 1000 : 1,
              unit: imperial ? l10n.unitLb : l10n.unitG,
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
    required this.scale,
    required this.unit,
    required this.changeUnit,
    required this.since,
    super.key,
  });

  final String label;
  final HeadlineStat stat;
  final int digits;
  final double scale;
  final String unit;
  final String changeUnit;

  /// The first scan's month, already formatted.
  final String since;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    final value = stat.value;
    final shown = stat.shownChange(digits: digits, scale: scale);
    final trend = stat.trend(digits: digits, scale: scale);

    final changeText = switch (shown) {
      null => stat.firstScan ? l10n.homeFirstScan : null,
      0 => l10n.homeNoChange(since),
      _ =>
        '${shown < 0 ? '▼' : '▲'} ${shown.abs().toStringAsFixed(digits)} '
            '$changeUnit ${l10n.homeSince(since)}',
    };
    final changeColor = switch (trend) {
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
          style: textTheme.labelSmall?.copyWith(color: tokens.textSecondary),
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

/// "May", or "May 2025" when it is not this year's May.
String _monthOf(BuildContext context, DateTime date, {required DateTime now}) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  return date.year == now.year
      ? DateFormat.MMM(locale).format(date)
      : DateFormat.yMMM(locale).format(date);
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
