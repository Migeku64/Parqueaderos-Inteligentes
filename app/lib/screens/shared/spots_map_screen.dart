import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../admin/residents_screen.dart' show pickResident;

/// Mapa de parqueaderos con disponibilidad en tiempo real (RF04, RF16).
class SpotsMapScreen extends StatefulWidget {
  const SpotsMapScreen({super.key, this.initialFilter});

  /// Estado con el que se abre el mapa: libre, asignada, ocupada o inactiva
  final String? initialFilter;

  @override
  State<SpotsMapScreen> createState() => _SpotsMapScreenState();
}

class _SpotsMapScreenState extends State<SpotsMapScreen> {
  late String _filter = widget.initialFilter ?? 'todas';
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final user = session.user!;
    return Loader<List<Map<String, dynamic>>>(
      load: () async => asList(await session.api.get('/spots')),
      reloadOn: const {'spots', 'movement', 'assignments'},
      builder: (context, spots, reload) {
        final counts = <String, int>{'libre': 0, 'asignada': 0, 'ocupada': 0, 'inactiva': 0};
        for (final s in spots) {
          final st = asStr(s['state']);
          counts[st] = (counts[st] ?? 0) + 1;
        }
        final q = normalizePlate(_query);
        final visible = spots.where((s) {
          if (_filter != 'todas' && asStr(s['state']) != _filter) return false;
          if (q.isEmpty) return true;
          return asStr(s['code']).contains(q) ||
              asStr(s['plate']).contains(q) ||
              normalizePlate(asStr(s['resident_name'])).contains(q);
        }).toList();
        final List<Map<String, dynamic>> mine =
            user.isResident ? spots.where((s) => asBool(s['mine'])).toList() : <Map<String, dynamic>>[];

        return RefreshIndicator(
          onRefresh: reload,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: PageHeader(
                  title: user.isResident ? 'Disponibilidad' : 'Mapa de parqueaderos',
                  subtitle: '${counts['libre']} libres · ${counts['asignada']} asignadas · '
                      '${counts['ocupada']} ocupadas',
                  actions: [
                    IconButton(tooltip: 'Actualizar', onPressed: reload, icon: const Icon(Icons.refresh)),
                    if (user.isAdmin)
                      IconButton(
                        tooltip: 'Agregar celdas',
                        onPressed: () async {
                          if (await _addSpotsDialog(context)) reload();
                        },
                        icon: const Icon(Icons.add_box_outlined),
                      ),
                    if (user.isAdmin)
                      IconButton(
                        tooltip: 'Eliminar celdas',
                        onPressed: () async {
                          if (await _deleteSpotsDialog(context)) reload();
                        },
                        icon: const Icon(Icons.delete_outline),
                      ),
                  ],
                ),
              ),
              if (mine.isNotEmpty)
                SliverToBoxAdapter(
                  child: SectionCard(
                    child: Row(
                      children: [
                        const Icon(Icons.star, color: AppColors.amber),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('Su celda asignada es la ${asStr(mine.first['code'])} '
                              '(${SpotStyle.of(asStr(mine.first['state'])).label.toLowerCase()})'),
                        ),
                      ],
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final f in const ['todas', 'libre', 'asignada', 'ocupada', 'inactiva'])
                        ChoiceChip(
                          label: Text(f == 'todas'
                              ? 'Todas (${spots.length})'
                              : '${SpotStyle.of(f).label} (${counts[f] ?? 0})'),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                      if (!user.isResident)
                        SizedBox(
                          width: 220,
                          child: TextField(
                            decoration: inputDeco('Buscar celda, placa o nombre', icon: Icons.search),
                            onChanged: (v) => setState(() => _query = v),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 130,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.95,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _SpotTile(
                      spot: visible[i],
                      onTap: user.isResident ? null : () => _showSpot(context, visible[i], reload),
                    ),
                    childCount: visible.length,
                  ),
                ),
              ),
              if (visible.isEmpty)
                const SliverToBoxAdapter(child: EmptyView(message: 'No hay celdas con ese filtro')),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showSpot(BuildContext context, Map<String, dynamic> s, Future<void> Function() reload) async {
    final user = session.user!;
    final style = SpotStyle.of(asStr(s['state']));
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Celda ${asStr(s['code'])}',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 10),
                  Pill(style.label, color: style.color, soft: style.soft),
                  if (asBool(s['is_disabled_spot'])) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.accessible, color: AppColors.blue),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              if (s['resident_name'] != null) ...[
                Text('Asignada a: ${asStr(s['resident_name'])}', style: const TextStyle(fontSize: 16)),
                Text('Casa ${asStr(s['house'])}', style: const TextStyle(color: AppColors.muted)),
                const SizedBox(height: 8),
                if (s['plate'] != null) PlateBadge(asStr(s['plate'])),
              ] else
                const Text('Sin asignación en el ciclo actual'),
              if (user.isAdmin) ...[
                const Divider(height: 28),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (s['assignment_id'] == null && asBool(s['is_active']))
                      FilledButton.icon(
                        icon: const Icon(Icons.person_add_alt),
                        label: const Text('Asignar manualmente'),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await _manualAssign(context, s);
                          reload();
                        },
                      ),
                    if (s['assignment_id'] != null)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Cancelar asignación'),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          if (await confirm(context, 'Cancelar asignación',
                              '¿Cancelar la asignación de ${asStr(s['resident_name'])} en la celda ${asStr(s['code'])}?',
                              danger: true, ok: 'Cancelar asignación')) {
                            if (!context.mounted) return;
                            await runAction(context,
                                () => session.api.post('/assignments/${asInt(s['assignment_id'])}/cancel', {}),
                                success: 'Asignación cancelada');
                            reload();
                          }
                        },
                      ),
                    OutlinedButton.icon(
                      icon: Icon(asBool(s['is_occupied']) ? Icons.event_available : Icons.directions_car),
                      label: Text(asBool(s['is_occupied']) ? 'Marcar como libre' : 'Marcar como ocupada'),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await runAction(
                            context,
                            () => session.api
                                .patch('/spots/${asInt(s['id'])}', {'is_occupied': !asBool(s['is_occupied'])}));
                        reload();
                      },
                    ),
                    OutlinedButton.icon(
                      icon: Icon(asBool(s['is_active']) ? Icons.block : Icons.check),
                      label: Text(asBool(s['is_active']) ? 'Desactivar celda' : 'Activar celda'),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await runAction(context,
                            () => session.api.patch('/spots/${asInt(s['id'])}', {'is_active': !asBool(s['is_active'])}));
                        reload();
                      },
                    ),
                    // Solo se ofrece en celdas sin asignación y desocupadas; la API además
                    // rechaza las que tienen historial (esas se deben desactivar).
                    if (s['assignment_id'] == null && !asBool(s['is_occupied']))
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Eliminar celda'),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          if (await confirm(
                              context,
                              'Eliminar celda',
                              '¿Eliminar la celda ${asStr(s['code'])}? Esta acción no se puede deshacer.\n\n'
                                  'Solo se eliminan celdas que nunca se han usado. Si la celda tiene historial '
                                  '(asignaciones o entradas), desactívela en su lugar.',
                              danger: true,
                              ok: 'Eliminar')) {
                            if (!context.mounted) return;
                            await runAction(context, () => session.api.delete('/spots/${asInt(s['id'])}'),
                                success: 'Celda ${asStr(s['code'])} eliminada');
                            reload();
                          }
                        },
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _manualAssign(BuildContext context, Map<String, dynamic> spot) async {
    final cycles = asList(await session.api.get('/cycles'));
    final open = cycles.where((c) => asStr(c['status']) != 'cerrado').toList();
    if (open.isEmpty) {
      if (context.mounted) showSnack(context, 'No hay ciclos activos o planeados', error: true);
      return;
    }
    if (!context.mounted) return;
    final active = open.firstWhere((c) => asStr(c['status']) == 'activo', orElse: () => open.first);
    final resident = await pickResident(context, title: 'Asignar celda ${asStr(spot['code'])} (${asStr(active['name'])})');
    if (resident == null || !context.mounted) return;
    final body = {
      'cycle_id': asInt(active['id']),
      'resident_id': asInt(resident['id']),
      'parking_spot_id': asInt(spot['id']),
      'notes': 'Asignación manual desde el mapa',
    };
    final ok = 'Celda ${asStr(spot['code'])} asignada a ${asStr(resident['full_name'])}';
    try {
      await session.api.post('/assignments', body);
      if (context.mounted) showSnack(context, ok);
    } on ApiException catch (e) {
      if (!context.mounted) return;
      final details = e.details;
      if (e.status == 409 && details is Map && details['code'] == 'ciclo_anterior') {
        // Usó el parqueadero en el ciclo anterior: solo se asigna como excepción, con motivo
        final reason = await _exceptionReason(context, e.message);
        if (reason == null || !context.mounted) return;
        await runAction(context, () => session.api.post('/assignments', {...body, 'force': true, 'reason': reason}),
            success: '$ok (excepción registrada en la auditoría)');
      } else {
        showSnack(context, e.message, error: true);
      }
    }
  }

  /// Pide el motivo de una excepción a la regla del ciclo anterior. Devuelve null si se cancela.
  Future<String?> _exceptionReason(BuildContext context, String message) async {
    final reason = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, color: AppColors.amber, size: 40),
          title: const Text('Usó el parqueadero en el ciclo anterior'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                const SizedBox(height: 12),
                TextField(
                  controller: reason,
                  autofocus: true,
                  maxLines: 2,
                  decoration: inputDeco('Motivo de la excepción', hint: 'Ej.: condición médica, orden de la administración'),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('No asignar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.amber),
              onPressed: reason.text.trim().isEmpty ? null : () => Navigator.pop(ctx, reason.text.trim()),
              child: const Text('Asignar como excepción'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _deleteSpotsDialog(BuildContext context) async {
    final prefix = TextEditingController(text: 'D');
    final from = TextEditingController(text: '1');
    final to = TextEditingController(text: '10');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar celdas'),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Se eliminan las celdas del rango que nunca se han usado. Las que tengan '
                  'asignaciones o entradas registradas se conservan (puede desactivarlas desde el mapa).'),
              const SizedBox(height: 12),
              TextField(controller: prefix, decoration: inputDeco('Prefijo (letra)')),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                      child: TextField(
                          controller: from, keyboardType: TextInputType.number, decoration: inputDeco('Desde'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: TextField(
                          controller: to, keyboardType: TextInputType.number, decoration: inputDeco('Hasta'))),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return false;
    final res = await runAction(
      context,
      () => session.api.post('/spots/bulk-delete', {
        'prefix': prefix.text,
        'from': int.tryParse(from.text) ?? 0,
        'to': int.tryParse(to.text) ?? 0,
      }),
    );
    if (res != null && context.mounted) {
      final m = asMap(res);
      final kept = asInt(m['kept']);
      showSnack(
          context,
          'Celdas eliminadas: ${asInt(m['deleted'])}'
          '${kept > 0 ? ' · $kept se conservaron porque tienen historial' : ''}');
    }
    return res != null;
  }

  Future<bool> _addSpotsDialog(BuildContext context) async {
    final prefix = TextEditingController(text: 'D');
    final from = TextEditingController(text: '1');
    final to = TextEditingController(text: '10');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Agregar celdas'),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Se crean las celdas del rango (las que ya existan se omiten). Ej: D01 a D50.'),
              const SizedBox(height: 12),
              TextField(controller: prefix, decoration: inputDeco('Prefijo (letra)')),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                      child: TextField(
                          controller: from, keyboardType: TextInputType.number, decoration: inputDeco('Desde'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: TextField(
                          controller: to, keyboardType: TextInputType.number, decoration: inputDeco('Hasta'))),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Crear')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return false;
    final res = await runAction(
      context,
      () => session.api.post('/spots/bulk', {
        'prefix': prefix.text,
        'from': int.tryParse(from.text) ?? 0,
        'to': int.tryParse(to.text) ?? 0,
      }),
    );
    if (res != null && context.mounted) showSnack(context, 'Celdas creadas: ${asInt(asMap(res)['created'])}');
    return res != null;
  }
}

/// Celda del mapa. Al pasar el cursor se agranda un poco, se ilumina con el
/// color de su estado y muestra un globo con el detalle.
class _SpotTile extends StatefulWidget {
  const _SpotTile({required this.spot, this.onTap});

  final Map<String, dynamic> spot;
  final VoidCallback? onTap;

  @override
  State<_SpotTile> createState() => _SpotTileState();
}

class _SpotTileState extends State<_SpotTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final spot = widget.spot;
    final style = SpotStyle.of(asStr(spot['state']));
    final mine = asBool(spot['mine']);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final card = Theme.of(context).cardColor;
    const duration = Duration(milliseconds: 180);

    // Fondo: suave en modo claro, tinte del color del estado en modo oscuro
    final Color bg = dark
        ? Color.alphaBlend(style.color.withAlpha(_hover ? 80 : 45), card)
        : (_hover ? Color.alphaBlend(style.color.withAlpha(45), style.soft) : style.soft);
    final Color textColor = dark ? Colors.white.withAlpha(230) : AppColors.text;
    final Color borderColor = mine ? AppColors.blueLight : style.color;
    final plate = spot['plate'] != null ? asStr(spot['plate']) : null;
    final tip = '${asStr(spot['code'])} · ${style.label}${plate != null ? ' · $plate' : ''}'
        '${asBool(spot['is_disabled_spot']) ? ' · Discapacidad' : ''}';
    final radius = BorderRadius.circular(AppRadius.tile);

    return Tooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 400),
      child: AnimatedScale(
        scale: _hover ? 1.05 : 1,
        duration: duration,
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: duration,
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: radius,
            border: Border.all(color: borderColor, width: mine ? 3 : (_hover ? 2.5 : 1.5)),
            boxShadow: _hover
                ? [BoxShadow(color: style.color.withAlpha(dark ? 110 : 90), blurRadius: 18, offset: const Offset(0, 6))]
                : const [],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              hoverColor: Colors.transparent,
              splashColor: style.color.withAlpha(60),
              onHover: (h) => setState(() => _hover = h),
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(asStr(spot['code']),
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: style.color)),
                        if (asBool(spot['is_disabled_spot']))
                          Padding(
                            padding: const EdgeInsets.only(left: 2),
                            child: Icon(Icons.accessible, size: 16, color: dark ? AppColors.blueLight : AppColors.blue),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    AnimatedScale(
                      scale: _hover ? 1.2 : 1,
                      duration: duration,
                      curve: Curves.easeOutBack,
                      child: Icon(style.icon, color: style.color),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      mine ? 'SU CELDA' : (plate ?? style.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
