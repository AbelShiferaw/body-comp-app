import 'package:app_body/src/domain/body_renderer.dart';
import 'package:app_body/src/presentation/body_providers.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

// TODO(body): move strings to localization once modules share l10n.

/// The Settings rows for how the body looks: the Studio or Midnight style,
/// and the game mode switch that turns the body into a hologram avatar.
class BodyStyleSetting extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(bodyStyleSettingProvider);
    final gameMode = ref.watch(gameModeProvider);
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Body style'),
          subtitle: Text(
            gameMode
                ? 'Game mode shows your body as a hologram'
                : 'How your 3D body looks',
          ),
        ),
        SegmentedButton<BodyStyle>(
          key: const Key('bodyStyle_toggle'),
          segments: const [
            ButtonSegment(value: BodyStyle.studio, label: Text('Studio')),
            ButtonSegment(value: BodyStyle.midnight, label: Text('Midnight')),
          ],
          selected: {style},
          showSelectedIcon: false,
          onSelectionChanged: gameMode
              ? null
              : (s) => ref.read(bodyStyleSettingProvider.notifier).set(s.first),
        ),
        const SizedBox(height: AppSpacing.md),
        SwitchListTile(
          key: const Key('bodyStyle_gameMode'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Game mode'),
          subtitle: Text(
            'Your body as a hologram avatar, with a level for every scan',
            style: TextStyle(color: tokens.textSecondary),
          ),
          value: gameMode,
          onChanged: (on) => ref.read(gameModeProvider.notifier).set(on: on),
        ),
      ],
    );
  }
}
