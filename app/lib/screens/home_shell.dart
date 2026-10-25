import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'admin/audit_screen.dart';
import 'admin/cycles_screen.dart';
import 'admin/dashboard_screen.dart';
import 'admin/reports_screen.dart';
import 'admin/residents_screen.dart';
import 'admin/users_screen.dart';
import 'guard/access_control_screen.dart';
import 'resident/help_screen.dart';
import 'resident/resident_home_screen.dart';
import 'resident/resident_draws_screen.dart';
import 'shared/movements_screen.dart';
import 'shared/notifications_screen.dart';
import 'shared/spots_map_screen.dart';

class _Dest {
  const _Dest(this.label, this.icon, this.builder);

  final String label;
  final IconData icon;
  final Widget Function() builder;
}

/// Navegación principal según el rol (Administrador, Guarda, Residente).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  late final List<_Dest> _dests;

  @override
  void initState() {
    super.initState();
    final user = session.user!;
    if (user.isAdmin) {
      _dests = [
        _Dest('Inicio', Icons.dashboard_outlined, () => const DashboardScreen()),
        _Dest('Mapa', Icons.grid_view, () => const SpotsMapScreen()),
        _Dest('Residentes', Icons.people_outline, () => const ResidentsScreen()),
        _Dest('Ciclos y sorteos', Icons.casino_outlined, () => const CyclesScreen()),
        _Dest('Control de acceso', Icons.qr_code_scanner, () => const AccessControlScreen()),
        _Dest('Movimientos', Icons.swap_vert, () => const MovementsScreen()),
        _Dest('Reportes', Icons.bar_chart, () => const ReportsScreen()),
        _Dest('Usuarios', Icons.manage_accounts_outlined, () => const UsersScreen()),
        _Dest('Auditoría y respaldos', Icons.history, () => const AuditScreen()),
      ];
    } else if (user.isGuard) {
      _dests = [
        _Dest('Control de acceso', Icons.qr_code_scanner, () => const AccessControlScreen()),
        _Dest('Mapa', Icons.grid_view, () => const SpotsMapScreen()),
        _Dest('Movimientos', Icons.swap_vert, () => const MovementsScreen()),
      ];
    } else {
      _dests = [
        _Dest('Mi parqueadero', Icons.home_outlined, () => const ResidentHomeScreen()),
        _Dest('Sorteos', Icons.casino_outlined, () => const ResidentDrawsScreen()),
        _Dest('Disponibilidad', Icons.grid_view, () => const SpotsMapScreen()),
        _Dest('Ayuda', Icons.help_outline, () => const HelpScreen()),
      ];
    }
    if (user.mustChangePassword) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showChangePasswordDialog(context, forced: true);
      });
    }
  }

  void _go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final user = session.user!;
    final dest = _dests[_index];
    final useDrawer = !wide && _dests.length > 5;

    final body = KeyedSubtree(key: ValueKey(_index), child: dest.builder());

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.blue,
        foregroundColor: Colors.white,
        titleSpacing: wide ? 16 : 0,
        title: Row(
          children: [
            if (wide) ...[
              const BrandLogo(size: 36),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                wide ? 'Parqueadero Comunitario' : dest.label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        actions: [
          ListenableBuilder(
            listenable: session,
            builder: (context, _) => IconButton(
              tooltip: 'Notificaciones',
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
                session.refreshUnread();
              },
              icon: Badge(
                isLabelVisible: session.unreadNotifications > 0,
                label: Text('${session.unreadNotifications}'),
                child: const Icon(Icons.notifications_outlined),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Cuenta',
            icon: const Icon(Icons.account_circle),
            onSelected: (v) async {
              if (v == 'password') showChangePasswordDialog(context);
              if (v == 'logout' &&
                  await confirm(context, 'Cerrar sesión', '¿Desea salir de la aplicación?', ok: 'Salir')) {
                session.logout();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
                    Text('${roleLabel(user.role)} · ${user.username}',
                        style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'password', child: Text('Cambiar contraseña')),
              const PopupMenuItem(value: 'logout', child: Text('Cerrar sesión')),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      drawer: useDrawer
          ? NavigationDrawer(
              selectedIndex: _index,
              onDestinationSelected: (i) {
                Navigator.pop(context);
                _go(i);
              },
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                  child: Row(
                    children: [
                      const BrandLogo(size: 48),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user.displayName,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis),
                            Text(roleLabel(user.role), style: const TextStyle(color: AppColors.muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                for (final d in _dests) NavigationDrawerDestination(icon: Icon(d.icon), label: Text(d.label)),
              ],
            )
          : null,
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  extended: MediaQuery.of(context).size.width >= 1200,
                  selectedIndex: _index,
                  onDestinationSelected: _go,
                  labelType: MediaQuery.of(context).size.width >= 1200
                      ? NavigationRailLabelType.none
                      : NavigationRailLabelType.all,
                  destinations: [
                    for (final d in _dests)
                      NavigationRailDestination(icon: Icon(d.icon), label: Text(d.label)),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            )
          : body,
      bottomNavigationBar: (!wide && !useDrawer)
          ? NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _go,
              destinations: [
                for (final d in _dests) NavigationDestination(icon: Icon(d.icon), label: d.label),
              ],
            )
          : null,
    );
  }
}

Future<void> showChangePasswordDialog(BuildContext context, {bool forced = false}) async {
  final current = TextEditingController();
  final next = TextEditingController();
  final repeat = TextEditingController();
  String? error;
  bool busy = false;
  await showDialog<void>(
    context: context,
    barrierDismissible: !forced,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(forced ? 'Cambie su contraseña temporal' : 'Cambiar contraseña'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (forced)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('Por seguridad, defina una contraseña personal antes de continuar.'),
                  ),
                TextField(controller: current, obscureText: true, decoration: inputDeco('Contraseña actual')),
                const SizedBox(height: 10),
                TextField(
                    controller: next,
                    obscureText: true,
                    decoration: inputDeco('Nueva contraseña', helper: 'Mínimo 6 caracteres')),
                const SizedBox(height: 10),
                TextField(controller: repeat, obscureText: true, decoration: inputDeco('Repetir nueva contraseña')),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(error!, style: const TextStyle(color: AppColors.red)),
                  ),
              ],
            ),
          ),
          actions: [
            if (!forced) TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            if (forced) TextButton(onPressed: () {
              Navigator.pop(ctx);
              session.logout();
            }, child: const Text('Salir')),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (next.text.length < 6) {
                        setState(() => error = 'La nueva contraseña debe tener al menos 6 caracteres');
                        return;
                      }
                      if (next.text != repeat.text) {
                        setState(() => error = 'Las contraseñas no coinciden');
                        return;
                      }
                      setState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await session.api.post('/auth/change-password', {
                          'current_password': current.text,
                          'new_password': next.text,
                        });
                        session.user?.mustChangePassword = false;
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) showSnack(context, 'Contraseña actualizada');
                      } catch (e) {
                        setState(() {
                          busy = false;
                          error = e.toString();
                        });
                      }
                    },
              child: const Text('Guardar'),
            ),
          ],
        ),
      );
    },
  );
}
