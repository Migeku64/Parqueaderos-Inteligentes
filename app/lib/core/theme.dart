import 'package:flutter/material.dart';

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
  static const muted = Color(0xFF5E6778);
}

/// Radios de esquina usados en toda la app (diseño redondeado / circular).
class AppRadius {
  static const card = 24.0;
  static const tile = 20.0;
  static const field = 30.0;
  static const sheet = 28.0;
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.blue,
    primary: AppColors.blue,
    secondary: AppColors.green,
    error: AppColors.red,
    brightness: Brightness.light,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.page,
    visualDensity: VisualDensity.standard,
    // Tarjetas con esquinas muy redondeadas
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
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
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.field)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: Color(0xFFD5DAE3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: AppColors.blue, width: 2),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.tile)),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.tile)),
    ),
    navigationDrawerTheme: const NavigationDrawerThemeData(indicatorShape: StadiumBorder()),
    navigationRailTheme: const NavigationRailThemeData(indicatorShape: StadiumBorder()),
  );
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
