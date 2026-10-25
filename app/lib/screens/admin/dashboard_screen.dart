import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Dashboard administrativo (RF14): ocupación, ciclo activo, movimientos del día.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Loader<Map<String, dynamic>>(
      load: () async => asMap(await session.api.get('/dashboard')),
      reloadOn: const {'spots', 'movement', 'assignments'},
      builder: (context, d, reload) {
        final spots = asMap(d['spots']);
        final today = asMap(d['today']);
        final residents = asMap(d['residents']);
        final active = d['active_cycle'] == null ? null : asMap(d['active_cycle']);
        final next = d['next_cycle'] == null ? null : asMap(d['next_cycle']);
        final week = asList(d['entries_last_7_days']);
        final recent = asList(d['recent_movements']);
        final wide = MediaQuery.of(context).size.width >= 700;

        final cards = [
          StatCard(
            label: 'Celdas libres',
            value: '${asInt(spots['free'])} / ${asInt(spots['total'])}',
            icon: Icons.local_parking,
            color: AppColors.green,
            footnote: 'Ocupación ${asInt(d['occupancy_rate'])}%',
          ),
          StatCard(
            label: 'Vehículos dentro',
            value: '${asInt(spots['occupied'])}',
            icon: Icons.directions_car,
            color: AppColors.red,
          ),
          StatCard(
            label: 'Entradas hoy',
            value: '${asInt(today['entries'])}',
            icon: Icons.login,
            color: AppColors.blue,
            footnote: '${asInt(today['exits'])} salidas',
          ),
          StatCard(
            label: 'Ingresos rechazados hoy',
            value: '${asInt(today['rejected'])}',
            icon: Icons.gpp_bad_outlined,
            color: AppColors.amber,
          ),
        ];

        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              const PageHeader(title: 'Panel de administración', subtitle: 'Resumen en tiempo real'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: GridView.count(
                  crossAxisCount: wide ? 4 : 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: wide ? 2.2 : 1.15,
                  children: cards,
                ),
              ),
              SectionCard(
                title: 'Ciclo actual',
                child: active == null
                    ? const Text('No hay un ciclo activo. Cree y active uno en "Ciclos y sorteos".')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(asStr(active['name']),
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                              ),
                              const Pill('ACTIVO', color: AppColors.green),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('Del ${fmtDate(active['start_date'])} al ${fmtDate(active['end_date'])}'),
                          const SizedBox(height: 10),
                          _progress(active),
                          const SizedBox(height: 8),
                          Text('${asInt(active['assigned'])} celdas asignadas · '
                              '${asInt(residents['active'])} residentes activos · '
                              '${asInt(residents['with_debt'])} con deuda'),
                          if (next != null) ...[
                            const Divider(height: 24),
                            Text(
                              'Próximo ciclo: ${asStr(next['name'])} · sorteo ${fmtLongDate(next['draw_date'])}',
                              style: const TextStyle(color: AppColors.muted),
                            ),
                          ],
                        ],
                      ),
              ),
              SectionCard(
                title: 'Entradas de los últimos 7 días',
                child: SizedBox(height: 140, child: _WeekChart(week)),
              ),
              SectionCard(
                title: 'Últimos movimientos',
                padding: 8,
                child: recent.isEmpty
                    ? const Padding(padding: EdgeInsets.all(12), child: Text('Sin movimientos registrados'))
                    : Column(
                        children: [
                          for (final m in recent)
                            ListTile(
                              dense: true,
                              leading: Icon(
                                asStr(m['type']) == 'entrada' ? Icons.login : Icons.logout,
                                color: asBool(m['authorized']) ? AppColors.blue : AppColors.red,
                              ),
                              title: Row(children: [PlateBadge(asStr(m['plate']))]),
                              subtitle: Text(asBool(m['authorized'])
                                  ? '${asStr(m['type'])} · celda ${asStr(m['spot_code'], '—')}'
                                  : 'Rechazado: ${asStr(m['reason'])}'),
                              trailing: Text(fmtTime(m['recorded_at'])),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _progress(Map<String, dynamic> c) {
    final start = parseDate(c['start_date']);
    final end = parseDate(c['end_date']);
    if (start == null || end == null) return const SizedBox.shrink();
    final total = end.difference(start).inDays;
    final done = DateTime.now().difference(start).inDays.clamp(0, total);
    final left = total - done;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : done / total,
            minHeight: 10,
            backgroundColor: AppColors.greySoft,
            color: left <= 7 ? AppColors.amber : AppColors.blue,
          ),
        ),
        const SizedBox(height: 4),
        Text('Quedan $left días', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
      ],
    );
  }
}

/// Gráfico de barras simple (sin paquetes externos).
class _WeekChart extends StatelessWidget {
  const _WeekChart(this.days);

  final List<Map<String, dynamic>> days;

  static const _names = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    final maxV = days.fold<int>(1, (m, d) => asInt(d['entries']) > m ? asInt(d['entries']) : m);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final d in days)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('${asInt(d['entries'])}', style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  Flexible(
                    child: FractionallySizedBox(
                      heightFactor: asInt(d['entries']) / maxV,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.blueLight,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _names[(parseDate(d['day'])?.weekday ?? 1) - 1],
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
