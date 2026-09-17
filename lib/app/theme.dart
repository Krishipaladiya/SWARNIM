import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tokens lifted directly from the approved mockup
/// ("Swarnim Connect Perfect.dc.html").
///
/// The app has an unusual but deliberate structure: DARK NAVY CHROME (status
/// bar, header, bottom nav) wrapping a LIGHT CONTENT AREA. Read the two groups
/// below as "on dark" and "on light" - mixing them is the easiest way to make a
/// screen look wrong.
abstract final class SwarnimColors {
  // ---- chrome (dark) ----
  static const navy = Color(0xFF0D2031); // header, footer, status bar
  static const navyMid = Color(0xFF1A2F4A);
  static const navyDeep = Color(0xFF0F1F2E);

  /// The launch animation's own background, averaged over the border of its
  /// first frame.
  ///
  /// Deliberately not [navy]: the animation sits on a lighter, bluer field.
  /// The Android launch screen and the Flutter splash both use this, so the
  /// hand-off between them is a change of content and not a flash of colour.
  static const splashField = Color(0xFF244855);
  static const dividerDark = Color(0xFF2A4361);
  static const inputUnderline = Color(0xFF3A5573);
  static const inkOnDark = Color(0xFFF5F5F5);
  static const metaOnDark = Color(0xFF9FB0C4);
  static const placeholderOnDark = Color(0xFF6D84A0);

  // ---- content (light) ----
  static const bodyTop = Color(0xFFF8F6F4);
  static const bodyBottom = Color(0xFFEFF0F3);
  static const cardTop = Color(0xFFF9FAFE);
  static const cardBottom = Color(0xFFF3F6FA);
  static const inkOnLight = Color(0xFF1A2F4A);
  static const metaOnLight = Color(0xFF647A92);
  static const borderLight = Color(0xFFC0C5D0);
  static const dividerLight = Color(0xFFDDE3EA);

  // ---- accent ----
  static const gold = Color(0xFFD4AF37);
  static const goldHover = Color(0xFFE8C766);
  static const goldSoft = Color(0xFFC9A572);

  // ---- buttons ----
  static const buttonPrimary = Color(0xFF24405F);
  static const buttonPrimaryText = Color(0xFFF2F2F3);
  static const buttonSecondaryTop = Color(0xFFF3F6FA);
  static const buttonSecondaryBottom = Color(0xFFE8EFF7);

  // ---- status ----
  static const statusOpen = Color(0xFFB23B3B);
  static const statusResolvedBg = Color(0xFFE4E9EF);

  // ---- gradients ----
  static const bodyGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [bodyTop, bodyBottom],
  );

  static const cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [cardTop, cardBottom],
  );

  static const avatarGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [navyMid, navyDeep],
  );

  static const secondaryButtonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [buttonSecondaryTop, buttonSecondaryBottom],
  );
}

/// Corner radii from the mockup: almost everything is 4px. Resisting the urge
/// to round things more is what keeps this looking like the approved design.
abstract final class SwarnimRadius {
  static const control = 4.0;
  static const image = 6.0;
}

abstract final class SwarnimTheme {
  static TextTheme _textTheme(TextTheme base) => GoogleFonts.poppinsTextTheme(base);

  static ThemeData build() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: SwarnimColors.buttonPrimary,
        onPrimary: SwarnimColors.buttonPrimaryText,
        secondary: SwarnimColors.gold,
        onSecondary: SwarnimColors.navy,
        surface: SwarnimColors.bodyTop,
        onSurface: SwarnimColors.inkOnLight,
        error: SwarnimColors.statusOpen,
        outline: SwarnimColors.borderLight,
      ),
    );

    return base.copyWith(
      // Navy, not the light body colour.
      //
      // Every screen in this app is navy chrome wrapping a light panel, and the
      // panel is painted by SwarnimScreen - so the only times the scaffold's own
      // colour is visible are the times the chrome should be: behind a route
      // transition, behind the bottom nav's safe-area inset on a gesture-nav
      // phone, and for the instant before a screen's first paint. Leaving this
      // light put a cream flash in all three.
      scaffoldBackgroundColor: SwarnimColors.navy,

      // Same reason. canvasColor is what Material paints behind a route while
      // it animates in, and it defaults to the light surface from the scheme.
      canvasColor: SwarnimColors.navy,
      textTheme: _textTheme(base.textTheme),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: SwarnimColors.buttonPrimary,
          foregroundColor: SwarnimColors.buttonPrimaryText,
          disabledBackgroundColor: SwarnimColors.buttonPrimary.withValues(alpha: 0.5),
          disabledForegroundColor: SwarnimColors.buttonPrimaryText.withValues(alpha: 0.7),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SwarnimRadius.control),
          ),
          textStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      // Fields inside the light content area.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: _lightBorder(SwarnimColors.borderLight),
        enabledBorder: _lightBorder(SwarnimColors.borderLight),
        focusedBorder: _lightBorder(SwarnimColors.gold),
        errorBorder: _lightBorder(SwarnimColors.statusOpen),
        focusedErrorBorder: _lightBorder(SwarnimColors.statusOpen),
        hintStyle: GoogleFonts.poppins(
          fontSize: 13,
          color: SwarnimColors.metaOnLight.withValues(alpha: 0.7),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: SwarnimColors.navyMid,
        contentTextStyle: GoogleFonts.poppins(
          color: SwarnimColors.inkOnDark,
          fontSize: 13,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SwarnimRadius.control),
        ),
      ),
    );
  }

  static OutlineInputBorder _lightBorder(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(SwarnimRadius.control),
        borderSide: BorderSide(color: color),
      );

  // ---- named text styles used across screens ----

  /// 20px / 700, sits on the navy header.
  static TextStyle get screenTitle => GoogleFonts.poppins(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: SwarnimColors.inkOnDark,
      );

  static TextStyle get screenSubtitle => GoogleFonts.poppins(
        fontSize: 11,
        color: SwarnimColors.metaOnDark,
      );

  /// Uppercase section label on the LIGHT body.
  static TextStyle get fieldLabel => GoogleFonts.poppins(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: SwarnimColors.metaOnLight,
      );

  /// Uppercase section label on the DARK chrome.
  static TextStyle get fieldLabelDark => GoogleFonts.poppins(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: SwarnimColors.metaOnDark,
      );

  static TextStyle get cardTitle => GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: SwarnimColors.inkOnLight,
      );

  static TextStyle get cardMeta => GoogleFonts.poppins(
        fontSize: 12,
        color: SwarnimColors.metaOnLight,
      );
}
