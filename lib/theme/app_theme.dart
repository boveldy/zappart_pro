import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Charte Zappart, version web. Reprend les partis pris de l'app officielle :
/// police **Maven Pro** partout, primaire **noir**, fond **blanc pur**
/// (#FFFFFF, jamais gris — cf. CLAUDE.md « DA : fond blanc »), focus noir sur
/// les champs, coins arrondis généreux.
class AppTheme {
  AppTheme._();

  // Palette
  static const Color bg = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF111111);
  static const Color inkSoft = Color(0xFF6B6B6B);
  static const Color line = Color(0xFFECECEC);
  static const Color panel = Color(0xFFF7F7F7);
  static const Color terracotta = Color(0xFFC4836A);
  static const Color danger = Color(0xFFB00020);
  static const Color success = Color(0xFF1E7F4F);

  // Métriques du shell
  static const double sidebarWidth = 248;
  static const double sidebarRailWidth = 72;
  static const double topbarHeight = 64;
  static const double contentMaxWidth = 1280;
  static const double breakpointCompact = 1024;

  static ThemeData build() {
    final base = ThemeData(
      brightness: Brightness.light,
      useMaterial3: false,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      colorScheme: const ColorScheme.light(
        primary: ink,
        onPrimary: Colors.white,
        secondary: ink,
        onSecondary: Colors.white,
        surface: bg,
        onSurface: ink,
        error: danger,
      ),
    );

    return base.copyWith(
      textTheme: GoogleFonts.mavenProTextTheme(base.textTheme),
      primaryTextTheme: GoogleFonts.mavenProTextTheme(base.primaryTextTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ink, width: 1.6),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: danger, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.mavenPro(
              fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle:
            GoogleFonts.mavenPro(color: Colors.white, fontSize: 13.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  // Helpers de style réutilisés par les écrans
  static TextStyle h1 = GoogleFonts.mavenPro(
      fontSize: 24, fontWeight: FontWeight.w700, color: ink);
  static TextStyle h2 = GoogleFonts.mavenPro(
      fontSize: 18, fontWeight: FontWeight.w700, color: ink);
  static TextStyle label = GoogleFonts.mavenPro(
      fontSize: 13, fontWeight: FontWeight.w500, color: inkSoft);
  static TextStyle body = GoogleFonts.mavenPro(fontSize: 14, color: ink);

  static BoxDecoration card = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: line),
  );
}
