import 'package:material_ui/material_ui.dart';

/// Design tokens from the design system on the UI canvas ("Graphite + Ice",
/// launch direction): a graphite ground so the body glows, and exactly two
/// data colors, never swapped: Ice means lean and muscle, Ember means fat.
/// Light mode keeps the names with deeper Ice and Ember for contrast on white.
///
/// Change values here, not at call sites. Read them with `context.tokens`.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const new({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.textPrimary,
    required this.textSecondary,
    required this.textFaint,
    required this.accent,
    required this.onAccent,
    required this.action,
    required this.onAction,
    required this.danger,
    required this.fat,
    required this.lean,
    required this.border,
    required this.accentSoft,
  });

  static const light = AppTokens(
    background: Color(0xFFF4F5F7),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFEBEDF0),
    textPrimary: Color(0xFF111317),
    textSecondary: Color(0xFF555B66),
    textFaint: Color(0xFF646A75),
    accent: Color(0xFF1F6FC5),
    onAccent: Color(0xFFFFFFFF),
    action: Color(0xFF111317),
    onAction: Color(0xFFFFFFFF),
    danger: Color(0xFFB3261E),
    fat: Color(0xFFB34E0C),
    lean: Color(0xFF1F6FC5),
    border: Color(0xFFD9DCE1),
    accentSoft: Color(0xFFE6EFFA),
  );

  static const dark = AppTokens(
    background: Color(0xFF0B0C0E),
    surface: Color(0xFF15171B),
    surfaceRaised: Color(0xFF1E2126),
    textPrimary: Color(0xFFF2F3F5),
    textSecondary: Color(0xFFA3A9B4),
    textFaint: Color(0xFF7D8491),
    accent: Color(0xFF7CC4FF),
    onAccent: Color(0xFF0B0C0E),
    action: Color(0xFFF2F3F5),
    onAction: Color(0xFF0B0C0E),
    danger: Color(0xFFFF8A80),
    fat: Color(0xFFFF8A3D),
    lean: Color(0xFF7CC4FF),
    border: Color(0xFF2A2E35),
    accentSoft: Color(0xFF15253A),
  );

  final Color background;
  final Color surface;

  /// Icon tiles, inputs and segmented controls on a surface.
  final Color surfaceRaised;
  final Color textPrimary;
  final Color textSecondary;

  /// Footnotes and captions (still 5:1 on the background).
  final Color textFaint;

  /// Ice: selection, links, badges. The same hue as [lean].
  final Color accent;
  final Color onAccent;

  /// The primary button: near white on graphite, near black on light.
  final Color action;
  final Color onAction;

  /// Errors only. Body numbers are never colored as alarms.
  final Color danger;
  final Color fat;
  final Color lean;
  final Color border;

  /// A quiet accent fill, for selected cards and chips.
  final Color accentSoft;

  @override
  AppTokens copyWith({
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? textPrimary,
    Color? textSecondary,
    Color? textFaint,
    Color? accent,
    Color? onAccent,
    Color? action,
    Color? onAction,
    Color? danger,
    Color? fat,
    Color? lean,
    Color? border,
    Color? accentSoft,
  }) => AppTokens(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textFaint: textFaint ?? this.textFaint,
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    action: action ?? this.action,
    onAction: onAction ?? this.onAction,
    danger: danger ?? this.danger,
    fat: fat ?? this.fat,
    lean: lean ?? this.lean,
    border: border ?? this.border,
    accentSoft: accentSoft ?? this.accentSoft,
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
      textFaint: l(textFaint, other.textFaint),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      action: l(action, other.action),
      onAction: l(onAction, other.onAction),
      danger: l(danger, other.danger),
      fat: l(fat, other.fat),
      lean: l(lean, other.lean),
      border: l(border, other.border),
      accentSoft: l(accentSoft, other.accentSoft),
    );
  }
}

/// Spacing on a 4 pt grid. Use these instead of literal numbers.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double smd = 12;
  static const double md = 16;

  /// Screen side margin.
  static const double gutter = 20;
  static const double lg = 24;
  static const double xl = 32;
}

/// Corner radii: controls, cards, sheets.
abstract final class AppRadius {
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double pill = 999;
}

extension AppTokensX on BuildContext {
  /// The current mode's tokens. Every theme built by `AppTheme` has them.
  AppTokens get tokens => Theme.of(this).extension<AppTokens>()!;
}
