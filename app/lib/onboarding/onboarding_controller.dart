import 'package:app_core/app_core.dart';
import 'package:app_dexa_sync/app_dexa_sync.dart';
import 'package:app_scans/app_scans.dart';
import 'package:body_comp/profile/domain/profile.dart';
import 'package:body_comp/profile/presentation/profile_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The health-data consent text version the user agrees to in onboarding.
/// Bump it when the consent copy changes, so we know who agreed to what.
const healthDataConsentVersion = 'health-data-2026-11';

enum OnboardingStep {
  /// The goals quiz. Sex, birth year and height come before it, in profile
  /// setup.
  goals,

  /// DEXA or photos.
  source,

  /// Health-data consent, before the first DEXA import.
  consent,

  /// BodySpec sign-in and the first import.
  connecting,

  /// The first look at the body built from the imported scans.
  reveal,

  /// "Photo estimates are coming soon."
  photos,
}

@immutable
class OnboardingState {
  const new({
    required this.step,
    this.returning = false,
    this.goals = const {},
    this.busy = false,
    this.error,
    this.result,
  });

  final OnboardingStep step;

  /// An onboarded user who came back from home to connect DEXA: no quiz,
  /// and finishing goes straight home.
  final bool returning;
  final Set<Goal> goals;

  /// Saving, granting consent or finishing.
  final bool busy;

  /// The last failure, shown on the current step.
  final AppException? error;

  /// The first import, for the reveal.
  final SyncResult? result;

  OnboardingState copyWith({
    OnboardingStep? step,
    Set<Goal>? goals,
    bool? busy,
    AppException? Function()? error,
    SyncResult? result,
  }) => OnboardingState(
    step: step ?? this.step,
    returning: returning,
    goals: goals ?? this.goals,
    busy: busy ?? this.busy,
    error: error == null ? this.error : error(),
    result: result ?? this.result,
  );
}

/// Drives onboarding: goals, DEXA or photos, consent, the first import and
/// the reveal. Users who finished onboarding and come back (to connect DEXA
/// from home) start at [OnboardingStep.source].
class OnboardingController extends Notifier<OnboardingState> {
  final _log = AppLogger('onboarding');

  @override
  OnboardingState build() {
    final profile = ref.read(profileProvider).value ?? const Profile();
    return OnboardingState(
      step: profile.isOnboarded ? OnboardingStep.source : OnboardingStep.goals,
      returning: profile.isOnboarded,
      goals: profile.goals,
    );
  }

  Profile get _profile => ref.read(profileProvider).value ?? const Profile();

  void toggleGoal(Goal goal) {
    final goals = {...state.goals};
    if (!goals.remove(goal)) goals.add(goal);
    state = state.copyWith(goals: goals, error: () => null);
  }

  void back() {
    final previous = switch (state.step) {
      OnboardingStep.source when !state.returning => OnboardingStep.goals,
      OnboardingStep.consent || OnboardingStep.photos => OnboardingStep.source,
      final step => step,
    };
    state = state.copyWith(step: previous, error: () => null);
  }

  /// Saves the goals and moves on.
  Future<bool> submitGoals() => _busy(() async {
    await ref
        .read(profileProvider.notifier)
        .save(_profile.copyWith(goals: state.goals));
    state = state.copyWith(step: OnboardingStep.source);
  });

  /// DEXA: ask for consent first unless the user already gave it.
  Future<bool> chooseDexa() => _busy(() async {
    final consents = await ref
        .read(consentsRepositoryProvider)
        .activeConsents();
    if (consents.containsKey(ConsentKind.healthData)) {
      await _connect();
    } else {
      state = state.copyWith(step: OnboardingStep.consent);
    }
  });

  /// Records the health-data consent, then signs in to BodySpec.
  Future<bool> agreeAndConnect() => _busy(() async {
    await ref
        .read(consentsRepositoryProvider)
        .grant(
          ConsentKind.healthData,
          documentVersion: healthDataConsentVersion,
        );
    _log.info('Health-data consent granted ($healthDataConsentVersion)');
    await _connect();
  });

  void choosePhotos() =>
      state = state.copyWith(step: OnboardingStep.photos, error: () => null);

  Future<void> _connect() async {
    final from = state.step;
    state = state.copyWith(step: OnboardingStep.connecting);
    try {
      final result = await ref
          .read(dexaSyncProvider.notifier)
          .connectAndImport();
      state = state.copyWith(step: OnboardingStep.reveal, result: result);
    } on CancelledException {
      state = state.copyWith(step: from);
    } on AppException {
      state = state.copyWith(step: from);
      rethrow;
    }
  }

  /// Finishes onboarding. The page then goes home.
  Future<bool> finish(BodySource source) => _busy(() async {
    final profile = _profile;
    await ref
        .read(profileProvider.notifier)
        .save(
          profile.copyWith(
            bodySource: source,
            onboardedAt: profile.onboardedAt ?? DateTime.now().toUtc(),
          ),
        );
  });

  /// Runs [body] with the busy flag. Returns false when it failed; the
  /// failure is in [OnboardingState.error] for the page to show.
  Future<bool> _busy(Future<void> Function() body) async {
    if (state.busy) return false;
    state = state.copyWith(busy: true, error: () => null);
    try {
      await body();
      state = state.copyWith(busy: false);
      return true;
    } on AppException catch (e) {
      if (e is! CancelledException) {
        _log.warning('Onboarding step failed (${e.code ?? e.kind})');
      }
      state = state.copyWith(
        busy: false,
        error: () => e is CancelledException ? null : e,
      );
      return false;
    }
  }
}

final NotifierProvider<OnboardingController, OnboardingState>
onboardingProvider =
    NotifierProvider.autoDispose<OnboardingController, OnboardingState>(
      OnboardingController.new,
    );
