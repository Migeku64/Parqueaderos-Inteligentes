import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Colores tomados de los mockups (Anexo 5): azul de fondo, botones negros, verde de estado activo.
class AppColors {
  static const navy = Color(0xFF1B2A4A);
  static const blue = Color(0xFF203F95);
  static const blueLight = Color(0xFF3B6FD8);
  static const green = Color(0xFF3DBE29);
  static const greenSoft = Color(0xFFE3F7DF);
  static const amber = Color(0xFFF2A516);
  static const amberSoft = Color(0xFFFFF1D6);
  static const red = Color(0xFFD93A3A);
  static const redSoft = Color(0xFFFDE2E2);
  static const grey = Color(0xFF9AA3B2);
  static const greySoft = Color(0xFFEDEFF3);
  static const page = Color(0xFFF4F6FB);
  static const text = Color(0xFF1C2333);
  static const muted = Color(0xFF6F788A);
}

/// Radios de esquina usados en toda la app (diseño redondeado / circular).
class AppRadius {
  static const card = 24.0;
  static const tile = 20.0;
  static const field = 30.0;
  static const sheet = 28.0;
}

/// Colores del modo oscuro.
class DarkColors {
  static const page = Color(0xFF0F1422);
  static const surface = Color(0xFF151B2A);
  static const card = Color(0xFF1C2435);
  static const border = Color(0xFF2E3850);
  static const primary = Color(0xFF4F7FE8);
}

ThemeData buildTheme({Brightness brightness = Brightness.light}) {
  final dark = brightness == Brightness.dark;
  final scheme = dark
      ? ColorScheme.fromSeed(
          seedColor: AppColors.blue,
          brightness: Brightness.dark,
          primary: DarkColors.primary,
          onPrimary: Colors.white,
          secondary: AppColors.green,
          error: AppColors.red,
          surface: DarkColors.surface,
        )
      : ColorScheme.fromSeed(
          seedColor: AppColors.blue,
          primary: AppColors.blue,
          secondary: AppColors.green,
          error: AppColors.red,
          brightness: Brightness.light,
        );
  final cardColor = dark ? DarkColors.card : Colors.white;
  final borderColor = dark ? DarkColors.border : const Color(0xFFD5DAE3);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? DarkColors.page : AppColors.page,
    cardColor: cardColor,
    canvasColor: dark ? DarkColors.surface : null,
    dividerColor: borderColor,
    visualDensity: VisualDensity.standard,
    // Tarjetas con esquinas muy redondeadas
    cardTheme: CardThemeData(
      elevation: 0,
      color: cardColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF16213E) : AppColors.blue,
      foregroundColor: Colors.white,
    ),
    // Botones en forma de píldora
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: const StadiumBorder()),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(shape: const StadiumBorder()),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(shape: CircleBorder()),
    // Campos de texto ovalados
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cardColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.field)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    chipTheme: const ChipThemeData(shape: StadiumBorder()),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.tile)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: dark ? DarkColors.card : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.tile)),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.tile)),
    ),
    navigationDrawerTheme: const NavigationDrawerThemeData(indicatorShape: StadiumBorder()),
    navigationRailTheme: const NavigationRailThemeData(indicatorShape: StadiumBorder()),
  );
}

/// Modo claro / oscuro de la app. Se guarda en el dispositivo.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController() : super(ThemeMode.light);

  static const _key = 'modo_tema';

  bool get isDark => value == ThemeMode.dark;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      value = prefs.getString(_key) == 'oscuro' ? ThemeMode.dark : ThemeMode.light;
    } catch (_) {
      value = ThemeMode.light;
    }
  }

  Future<void> toggle() async {
    value = isDark ? ThemeMode.light : ThemeMode.dark;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, isDark ? 'oscuro' : 'claro');
    } catch (_) {}
  }
}

final themeController = ThemeController();

/// Botón de sol / luna para cambiar entre modo claro y oscuro.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeController,
      builder: (context, mode, _) {
        final dark = mode == ThemeMode.dark;
        return IconButton(
          tooltip: dark ? 'Modo claro' : 'Modo oscuro',
          color: color,
          onPressed: themeController.toggle,
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, anim) => RotationTransition(
              turns: Tween<double>(begin: 0.75, end: 1).animate(anim),
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: Icon(
              dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              key: ValueKey(dark),
            ),
          ),
        );
      },
    );
  }
}

/// Estado de una celda del parqueadero -> color y etiqueta.
class SpotStyle {
  const SpotStyle(this.color, this.soft, this.label, this.icon);

  final Color color;
  final Color soft;
  final String label;
  final IconData icon;

  static SpotStyle of(String state) {
    switch (state) {
      case 'libre':
        return const SpotStyle(AppColors.green, AppColors.greenSoft, 'Libre', Icons.check_circle_outline);
      case 'asignada':
        return const SpotStyle(AppColors.amber, AppColors.amberSoft, 'Asignada', Icons.bookmark_outline);
      case 'ocupada':
        return const SpotStyle(AppColors.red, AppColors.redSoft, 'Ocupada', Icons.directions_car);
      default:
        return const SpotStyle(AppColors.grey, AppColors.greySoft, 'Inactiva', Icons.block);
    }
  }
}

/// Logo de la app: "P" de parqueadero con el punto verde de celda libre.
/// [full] = true muestra la versión con "Conjunto Residencial Nueva Castilla Etapa 3".
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 120, this.full = false});

  final double size;
  final bool full;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        full ? 'assets/logo_full.png' : 'assets/logo.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}
