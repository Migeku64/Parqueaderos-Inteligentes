import 'package:flutter/foundation.dart';

/// Pedido para cambiar de sección dentro del menú principal
/// (por ejemplo, al tocar una tarjeta del panel de administración).
class NavRequest {
  const NavRequest(this.section, {this.filter});

  /// Nombre de la sección tal como aparece en el menú ("Mapa", "Movimientos"...).
  final String section;

  /// Filtro con el que debe abrirse la sección (por ejemplo "libre" o "rechazados").
  final String? filter;
}

final shellNav = ValueNotifier<NavRequest?>(null);

/// Abre una sección del menú principal, opcionalmente con un filtro.
void goToSection(String section, {String? filter}) =>
    shellNav.value = NavRequest(section, filter: filter);
