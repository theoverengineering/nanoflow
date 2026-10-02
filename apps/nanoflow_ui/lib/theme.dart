import 'package:flutter/material.dart';

/// Colors of the mockups in docs/design/ (their HTML has the exact values).
abstract final class AppColors {
  /// The window behind every screen.
  static const window = Color(0xFF1F2023);

  /// Lines between areas: under the graph screen's header.
  static const divider = Color(0xFF2B2C30);

  static const card = Color(0xFF26272B);
  static const cardBorder = Color(0xFF303136);

  /// A card under the pointer or selected.
  static const accentSurface = Color(0xFF2B2745);
  static const accentBorder = Color(0xFF4B4380);

  /// The square an icon sits in.
  static const tile = Color(0xFF323338);
  static const tileBorder = Color(0xFF45464C);

  /// Small secondary buttons (`Remove`); also the missing card's dashes.
  static const control = Color(0xFF2A2B30);
  static const controlBorder = Color(0xFF3A3B41);

  /// The primary button and the selected run.
  static const accent = Color(0xFF6D5DE8);
  static const onAccent = Color(0xFFFFFFFF);

  static const textPrimary = Color(0xFFECECEE);
  static const textSecondary = Color(0xFFD5D6DA);
  static const textMuted = Color(0xFFA7A8AE);
  static const textFaint = Color(0xFF8E8F96);
  static const textDim = Color(0xFF6E6F76);

  static const dangerSurface = Color(0xFF3A1D20);
  static const dangerText = Color(0xFFF7878C);
}

/// Text of the mockups: UI text in Geist; ids, paths, commands and logs in
/// Geist Mono. Sizes, weights and colors are the mockups' CSS.
abstract final class AppText {
  static const sans = 'Geist';
  static const mono = 'Geist Mono';

  // CSS `normal` line height of the Google Fonts Geist the mockups were drawn
  // with: 1.3 em, the baseline 1.005 em from the top. The bundled fonts put
  // their lines closer; this spacing puts text where the mockups have it.
  static const _lineHeight = 1.3;
  static const _leading = TextLeadingDistribution.even;

  /// The default for text that names no style.
  static const body = TextStyle(
    height: _lineHeight,
    leadingDistribution: _leading,
    inherit: false,
    fontFamily: sans,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    textBaseline: TextBaseline.alphabetic,
  );

  // Start screen.
  static const pageTitle = TextStyle(
    height: _lineHeight,
    leadingDistribution: _leading,
    fontFamily: sans,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    letterSpacing: 26 * -0.015,
    color: AppColors.textPrimary,
  );
  static const pageHint = TextStyle(
    height: _lineHeight,
    leadingDistribution: _leading,
    fontFamily: sans,
    fontSize: 13.5,
    color: AppColors.textMuted,
  );
  static const primaryButton = TextStyle(
    height: _lineHeight,
    leadingDistribution: _leading,
    fontFamily: sans,
    fontSize: 13.5,
    fontWeight: FontWeight.w600,
    color: AppColors.onAccent,
  );
  static const sectionTitle = TextStyle(
    height: _lineHeight,
    leadingDistribution: _leading,
    fontFamily: sans,
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
  );
  static const count = TextStyle(
    height: _lineHeight,
    leadingDistribution: _leading,
    fontFamily: mono,
    fontSize: 11.5,
    color: AppColors.textFaint,
  );
  static const cardTitle = TextStyle(
    height: _lineHeight,
    leadingDistribution: _leading,
    fontFamily: sans,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  static const cardPath = TextStyle(
    height: _lineHeight,
    leadingDistribution: _leading,
    fontFamily: mono,
    fontSize: 11.5,
    color: AppColors.textMuted,
  );
  static const cardMeta = TextStyle(
    height: _lineHeight,
    leadingDistribution: _leading,
    fontFamily: sans,
    fontSize: 12,
    color: AppColors.textMuted,
  );
  static const badge = TextStyle(
    height: _lineHeight,
    leadingDistribution: _leading,
    fontFamily: sans,
    fontSize: 10.5,
    fontWeight: FontWeight.w600,
  );
  static const button = TextStyle(
    height: _lineHeight,
    leadingDistribution: _leading,
    fontFamily: sans,
    fontSize: 12,
    color: AppColors.textSecondary,
  );

  // Graph screen header.
  static const crumb = TextStyle(
    height: _lineHeight,
    leadingDistribution: _leading,
    fontFamily: sans,
    fontSize: 13,
    color: AppColors.textMuted,
  );
  static const crumbSeparator = TextStyle(
    height: _lineHeight,
    leadingDistribution: _leading,
    fontFamily: sans,
    fontSize: 13,
    color: AppColors.textDim,
  );
  static const headerTitle = TextStyle(
    height: _lineHeight,
    leadingDistribution: _leading,
    fontFamily: sans,
    fontSize: 13.5,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  static const headerPath = TextStyle(
    height: _lineHeight,
    leadingDistribution: _leading,
    fontFamily: mono,
    fontSize: 11.5,
    color: AppColors.textFaint,
  );
}

/// The app's dark theme.
ThemeData nanoflowTheme() => ThemeData(
  brightness: Brightness.dark,
  colorScheme: const ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: AppColors.onAccent,
    surface: AppColors.window,
    onSurface: AppColors.textPrimary,
  ),
  scaffoldBackgroundColor: AppColors.window,
  // Complete styles: Material's own would lend their letter spacing to text
  // under a Material widget.
  textTheme: const TextTheme(
    displayLarge: AppText.body,
    displayMedium: AppText.body,
    displaySmall: AppText.body,
    headlineLarge: AppText.body,
    headlineMedium: AppText.body,
    headlineSmall: AppText.body,
    titleLarge: AppText.body,
    titleMedium: AppText.body,
    titleSmall: AppText.body,
    bodyLarge: AppText.body,
    bodyMedium: AppText.body,
    bodySmall: AppText.body,
    labelLarge: AppText.body,
    labelMedium: AppText.body,
    labelSmall: AppText.body,
  ),
);
