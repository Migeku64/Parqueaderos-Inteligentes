import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/session.dart';
import '../../widgets/common.dart';
import '../guard/access_control_screen.dart' show movementTile;

/// Historial de entradas y salidas con filtros.
class MovementsScreen extends StatefulWidget {
  const MovementsScreen({super.key});

  @override
  State<MovementsScreen> createState() => _MovementsScreenState();
}

class _MovementsScreenState extends State<MovementsScreen> {
  String _plate = '';
  String _filter = 'todos';
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
              SizedBox(
                width: 200,
                child: TextField(
                  decoration: inputDeco('Placa', icon: Icons.search),
                  onSubmitted: (v) => setState(() => _plate = normalizePlate(v)),
                  onChanged: (v) {
                    if (v.isEmpty) setState(() => _plate = '');
                  },
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text(_allDays ? 'Todas las fechas' : fmtDate(isoDate(_day))),
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
              ),
              FilterChip(
                label: const Text('Todas las fechas'),
                selected: _allDays,
                onSelected: (v) => setState(() => _allDays = v),
              ),
              for (final f in const ['todos', 'autorizados', 'rechazados'])
                ChoiceChip(
                  label: Text(f[0].toUpperCase() + f.substring(1)),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
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
                      itemBuilder: (context, i) => Container(color: Colors.white, child: movementTile(list[i])),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
