import 'package:app_body/src/domain/body_renderer.dart';
import 'package:app_body/src/presentation/body_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

// TODO(body): move strings to localization once modules share l10n.

/// The Settings row that switches the body between Studio and Midnight.
class BodyStyleSetting extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(bodyStyleProvider);
    return ListTile(
      title: const Text('Body style'),
      subtitle: const Text('How your 3D body looks'),
      trailing: SegmentedButton<BodyStyle>(
        key: const Key('bodyStyle_toggle'),
        segments: const [
          ButtonSegment(value: BodyStyle.studio, label: Text('Studio')),
          ButtonSegment(value: BodyStyle.midnight, label: Text('Midnight')),
        ],
        selected: {style},
        showSelectedIcon: false,
        onSelectionChanged: (s) =>
            ref.read(bodyStyleProvider.notifier).set(s.first),
      ),
    );
  }
}
