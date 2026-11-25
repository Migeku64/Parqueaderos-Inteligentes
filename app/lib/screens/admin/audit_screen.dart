import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/files.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Auditoría de movimientos del sistema (RF15) y respaldos automáticos (RF20).
class AuditScreen extends StatelessWidget {
  const AuditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const PageHeader(title: 'Auditoría y respaldos', subtitle: 'Trazabilidad de acciones y copias de seguridad'),
          TabBar(tabs: const [Tab(text: 'Auditoría'), Tab(text: 'Respaldos')]),
          const Expanded(child: _Tabs()),
        ],
      ),
    );
  }
}

const _actionLabels = {
  'login': 'Inicio de sesión',
  'login_fallido': 'Inicio de sesión fallido',
  'usuario_bloqueado': 'Usuario bloqueado',
  'usuario_desbloqueado': 'Usuario desbloqueado',
  'crear_residente': 'Residente creado',
  'editar_residente': 'Residente editado',
  'inactivar_residente': 'Residente inactivado',
  'crear_vehiculo': 'Vehículo creado',
  'editar_vehiculo': 'Vehículo editado',
  'sorteo': 'Sorteo realizado',
  'asignacion_manual': 'Asignación manual',
  'cancelar_asignacion': 'Asignación cancelada',
  'crear_ciclo': 'Ciclo creado',
  'activar_ciclo': 'Ciclo activado',
  'cerrar_ciclo': 'Ciclo finalizado',
  'registro_entrada': 'Entrada registrada',
  'registro_salida': 'Salida registrada',
  'ingreso_rechazado': 'Ingreso rechazado',
  'restablecer_contrasena': 'Contraseña restablecida',
  'cambio_contrasena': 'Cambio de contraseña',
  'respaldo_manual': 'Respaldo manual',
  'sorteo_automatico': 'Sorteo automático',
  'editar_ciclo': 'Ciclo editado',
  'eliminar_ciclo': 'Ciclo eliminado',
  'crear_celda': 'Celda creada',
  'crear_celdas': 'Celdas creadas',
  'editar_celda': 'Celda editada',
  'eliminar_celda': 'Celda eliminada',
  'eliminar_celdas': 'Celdas eliminadas',
  'eliminar_residente': 'Residente eliminado',
  'inactivar_vehiculo': 'Vehículo retirado',
  'eliminar_vehiculo': 'Vehículo eliminado',
  'crear_usuario': 'Usuario creado',
  'editar_usuario': 'Usuario editado',
  'eliminar_usuario': 'Usuario eliminado',
  'solicitud_recuperacion': 'Solicitud de recuperación de contraseña',
  'alerta_seguridad': 'Alerta de seguridad',
  'informe_auditoria': 'Informe de auditoría',
  'exportar_auditoria': 'Auditoría exportada',
};

class _AuditTab extends StatefulWidget {
  const _AuditTab();

  @override
  State<_AuditTab> createState() => _AuditTabState();
}

class _AuditTabState extends State<_AuditTab> {
  String _action = '';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 320,
                child: LabeledDropdown<String>(
                  label: 'Tipo de acción',
                  value: _action,
                  items: {'': 'Todas', ..._actionLabels},
                  onChanged: (v) => setState(() => _action = v),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Exportar la auditoría',
                onSelected: (f) => _export(context, f),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'pdf', child: Text('PDF')),
                  PopupMenuItem(value: 'xlsx', child: Text('Excel (.xlsx)')),
                  PopupMenuItem(value: 'csv', child: Text('CSV')),
                ],
                child: const IgnorePointer(
                  child: OutlinedButton(
                    onPressed: _noop,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.download_outlined),
                      SizedBox(width: 6),
                      Text('Exportar'),
                    ]),
                  ),
                ),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.forward_to_inbox_outlined),
                label: const Text('Enviar informe ahora'),
                onPressed: () async {
                  if (await confirm(context, 'Informe de auditoría',
                      'Se enviará a la administración el resumen de los últimos 7 días, en la aplicación y por correo. '
                          'Además, el sistema lo envía automáticamente cada lunes.')) {
                    if (!context.mounted) return;
                    await runAction(context, () => session.api.post('/audit/report', {'days': 7}),
                        success: 'Informe de auditoría enviado');
                  }
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: Loader<List<Map<String, dynamic>>>(
            key: ValueKey(_action),
            load: () async => asList(await session.api.get('/audit', query: {'action': _action, 'limit': 300})),
            builder: (context, list, reload) => list.isEmpty
                ? const EmptyView(message: 'Sin registros')
                : RefreshIndicator(
                    onRefresh: reload,
                    child: ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      // Builder: cada fila toma los colores del tema actual al cambiar entre modo claro y oscuro
                      itemBuilder: (_, i) => Builder(builder: (context) {
                        final a = list[i];
                        final details = a['details'];
                        return Container(
                          color: Theme.of(context).cardColor,
                          child: ListTile(
                            dense: true,
                            leading: const Icon(Icons.receipt_long, color: AppColors.blue),
                            title: Text(_actionLabels[asStr(a['action'])] ?? asStr(a['action'])),
                            subtitle: Text(
                              '${asStr(a['username'], 'sistema')} · ${asStr(a['entity_name'])} ${asStr(a['entity_id'])}'
                              '${details != null ? '\n${_short(details)}' : ''}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(fmtDateTime(a['performed_at']), style: const TextStyle(fontSize: 12)),
                            onTap: details == null
                                ? null
                                : () => showDialog<void>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: Text(_actionLabels[asStr(a['action'])] ?? asStr(a['action'])),
                                        content: SingleChildScrollView(
                                          child: SelectableText(const JsonEncoder.withIndent('  ').convert(details)),
                                        ),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
                                        ],
                                      ),
                                    ),
                          ),
                        );
                      }),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  static void _noop() {}

  Future<void> _export(BuildContext context, String format) async {
    final bytes = await runAction(
        context, () => session.api.getBytes('/audit', query: {'format': format, if (_action.isNotEmpty) 'action': _action}));
    if (bytes == null || !context.mounted) return;
    final name = 'auditoria-${isoDate(DateTime.now())}.$format';
    try {
      final file = await AppFiles.save(name, bytes);
      await AppFiles.open(file);
      if (context.mounted) showSnack(context, 'Auditoría exportada: ${file.path}');
    } catch (_) {
      if (context.mounted) showSnack(context, 'No se pudo guardar el archivo en este dispositivo.', error: true);
    }
  }

  String _short(dynamic d) {
    final s = jsonEncode(d);
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }
}

class _BackupsTab extends StatefulWidget {
  const _BackupsTab();

  @override
  State<_BackupsTab> createState() => _BackupsTabState();
}

class _BackupsTabState extends State<_BackupsTab> {
  int _version = 0;

  @override
  Widget build(BuildContext context) {
    return Loader<List<Map<String, dynamic>>>(
      key: ValueKey(_version),
      load: () async => asList(await session.api.get('/backups')),
      builder: (context, list, reload) => ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SectionCard(
            child: Row(
              children: [
                const Expanded(
                  child: Text('El servidor genera un respaldo automático cada 24 horas (configurable). '
                      'También puede generar uno ahora.'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.backup),
                  label: const Text('Respaldar ahora'),
                  onPressed: () async {
                    await runAction(context, () => session.api.post('/backups'), success: 'Respaldo generado');
                    setState(() => _version++);
                  },
                ),
              ],
            ),
          ),
          if (list.isEmpty) const EmptyView(message: 'Aún no hay respaldos'),
          for (final b in list)
            Card(
              elevation: 0,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
              child: ListTile(
                leading: Icon(
                  asStr(b['status']) == 'ok' ? Icons.cloud_done : Icons.error_outline,
                  color: asStr(b['status']) == 'ok' ? AppColors.green : AppColors.red,
                ),
                title: Text(asStr(b['file_name'])),
                subtitle: Text('${fmtDateTime(b['created_at'])} · ${asStr(b['trigger'])} · '
                    '${(asInt(b['size_bytes']) / 1024).toStringAsFixed(1)} KB'
                    '${b['error'] != null ? '\n${asStr(b['error'])}' : ''}'),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs();

  @override
  Widget build(BuildContext context) => TabBarView(children: const [_AuditTab(), _BackupsTab()]);
}
