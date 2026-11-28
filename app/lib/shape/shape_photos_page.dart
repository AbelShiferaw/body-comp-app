import 'dart:typed_data';

import 'package:app_body_photos/app_body_photos.dart';
import 'package:app_core/app_core.dart';
import 'package:app_scans/app_scans.dart';
import 'package:app_ui/app_ui.dart';
import 'package:body_comp/l10n/l10n.dart';
import 'package:body_comp/profile/domain/profile.dart' as pf;
import 'package:body_comp/profile/presentation/profile_providers.dart';
import 'package:body_comp/shape/measure_text.dart';
import 'package:body_mapping/body_mapping.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// A photo session within this many days of a DEXA scan is paired with it,
/// for calibrating photo estimates against DEXA later.
const pairWindow = Duration(days: 14);

enum _Step { intro, front, side, measuring, result }

/// Guided front and side photos, measured on the phone, then saved as a
/// photo session. Only the measurements are saved; the photos stay in
/// memory until this page closes.
class ShapePhotosPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<ShapePhotosPage> createState() => _ShapePhotosPageState();
}

class _ShapePhotosPageState extends ConsumerState<ShapePhotosPage> {
  final _log = AppLogger('shape');
  _Step _step = .intro;
  Uint8List? _front;
  Uint8List? _side;
  late PhotoMeasurement _result;
  String? _problem;
  bool _saving = false;

  Future<void> _pick(BodyPhoto which, PhotoOrigin origin) async {
    try {
      final photo = await ref.read(photoSourceProvider).pick(origin);
      if (photo == null || !mounted) return;
      setState(() {
        _problem = null;
        if (which == .front) {
          _front = photo;
        } else {
          _side = photo;
        }
      });
    } on AppException catch (e) {
      setState(() => _problem = _problemText(e));
    }
  }

  Future<void> _measure() async {
    final profile = ref.read(profileProvider).value;
    final heightCm = profile?.heightCm;
    final sex = profile?.sex;
    if (heightCm == null || sex == null) return;
    setState(() => _step = .measuring);
    try {
      final result = await ref
          .read(photoMeasurerProvider)
          .measure(
            front: _front!,
            side: _side!,
            heightCm: heightCm,
            sex: sex == pf.Sex.male ? Sex.male : Sex.female,
          );
      if (!mounted) return;
      setState(() {
        _result = result;
        _step = .result;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      final bad = PhotoErrorCodes.parse(e.code)?.$1;
      setState(() {
        _problem = _problemText(e);
        // Back to the photo that needs retaking.
        _step = bad == BodyPhoto.front ? .front : .side;
      });
    }
  }

  Future<void> _save() async {
    final result = _result;
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final scans = await ref.read(drawableScansProvider.future);
      final paired = scans
          .where(
            (s) =>
                s.scannedAt.difference(result.capturedAt).abs() <= pairWindow,
          )
          .firstOrNull;
      await ref
          .read(measurementsRepositoryProvider)
          .savePhotoSession(
            capturedAt: result.capturedAt,
            measurementsCm: {
              for (final MapEntry(:key, :value)
                  in result.measurements.cm.entries)
                MeasurementKind.fromKey(key.key): (value * 10).round() / 10,
            },
            sdk: PhotoMeasurement.sdk,
            sdkVersion: result.version,
            pairedScanId: paired?.id,
          );
      _log.info('Saved photo measurements, paired: ${paired != null}');
      ref.invalidate(currentMeasurementsProvider);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.shapeSaved)));
      context.pop();
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is NetworkException ? l10n.errorNetwork : l10n.errorGeneric,
          ),
        ),
      );
    }
  }

  String _problemText(AppException e) {
    final l10n = context.l10n;
    if (e.code == 'photo_access_denied') return l10n.photosProblemAccess;
    if (e.code == 'photo_unreadable') return l10n.photosProblemUnreadable;
    return switch (PhotoErrorCodes.parse(e.code)) {
      (final photo, SilhouetteProblem.noPerson) => l10n.photosProblemNoPerson(
        photo == .front ? l10n.photosFront : l10n.photosSide,
      ),
      (_, SilhouetteProblem.legsTogether) => l10n.photosProblemLegs,
      (_, SilhouetteProblem.armsDown) => l10n.photosProblemArms,
      (_, SilhouetteProblem.mismatch) => l10n.photosProblemMismatch,
      null => e is NetworkException ? l10n.errorNetwork : l10n.errorGeneric,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (_step) {
          .intro => l10n.photosShapeTitle,
          .front => l10n.photosFrontTitle,
          .side => l10n.photosSideTitle,
          .measuring || .result => l10n.photosResultTitle,
        }),
      ),
      body: SafeArea(
        child: switch (_step) {
          .intro => _Intro(onStart: () => setState(() => _step = .front)),
          .front => _PhotoStep(
            step: 1,
            pose: l10n.photosFrontPose,
            icon: Icons.accessibility_new,
            photo: _front,
            problem: _problem,
            onPick: (o) => _pick(.front, o),
            onClear: () => setState(() => _front = null),
            actionLabel: l10n.photosNext,
            onAction: () => setState(() {
              _problem = null;
              _step = .side;
            }),
          ),
          .side => _PhotoStep(
            step: 2,
            pose: l10n.photosSidePose,
            icon: Icons.person_outline,
            photo: _side,
            problem: _problem,
            onPick: (o) => _pick(.side, o),
            onClear: () => setState(() => _side = null),
            actionLabel: l10n.photosMeasure,
            onAction: _measure,
          ),
          .measuring => _Measuring(text: l10n.photosMeasuring),
          .result => _Result(
            result: _result,
            units: ref.watch(unitsProvider),
            saving: _saving,
            onSave: _save,
            onRetake: () => setState(() => _step = .front),
          ),
        },
      ),
    );
  }
}

/// Bottom-anchored layout shared by the steps: content, then actions.
class _StepLayout extends StatelessWidget {
  const new({required this.content, required this.actions});

  final List<Widget> content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          children: content,
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          0,
          AppSpacing.gutter,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, a) in actions.indexed) ...[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              a,
            ],
          ],
        ),
      ),
    ],
  );
}

class _Intro extends StatelessWidget {
  const new({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    Widget tip(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tokens.lean, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: textTheme.bodyMedium?.copyWith(color: tokens.textPrimary),
            ),
          ),
        ],
      ),
    );
    return _StepLayout(
      content: [
        Container(
          key: const Key('photos_privacy'),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: tokens.border),
          ),
          child: Row(
            children: [
              Icon(Icons.lock_outline, color: tokens.lean),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l10n.photosShapePrivacy,
                  style: textTheme.bodyMedium?.copyWith(
                    color: tokens.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          l10n.photosShapeTipsTitle.toUpperCase(),
          style: textTheme.labelSmall?.copyWith(color: tokens.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        tip(Icons.timer_outlined, l10n.photosShapeTipSpace),
        tip(Icons.checkroom_outlined, l10n.photosShapeTipClothes),
        tip(Icons.crop_portrait, l10n.photosShapeTipFrame),
      ],
      actions: [
        AppButton(
          key: const Key('photos_start'),
          label: l10n.photosShapeStart,
          onPressed: onStart,
        ),
      ],
    );
  }
}

class _PhotoStep extends StatelessWidget {
  const new({
    required this.step,
    required this.pose,
    required this.icon,
    required this.photo,
    required this.problem,
    required this.onPick,
    required this.onClear,
    required this.actionLabel,
    required this.onAction,
  });

  final int step;
  final String pose;
  final IconData icon;
  final Uint8List? photo;
  final String? problem;
  final ValueChanged<PhotoOrigin> onPick;

  /// Drops the photo, to take or choose another.
  final VoidCallback onClear;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    final p = photo;
    return _StepLayout(
      content: [
        Text(
          l10n.photosStep(step).toUpperCase(),
          style: textTheme.labelSmall?.copyWith(color: tokens.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          pose,
          style: textTheme.bodyLarge?.copyWith(color: tokens.textPrimary),
        ),
        const SizedBox(height: AppSpacing.md),
        AspectRatio(
          aspectRatio: 3 / 4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: tokens.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: p == null
                  ? Icon(icon, size: 120, color: tokens.textSecondary)
                  : Image.memory(
                      p,
                      key: Key('photo_$step'),
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      // Some formats (HEIC on Android) do not preview; the
                      // segmenter still reads them.
                      errorBuilder: (_, _, _) => Icon(
                        Icons.check_circle_outline,
                        size: 96,
                        color: tokens.lean,
                      ),
                    ),
            ),
          ),
        ),
        if (problem case final text?) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            text,
            key: const Key('photos_problem'),
            style: textTheme.bodyMedium?.copyWith(color: tokens.danger),
          ),
        ],
      ],
      actions: [
        if (p == null) ...[
          AppButton(
            key: const Key('photos_take'),
            label: l10n.photosTake,
            onPressed: () => onPick(PhotoOrigin.camera),
          ),
          AppButton(
            key: const Key('photos_choose'),
            label: l10n.photosChoose,
            secondary: true,
            onPressed: () => onPick(PhotoOrigin.library),
          ),
        ] else ...[
          AppButton(
            key: const Key('photos_next'),
            label: actionLabel,
            onPressed: problem == null ? onAction : null,
          ),
          AppButton(
            key: const Key('photos_retake'),
            label: l10n.photosRetake,
            secondary: true,
            onPressed: onClear,
          ),
        ],
      ],
    );
  }
}

class _Measuring extends StatelessWidget {
  const new({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: AppSpacing.md),
        Text(text, style: Theme.of(context).textTheme.bodyLarge),
      ],
    ),
  );
}

class _Result extends StatelessWidget {
  const new({
    required this.result,
    required this.units,
    required this.saving,
    required this.onSave,
    required this.onRetake,
  });

  final PhotoMeasurement result;
  final pf.Units units;
  final bool saving;
  final VoidCallback onSave;
  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    final rows = [
      for (final kind in shapeMeasurements)
        if (result.measurements[Measure.fromKey(kind.key)!] case final cm?)
          (kind, cm),
    ];
    return _StepLayout(
      content: [
        Text(
          l10n.photosResultBody,
          style: textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: tokens.border),
          ),
          child: Column(
            children: [
              for (final (i, (kind, cm)) in rows.indexed) ...[
                if (i > 0) Divider(height: 1, color: tokens.border),
                ListTile(
                  key: Key('result_${kind.key}'),
                  title: Text(l10n.measureName(kind)),
                  trailing: Text(
                    '${formatLength(cm, units)} ${l10n.lengthUnit(units)}',
                    style: textTheme.titleMedium?.copyWith(
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
      actions: [
        AppButton(
          key: const Key('photos_save'),
          label: l10n.photosSave,
          loading: saving,
          onPressed: saving ? null : onSave,
        ),
        AppButton(
          key: const Key('photos_again'),
          label: l10n.photosRetake,
          secondary: true,
          onPressed: saving ? null : onRetake,
        ),
      ],
    );
  }
}
