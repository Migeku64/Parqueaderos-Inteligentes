import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/session.dart';
import '../../widgets/common.dart';
import '../guard/access_control_screen.dart' show movementTile;

/// Historial de entradas y salidas con filtros.
class MovementsScreen extends StatefulWidget {
  const MovementsScreen({super.key, this.initialFilter});

  /// Filtro con el que se abre: todos, autorizados o rechazados (siempre del día de hoy)
  final String? initialFilter;

  @override
  State<MovementsScreen> createState() => _MovementsScreenState();
}

class _MovementsScreenState extends State<MovementsScreen> {
  String _plate = '';
  late String _filter = widget.initialFilter ?? 'todos';
  // Rango de fechas como en Reportes (Desde / Hasta). Se abre con el día de hoy.
  DateTime? _from = DateTime.now();
  DateTime? _to = DateTime.now();

  Future<void> _pick(bool from) async {
    final d = await showDatePicker(
      context: context,
      initialDate: (from ? _from : _to) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d == null) return;
    setState(() {
      if (from) {
        _from = d;
        if (_to != null && _to!.isBefore(d)) _to = d;
      } else {
        _to = d;
        if (_from != null && _from!.isAfter(d)) _from = d;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = <String, dynamic>{
      'plate': _plate,
      'limit': 500,
      if (_from != null) 'from': isoDate(_from!),
      if (_to != null) 'to': isoDate(_to!),
      if (_filter == 'rechazados') 'authorized': 'false',
      if (_filter == 'autorizados') 'authorized': 'true',
    };
    return Column(
      children: [
        const PageHeader(title: 'Entradas y salidas', subtitle: 'Registro histórico de movimientos'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
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
              for (final f in const ['todos', 'autorizados', 'rechazados'])
                ChoiceChip(
                  label: Text(f[0].toUpperCase() + f.substring(1)),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ),
              SizedBox(
                width: 340,
                child: TextField(
                  decoration: inputDeco('Buscar placa', icon: Icons.search),
                  onSubmitted: (v) => setState(() => _plate = normalizePlate(v)),
                  onChanged: (v) {
                    if (v.isEmpty) setState(() => _plate = '');
                  },
                ),
              ),
              if (_from != null || _to != null)
                TextButton(
                  onPressed: () => setState(() {
                    _from = null;
                    _to = null;
                  }),
                  child: const Text('Todas las fechas'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Loader<List<Map<String, dynamic>>>(
            key: ValueKey(query.toString()),
            load: () async => asList(await session.api.get('/movements', query: query)),
            reloadOn: const {'movement'},
            builder: (context, list, reload) => list.isEmpty
                ? const EmptyView(message: 'No hay movimientos con estos filtros')
                : RefreshIndicator(
                    onRefresh: reload,
                    child: ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => Builder(
                        builder: (context) => Container(color: Theme.of(context).cardColor, child: movementTile(list[i])),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
