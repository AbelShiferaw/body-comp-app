import 'package:app_ui/app_ui.dart';
import 'package:body_comp/l10n/l10n.dart';
import 'package:body_comp/router/router.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Placeholder home. The 3D body and real metrics replace the placeholder
/// once the body feature lands.
class HomePage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.tokens;
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
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.surfaceRaised,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    l10n.homeBodyPlaceholder,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: tokens.textSecondary),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            childAspectRatio: 1.6,
            children: [
              MetricTile(label: l10n.metricBodyFat, value: '–', unit: '%'),
              MetricTile(label: l10n.metricLeanMass, value: '–', unit: 'kg'),
              MetricTile(label: l10n.metricFatMass, value: '–', unit: 'kg'),
              MetricTile(label: l10n.metricVisceralFat, value: '–', unit: 'g'),
            ],
          ),
        ],
      ),
    );
  }
}
