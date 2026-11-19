import 'package:app_body/app_body.dart';
import 'package:body_comp/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// App settings. Each module contributes its own rows.
class SettingsPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.settingsTitle)),
    body: ListView(children: const [BodyStyleSetting()]),
  );
}
