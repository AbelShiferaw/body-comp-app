import 'package:app_ui/src/theme/app_tokens.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Builds the Material themes from [AppTokens] and the type scale from the
/// design system: Archivo (expanded) for headlines and numbers, Inter for
/// everything you read.
///
/// The app passes both to `MaterialApp(theme:, darkTheme:)` with
/// `themeMode: ThemeMode.system`, so it follows the phone's light/dark setting.
abstract final class AppTheme {
  static ThemeData get light => _build(AppTokens.light, Brightness.light);
  static ThemeData get dark => _build(AppTokens.dark, Brightness.dark);

  /// Archivo at a width (100 normal, 125 widest) and weight.
  static TextStyle display({
    required double size,
    double weight = 700,
    double width = 112,
    double? height,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: 'Archivo',
    package: 'app_ui',
    fontSize: size,
    fontWeight: _weight(weight),
    fontVariations: [FontVariation.weight(weight), FontVariation.width(width)],
    height: height,
    letterSpacing: letterSpacing,
  );

  /// Inter at a weight.
  static TextStyle body({
    required double size,
    double weight = 400,
    double? height,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: 'Inter',
    package: 'app_ui',
    fontSize: size,
    fontWeight: _weight(weight),
    fontVariations: [FontVariation.weight(weight)],
    height: height,
    letterSpacing: letterSpacing,
  );

  /// The app name as a wordmark.
  static TextStyle get wordmark =>
      display(size: 15, weight: 800, width: 125, letterSpacing: 2.7);

  /// Registers the bundled fonts' licenses with the license page. Call once
  /// at startup.
  static void registerFontLicenses() {
    LicenseRegistry.addLicense(() async* {
      for (final family in ['Archivo', 'Inter']) {
        final text = await rootBundle.loadString(
          'packages/app_ui/fonts/$family-OFL.txt',
        );
        yield LicenseEntryWithLineBreaks([family], text);
      }
    });
  }

  static FontWeight _weight(double w) =>
      FontWeight.values[((w / 100).round() - 1).clamp(0, 8)];

  static TextTheme _text(AppTokens t) {
    final primary = t.textPrimary;
    return TextTheme(
      displayLarge: display(size: 56, height: 1),
      displayMedium: display(size: 44, height: 1),
      displaySmall: display(size: 36, height: 1.05),
      headlineLarge: display(
        size: 32,
        weight: 800,
        height: 1.05,
        letterSpacing: -0.3,
      ),
      headlineMedium: display(
        size: 28,
        weight: 800,
        height: 1.08,
        letterSpacing: -0.2,
      ),
      headlineSmall: display(size: 22, height: 1.15),
      titleLarge: display(size: 20, height: 1.2),
      titleMedium: body(size: 16, weight: 600, height: 1.3),
      titleSmall: body(size: 14, weight: 600, height: 1.3),
      bodyLarge: body(size: 15, height: 1.45),
      bodyMedium: body(size: 14, height: 1.45),
      bodySmall: body(size: 12, height: 1.4),
      labelLarge: body(size: 16, weight: 600),
      labelMedium: body(size: 12, weight: 500),
      labelSmall: body(size: 11, weight: 600, letterSpacing: 0.9),
    ).apply(bodyColor: primary, displayColor: primary);
  }

  static ThemeData _build(AppTokens t, Brightness brightness) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: t.accent,
          brightness: brightness,
        ).copyWith(
          primary: t.accent,
          onPrimary: t.onAccent,
          surface: t.surface,
          onSurface: t.textPrimary,
          onSurfaceVariant: t.textSecondary,
          surfaceContainerHighest: t.surfaceRaised,
          error: t.danger,
          outline: t.border,
          outlineVariant: t.border,
        );
    final text = _text(t);
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: text,
      fontFamily: 'Inter',
      package: 'app_ui',
      scaffoldBackgroundColor: t.background,
      extensions: [t],
      appBarTheme: AppBarTheme(
        backgroundColor: t.background,
        foregroundColor: t.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: t.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: t.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: t.action,
          foregroundColor: t.onAction,
          disabledBackgroundColor: t.surfaceRaised,
          disabledForegroundColor: t.textFaint,
          minimumSize: const Size.fromHeight(54),
          shape: controlShape,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: t.surface,
          foregroundColor: t.textPrimary,
          minimumSize: const Size.fromHeight(48),
          side: BorderSide(color: t.border),
          shape: controlShape,
          textStyle: text.labelLarge?.copyWith(fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: t.accent,
          textStyle: text.titleSmall,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(color: t.textFaint, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.accent : null,
        ),
        checkColor: WidgetStatePropertyAll(t.onAccent),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: t.accent,
        linearTrackColor: t.surfaceRaised,
        circularTrackColor: t.surfaceRaised,
      ),
      dividerTheme: DividerThemeData(color: t.border, space: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: t.action,
        contentTextStyle: text.bodyMedium?.copyWith(color: t.onAction),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.surfaceRaised,
        labelStyle: text.bodyLarge?.copyWith(color: t.textSecondary),
        hintStyle: text.bodyLarge?.copyWith(color: t.textFaint),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: t.accent, width: 2),
        ),
      ),
    );
  }
}
