import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../admin/residents_screen.dart' show pickResident;

/// Mapa de parqueaderos con disponibilidad en tiempo real (RF04, RF16).
class SpotsMapScreen extends StatefulWidget {
  const SpotsMapScreen({super.key});

  @override
  State<SpotsMapScreen> createState() => _SpotsMapScreenState();
}

class _SpotsMapScreenState extends State<SpotsMapScreen> {
  String _filter = 'todas';
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
    await runAction(
      context,
      () => session.api.post('/assignments', {
        'cycle_id': asInt(active['id']),
        'resident_id': asInt(resident['id']),
        'parking_spot_id': asInt(spot['id']),
        'notes': 'Asignación manual desde el mapa',
      }),
      success: 'Celda ${asStr(spot['code'])} asignada a ${asStr(resident['full_name'])}',
    );
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

class _SpotTile extends StatelessWidget {
  const _SpotTile({required this.spot, this.onTap});

  final Map<String, dynamic> spot;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = SpotStyle.of(asStr(spot['state']));
    final mine = asBool(spot['mine']);
    return Material(
      color: style.soft,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: mine ? AppColors.blue : style.color, width: mine ? 3 : 1.5),
          ),
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
                    const Padding(
                      padding: EdgeInsets.only(left: 2),
                      child: Icon(Icons.accessible, size: 16, color: AppColors.blue),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Icon(style.icon, color: style.color),
              const SizedBox(height: 4),
              Text(
                mine ? 'SU CELDA' : (spot['plate'] != null ? asStr(spot['plate']) : style.label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
