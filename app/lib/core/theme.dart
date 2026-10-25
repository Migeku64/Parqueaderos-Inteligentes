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
