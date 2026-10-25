import 'dart:convert';

import 'package:flutter/material.dart';

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
          child: SizedBox(
            width: 320,
            child: LabeledDropdown<String>(
              label: 'Tipo de acción',
              value: _action,
              items: {'': 'Todas', ..._actionLabels},
              onChanged: (v) => setState(() => _action = v),
            ),
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
                      itemBuilder: (context, i) {
                        final a = list[i];
                        final details = a['details'];
                        return Container(
                          color: Colors.white,
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
                      },
                    ),
                  ),
          ),
        ),
      ],
    );
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
              color: Colors.white,
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
