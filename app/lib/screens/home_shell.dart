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
                wide ? 'Nueva Castilla Etapa 3 Parking' : dest.label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        actions: [
          const ThemeToggleButton(),
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
                        style: const TextStyle(fontWeight: FontWeight.w700)),
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
                _SideMenu(
                  dests: _dests,
                  selected: _index,
                  extended: MediaQuery.of(context).size.width >= 1200,
                  onSelect: _go,
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

/// Menú lateral (pantallas anchas): cada opción cambia de color al pasar el cursor
/// y la opción activa se resalta con una píldora de color.
class _SideMenu extends StatelessWidget {
  const _SideMenu({required this.dests, required this.selected, required this.extended, required this.onSelect});

  final List<_Dest> dests;
  final int selected;
  final bool extended;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: extended ? 260 : 104,
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          for (var i = 0; i < dests.length; i++)
            _SideItem(
              dest: dests[i],
              selected: i == selected,
              extended: extended,
              onTap: () => onSelect(i),
            ),
        ],
      ),
    );
  }
}

class _SideItem extends StatefulWidget {
  const _SideItem({required this.dest, required this.selected, required this.extended, required this.onTap});

  final _Dest dest;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;

  @override
  State<_SideItem> createState() => _SideItemState();
}

class _SideItemState extends State<_SideItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sel = widget.selected;
    final bg = sel
        ? cs.primary
        : _hover
            ? cs.primary.withAlpha(36)
            : Colors.transparent;
    final fg = sel
        ? cs.onPrimary
        : _hover
            ? cs.primary
            : cs.onSurfaceVariant;
    final weight = sel || _hover ? FontWeight.w700 : FontWeight.w500;
    const duration = Duration(milliseconds: 180);

    final icon = AnimatedScale(
      scale: _hover && !sel ? 1.12 : 1,
      duration: duration,
      child: Icon(widget.dest.icon, color: fg),
    );
    final Widget content = widget.extended
        ? Row(
            children: [
              icon,
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  widget.dest.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontWeight: weight),
                ),
              ),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(height: 4),
              Text(
                widget.dest.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontWeight: weight, fontSize: 11),
              ),
            ],
          );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(widget.extended ? 999 : 22),
          boxShadow: sel
              ? [BoxShadow(color: cs.primary.withAlpha(70), blurRadius: 12, offset: const Offset(0, 4))]
              : const [],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(widget.extended ? 999 : 22),
            hoverColor: Colors.transparent,
            splashColor: cs.primary.withAlpha(50),
            onHover: (h) => setState(() => _hover = h),
            onTap: widget.onTap,
            child: AnimatedPadding(
              duration: duration,
              curve: Curves.easeOut,
              padding: widget.extended
                  ? EdgeInsets.fromLTRB(_hover && !sel ? 24 : 18, 13, 16, 13)
                  : const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              child: content,
            ),
          ),
        ),
      ),
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
