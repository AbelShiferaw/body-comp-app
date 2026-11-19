import 'package:app_body/app_body.dart';
import 'package:app_core/app_core.dart';
import 'package:app_dexa_sync/app_dexa_sync.dart';
import 'package:app_scans/app_scans.dart';
import 'package:app_ui/app_ui.dart';
import 'package:body_comp/l10n/l10n.dart';
import 'package:body_comp/onboarding/onboarding_controller.dart';
import 'package:body_comp/profile/domain/profile.dart';
import 'package:body_comp/router/router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// Onboarding after profile setup: goals, DEXA or photos, health-data
/// consent, the first BodySpec import and the first look at the body.
class OnboardingPage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final controller = ref.read(onboardingProvider.notifier);

    Future<void> finish(BodySource source) async {
      if (await controller.finish(source) && context.mounted) {
        context.go(Routes.home);
      }
    }

    final canGoBack =
        !state.busy &&
        switch (state.step) {
          OnboardingStep.source => !state.returning,
          OnboardingStep.consent || OnboardingStep.photos => true,
          _ => false,
        };
    // A returning user can always leave back to home, except mid-import.
    final canClose = state.returning && state.step == OnboardingStep.source;

    return PopScope(
      canPop: canClose,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && canGoBack) controller.back();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: canGoBack
              ? IconButton(
                  key: const Key('onboarding_back'),
                  tooltip: context.l10n.onboardingBack,
                  icon: const Icon(Icons.arrow_back),
                  onPressed: controller.back,
                )
              : canClose
              ? IconButton(
                  key: const Key('onboarding_close'),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  icon: const Icon(Icons.close),
                  onPressed: () => context.go(Routes.home),
                )
              : null,
          title: state.returning ? null : _StepLabel(step: state.step),
        ),
        body: SafeArea(
          top: false,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: KeyedSubtree(
              key: ValueKey(state.step),
              child: switch (state.step) {
                OnboardingStep.goals => _GoalsStep(state: state),
                OnboardingStep.source => _SourceStep(state: state),
                OnboardingStep.consent => _ConsentStep(state: state),
                OnboardingStep.connecting => const _ConnectingStep(),
                OnboardingStep.reveal => _RevealStep(
                  state: state,
                  onFinish: () => finish(BodySource.dexa),
                ),
                OnboardingStep.photos => _PhotosStep(
                  state: state,
                  onFinish: () => finish(BodySource.photos),
                ),
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// "Step 1 of 3": goals, how to build the body, then connect or photos.
class _StepLabel extends StatelessWidget {
  const new({required this.step});

  final OnboardingStep step;

  @override
  Widget build(BuildContext context) {
    final current = switch (step) {
      OnboardingStep.goals => 1,
      OnboardingStep.source => 2,
      _ => 3,
    };
    return Text(
      context.l10n.onboardingStep(current, 3),
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: context.tokens.textSecondary),
    );
  }
}

/// A scrolling body with a title, and the primary action pinned below it.
class _StepScaffold extends StatelessWidget {
  const new({
    required this.title,
    required this.children,
    this.subtitle,
    this.action,
    this.error,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? action;
  final AppException? error;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            children: [
              Text(title, style: text.headlineMedium),
              if (subtitle case final s?) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(s, style: TextStyle(color: tokens.textSecondary)),
              ],
              const SizedBox(height: AppSpacing.lg),
              ...children,
            ],
          ),
        ),
        if (error != null || action != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (error case final e?) ...[
                  _ErrorText(e),
                  const SizedBox(height: AppSpacing.sm),
                ],
                ?action,
              ],
            ),
          ),
      ],
    );
  }
}

/// A selectable card: goals (multi) and body sources (single tap).
class _ChoiceCard extends StatelessWidget {
  const new({
    required this.title,
    required this.body,
    required this.icon,
    required this.onTap,
    this.selected = false,
    this.badge,
    this.enabled = true,
    super.key,
  });

  final String title;
  final String body;
  final IconData icon;
  final VoidCallback? onTap;
  final bool selected;
  final String? badge;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme;
    final fg = enabled ? tokens.textPrimary : tokens.textSecondary;
    return Semantics(
      selected: selected,
      button: true,
      enabled: enabled,
      child: Material(
        color: selected ? tokens.accentSoft : tokens.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(
            color: selected ? tokens.accent : tokens.border,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: selected ? tokens.accent : fg),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: text.titleMedium?.copyWith(color: fg),
                            ),
                          ),
                          if (badge case final b?) ...[
                            const SizedBox(width: AppSpacing.sm),
                            _Badge(label: b),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        body,
                        style: text.bodyMedium?.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Icon(Icons.check_circle, color: tokens.accent),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const new({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.accent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs / 2,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: tokens.onAccent),
        ),
      ),
    );
  }
}

class _GoalsStep extends ConsumerWidget {
  const new({required this.state});

  final OnboardingState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final controller = ref.read(onboardingProvider.notifier);
    final goals = [
      (
        Goal.loseFat,
        l10n.goalLoseFat,
        l10n.goalLoseFatHelp,
        Icons.local_fire_department_outlined,
      ),
      (
        Goal.buildMuscle,
        l10n.goalBuildMuscle,
        l10n.goalBuildMuscleHelp,
        Icons.fitness_center,
      ),
      (
        Goal.trackHealth,
        l10n.goalTrackHealth,
        l10n.goalTrackHealthHelp,
        Icons.favorite_outline,
      ),
    ];
    return _StepScaffold(
      title: l10n.goalsTitle,
      subtitle: l10n.goalsSubtitle,
      error: state.error,
      action: AppButton(
        key: const Key('goals_continue'),
        label: l10n.onboardingContinue,
        loading: state.busy,
        onPressed: state.goals.isEmpty ? null : controller.submitGoals,
      ),
      children: [
        for (final (goal, title, body, icon) in goals) ...[
          _ChoiceCard(
            key: Key('goal_${goal.key}'),
            title: title,
            body: body,
            icon: icon,
            selected: state.goals.contains(goal),
            onTap: () => controller.toggleGoal(goal),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _SourceStep extends ConsumerWidget {
  const new({required this.state});

  final OnboardingState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final tokens = context.tokens;
    final controller = ref.read(onboardingProvider.notifier);
    final link = ref.watch(dexaSyncProvider);
    final value = link.value;
    final dexaOpen = value != null && value.configured && value.allowed;
    final note = value == null || link.isLoading
        ? null
        : !value.configured
        ? l10n.sourceDexaUnavailable
        : !value.allowed
        ? l10n.sourceDexaInviteOnly
        : null;

    return _StepScaffold(
      title: l10n.sourceTitle,
      subtitle: l10n.sourceSubtitle,
      error: state.error,
      children: [
        _ChoiceCard(
          key: const Key('source_dexa'),
          title: l10n.sourceDexaTitle,
          body: l10n.sourceDexaBody,
          icon: Icons.accessibility_new,
          badge: l10n.sourceDexaRecommended,
          enabled: dexaOpen && !state.busy,
          onTap: controller.chooseDexa,
        ),
        if (link.isLoading)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.sm),
            child: LinearProgressIndicator(),
          ),
        if (link.hasError)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: TextButton(
              onPressed: () => ref.invalidate(dexaSyncProvider),
              child: Text(l10n.retry),
            ),
          ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              note,
              key: const Key('source_dexa_note'),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: tokens.textSecondary),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        _ChoiceCard(
          key: const Key('source_photos'),
          title: l10n.sourcePhotosTitle,
          body: l10n.sourcePhotosBody,
          icon: Icons.photo_camera_outlined,
          enabled: !state.busy,
          onTap: controller.choosePhotos,
        ),
      ],
    );
  }
}

class _ConsentStep extends ConsumerStatefulWidget {
  const new({required this.state});

  final OnboardingState state;

  @override
  ConsumerState<_ConsentStep> createState() => _ConsentStepState();
}

class _ConsentStepState extends ConsumerState<_ConsentStep> {
  bool _agreed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.tokens;
    final state = widget.state;
    final points = [
      (Icons.monitor_weight_outlined, l10n.consentPointStore),
      (Icons.badge_outlined, l10n.consentPointIdentity),
      (Icons.phone_iphone, l10n.consentPointToken),
      (Icons.delete_outline, l10n.consentPointDelete),
    ];
    return _StepScaffold(
      title: l10n.consentTitle,
      subtitle: l10n.consentIntro,
      error: state.error,
      action: AppButton(
        key: const Key('consent_continue'),
        label: l10n.consentContinue,
        loading: state.busy,
        onPressed: _agreed
            ? ref.read(onboardingProvider.notifier).agreeAndConnect
            : null,
      ),
      children: [
        for (final (icon, text) in points)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: tokens.accent),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Text(text)),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        CheckboxListTile(
          key: const Key('consent_agree'),
          value: _agreed,
          onChanged: state.busy
              ? null
              : (v) => setState(() => _agreed = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.consentAgree),
        ),
      ],
    );
  }
}

class _ConnectingStep extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final run = ref.watch(syncRunProvider);
    final signingIn = run is SyncRunning && run.connecting;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.lg),
            Text(
              signingIn ? l10n.connectSigningIn : l10n.connectImporting,
              key: const Key('connecting_label'),
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (!signingIn) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.connectImportingHelp,
                style: TextStyle(color: context.tokens.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RevealStep extends ConsumerWidget {
  const new({required this.state, required this.onFinish});

  final OnboardingState state;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final tokens = context.tokens;
    final scans = ref.watch(drawableScansProvider);
    final latest = scans.value?.firstOrNull;
    final count = scans.value?.length ?? 0;
    final review = state.result?.needsReview ?? 0;
    final locale = Localizations.localeOf(context).toLanguageTag();

    String fmt(num? x, int digits) => x == null
        ? '–'
        : NumberFormat.decimalPatternDigits(
            locale: locale,
            decimalDigits: digits,
          ).format(x);

    final Widget body;
    if (scans.isLoading && !scans.hasValue) {
      body = const LoadingView();
    } else if (scans.hasError) {
      body = ErrorView(
        message: l10n.errorGeneric,
        retryLabel: l10n.retry,
        onRetry: () => ref.invalidate(scansProvider),
      );
    } else if (latest == null) {
      body = Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          l10n.syncNoScans,
          key: const Key('reveal_no_scans'),
          textAlign: TextAlign.center,
        ),
      );
    } else {
      body = Column(
        children: [
          Expanded(child: BodyView(emptyMessage: l10n.homeBodyPlaceholder)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              spacing: AppSpacing.sm,
              children: [
                for (final (label, value, unit) in [
                  (l10n.metricBodyFat, latest.bodyFatPct, l10n.unitPercent),
                  (l10n.metricLeanMass, _kg(latest.leanG), l10n.unitKg),
                  (l10n.metricFatMass, _kg(latest.fatG), l10n.unitKg),
                ])
                  Expanded(
                    child: MetricTile(
                      label: label,
                      value: fmt(value, 1),
                      unit: unit,
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.revealTitle,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              if (latest != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.revealSubtitle(
                    count,
                    DateFormat.yMMMd(locale).format(latest.scannedAt.toLocal()),
                  ),
                  style: TextStyle(color: tokens.textSecondary),
                ),
              ],
              if (review > 0) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.revealNeedsReview(review),
                  key: const Key('reveal_needs_review'),
                  style: TextStyle(color: tokens.textSecondary),
                ),
              ],
            ],
          ),
        ),
        Expanded(child: body),
        if (state.error case final e?)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              0,
            ),
            child: _ErrorText(e),
          ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: AppButton(
            key: const Key('reveal_finish'),
            label: l10n.revealFinish,
            loading: state.busy,
            onPressed: onFinish,
          ),
        ),
      ],
    );
  }

  static double? _kg(int? grams) => grams == null ? null : grams / 1000;
}

class _PhotosStep extends StatelessWidget {
  const new({required this.state, required this.onFinish});

  final OnboardingState state;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.tokens;
    return _StepScaffold(
      title: l10n.photosTitle,
      error: state.error,
      action: AppButton(
        key: const Key('photos_finish'),
        label: l10n.photosFinish,
        loading: state.busy,
        onPressed: onFinish,
      ),
      children: [
        Icon(Icons.photo_camera_outlined, size: 56, color: tokens.accent),
        const SizedBox(height: AppSpacing.md),
        Text(l10n.photosBody),
        const SizedBox(height: AppSpacing.md),
        Text(l10n.photosHint, style: TextStyle(color: tokens.textSecondary)),
      ],
    );
  }
}

/// One plain message per failure (LLD "Errors"); never `error.toString()`.
/// A failure in the danger color, keyed for tests.
class _ErrorText extends StatelessWidget {
  const new(this.error);

  final AppException error;

  @override
  Widget build(BuildContext context) => Text(
    errorText(context.l10n, error),
    key: const Key('onboarding_error'),
    style: TextStyle(color: context.tokens.danger),
  );
}

String errorText(AppLocalizations l10n, AppException error) =>
    switch (error.code) {
      SyncErrorCodes.notInBeta => l10n.syncErrorNotInBeta,
      SyncErrorCodes.providerReauth ||
      SyncErrorCodes.notLinkedOnThisPhone => l10n.syncErrorSignIn,
      SyncErrorCodes.providerForbidden => l10n.syncErrorForbidden,
      SyncErrorCodes.providerBusy => l10n.syncErrorBusy,
      SyncErrorCodes.consentRequired => l10n.syncErrorConsent,
      _ => error is NetworkException ? l10n.errorNetwork : l10n.errorGeneric,
    };
