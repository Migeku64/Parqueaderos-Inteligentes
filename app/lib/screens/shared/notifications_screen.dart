import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Notificaciones automáticas (RF13): sorteos, fin de ciclo, alertas de ingreso, bloqueos.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  int _version = 0;

  /// Notificaciones ya borradas en esta pantalla: se ocultan de inmediato, sin esperar a recargar
  final Set<int> _gone = {};

  IconData _icon(String kind) {
    if (kind == 'alerta') return Icons.warning_amber;
    if (kind == 'sorteo') return Icons.casino;
    if (kind.startsWith('fin_ciclo') || kind == 'ciclo') return Icons.event;
    if (kind == 'recuperacion') return Icons.key;
    if (kind == 'asignacion') return Icons.local_parking;
    return Icons.notifications;
  }

  Future<void> _menu(BuildContext context, String v) async {
    if (v == 'read') {
      await runAction(context, () => session.api.post('/notifications/read-all'));
    } else {
      final all = v == 'delete_all';
      final ok = await confirm(
        context,
        all ? 'Borrar todas las notificaciones' : 'Borrar las notificaciones leídas',
        all
            ? 'Se borrarán todas sus notificaciones, también las que no ha leído. Esto no se puede deshacer.'
            : 'Se borrarán las notificaciones que ya leyó. Las no leídas se conservan.',
        ok: 'Borrar',
        danger: true,
      );
      if (!ok || !context.mounted) return;
      await runAction(context, () => session.api.delete(all ? '/notifications' : '/notifications?only=read'),
          success: all ? 'Notificaciones borradas' : 'Notificaciones leídas borradas');
    }
    session.refreshUnread();
    if (mounted) setState(() => _version++);
  }

  /// Borra una notificación (al deslizarla o con la papelera).
  Future<void> _deleteOne(Map<String, dynamic> n) async {
    final id = asInt(n['id']);
    setState(() => _gone.add(id));
    try {
      await session.api.delete('/notifications/$id');
    } catch (_) {
      // Si no se pudo borrar en el servidor, vuelve a aparecer
      if (mounted) setState(() => _gone.remove(id));
      if (mounted) showSnack(context, 'No se pudo borrar la notificación', error: true);
    }
    session.refreshUnread();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        foregroundColor: Colors.white,
        actions: [
          // Menú ⋮ : marcar como leídas y borrar (cabe bien también en el celular)
          PopupMenuButton<String>(
            tooltip: 'Opciones',
            onSelected: (v) => _menu(context, v),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'read',
                child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.done_all),
                    title: Text('Marcar todas como leídas')),
              ),
              PopupMenuItem(
                value: 'delete_read',
                child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_sweep_outlined),
                    title: Text('Borrar las leídas')),
              ),
              PopupMenuItem(
                value: 'delete_all',
                child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_forever_outlined, color: AppColors.red),
                    title: Text('Borrar todas')),
              ),
            ],
          ),
        ],
      ),
      body: Loader<Map<String, dynamic>>(
        key: ValueKey(_version),
        load: () async => asMap(await session.api.get('/notifications')),
        reloadOn: const {'notification'},
        builder: (context, d, reload) {
          final items = asList(d['items']).where((n) => !_gone.contains(asInt(n['id']))).toList();
          if (items.isEmpty) return const EmptyView(message: 'No tiene notificaciones', icon: Icons.notifications_none);
          return MaxWidth(
            width: 760,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              // Builder: cada tarjeta toma los colores del tema actual al cambiar entre modo claro y oscuro
              itemBuilder: (_, i) => Builder(builder: (context) {
                final n = items[i];
                final unread = n['read_at'] == null;
                final kind = asStr(n['kind']);
                // Deslizar la notificación hacia un lado la borra
                return Dismissible(
                  key: ValueKey('notif-${asInt(n['id'])}'),
                  background: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(12)),
                    alignment: Alignment.centerLeft,
                    child: const Icon(Icons.delete_outline, color: Colors.white),
                  ),
                  secondaryBackground: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(12)),
                    alignment: Alignment.centerRight,
                    child: const Icon(Icons.delete_outline, color: Colors.white),
                  ),
                  onDismissed: (_) => _deleteOne(n),
                  child: Card(
                  elevation: 0,
                  color: unread ? Theme.of(context).colorScheme.primary.withAlpha(28) : Theme.of(context).cardColor,
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: ListTile(
                    leading: Icon(_icon(kind), color: kind == 'alerta' ? AppColors.red : AppColors.blue),
                    title: Text(asStr(n['title']),
                        style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w500)),
                    subtitle: Text('${asStr(n['body'])}\n${fmtDateTime(n['created_at'])}'),
                    isThreeLine: true,
                    trailing: IconButton(
                      tooltip: 'Borrar',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteOne(n),
                    ),
                    onTap: unread
                        ? () async {
                            try {
                              await session.api.post('/notifications/${asInt(n['id'])}/read');
                            } catch (_) {}
                            session.refreshUnread();
                            reload();
                          }
                        : null,
                  ),
                ),
                );
              }),
            ),
          );
        },
      ),
    );
  }
}
