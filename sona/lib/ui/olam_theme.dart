import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const accent = Color(0xFFD6ED69);
const lavender = Color(0xFFCF9DEB);
const ink = Color(0xFFF6F2FF);
const muted = Color(0xFFB8B3C4);
const cream = Color(0xFF09090F);
const paper = Color(0xFF1C1B24);
const hairline = Color(0xFF3D3949);

ThemeData olamTheme() => ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: Colors.transparent,
  colorScheme: ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
    primary: accent,
    onPrimary: cream,
    surface: cream,
    onSurface: ink,
    secondary: const Color(0xFFD89EFF),
    outline: hairline,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.transparent,
    foregroundColor: ink,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: true,
    systemOverlayStyle: SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: cream,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  ),
  dividerTheme: const DividerThemeData(
    color: hairline,
    thickness: .6,
    space: 24,
  ),
  iconTheme: const IconThemeData(color: ink, size: 22),
  sliderTheme: const SliderThemeData(
    trackHeight: 2,
    activeTrackColor: accent,
    inactiveTrackColor: hairline,
    thumbColor: accent,
    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5),
  ),
  chipTheme: ChipThemeData(
    backgroundColor: cream,
    selectedColor: accent,
    side: const BorderSide(color: hairline),
    labelStyle: const TextStyle(fontSize: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: accent,
      foregroundColor: cream,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: paper,
    surfaceTintColor: Colors.transparent,
    showDragHandle: true,
  ),
  snackBarTheme: const SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: ink,
    contentTextStyle: TextStyle(color: cream),
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: cream,
    indicatorColor: accent,
    iconTheme: WidgetStateProperty.resolveWith(
      (states) => IconThemeData(
        color: states.contains(WidgetState.selected) ? cream : muted,
      ),
    ),
    elevation: 0,
    labelTextStyle: WidgetStateProperty.resolveWith(
      (states) => TextStyle(
        color: states.contains(WidgetState.selected) ? accent : muted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: paper,
    hintStyle: const TextStyle(color: muted),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: BorderSide.none,
    ),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: paper,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
  ),
  popupMenuTheme: PopupMenuThemeData(
    color: paper,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  ),
  listTileTheme: const ListTileThemeData(iconColor: accent, textColor: ink),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      color: ink,
      fontSize: 28,
      fontWeight: FontWeight.w700,
      letterSpacing: -.8,
    ),
    headlineMedium: TextStyle(
      color: ink,
      fontSize: 24,
      fontWeight: FontWeight.w700,
      letterSpacing: -.5,
    ),
    titleLarge: TextStyle(
      color: ink,
      fontSize: 20,
      fontWeight: FontWeight.w600,
    ),
    titleMedium: TextStyle(
      color: ink,
      fontSize: 15,
      fontWeight: FontWeight.w600,
    ),
    bodyMedium: TextStyle(color: ink, fontSize: 14, height: 1.45),
  ),
);

class RaagaBackdrop extends StatelessWidget {
  const RaagaBackdrop({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: cream,
      gradient: RadialGradient(
        center: Alignment(-.95, -1.05),
        radius: .85,
        colors: [Color(0xFF743755), Color(0xFF332644), cream],
        stops: [0, .3, .8],
      ),
    ),
    child: child,
  );
}
