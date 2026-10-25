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

  IconData _icon(String kind) {
    if (kind == 'alerta') return Icons.warning_amber;
    if (kind == 'sorteo') return Icons.casino;
    if (kind.startsWith('fin_ciclo') || kind == 'ciclo') return Icons.event;
    if (kind == 'recuperacion') return Icons.key;
    if (kind == 'asignacion') return Icons.local_parking;
    return Icons.notifications;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        backgroundColor: AppColors.blue,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: () async {
              await runAction(context, () => session.api.post('/notifications/read-all'));
              session.refreshUnread();
              setState(() => _version++);
            },
            child: const Text('Marcar todas como leídas', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Loader<Map<String, dynamic>>(
        key: ValueKey(_version),
        load: () async => asMap(await session.api.get('/notifications')),
        reloadOn: const {'notification'},
        builder: (context, d, reload) {
          final items = asList(d['items']);
          if (items.isEmpty) return const EmptyView(message: 'No tiene notificaciones', icon: Icons.notifications_none);
          return MaxWidth(
            width: 760,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final n = items[i];
                final unread = n['read_at'] == null;
                final kind = asStr(n['kind']);
                return Card(
                  elevation: 0,
                  color: unread ? const Color(0xFFEAF0FF) : Colors.white,
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: ListTile(
                    leading: Icon(_icon(kind), color: kind == 'alerta' ? AppColors.red : AppColors.blue),
                    title: Text(asStr(n['title']),
                        style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w500)),
                    subtitle: Text('${asStr(n['body'])}\n${fmtDateTime(n['created_at'])}'),
                    isThreeLine: true,
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
                );
              },
            ),
          );
        },
      ),
    );
  }
}
