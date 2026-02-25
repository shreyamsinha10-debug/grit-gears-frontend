// ---------------------------------------------------------------------------
// Jupiter Arena – App-wide theme (light and dark).
// ---------------------------------------------------------------------------
// Defines colors, typography (Poppins), and Material 3 theme data used
// across all screens. Use [AppTheme.light] / [AppTheme.dark] in MaterialApp.
// Default branding when no gym admin is logged in or gym has no custom name/logo.
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Default gym name and logo asset when not overridden by gym profile.
const String defaultGymName = 'Grit & Gears';
const String defaultLogoAsset = 'assets/logo.png';

/// Jupiter Arena – Light, clean SaaS theme.
/// Backgrounds: Pure White, light grey cards.
/// Primary: Soft Indigo / Periwinkle.
class AppTheme {
  AppTheme._();

  static const Color primary = Color(0xFF8A8EF2);
  static const Color primaryDark = Color(0xFF6B6FCF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF8F9FA);
  static const Color onSurface = Color(0xFF1A1A1A);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color outline = Color(0xFFE0E0E0);
  static const Color onSurfaceVariant = Color(0xFF5C5C6B);
  static const Color success = Color(0xFF22C55E);
  static const Color error = Color(0xFFE53935);

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: surface,
      colorScheme: const ColorScheme.light(
        primary: primary,
        onPrimary: onPrimary,
        surface: surface,
        onSurface: onSurface,
        secondary: primaryDark,
        onSecondary: onPrimary,
        error: error,
        outline: outline,
      ),
      textTheme: GoogleFonts.poppinsTextTheme(ThemeData.light().textTheme).copyWith(
        bodyLarge: GoogleFonts.poppins(color: onSurface),
        bodyMedium: GoogleFonts.poppins(color: onSurface),
        titleLarge: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: onSurface),
        titleMedium: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: onSurface),
        labelLarge: GoogleFonts.poppins(fontWeight: FontWeight.w500),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: onSurface,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: onSurface),
      ),
      cardTheme: CardThemeData(
        color: surfaceVariant,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(0),
        clipBehavior: Clip.antiAlias,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceVariant,
        labelStyle: GoogleFonts.poppins(color: onSurface),
        hintStyle: GoogleFonts.poppins(color: Colors.grey),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: outline),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: onSurface,
        contentTextStyle: GoogleFonts.poppins(color: surface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  static ThemeData get dark {
    const surfaceDark = Color(0xFF1E1E2E);
    const surfaceVariantDark = Color(0xFF252536);
    const onSurfaceDark = Color(0xFFE4E4E7);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: surfaceDark,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        onPrimary: onPrimary,
        surface: surfaceDark,
        onSurface: onSurfaceDark,
        secondary: primaryDark,
        onSecondary: onPrimary,
        error: error,
        outline: Color(0xFF3F3F50),
      ),
      textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme).copyWith(
        bodyLarge: GoogleFonts.poppins(color: onSurfaceDark),
        bodyMedium: GoogleFonts.poppins(color: onSurfaceDark),
        titleLarge: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: onSurfaceDark),
        titleMedium: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: onSurfaceDark),
        labelLarge: GoogleFonts.poppins(fontWeight: FontWeight.w500, color: onSurfaceDark),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceDark,
        foregroundColor: onSurfaceDark,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: onSurfaceDark),
      ),
      cardTheme: CardThemeData(
        color: surfaceVariantDark,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(0),
        clipBehavior: Clip.antiAlias,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceVariantDark,
        labelStyle: GoogleFonts.poppins(color: onSurfaceDark),
        hintStyle: GoogleFonts.poppins(color: Colors.grey),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF3F3F50)),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: onSurfaceDark,
        contentTextStyle: GoogleFonts.poppins(color: surfaceDark),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

/// Responsive padding: use for consistent, screen-adaptive layout.
class LayoutConstants {
  LayoutConstants._();

  static double screenPadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 360) return 16;
    if (width > 600) return 24;
    return 20;
  }

  static double cardRadius(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width > 600 ? 16 : 12;
  }
}
