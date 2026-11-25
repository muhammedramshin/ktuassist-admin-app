import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

class Brand {
  static const yellow = Color(0xffFFD60A);
  static const yellowSoft = Color(0xffFFF3BF);
  static const ink = Color(0xff121316);
  static const radius = 22.0;
}

/// Semantic tones used by pills, metrics and banners.
@immutable
class Tones extends ThemeExtension<Tones> {
  const Tones({
    required this.success,
    required this.successBg,
    required this.warning,
    required this.warningBg,
    required this.danger,
    required this.dangerBg,
    required this.info,
    required this.infoBg,
    required this.violet,
    required this.violetBg,
    required this.muted,
  });
  final Color success, successBg, warning, warningBg, danger, dangerBg;
  final Color info, infoBg, violet, violetBg, muted;

  static const light = Tones(
    success: Color(0xff0E8A5F),
    successBg: Color(0xffDDF6EA),
    warning: Color(0xffA15C00),
    warningBg: Color(0xffFFEFD1),
    danger: Color(0xffC62F3A),
    dangerBg: Color(0xffFDE3E4),
    info: Color(0xff2257D6),
    infoBg: Color(0xffE1EAFF),
    violet: Color(0xff6A3FD8),
    violetBg: Color(0xffECE5FF),
    muted: Color(0xff6B6F7B),
  );
  static const dark = Tones(
    success: Color(0xff5FD8A6),
    successBg: Color(0xff123326),
    warning: Color(0xffFFC266),
    warningBg: Color(0xff3A2A10),
    danger: Color(0xffFF8A92),
    dangerBg: Color(0xff3D1A1D),
    info: Color(0xff8FB0FF),
    infoBg: Color(0xff17244A),
    violet: Color(0xffB9A2FF),
    violetBg: Color(0xff2A2147),
    muted: Color(0xff9A9EAA),
  );

  @override
  Tones copyWith() => this;
  @override
  Tones lerp(ThemeExtension<Tones>? other, double t) =>
      t < .5 ? this : (other as Tones? ?? this);
}

extension ThemeX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  Tones get tones => Theme.of(this).extension<Tones>()!;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  bool get isWide => MediaQuery.sizeOf(this).width >= 900;
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: Brand.yellow,
        brightness: brightness,
      ).copyWith(
        primary: dark ? Brand.yellow : Brand.ink,
        onPrimary: dark ? Brand.ink : Colors.white,
        primaryContainer: dark ? const Color(0xff3A3214) : Brand.yellowSoft,
        onPrimaryContainer: dark ? Brand.yellow : const Color(0xff3D3200),
        secondary: dark ? const Color(0xffE6E1D3) : const Color(0xff4A4636),
        secondaryContainer: dark
            ? const Color(0xff2A2B30)
            : const Color(0xffF0EEE6),
        tertiary: Brand.yellow,
        surface: dark ? const Color(0xff16171B) : Colors.white,
        onSurface: dark ? const Color(0xffF2F2F4) : Brand.ink,
        onSurfaceVariant: dark
            ? const Color(0xffA3A6B0)
            : const Color(0xff676B76),
        surfaceContainerLowest: dark
            ? const Color(0xff0E0F12)
            : const Color(0xffF6F5F1),
        surfaceContainerLow: dark
            ? const Color(0xff1B1C21)
            : const Color(0xffF3F2EE),
        surfaceContainer: dark
            ? const Color(0xff202127)
            : const Color(0xffEEEDE8),
        surfaceContainerHigh: dark
            ? const Color(0xff26272E)
            : const Color(0xffE8E7E1),
        surfaceContainerHighest: dark
            ? const Color(0xff2D2E35)
            : const Color(0xffE1E0DA),
        outline: dark ? const Color(0xff3A3B43) : const Color(0xffDCDAD3),
        outlineVariant: dark
            ? const Color(0xff2A2B31)
            : const Color(0xffEAE8E2),
        error: dark ? const Color(0xffFF8A92) : const Color(0xffC62F3A),
      );
  final base = ThemeData(brightness: brightness).textTheme.apply(
    fontFamily: 'PlusJakartaSans',
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );
  final text = base.copyWith(
    displaySmall: base.displaySmall?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -1.2,
    ),
    headlineMedium: base.headlineMedium?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -.8,
    ),
    headlineSmall: base.headlineSmall?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -.5,
    ),
    titleLarge: base.titleLarge?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -.3,
    ),
    titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w700),
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  final background = scheme.surfaceContainerLowest;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    textTheme: text,
    scaffoldBackgroundColor: background,
    extensions: [dark ? Tones.dark : Tones.light],
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Brand.radius),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      space: 1,
      thickness: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? scheme.surfaceContainer : scheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.error),
      ),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      hintStyle: TextStyle(
        color: scheme.onSurfaceVariant.withValues(alpha: .7),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 50),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: shape,
        textStyle: text.labelLarge?.copyWith(fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 46),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: shape,
        side: BorderSide(color: scheme.outline),
        foregroundColor: scheme.onSurface,
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: shape,
        foregroundColor: scheme.onSurface,
        textStyle: text.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: scheme.onSurface),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide(color: scheme.outline),
      backgroundColor: scheme.surface,
      selectedColor: dark ? Brand.yellow : Brand.ink,
      secondarySelectedColor: dark ? Brand.yellow : Brand.ink,
      labelStyle: text.labelLarge?.copyWith(color: scheme.onSurface),
      secondaryLabelStyle: text.labelLarge?.copyWith(
        color: dark ? Brand.ink : Colors.white,
      ),
      checkmarkColor: dark ? Brand.ink : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: dark ? Brand.yellow : Brand.ink,
        selectedForegroundColor: dark ? Brand.ink : Colors.white,
        side: BorderSide(color: scheme.outline),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 70,
      elevation: 0,
      backgroundColor: scheme.surface,
      indicatorColor: Brand.yellow,
      labelTextStyle: WidgetStatePropertyAll(
        text.labelSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? Brand.ink
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: Brand.yellow,
      selectedIconTheme: const IconThemeData(color: Brand.ink),
      selectedLabelTextStyle: text.labelLarge,
      unselectedLabelTextStyle: text.labelLarge?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xffF2F2F4) : Brand.ink,
      contentTextStyle: text.bodyMedium?.copyWith(
        color: dark ? Brand.ink : Colors.white,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle: text.titleSmall?.copyWith(fontSize: 15),
      subtitleTextStyle: text.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
        fontSize: 13,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? (dark ? Brand.ink : Colors.white)
            : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? (dark ? Brand.yellow : Brand.ink)
            : null,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: dark ? Brand.yellow : Brand.ink,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: Brand.yellow,
      foregroundColor: Brand.ink,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      extendedTextStyle: text.labelLarge?.copyWith(fontSize: 15),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      indicatorSize: TabBarIndicatorSize.tab,
      labelColor: dark ? Brand.ink : Colors.white,
      unselectedLabelColor: scheme.onSurfaceVariant,
      labelStyle: text.labelLarge,
      indicator: BoxDecoration(
        color: dark ? Brand.yellow : Brand.ink,
        borderRadius: BorderRadius.circular(14),
      ),
      tabAlignment: TabAlignment.start,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
  );
}
