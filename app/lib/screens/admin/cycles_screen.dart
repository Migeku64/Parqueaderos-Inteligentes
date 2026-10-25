import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

Color cycleColor(String status) => status == 'activo'
    ? AppColors.green
    : status == 'planeado'
        ? AppColors.blue
        : AppColors.grey;

/// Ciclos de rotación (RF17) y sorteos (RF03).
class CyclesScreen extends StatefulWidget {
  const CyclesScreen({super.key});

  @override
  State<CyclesScreen> createState() => _CyclesScreenState();
}

class _CyclesScreenState extends State<CyclesScreen> {
  int _version = 0;

  void _refresh() => setState(() => _version++);

  @override
  Widget build(BuildContext context) {
    return Loader<List<Map<String, dynamic>>>(
      key: ValueKey(_version),
      load: () async => asList(await session.api.get('/cycles')),
      reloadOn: const {'assignments'},
      builder: (context, cycles, reload) => RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            PageHeader(
              title: 'Ciclos y sorteos',
              subtitle: 'Cada ciclo dura de 2 a 6 meses. Quien usó el parqueadero en el ciclo anterior no participa.',
              actions: [
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Nuevo ciclo'),
                  onPressed: () async {
                    if (await showCycleForm(context, cycles: cycles)) _refresh();
                  },
                ),
              ],
            ),
            const _IpaExplanation(),
            if (cycles.isEmpty) const EmptyView(message: 'Aún no hay ciclos. Cree el primero.'),
            for (final c in cycles) _CycleCard(cycle: c, onChanged: _refresh),
          ],
        ),
      ),
    );
  }
}

class _IpaExplanation extends StatelessWidget {
  const _IpaExplanation();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: const ExpansionTile(
          tilePadding: EdgeInsets.zero,
          leading: Icon(Icons.functions, color: AppColors.blue),
          title: Text('¿Cómo funciona el sorteo? Índice de Prioridad de Asignación (IPA)'),
          childrenPadding: EdgeInsets.only(bottom: 8),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text('IPA = (Te + Pa + Hn) / (Cu + 1)',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
            ),
            SizedBox(height: 10),
            Text('• Te: meses de espera desde su último uso del parqueadero (máx. 24).'),
            Text('• Pa: puntaje administrativo de 0 a 5 que asigna la administración.'),
            Text('• Hn: de los últimos 6 ciclos, en cuántos NO tuvo parqueadero.'),
            Text('• Cu: cantidad de ciclos en los que ya ha usado el parqueadero.'),
            SizedBox(height: 8),
            Text('Requisitos: estar al día con la administración, tener vehículo registrado y no haber '
                'usado el parqueadero en el ciclo anterior. Las celdas para discapacidad se asignan primero '
                'a quienes las requieren.'),
            SizedBox(height: 8),
            Text('Modo "ponderado": rifa donde la probabilidad es proporcional al IPA + 1. '
                'Modo "prioridad": se asigna en orden de IPA (empates al azar).'),
          ],
        ),
      ),
    );
  }
}

class _CycleCard extends StatelessWidget {
  const _CycleCard({required this.cycle, required this.onChanged});

  final Map<String, dynamic> cycle;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final status = asStr(cycle['status']);
    final color = cycleColor(status);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(asStr(cycle['name']), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              Pill(status.toUpperCase(), color: color),
            ],
          ),
          const SizedBox(height: 4),
          Text('Del ${fmtDate(cycle['start_date'])} al ${fmtDate(cycle['end_date'])}'
              '${cycle['draw_date'] != null ? ' · Sorteo: ${fmtDate(cycle['draw_date'])}' : ''}'),
          Text('${asInt(cycle['assignments'])} asignaciones', style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.list_alt),
                label: const Text('Asignaciones'),
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => CycleDetailScreen(cycleId: asInt(cycle['id'])),
                  ));
                  onChanged();
                },
              ),
              if (status != 'cerrado')
                FilledButton.icon(
                  icon: const Icon(Icons.casino),
                  label: const Text('Sorteo'),
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DrawScreen(cycle: cycle)));
                    onChanged();
                  },
                ),
              if (status == 'planeado')
                OutlinedButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Activar'),
                  onPressed: () async {
                    if (await confirm(context, 'Activar ciclo',
                        'Las asignaciones de este ciclo quedarán vigentes y los residentes serán notificados.')) {
                      if (!context.mounted) return;
                      final r = await runAction(context, () => session.api.post('/cycles/${asInt(cycle['id'])}/activate'),
                          success: 'Ciclo activado');
                      if (r != null) onChanged();
                    }
                  },
                ),
              if (status != 'cerrado')
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit_calendar),
                  label: const Text('Editar'),
                  onPressed: () async {
                    if (await showCycleForm(context, existing: cycle)) onChanged();
                  },
                ),
              if (status == 'activo')
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.red),
                  icon: const Icon(Icons.autorenew),
                  label: const Text('Finalizar ciclo'),
                  onPressed: () async {
                    if (await confirm(
                        context,
                        'Finalizar ciclo',
                        'Se liberarán todas las asignaciones vigentes y se notificará a los residentes. '
                            'Esta acción no se puede deshacer.',
                        danger: true,
                        ok: 'Finalizar')) {
                      if (!context.mounted) return;
                      final r = await runAction(context, () => session.api.post('/cycles/${asInt(cycle['id'])}/close'),
                          success: 'Ciclo finalizado');
                      if (r != null) onChanged();
                    }
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<DateTime?> _pickDate(BuildContext context, DateTime? initial) => showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Seleccione la fecha',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );

DateTime _addMonths(DateTime d, int m) => DateTime(d.year, d.month + m, d.day);

/// Crear / editar ciclo.
Future<bool> showCycleForm(BuildContext context,
    {Map<String, dynamic>? existing, List<Map<String, dynamic>> cycles = const []}) async {
  DateTime start;
  if (existing != null) {
    start = parseDate(existing['start_date']) ?? DateTime.now();
  } else {
    // Por defecto: empieza cuando termina el último ciclo
    final ends = cycles.map((c) => parseDate(c['end_date'])).whereType<DateTime>().toList()..sort();
    start = ends.isNotEmpty && ends.last.isAfter(DateTime.now()) ? ends.last : DateTime.now();
    start = DateTime(start.year, start.month, start.day);
  }
  DateTime end = existing != null ? (parseDate(existing['end_date']) ?? _addMonths(start, 4)) : _addMonths(start, 4);
  DateTime? draw = existing != null ? parseDate(existing['draw_date']) : start.subtract(const Duration(days: 7));
  final name = TextEditingController(
      text: existing != null ? asStr(existing['name']) : 'Ciclo ${start.year}-${two(start.month)}');
  String? error;
  bool saved = false;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        Widget dateRow(String label, DateTime? value, ValueChanged<DateTime> onPick) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(label),
              subtitle: Text(value == null ? 'Sin definir' : fmtLongDate(isoDate(value))),
              trailing: const Icon(Icons.edit),
              onTap: () async {
                final d = await _pickDate(ctx, value);
                if (d != null) setState(() => onPick(d));
              },
            );
        return AlertDialog(
          title: Text(existing == null ? 'Nuevo ciclo' : 'Editar ciclo'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: inputDeco('Nombre del ciclo')),
                const SizedBox(height: 8),
                dateRow('Inicio', start, (d) => start = d),
                dateRow('Fin', end, (d) => end = d),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final m in const [2, 3, 4, 6])
                      ActionChip(
                        label: Text('$m meses'),
                        onPressed: () => setState(() => end = _addMonths(start, m)),
                      ),
                  ],
                ),
                dateRow('Fecha del sorteo', draw, (d) => draw = d),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error!, style: const TextStyle(color: AppColors.red)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                final body = {
                  'name': name.text.trim(),
                  'start_date': isoDate(start),
                  'end_date': isoDate(end),
                  'draw_date': draw == null ? null : isoDate(draw!),
                };
                try {
                  if (existing == null) {
                    await session.api.post('/cycles', body);
                  } else {
                    await session.api.patch('/cycles/${asInt(existing['id'])}', body);
                  }
                  saved = true;
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  setState(() => error = e.toString());
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    ),
  );
  if (saved && context.mounted) showSnack(context, 'Ciclo guardado');
  return saved;
}

/// Asignaciones de un ciclo.
class CycleDetailScreen extends StatelessWidget {
  const CycleDetailScreen({super.key, required this.cycleId});

  final int cycleId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Asignaciones del ciclo'), backgroundColor: AppColors.blue, foregroundColor: Colors.white),
      body: Loader<Map<String, dynamic>>(
        load: () async => asMap(await session.api.get('/cycles/$cycleId')),
        reloadOn: const {'assignments'},
        builder: (context, c, reload) {
          final list = asList(c['assignment_list']);
          return MaxWidth(
            child: ListView(
              children: [
                PageHeader(
                  title: asStr(c['name']),
                  subtitle: 'Del ${fmtDate(c['start_date'])} al ${fmtDate(c['end_date'])} · ${asStr(c['status'])}',
                ),
                if (list.isEmpty) const EmptyView(message: 'Este ciclo no tiene asignaciones. Ejecute el sorteo.'),
                for (final a in list)
                  Card(
                    elevation: 0,
                    color: Colors.white,
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: asStr(a['status']) == 'vigente' ? AppColors.greenSoft : AppColors.greySoft,
                        child: Text(asStr(a['spot_code']),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.text)),
                      ),
                      title: Text('${asStr(a['full_name'])} · Casa ${asStr(a['house'])}'),
                      subtitle: Text('${asStr(a['plate'])} · ${asStr(a['method'])}'
                          '${a['ipa_score'] != null ? ' · IPA ${asDouble(a['ipa_score']).toStringAsFixed(2)}' : ''}'
                          ' · ${asStr(a['status'])}'),
                      trailing: asStr(a['status']) == 'vigente' && asStr(c['status']) != 'cerrado'
                          ? IconButton(
                              tooltip: 'Cancelar asignación',
                              icon: const Icon(Icons.cancel_outlined, color: AppColors.red),
                              onPressed: () async {
                                if (await confirm(context, 'Cancelar asignación',
                                    '¿Cancelar la celda ${asStr(a['spot_code'])} de ${asStr(a['full_name'])}?',
                                    danger: true, ok: 'Cancelar asignación')) {
                                  if (!context.mounted) return;
                                  await runAction(context,
                                      () => session.api.post('/assignments/${asInt(a['id'])}/cancel', {}),
                                      success: 'Asignación cancelada');
                                  reload();
                                }
                              },
                            )
                          : null,
                    ),
                  ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Sorteo: simular, revisar (y ajustar) y confirmar (UC-04).
class DrawScreen extends StatefulWidget {
  const DrawScreen({super.key, required this.cycle});

  final Map<String, dynamic> cycle;

  @override
  State<DrawScreen> createState() => _DrawScreenState();
}

class _DrawScreenState extends State<DrawScreen> {
  String _mode = 'ponderado';
  bool _busy = false;
  Map<String, dynamic>? _preview;
  List<Map<String, dynamic>> _proposal = [];
  Map<String, dynamic>? _result;

  int get _cycleId => asInt(widget.cycle['id']);

  Future<void> _simulate() async {
    setState(() => _busy = true);
    final r = await runAction(context, () => session.api.post('/cycles/$_cycleId/draw/preview', {'mode': _mode}));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r != null) {
        _preview = asMap(r);
        _proposal = asList(_preview!['proposal']);
        _result = null;
      }
    });
  }

  Future<void> _confirm() async {
    if (_proposal.isEmpty) return;
    final ok = await confirm(
      context,
      'Confirmar sorteo',
      'Se guardarán ${_proposal.length} asignaciones y se notificará a los residentes. ¿Continuar?',
      ok: 'Confirmar',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final r = await runAction(
      context,
      () => session.api.post('/cycles/$_cycleId/draw', {
        'mode': _mode,
        'proposal': [
          for (final p in _proposal) {'resident_id': p['resident_id'], 'parking_spot_id': p['parking_spot_id']}
        ],
      }),
      success: 'Sorteo guardado',
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r != null) {
        _result = asMap(r);
        _preview = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final result = _result;
    return Scaffold(
      appBar: AppBar(
        title: Text('Sorteo · ${asStr(widget.cycle['name'])}'),
        backgroundColor: AppColors.blue,
        foregroundColor: Colors.white,
      ),
      body: MaxWidth(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            SectionCard(
              title: 'Modo de sorteo',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'ponderado', label: Text('Ponderado (rifa)'), icon: Icon(Icons.casino)),
                      ButtonSegment(value: 'prioridad', label: Text('Por prioridad'), icon: Icon(Icons.sort)),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) => setState(() => _mode = s.first),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : _simulate,
                        icon: const Icon(Icons.play_circle_outline),
                        label: Text(preview == null ? 'Simular sorteo' : 'Volver a sortear'),
                      ),
                      if (preview != null)
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: AppColors.green),
                          onPressed: _busy || _proposal.isEmpty ? null : _confirm,
                          icon: const Icon(Icons.check_circle_outline),
                          label: Text('Confirmar ${_proposal.length} asignaciones'),
                        ),
                    ],
                  ),
                  if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
                ],
              ),
            ),
            if (preview == null && result == null)
              const EmptyView(
                icon: Icons.casino_outlined,
                message: 'Pulse "Simular sorteo" para ver la propuesta. Nada se guarda hasta que la confirme.',
              ),
            if (preview != null) ..._previewWidgets(preview),
            if (result != null) ..._resultWidgets(result),
          ],
        ),
      ),
    );
  }

  List<Widget> _previewWidgets(Map<String, dynamic> p) {
    final waitlist = asList(p['waitlist']);
    final excluded = asList(p['excluded']);
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Wrap(
          children: [
            SizedBox(
                width: 250,
                child: StatCard(
                    label: 'Celdas disponibles', value: '${asInt(p['spots_available'])}', icon: Icons.local_parking)),
            SizedBox(
                width: 250,
                child: StatCard(
                    label: 'Residentes elegibles',
                    value: '${asInt(p['eligible_count'])}',
                    icon: Icons.how_to_reg,
                    color: AppColors.green)),
            SizedBox(
                width: 250,
                child: StatCard(
                    label: 'No elegibles', value: '${excluded.length}', icon: Icons.person_off, color: AppColors.red)),
          ],
        ),
      ),
      SectionCard(
        title: 'Propuesta de asignación (${_proposal.length})',
        padding: 8,
        child: _proposal.isEmpty
            ? const Padding(padding: EdgeInsets.all(8), child: Text('No hay asignaciones posibles.'))
            : Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Text('Puede quitar a alguien de la propuesta antes de confirmar (por ejemplo, si renunció).',
                        style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  ),
                  for (final a in _proposal)
                    ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        backgroundColor: AppColors.greenSoft,
                        child: Text(asStr(a['spot_code']),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.text)),
                      ),
                      title: Text('${asInt(a['position'])}. ${asStr(a['full_name'])} · Casa ${asStr(a['house'])}'),
                      subtitle: Text('${asStr(a['plate'])} · ${_ipaText(a)}'),
                      trailing: IconButton(
                        tooltip: 'Quitar de la propuesta',
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () => setState(() => _proposal.remove(a)),
                      ),
                    ),
                ],
              ),
      ),
      if (waitlist.isNotEmpty)
        SectionCard(
          title: 'Lista de espera (${waitlist.length})',
          padding: 8,
          child: Column(
            children: [
              for (final w in waitlist)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.hourglass_empty, color: AppColors.amber),
                  title: Text('${asStr(w['full_name'])} · Casa ${asStr(w['house'])}'),
                  subtitle: Text(_ipaText(w)),
                ),
            ],
          ),
        ),
      if (excluded.isNotEmpty)
        SectionCard(
          padding: 8,
          child: ExpansionTile(
            title: Text('No elegibles (${excluded.length})'),
            children: [
              for (final x in excluded)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.block, color: AppColors.red),
                  title: Text('${asStr(x['full_name'])} · Casa ${asStr(x['house'])}'),
                  subtitle: Text((x['reasons'] is List ? (x['reasons'] as List) : const []).join(' · ')),
                ),
            ],
          ),
        ),
    ];
  }

  String _ipaText(Map<String, dynamic> a) {
    final c = asMap(a['components']);
    return 'IPA ${asDouble(a['ipa']).toStringAsFixed(2)} '
        '(Te ${asInt(c['te'])}, Pa ${asInt(c['pa'])}, Hn ${asInt(c['hn'])}, Cu ${asInt(c['cu'])})';
  }

  List<Widget> _resultWidgets(Map<String, dynamic> r) {
    final assigned = asList(r['assigned']);
    return [
      SectionCard(
        title: 'Sorteo guardado: ${assigned.length} celdas asignadas',
        child: Column(
          children: [
            for (final a in assigned)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle, color: AppColors.green),
                title: Text('${asStr(a['spot_code'])} → ${asStr(a['full_name'])} (Casa ${asStr(a['house'])})'),
                subtitle: Text(asStr(a['plate'])),
              ),
            const SizedBox(height: 8),
            const Text('Los residentes fueron notificados. Si el ciclo está planeado, actívelo cuando comience.',
                style: TextStyle(color: AppColors.muted)),
          ],
        ),
      ),
    ];
  }
}
