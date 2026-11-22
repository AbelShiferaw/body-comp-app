import 'package:app_auth/app_auth.dart';
import 'package:app_body/app_body.dart';
import 'package:app_core/app_core.dart';
import 'package:app_ui/app_ui.dart';
import 'package:body_comp/l10n/l10n.dart';
import 'package:body_comp/profile/domain/profile.dart';
import 'package:body_comp/profile/presentation/profile_form.dart';
import 'package:body_comp/profile/presentation/profile_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Profile and account. Signing out or deleting the account clears the user,
/// and the router takes over from there.
class SettingsPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on AppException catch (e) {
      if (!mounted) return;
      final l10n = context.l10n;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is NetworkException ? l10n.errorNetwork : l10n.errorGeneric,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete() async {
    final l10n = context.l10n;
    final tokens = context.tokens;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteAccountTitle),
        content: Text(l10n.deleteAccountBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('settings_confirmDelete'),
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: tokens.danger),
            child: Text(l10n.deleteAccountConfirm),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await _run(ref.read(authRepositoryProvider).deleteAccount);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    final profile = ref.watch(profileProvider);
    final email = ref.watch(authUserProvider).value?.email;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabProfile)),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(l10n.settingsProfileSection, style: textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            switch (profile) {
              AsyncError() => ErrorView(
                message: l10n.errorGeneric,
                retryLabel: l10n.retry,
                onRetry: () => ref.invalidate(profileProvider),
              ),
              AsyncValue(:final value) when profile.hasValue => ProfileForm(
                // Rebuilt when Units changes, so height follows it.
                key: ValueKey(value?.units),
                initial: value ?? const Profile(),
                showUnits: false,
                submitLabel: l10n.save,
                onSaved: () => ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(l10n.profileSaved))),
              ),
              _ => const LoadingView(),
            },
            const SizedBox(height: AppSpacing.lg),
            if (profile.value case final p?) ...[
              _UnitsSetting(profile: p),
              const SizedBox(height: AppSpacing.lg),
            ],
            const BodyStyleSetting(),
            const SizedBox(height: AppSpacing.xl),
            Text(l10n.settingsAccountSection, style: textTheme.titleMedium),
            if (email != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(email, style: TextStyle(color: tokens.textSecondary)),
            ],
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              key: const Key('settings_signOut'),
              onPressed: () => _run(ref.read(authRepositoryProvider).signOut),
              child: Text(l10n.signOut),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              key: const Key('settings_delete'),
              onPressed: _confirmDelete,
              style: TextButton.styleFrom(foregroundColor: tokens.danger),
              child: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.deleteAccount),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pounds and feet/inches (the default) or kilograms and centimetres. Saves
/// at once, like the body style.
class _UnitsSetting extends ConsumerWidget {
  const new({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.settingsUnitsLabel),
          subtitle: Text(l10n.settingsUnitsHelp),
        ),
        SegmentedButton<Units>(
          key: const Key('settings_units'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: Units.imperial,
              label: Text(l10n.unitsImperial),
            ),
            ButtonSegment(value: Units.metric, label: Text(l10n.unitsMetric)),
          ],
          selected: {profile.units},
          onSelectionChanged: (s) async {
            final messenger = ScaffoldMessenger.of(context);
            try {
              await ref
                  .read(profileProvider.notifier)
                  .save(profile.copyWith(units: s.first));
            } on AppException catch (e) {
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    e is NetworkException
                        ? l10n.errorNetwork
                        : l10n.errorGeneric,
                  ),
                ),
              );
            }
          },
        ),
      ],
    );
  }
}
