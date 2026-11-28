import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:body_comp/l10n/l10n.dart';
import 'package:body_comp/router/router.dart';
import 'package:body_comp/shape/shape_prompt.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// "Make it look like you": on home until the user adds photos or tape
/// measurements, or closes it. Opens the photo flow.
class ShapeCard extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(shapePromptProvider)) return const SizedBox.shrink();
    final l10n = context.l10n;
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      child: Material(
        key: const Key('shape_card'),
        color: tokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: tokens.border),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(Icons.photo_camera_outlined, color: tokens.lean),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.shapeCardTitle,
                      style: textTheme.titleSmall?.copyWith(
                        color: tokens.textPrimary,
                      ),
                    ),
                    Text(
                      l10n.shapeCardBody,
                      style: textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TextButton(
                    key: const Key('shape_card_start'),
                    onPressed: () => context.push(Routes.shapePhotos),
                    child: Text(l10n.shapeCardAction),
                  ),
                  TextButton(
                    key: const Key('shape_card_dismiss'),
                    style: TextButton.styleFrom(
                      foregroundColor: tokens.textSecondary,
                    ),
                    onPressed: () => unawaited(
                      ref.read(shapePromptProvider.notifier).dismiss(),
                    ),
                    child: Text(l10n.shapeCardDismiss),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
