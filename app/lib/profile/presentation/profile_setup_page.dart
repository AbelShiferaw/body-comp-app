import 'package:app_ui/app_ui.dart';
import 'package:body_comp/l10n/l10n.dart';
import 'package:body_comp/profile/domain/profile.dart';
import 'package:body_comp/profile/presentation/profile_form.dart';
import 'package:body_comp/profile/presentation/profile_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Shown after sign-up until the profile is complete. The router moves on to
/// home as soon as the saved profile is complete, so this page never navigates.
class ProfileSetupPage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme;
    final profile = ref.watch(profileProvider);
    return Scaffold(
      body: SafeArea(
        child: switch (profile) {
          AsyncError() => ErrorView(
            message: l10n.errorGeneric,
            retryLabel: l10n.retry,
            onRetry: () => ref.invalidate(profileProvider),
          ),
          AsyncValue(:final value) when profile.hasValue => ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.gutter,
              AppSpacing.gutter,
              AppSpacing.xl,
            ),
            children: [
              Center(
                child: Text(
                  l10n.appTitle.toUpperCase(),
                  style: AppTheme.wordmark.copyWith(color: tokens.textPrimary),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(l10n.profileSetupTitle, style: text.headlineLarge),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.profileSetupSubtitle,
                style: text.bodyLarge?.copyWith(color: tokens.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xl),
              ProfileForm(
                initial: value ?? const Profile(),
                submitLabel: l10n.profileSetupSubmit,
              ),
            ],
          ),
          _ => const LoadingView(),
        },
      ),
    );
  }
}
