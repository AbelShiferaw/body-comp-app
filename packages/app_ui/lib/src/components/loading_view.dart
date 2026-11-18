import 'package:material_ui/material_ui.dart';

/// Full-area loading state.
class LoadingView extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}
