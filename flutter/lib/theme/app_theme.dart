import 'package:flutter/material.dart';

/// "Calm Future" design tokens: one accent gradient, glass surfaces, quiet text.
/// Read them anywhere with `CalmTokens.of(context)`.
@immutable
class CalmTokens extends ThemeExtension<CalmTokens> {
  const CalmTokens({
    required this.accentA,
    required this.accentB,
    required this.warn,
    required this.support,
    required this.glassFill,
    required this.glassBorder,
    required this.sheetFill,
    required this.glow,
    required this.muted,
  });

  final Color accentA; // teal
  final Color accentB; // cyan
  final Color warn; // amber: only for "ahead of pace"
  final Color support; // violet: reserved for Family support
  final Color glassFill;
  final Color glassBorder;
  final Color sheetFill; // more opaque glass for bottom sheets and the nav bar
  final Color glow;
  final Color muted;

  LinearGradient get accent => LinearGradient(colors: [accentA, accentB]);

  static const dark = CalmTokens(
    accentA: Color(0xFF2DD4BF),
    accentB: Color(0xFF22D3EE),
    warn: Color(0xFFFBBF24),
    support: Color(0xFFA78BFA),
    glassFill: Color(0x12FFFFFF),
    glassBorder: Color(0x1FFFFFFF),
    sheetFill: Color(0xD9121820),
    glow: Color(0x402DD4BF),
    muted: Color(0xFF8B98A5),
  );

  static const light = CalmTokens(
    accentA: Color(0xFF0D9488),
    accentB: Color(0xFF0891B2),
    warn: Color(0xFFD97706),
    support: Color(0xFF7C3AED),
    glassFill: Color(0xB8FFFFFF),
    glassBorder: Color(0x14000000),
    sheetFill: Color(0xEBFFFFFF),
    glow: Color(0x3314B8A6),
    muted: Color(0xFF5B6770),
  );

  static CalmTokens of(BuildContext context) => Theme.of(context).extension<CalmTokens>() ?? dark;

  @override
  CalmTokens copyWith({
    Color? accentA,
    Color? accentB,
    Color? warn,
    Color? support,
    Color? glassFill,
    Color? glassBorder,
    Color? sheetFill,
    Color? glow,
    Color? muted,
  }) =>
      CalmTokens(
        accentA: accentA ?? this.accentA,
        accentB: accentB ?? this.accentB,
        warn: warn ?? this.warn,
        support: support ?? this.support,
        glassFill: glassFill ?? this.glassFill,
        glassBorder: glassBorder ?? this.glassBorder,
        sheetFill: sheetFill ?? this.sheetFill,
        glow: glow ?? this.glow,
        muted: muted ?? this.muted,
      );

  @override
  CalmTokens lerp(ThemeExtension<CalmTokens>? other, double t) {
    if (other is! CalmTokens) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return CalmTokens(
      accentA: l(accentA, other.accentA),
      accentB: l(accentB, other.accentB),
      warn: l(warn, other.warn),
      support: l(support, other.support),
      glassFill: l(glassFill, other.glassFill),
      glassBorder: l(glassBorder, other.glassBorder),
      sheetFill: l(sheetFill, other.sheetFill),
      glow: l(glow, other.glow),
      muted: l(muted, other.muted),
    );
  }
}

class AppTheme {
  AppTheme._();

  // ---- Classic: the original Material 3 look (unchanged) ----

  static const Color classicSeed = Color(0xFF0F766E); // deep teal

  static ThemeData light() => _classic(Brightness.light);
  static ThemeData dark() => _classic(Brightness.dark);

  static ThemeData _classic(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: classicSeed,
      brightness: brightness,
      surface: brightness == Brightness.light ? const Color(0xFFF6F8F7) : const Color(0xFF101413),
    );
    final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness);
    final text = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: text,
      // Calm tokens are attached too, so shared widgets never miss them.
      extensions: [brightness == Brightness.dark ? CalmTokens.dark : CalmTokens.light],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      // Comfortable touch targets everywhere.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );
  }

  // ---- Futuristic: "Calm Future" ----

  static const Color seed = Color(0xFF2DD4BF);
  static const Color darkBg = Color(0xFF0A0E13);
  static const Color lightBg = Color(0xFFF6F8F8);

  static ThemeData calmLight() => _calm(Brightness.light);
  static ThemeData calmDark() => _calm(Brightness.dark);

  static const _tabular = [FontFeature.tabularFigures()];

  static ThemeData _calm(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final tokens = isDark ? CalmTokens.dark : CalmTokens.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      surface: isDark ? darkBg : lightBg,
      primary: tokens.accentA,
      onPrimary: isDark ? const Color(0xFF032724) : Colors.white,
      secondary: tokens.accentB,
    );
    final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness);
    // Two weights only: 400 for text, 600 for emphasis. Money uses tabular figures so digits don't jump.
    final text = base.textTheme.copyWith(
      displayLarge: base.textTheme.displayLarge
          ?.copyWith(fontSize: 56, fontWeight: FontWeight.w600, letterSpacing: -2, height: 1.05, fontFeatures: _tabular),
      displaySmall: base.textTheme.displaySmall
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -1, fontFeatures: _tabular),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.5),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.3),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontFeatures: _tabular),
      labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.2),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(color: tokens.muted),
    );

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: text,
      extensions: [tokens],
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.glassFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: tokens.glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: tokens.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: tokens.accentA, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          side: BorderSide(color: tokens.glassBorder),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: tokens.glassFill,
        selectedColor: tokens.accentA.withValues(alpha: 0.18),
        side: BorderSide(color: tokens.glassBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Colors.transparent, elevation: 0),
      dividerTheme: DividerThemeData(color: tokens.glassBorder, thickness: 1, space: 1),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      // Comfortable touch targets everywhere.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );
  }
}

/// Durations that collapse to zero when the user has asked the OS to reduce motion.
class Motion {
  Motion._();

  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static Duration of(BuildContext context, Duration normal) => reduced(context) ? Duration.zero : normal;

  static const Duration short = Duration(milliseconds: 200);
  static const Duration medium = Duration(milliseconds: 300);
  static const Duration long = Duration(milliseconds: 700);
}
