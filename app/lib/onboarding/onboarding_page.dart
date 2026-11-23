import 'package:app_body/app_body.dart';
import 'package:app_core/app_core.dart';
import 'package:app_dexa_sync/app_dexa_sync.dart';
import 'package:app_scans/app_scans.dart';
import 'package:app_ui/app_ui.dart';
import 'package:body_comp/l10n/l10n.dart';
import 'package:body_comp/onboarding/onboarding_controller.dart';
import 'package:body_comp/profile/domain/profile.dart';
import 'package:body_comp/profile/domain/profile_rules.dart';
import 'package:body_comp/profile/presentation/profile_providers.dart';
import 'package:body_comp/router/router.dart';
import 'package:body_mapping/body_mapping.dart' as body;
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
          centerTitle: true,
          toolbarHeight: 52,
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
          title: Text(
            context.l10n.appTitle.toUpperCase(),
            style: AppTheme.wordmark,
          ),
          bottom: state.returning
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(20),
                  child: _StepProgress(step: state.step),
                ),
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

/// Three segments under the wordmark, with "Step 1 of 3" for screen readers
/// and as a small caption: goals, how to build the body, then the last step.
class _StepProgress extends StatelessWidget {
  const new({required this.step});

  final OnboardingStep step;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final current = switch (step) {
      OnboardingStep.goals => 1,
      OnboardingStep.source => 2,
      _ => 3,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        0,
        AppSpacing.gutter,
        AppSpacing.sm,
      ),
      child: Row(
        spacing: AppSpacing.sm,
        children: [
          for (var i = 1; i <= 3; i++)
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 4,
                decoration: BoxDecoration(
                  color: i <= current ? tokens.accent : tokens.surfaceRaised,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
          Text(
            context.l10n.onboardingStep(current, 3),
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: tokens.textFaint),
          ),
        ],
      ),
    );
  }
}

/// A scrolling body with an optional [hero] above a headline, and the
/// primary action (plus an optional [footnote]) pinned below it.
class _StepScaffold extends StatelessWidget {
  const new({
    required this.title,
    required this.children,
    this.subtitle,
    this.hero,
    this.action,
    this.footnote,
    this.error,
  });

  final String title;
  final String? subtitle;
  final Widget? hero;
  final List<Widget> children;
  final Widget? action;
  final String? footnote;
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
              AppSpacing.gutter,
              AppSpacing.sm,
              AppSpacing.gutter,
              AppSpacing.lg,
            ),
            children: [
              ?hero,
              Text(title, style: text.headlineLarge),
              if (subtitle case final s?) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  s,
                  style: text.bodyLarge?.copyWith(color: tokens.textSecondary),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              ...children,
            ],
          ),
        ),
        if (error != null || action != null)
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
                if (error case final e?) ...[
                  _ErrorText(e),
                  const SizedBox(height: AppSpacing.sm),
                ],
                ?action,
                if (footnote case final f?) ...[
                  const SizedBox(height: AppSpacing.smd),
                  Text(
                    f,
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(color: tokens.textFaint),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// A square tile holding an icon, as on the design's choice cards.
class _IconTile extends StatelessWidget {
  const new({required this.icon, this.color, this.size = 44});

  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(icon, size: size / 2, color: color ?? tokens.textSecondary),
    );
  }
}

/// A selectable card: an icon tile, a title with an optional badge, and a
/// line of help. Selected cards get an Ice border.
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
    final fg = enabled ? tokens.textPrimary : tokens.textFaint;
    return Semantics(
      selected: selected,
      button: true,
      enabled: enabled,
      child: Material(
        color: tokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(
            color: selected ? tokens.accent : tokens.border,
            width: 2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.smd + 2,
            ),
            child: Row(
              spacing: AppSpacing.smd + 2,
              children: [
                _IconTile(
                  icon: icon,
                  color: selected
                      ? tokens.accent
                      : enabled
                      ? tokens.textSecondary
                      : tokens.textFaint,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Row(
                        spacing: AppSpacing.sm,
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: text.titleMedium?.copyWith(color: fg),
                            ),
                          ),
                          if (badge case final b?) _Badge(label: b),
                        ],
                      ),
                      Text(
                        body,
                        style: text.bodySmall?.copyWith(
                          fontSize: 13,
                          height: 1.35,
                          color: enabled
                              ? tokens.textSecondary
                              : tokens.textFaint,
                        ),
                      ),
                    ],
                  ),
                ),
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
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 2,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: tokens.onAccent, letterSpacing: 0),
        ),
      ),
    );
  }
}

/// The body hero of the design, above a step's headline.
class _BodyHero extends StatelessWidget {
  const new();

  /// A fifth of the screen, so both choice cards and Continue fit on one
  /// phone screen (iPhone 17 Pro included) without scrolling.
  @override
  Widget build(BuildContext context) => SizedBox(
    height: (MediaQuery.sizeOf(context).height * 0.2).clamp(120, 260),
    child: const _PreviewBody(),
  );
}

/// The base body in the sex the user picked in their profile.
class _PreviewBody extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sex = ref.watch(profileProvider).value?.sex;
    return switch (sex) {
      Sex.male => const BodyPreview(sex: body.Sex.male),
      Sex.female => const BodyPreview(sex: body.Sex.female),
      null => const SizedBox.expand(),
    };
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
          const SizedBox(height: AppSpacing.smd),
        ],
      ],
    );
  }
}

/// The design's start screen: the body, the headline, DEXA or photos, and
/// one Continue whose label follows the choice.
class _SourceStep extends ConsumerStatefulWidget {
  const new({required this.state});

  final OnboardingState state;

  @override
  ConsumerState<_SourceStep> createState() => _SourceStepState();
}

class _SourceStepState extends ConsumerState<_SourceStep> {
  /// Null until the user taps a card: DEXA when it is open, else photos.
  BodySource? _picked;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.tokens;
    final state = widget.state;
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
    final picked = _picked ?? (dexaOpen ? BodySource.dexa : BodySource.photos);
    final dexa = picked == BodySource.dexa && dexaOpen;

    return _StepScaffold(
      hero: const _BodyHero(),
      title: l10n.sourceHeadline,
      subtitle: l10n.sourceLead,
      error: state.error,
      footnote: l10n.sourcePrivacy,
      action: AppButton(
        key: const Key('source_continue'),
        label: dexa ? l10n.sourceContinueDexa : l10n.sourceContinuePhotos,
        loading: state.busy,
        onPressed: link.isLoading
            ? null
            : dexa
            ? controller.chooseDexa
            : controller.choosePhotos,
      ),
      children: [
        _ChoiceCard(
          key: const Key('source_dexa'),
          title: l10n.sourceDexaTitle,
          body: l10n.sourceDexaBody,
          icon: Icons.document_scanner_outlined,
          badge: l10n.sourceDexaRecommended,
          enabled: dexaOpen && !state.busy,
          selected: dexa,
          onTap: () => setState(() => _picked = BodySource.dexa),
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
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs,
              AppSpacing.sm,
              AppSpacing.xs,
              0,
            ),
            child: Text(
              note,
              key: const Key('source_dexa_note'),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: tokens.textSecondary),
            ),
          ),
        const SizedBox(height: AppSpacing.smd),
        _ChoiceCard(
          key: const Key('source_photos'),
          title: l10n.sourcePhotosTitle,
          body: l10n.sourcePhotosBody,
          icon: Icons.photo_camera_outlined,
          enabled: !state.busy,
          selected: !dexa,
          onTap: () => setState(() => _picked = BodySource.photos),
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
    final text = Theme.of(context).textTheme;
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
        for (final (icon, line) in points)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              spacing: AppSpacing.smd + 2,
              children: [
                _IconTile(icon: icon, color: tokens.accent, size: 40),
                Expanded(child: Text(line, style: text.bodyMedium)),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        Material(
          color: tokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: BorderSide(
              color: _agreed ? tokens.accent : tokens.border,
              width: _agreed ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: CheckboxListTile(
            key: const Key('consent_agree'),
            value: _agreed,
            onChanged: state.busy
                ? null
                : (v) => setState(() => _agreed = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            title: Text(l10n.consentAgree, style: text.bodyMedium),
          ),
        ),
      ],
    );
  }
}

/// Sign-in, then the import: the body turns while the scans come in.
class _ConnectingStep extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme;
    final run = ref.watch(syncRunProvider);
    final signingIn = run is SyncRunning && run.connecting;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Expanded(child: _PreviewBody()),
          Text(
            signingIn ? l10n.connectSigningIn : l10n.connectImporting,
            key: const Key('connecting_label'),
            style: text.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            signingIn ? l10n.connectSigningInHelp : l10n.connectImportingHelp,
            style: text.bodyLarge?.copyWith(color: tokens.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          const ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.pill)),
            child: LinearProgressIndicator(minHeight: 4),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
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
    final imperial = ref.watch(unitsProvider) == Units.imperial;
    final massUnit = imperial ? l10n.unitLb : l10n.unitKg;
    double? mass(int? grams) =>
        grams == null ? null : grams / 1000 * (imperial ? Mass.lbPerKg : 1);

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
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
            child: Row(
              spacing: AppSpacing.sm,
              children: [
                for (final (label, value, unit, color) in [
                  (
                    l10n.metricBodyFat,
                    latest.bodyFatPct,
                    l10n.unitPercent,
                    null,
                  ),
                  (
                    l10n.metricLeanMass,
                    mass(latest.leanG),
                    massUnit,
                    tokens.lean,
                  ),
                  (l10n.metricFatMass, mass(latest.fatG), massUnit, tokens.fat),
                ])
                  Expanded(
                    child: MetricTile(
                      label: label,
                      value: fmt(value, 1),
                      unit: unit,
                      valueColor: color,
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
            AppSpacing.gutter,
            AppSpacing.sm,
            AppSpacing.gutter,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.revealTitle,
                style: Theme.of(context).textTheme.headlineLarge,
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
              AppSpacing.gutter,
              AppSpacing.md,
              AppSpacing.gutter,
              0,
            ),
            child: _ErrorText(e),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.md,
            AppSpacing.gutter,
            AppSpacing.md,
          ),
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
        Align(
          alignment: Alignment.centerLeft,
          child: _IconTile(
            icon: Icons.photo_camera_outlined,
            color: tokens.accent,
            size: 64,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(l10n.photosBody, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.photosHint,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: tokens.textSecondary),
        ),
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
