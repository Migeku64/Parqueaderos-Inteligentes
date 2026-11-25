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
  DateTime _day = DateTime.now();
  bool _allDays = false;

  @override
  Widget build(BuildContext context) {
    final query = <String, dynamic>{
      'plate': _plate,
      'limit': 500,
      if (!_allDays) 'from': isoDate(_day),
      if (!_allDays) 'to': isoDate(_day),
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
              // Igual que en Usuarios: botones redondeados en una fila y el buscador al final.
              // La fecha nunca queda marcada; solo se marca Todos, Autorizados o Rechazados.
              InputChip(
                avatar: const Icon(Icons.event, size: 18),
                label: Text(_allDays ? 'Todas las fechas' : fmtDate(isoDate(_day))),
                tooltip: 'Elegir fecha',
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _day,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (d != null) {
                    setState(() {
                      _day = d;
                      _allDays = false;
                    });
                  }
                },
                // La X aparece solo con un día elegido y vuelve a todas las fechas
                onDeleted: _allDays ? null : () => setState(() => _allDays = true),
                deleteButtonTooltipMessage: 'Ver todas las fechas',
              ),
              for (final f in const ['todos', 'autorizados', 'rechazados'])
                ChoiceChip(
                  label: Text(f[0].toUpperCase() + f.substring(1)),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ),
              SizedBox(
                width: 220,
                child: TextField(
                  decoration: inputDeco('Buscar placa', icon: Icons.search),
                  onSubmitted: (v) => setState(() => _plate = normalizePlate(v)),
                  onChanged: (v) {
                    if (v.isEmpty) setState(() => _plate = '');
                  },
                ),
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
