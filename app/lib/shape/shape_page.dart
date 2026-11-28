import 'package:app_core/app_core.dart';
import 'package:app_scans/app_scans.dart';
import 'package:app_ui/app_ui.dart';
import 'package:body_comp/l10n/l10n.dart';
import 'package:body_comp/profile/domain/profile.dart';
import 'package:body_comp/profile/presentation/profile_providers.dart';
import 'package:body_comp/router/router.dart';
import 'package:body_comp/shape/measure_text.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// "Your shape": the measurements the 3D body's proportions are fitted to,
/// where each came from, a way to measure from photos, and tape edits.
class ShapePage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    final current = ref.watch(currentMeasurementsProvider);
    final units = ref.watch(unitsProvider);
    final fromPhotos =
        current.value?.values.any((m) => m.source == .photo) ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.shapeTitle)),
      body: switch (current) {
        AsyncError() => ErrorView(
          message: l10n.errorGeneric,
          retryLabel: l10n.retry,
          onRetry: () => ref.invalidate(currentMeasurementsProvider),
        ),
        AsyncValue(:final value?) => ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.sm,
            AppSpacing.gutter,
            AppSpacing.xl,
          ),
          children: [
            Text(
              l10n.shapeIntro,
              style: textTheme.bodyMedium?.copyWith(
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              key: const Key('shape_photos'),
              label: fromPhotos ? l10n.shapeRetakePhotos : l10n.shapeTakePhotos,
              onPressed: () => context.push(Routes.shapePhotos),
            ),
            const SizedBox(height: AppSpacing.lg),
            Material(
              color: tokens.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                side: BorderSide(color: tokens.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final (i, kind) in shapeMeasurements.indexed) ...[
                    if (i > 0) Divider(height: 1, color: tokens.border),
                    _MeasurementRow(
                      kind: kind,
                      value: value[kind],
                      units: units,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.shapeEditHint,
              style: textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
            ),
          ],
        ),
        _ => const LoadingView(),
      },
    );
  }
}

class _MeasurementRow extends ConsumerWidget {
  const new({required this.kind, required this.value, required this.units});

  final MeasurementKind kind;
  final BodyMeasurement? value;
  final Units units;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    final v = value;
    return ListTile(
      key: Key('shape_${kind.key}'),
      title: Text(l10n.measureName(kind)),
      subtitle: Text(switch (v?.source) {
        null => l10n.shapeSourceAverage,
        MeasurementSource.photo => l10n.shapeSourcePhoto(v!.measuredAt),
        MeasurementSource.tape => l10n.shapeSourceTape(v!.measuredAt),
      }, style: textTheme.bodySmall?.copyWith(color: tokens.textSecondary)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            v == null
                ? '–'
                : '${formatLength(v.valueCm, units)} ${l10n.lengthUnit(units)}',
            style: textTheme.titleMedium?.copyWith(color: tokens.textPrimary),
          ),
          const SizedBox(width: AppSpacing.xs),
          Icon(Icons.edit_outlined, size: 18, color: tokens.textSecondary),
        ],
      ),
      onTap: () => _edit(context, ref),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final cm = await showDialog<double>(
      context: context,
      builder: (_) =>
          TapeDialog(kind: kind, units: units, initialCm: value?.valueCm),
    );
    if (cm == null) return;
    try {
      await ref
          .read(measurementsRepositoryProvider)
          .saveTapeMeasurement(kind, cm);
      ref.invalidate(currentMeasurementsProvider);
      messenger.showSnackBar(SnackBar(content: Text(l10n.shapeSaved)));
    } on AppException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is NetworkException ? l10n.errorNetwork : l10n.errorGeneric,
          ),
        ),
      );
    }
  }
}

/// Types in one tape measurement. Pops the value in cm, or null.
class TapeDialog extends StatefulWidget {
  const new({
    required this.kind,
    required this.units,
    this.initialCm,
    super.key,
  });

  final MeasurementKind kind;
  final Units units;
  final double? initialCm;

  @override
  State<TapeDialog> createState() => _TapeDialogState();
}

class _TapeDialogState extends State<TapeDialog> {
  late final _text = TextEditingController(
    text: switch (widget.initialCm) {
      final cm? => formatLength(cm, widget.units),
      null => '',
    },
  );
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final cm = parseLength(_text.text, widget.units, widget.kind);
    if (cm == null) {
      final (lo, hi) = plausibleCm(widget.kind);
      setState(
        () => _error = context.l10n.shapeEditInvalid(
          formatLength(lo, widget.units),
          formatLength(hi, widget.units),
        ),
      );
      return;
    }
    Navigator.of(context).pop(cm);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = l10n.measureName(widget.kind);
    return AlertDialog(
      title: Text(l10n.shapeEditTitle(name)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.measureHow(widget.kind)),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('tape_value'),
            controller: _text,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[0-9.,]')),
            ],
            decoration: InputDecoration(
              labelText: name,
              suffixText: l10n.lengthUnit(widget.units),
              errorText: _error,
            ),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: const Key('tape_save'),
          onPressed: _save,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
