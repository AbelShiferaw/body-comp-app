import 'package:app_ui/app_ui.dart';
import 'package:material_ui/material_ui.dart';

/// A tab whose screen is not built yet: its title and one line on what it
/// will show.
class ComingSoonPage extends StatelessWidget {
  const new({
    required this.title,
    required this.body,
    required this.icon,
    super.key,
  });

  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: tokens.lean),
              const SizedBox(height: AppSpacing.md),
              Text(
                body,
                textAlign: TextAlign.center,
                style: textTheme.bodyLarge?.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
