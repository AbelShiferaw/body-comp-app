import 'package:app_body/src/domain/body_renderer.dart';
import 'package:app_body/src/presentation/body_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

// TODO(body): move strings to localization once modules share l10n.

/// The Settings row that switches the body between Hologram, Studio and
/// Midnight.
class BodyStyleSetting extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(bodyStyleProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Body style'),
          subtitle: Text('How your 3D body looks'),
        ),
        SegmentedButton<BodyStyle>(
          key: const Key('bodyStyle_toggle'),
          segments: const [
            ButtonSegment(value: BodyStyle.hologram, label: Text('Hologram')),
            ButtonSegment(value: BodyStyle.studio, label: Text('Studio')),
            ButtonSegment(value: BodyStyle.midnight, label: Text('Midnight')),
          ],
          selected: {style},
          showSelectedIcon: false,
          onSelectionChanged: (s) =>
              ref.read(bodyStyleProvider.notifier).set(s.first),
        ),
      ],
    );
  }
}
