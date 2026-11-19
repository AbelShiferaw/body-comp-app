import 'package:app_body/app_body.dart';
import 'package:app_ui/app_ui.dart';
import 'package:body_comp/l10n/l10n.dart';
import 'package:body_comp/router/router.dart';
import 'package:body_mapping/body_mapping.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Home: the 3D body from the user's scans, with the headline numbers of
/// the latest scan below it.
class HomePage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final latest = ref.watch(bodyScansProvider).value?.lastOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.homeTitle),
        actions: [
          IconButton(
            key: const Key('home_settings'),
            tooltip: l10n.settingsTitle,
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.push(Routes.settings),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(child: BodyView(emptyMessage: l10n.homeBodyPlaceholder)),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: _Metrics(scan: latest),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metrics extends StatelessWidget {
  const new({required this.scan});

  final BodyScan? scan;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final s = scan;
    String v(double? x, int digits) =>
        x == null ? '–' : x.toStringAsFixed(digits);
    return Row(
      children:
          [
              for (final tile in [
                MetricTile(
                  label: l10n.metricBodyFat,
                  value: v(s?.bodyFatPct, 1),
                  unit: '%',
                ),
                MetricTile(
                  label: l10n.metricLeanMass,
                  value: v(s?.totalLeanKg, 1),
                  unit: 'kg',
                ),
                MetricTile(
                  label: l10n.metricVisceralFat,
                  value: v(s?.visceralFatG, 0),
                  unit: 'g',
                ),
              ]) ...[Expanded(child: tile)],
            ].expand((w) => [w, const SizedBox(width: AppSpacing.sm)]).toList()
            ..removeLast(),
    );
  }
}
