import 'package:material_ui/material_ui.dart';

/// Design tokens. PLACEHOLDER values until the UI design review lands; swap the
/// values in [AppTokens.light] and [AppTokens.dark], not the call sites.
///
/// Read them in widgets with `context.tokens`.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const new({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.onAccent,
    required this.danger,
    required this.fat,
    required this.lean,
    required this.border,
  });

  // Body-composition colors (fat, lean) are tokens too, so the 3D heatmap and
  // charts stay consistent with the rest of the UI in both modes.
  static const light = AppTokens(
    background: Color(0xFFF6F7F9),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFEEF1F4),
    textPrimary: Color(0xFF14171A),
    textSecondary: Color(0xFF5B6570),
    accent: Color(0xFF2F7FD8),
    onAccent: Color(0xFFFFFFFF),
    danger: Color(0xFFC6383B),
    fat: Color(0xFFE08A2E),
    lean: Color(0xFF2FA88A),
    border: Color(0xFFD9DEE3),
  );

  static const dark = AppTokens(
    background: Color(0xFF0E1013),
    surface: Color(0xFF171A1F),
    surfaceRaised: Color(0xFF20242A),
    textPrimary: Color(0xFFF1F3F5),
    textSecondary: Color(0xFF9AA4AE),
    accent: Color(0xFF8CC8FF),
    onAccent: Color(0xFF06223D),
    danger: Color(0xFFFF7A7D),
    fat: Color(0xFFFFB36B),
    lean: Color(0xFF63D9B9),
    border: Color(0xFF2C3138),
  );

  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color textPrimary;
  final Color textSecondary;
  final Color accent;
  final Color onAccent;
  final Color danger;
  final Color fat;
  final Color lean;
  final Color border;

  @override
  AppTokens copyWith({
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? textPrimary,
    Color? textSecondary,
    Color? accent,
    Color? onAccent,
    Color? danger,
    Color? fat,
    Color? lean,
    Color? border,
  }) => AppTokens(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    danger: danger ?? this.danger,
    fat: fat ?? this.fat,
    lean: lean ?? this.lean,
    border: border ?? this.border,
  );

  @override
  AppTokens lerp(AppTokens? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppTokens(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceRaised: l(surfaceRaised, other.surfaceRaised),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      danger: l(danger, other.danger),
      fat: l(fat, other.fat),
      lean: l(lean, other.lean),
      border: l(border, other.border),
    );
  }
}

/// Spacing and radius scale. Use these instead of literal numbers.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 14;
  static const double lg = 22;
}

extension AppTokensX on BuildContext {
  /// The current mode's tokens. Every theme built by `AppTheme` has them.
  AppTokens get tokens => Theme.of(this).extension<AppTokens>()!;
}
