import 'package:app_ui/app_ui.dart';
import 'package:body_comp/l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// The signed-in app: one tab per branch of the router's shell route, with
/// the tab bar from the launch design (Body, Progress, Scans, Profile).
/// Each tab keeps its own navigation stack.
class AppShell extends StatelessWidget {
  const new(this.shell, {super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      body: shell,
      bottomNavigationBar: _TabBar(
        current: shell.currentIndex,
        // Tapping the current tab again returns it to its first page.
        onTap: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
        tabs: [
          (key: 'tab_body', icon: Icons.accessibility_new, label: l10n.tabBody),
          (
            key: 'tab_progress',
            icon: Icons.trending_up,
            label: l10n.tabProgress,
          ),
          (
            key: 'tab_scans',
            icon: Icons.article_outlined,
            label: l10n.tabScans,
          ),
          (
            key: 'tab_profile',
            icon: Icons.person_outline,
            label: l10n.tabProfile,
          ),
        ],
      ),
    );
  }
}

typedef _Tab = ({String key, IconData icon, String label});

class _TabBar extends StatelessWidget {
  const new({required this.current, required this.onTap, required this.tabs});

  final int current;
  final ValueChanged<int> onTap;
  final List<_Tab> tabs;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final label = Theme.of(context).textTheme.labelMedium;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.background,
        border: Border(top: BorderSide(color: tokens.surfaceRaised)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              for (final (i, tab) in tabs.indexed)
                Expanded(
                  child: _TabButton(
                    key: Key(tab.key),
                    tab: tab,
                    selected: i == current,
                    color: i == current ? tokens.textPrimary : tokens.textFaint,
                    style: label,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const new({
    required this.tab,
    required this.selected,
    required this.color,
    required this.style,
    required this.onTap,
    super.key,
  });

  final _Tab tab;
  final bool selected;
  final Color color;
  final TextStyle? style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: InkResponse(
      onTap: onTap,
      radius: 36,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(tab.icon, size: 22, color: color),
            const SizedBox(height: AppSpacing.xs),
            Text(
              tab.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style?.copyWith(color: color),
            ),
          ],
        ),
      ),
    ),
  );
}
