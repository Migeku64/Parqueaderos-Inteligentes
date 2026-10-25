import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Reportes administrativos (RF08, UC-07) y exportación a CSV / Excel (RF19).
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  static const _types = {
    'ocupacion': 'Ocupación por celda',
    'ciclos': 'Cumplimiento de ciclos',
    'asignaciones': 'Historial de asignaciones',
    'movimientos': 'Entradas y salidas',
  };

  String _type = 'ocupacion';
  DateTime? _from;
  DateTime? _to;
  final _spot = TextEditingController();
  int _version = 0;

  Map<String, dynamic> get _query => {
        if (_from != null) 'from': isoDate(_from!),
        if (_to != null) 'to': isoDate(_to!),
        if (_spot.text.trim().isNotEmpty) 'spot': _spot.text.trim().toUpperCase(),
      };

  @override
  void dispose() {
    _spot.dispose();
    super.dispose();
  }

  Future<void> _pick(bool from) async {
    final d = await showDatePicker(
      context: context,
      initialDate: (from ? _from : _to) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    setState(() {
      if (from) {
        _from = d;
      } else {
        _to = d;
      }
      _version++;
    });
  }

  Future<void> _export() async {
    final csv = await runAction(context, () => session.api.getText('/reports/$_type', query: {..._query, 'format': 'csv'}));
    if (csv == null || !mounted) return;
    final name = 'reporte-$_type-${isoDate(DateTime.now())}.csv';
    try {
      Directory? dir;
      try {
        dir = await getDownloadsDirectory();
      } catch (_) {
        dir = null;
      }
      dir ??= await getApplicationDocumentsDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      await file.writeAsString(csv);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reporte exportado'),
          content: SelectableText('Se guardó el archivo (se abre con Excel):\n\n${file.path}'),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: csv));
                Navigator.pop(ctx);
                showSnack(context, 'Contenido copiado al portapapeles');
              },
              child: const Text('Copiar contenido'),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Listo')),
          ],
        ),
      );
    } catch (e) {
      await Clipboard.setData(ClipboardData(text: csv));
      if (mounted) showSnack(context, 'No se pudo guardar el archivo; el CSV se copió al portapapeles.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PageHeader(
          title: 'Reportes',
          subtitle: 'Seleccione el tipo de reporte y los filtros',
          actions: [
            FilledButton.icon(onPressed: _export, icon: const Icon(Icons.download), label: const Text('Exportar CSV')),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                child: LabeledDropdown<String>(
                  label: 'Tipo de reporte',
                  value: _type,
                  items: _types,
                  onChanged: (v) => setState(() => _type = v),
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text(_from == null ? 'Desde' : 'Desde ${fmtDate(isoDate(_from!))}'),
                onPressed: () => _pick(true),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text(_to == null ? 'Hasta' : 'Hasta ${fmtDate(isoDate(_to!))}'),
                onPressed: () => _pick(false),
              ),
              if (_type != 'ciclos')
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _spot,
                    decoration: inputDeco('Celda', hint: 'D25'),
                    onSubmitted: (_) => setState(() => _version++),
                  ),
                ),
              TextButton(
                onPressed: () => setState(() {
                  _from = null;
                  _to = null;
                  _spot.clear();
                  _version++;
                }),
                child: const Text('Limpiar filtros'),
              ),
              IconButton(
                  tooltip: 'Generar', onPressed: () => setState(() => _version++), icon: const Icon(Icons.refresh)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Loader<Map<String, dynamic>>(
            key: ValueKey('$_type#$_version#${_query.toString()}'),
            load: () async => asMap(await session.api.get('/reports/$_type', query: _query)),
            builder: (context, rep, reload) {
              final cols = asList(rep['columns']);
              final rows = asList(rep['rows']);
              if (rows.isEmpty) return const EmptyView(message: 'El reporte no tiene datos con estos filtros');
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Text('${asStr(rep['title'])} · ${rows.length} filas',
                        style: const TextStyle(color: AppColors.muted)),
                  ),
                  Expanded(
                    child: Card(
                      elevation: 0,
                      color: Colors.white,
                      margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: SingleChildScrollView(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: [
                              for (final c in cols)
                                DataColumn(
                                    label: Text(asStr(c['label']), style: const TextStyle(fontWeight: FontWeight.w700))),
                            ],
                            rows: [
                              for (final r in rows)
                                DataRow(cells: [
                                  for (final c in cols) DataCell(Text(_cell(asStr(c['key']), r[asStr(c['key'])]))),
                                ]),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  String _cell(String key, dynamic v) {
    if (v == null) return '—';
    if (key.endsWith('_at') || key == 'last_movement') return fmtDateTime(v);
    if (key.endsWith('_date')) return fmtDate(v);
    if (key == 'ipa_score') return asDouble(v).toStringAsFixed(2);
    return v.toString();
  }
}
