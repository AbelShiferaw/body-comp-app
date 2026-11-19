import 'package:app_core/app_core.dart';
import 'package:app_ui/app_ui.dart';
import 'package:body_comp/l10n/l10n.dart';
import 'package:body_comp/profile/domain/profile.dart';
import 'package:body_comp/profile/domain/profile_rules.dart';
import 'package:body_comp/profile/presentation/profile_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Sex, birth year and height, with a metric/imperial switch. Used by profile
/// setup and by settings. Calls [onSaved] after a successful save.
class ProfileForm extends ConsumerStatefulWidget {
  const new({
    required this.initial,
    required this.submitLabel,
    this.onSaved,
    this.now,
    super.key,
  });

  final Profile initial;
  final String submitLabel;
  final VoidCallback? onSaved;

  /// Today's date, for the age check. Tests pass a fixed date.
  final DateTime? now;

  @override
  ConsumerState<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<ProfileForm> {
  final _formKey = GlobalKey<FormState>();
  late Sex? _sex = widget.initial.sex;
  late Units _units = widget.initial.units;
  late final _birthYear = TextEditingController(
    text: widget.initial.birthYear?.toString() ?? '',
  );
  final _cm = TextEditingController();
  final _feet = TextEditingController();
  final _inches = TextEditingController();
  bool _saving = false;
  bool _showSexError = false;
  bool _submitted = false;
  AppException? _error;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _fillHeight(widget.initial.heightCm);
  }

  @override
  void dispose() {
    _birthYear.dispose();
    _cm.dispose();
    _feet.dispose();
    _inches.dispose();
    super.dispose();
  }

  void _fillHeight(double? cm) {
    if (cm == null) return;
    _cm.text = cm.toStringAsFixed(cm.truncateToDouble() == cm ? 0 : 1);
    final imperial = Height.toFeetInches(cm);
    _feet.text = '${imperial.feet}';
    _inches.text = '${imperial.inches}';
  }

  /// The height as typed, in cm, or null if it is not a number yet.
  double? _heightCm() {
    if (_units == Units.metric) {
      final cm = double.tryParse(_cm.text.trim().replaceAll(',', '.'));
      return cm == null ? null : Height.roundCm(cm);
    }
    final feet = int.tryParse(_feet.text.trim());
    final inches = double.tryParse(_inches.text.trim().ifEmpty('0'));
    if (feet == null || inches == null || inches < 0 || inches >= 12) {
      return null;
    }
    return Height.fromFeetInches(feet, inches);
  }

  void _switchUnits(Units units) {
    // Carry the typed height across, so switching never loses it.
    final cm = _heightCm();
    setState(() => _units = units);
    _fillHeight(cm);
  }

  String? _validateHeight() {
    final cm = _heightCm();
    if (cm == null || !ProfileRules.isValidHeightCm(cm)) {
      final l10n = context.l10n;
      return _units == Units.metric
          ? l10n.profileHeightInvalid
          : l10n.profileHeightInvalidImperial;
    }
    return null;
  }

  Future<void> _submit() async {
    setState(() {
      _submitted = true;
      _showSexError = _sex == null;
      _error = null;
    });
    final formValid = _formKey.currentState!.validate();
    if (!formValid || _sex == null) return;

    setState(() => _saving = true);
    try {
      await ref
          .read(profileProvider.notifier)
          .save(
            Profile(
              sex: _sex,
              birthYear: int.parse(_birthYear.text.trim()),
              heightCm: _heightCm(),
              units: _units,
            ),
          );
      widget.onSaved?.call();
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    final digitsOnly = [FilteringTextInputFormatter.digitsOnly];

    return Form(
      key: _formKey,
      // After the first submit, errors clear as soon as the field is fixed.
      autovalidateMode: _submitted
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.profileSexLabel, style: textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          SegmentedButton<Sex>(
            key: const Key('profile_sex'),
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: Sex.male, label: Text(l10n.profileSexMale)),
              ButtonSegment(
                value: Sex.female,
                label: Text(l10n.profileSexFemale),
              ),
            ],
            selected: {?_sex},
            onSelectionChanged: (s) => setState(() {
              _sex = s.firstOrNull;
              _showSexError = false;
            }),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _showSexError ? l10n.profileSexRequired : l10n.profileSexHelp,
            style: textTheme.bodySmall?.copyWith(
              color: _showSexError ? tokens.danger : tokens.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextFormField(
            key: const Key('profile_birthYear'),
            controller: _birthYear,
            keyboardType: TextInputType.number,
            inputFormatters: [
              ...digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            decoration: InputDecoration(
              labelText: l10n.profileBirthYearLabel,
              errorMaxLines: 2,
            ),
            validator: (value) {
              final year = int.tryParse(value?.trim() ?? '');
              if (year == null || !ProfileRules.isValidBirthYear(year, _now)) {
                return l10n.profileBirthYearInvalid(ProfileRules.minAge);
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.profileHeightLabel,
                  style: textTheme.titleSmall,
                ),
              ),
              SegmentedButton<Units>(
                key: const Key('profile_units'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: Units.metric, label: Text(l10n.unitCm)),
                  ButtonSegment(
                    value: Units.imperial,
                    label: Text(l10n.unitFtIn),
                  ),
                ],
                selected: {_units},
                onSelectionChanged: (s) => _switchUnits(s.first),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_units == Units.metric)
            TextFormField(
              key: const Key('profile_heightCm'),
              controller: _cm,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                suffixText: l10n.unitCm,
                errorMaxLines: 2,
              ),
              validator: (_) => _validateHeight(),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    key: const Key('profile_heightFeet'),
                    controller: _feet,
                    keyboardType: TextInputType.number,
                    inputFormatters: digitsOnly,
                    decoration: InputDecoration(
                      suffixText: l10n.unitFt,
                      errorMaxLines: 3,
                    ),
                    validator: (_) => _validateHeight(),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextFormField(
                    key: const Key('profile_heightInches'),
                    controller: _inches,
                    keyboardType: TextInputType.number,
                    inputFormatters: digitsOnly,
                    decoration: InputDecoration(suffixText: l10n.unitIn),
                  ),
                ),
              ],
            ),
          if (_error case final error?) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              switch (error) {
                NetworkException() => l10n.errorNetwork,
                _ => l10n.errorGeneric,
              },
              key: const Key('profile_error'),
              style: TextStyle(color: tokens.danger),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            key: const Key('profile_submit'),
            label: widget.submitLabel,
            loading: _saving,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
