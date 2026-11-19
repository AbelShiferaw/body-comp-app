import 'package:material_ui/material_ui.dart';

/// Design tokens: direction A "Graphite + Ice" from the launch design (two data
/// colors only: Ice = lean and primary, Ember = fat). Change the values in
/// [AppTokens.light] and [AppTokens.dark], not the call sites.
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
  // charts stay consistent with the rest of the UI in both modes. A change is
  // colored by what it means: less fat or more lean is [lean], the opposite
  // is [fat].
  static const light = AppTokens(
    background: Color(0xFFF4F5F7),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFEBEDF0),
    textPrimary: Color(0xFF111317),
    textSecondary: Color(0xFF555B66),
    accent: Color(0xFF1F6FC5),
    onAccent: Color(0xFFFFFFFF),
    danger: Color(0xFFC6383B),
    fat: Color(0xFFB34E0C),
    lean: Color(0xFF1F6FC5),
    border: Color(0xFFD9DCE1),
  );

  static const dark = AppTokens(
    background: Color(0xFF0B0C0E),
    surface: Color(0xFF15171B),
    surfaceRaised: Color(0xFF1E2126),
    textPrimary: Color(0xFFF2F3F5),
    textSecondary: Color(0xFFA3A9B4),
    accent: Color(0xFF7CC4FF),
    onAccent: Color(0xFF0B0C0E),
    danger: Color(0xFFFF7A7D),
    fat: Color(0xFFFF8A3D),
    lean: Color(0xFF7CC4FF),
    border: Color(0xFF2A2E35),
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
