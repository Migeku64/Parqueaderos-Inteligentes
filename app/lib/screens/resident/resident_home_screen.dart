import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

Future<Map<String, dynamic>> loadMySummary() async => asMap(await session.api.get('/me/summary'));

/// Pantalla principal del residente (mockup "Menú principal").
class ResidentHomeScreen extends StatelessWidget {
  const ResidentHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Loader<Map<String, dynamic>>(
      load: loadMySummary,
      reloadOn: const {'assignments', 'notification'},
      builder: (context, d, reload) {
        final r = asMap(d['resident']);
        final vehicles = asList(d['vehicles']);
        final current = d['current_assignment'] == null ? null : asMap(d['current_assignment']);
        final turn = asStr(d['turn_status'], 'INACTIVO');
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              MaxWidth(
                width: 640,
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: AppColors.blue, borderRadius: BorderRadius.circular(18)),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const BrandLogo(size: 56),
                          const Spacer(),
                          Text('RESIDENTE',
                              style: TextStyle(
                                  color: Colors.white.withAlpha(230), fontWeight: FontWeight.w900, fontSize: 18)),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        asStr(r['full_name']).toUpperCase(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 16),
                      _row('ESTADO', asStr(r['status']) == 'activo' ? 'RESIDENTE' : 'INACTIVO'),
                      _row('CASA', asStr(r['house'])),
                      _row('TURNO', turn,
                          valueColor: turn == 'ACTIVO'
                              ? AppColors.green
                              : turn == 'PRÓXIMO'
                                  ? AppColors.amber
                                  : null),
                      if (current != null) _row('CELDA', asStr(current['spot_code']), valueColor: AppColors.green),
                      if (asDouble(r['debt']) > 0)
                        _row('DEUDA', fmtMoney(r['debt']), valueColor: AppColors.redSoft),
                    ],
                  ),
                ),
              ),
              MaxWidth(
                width: 640,
                child: SectionCard(
                  title: 'AUTOMÓVIL',
                  child: vehicles.isEmpty
                      ? const Text('No tiene vehículos registrados. Acérquese a la administración para registrarlo; '
                          'sin vehículo no puede participar en el sorteo.')
                      : Column(
                          children: [
                            for (final v in vehicles)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  children: [
                                    Icon(asStr(v['type']) == 'moto' ? Icons.two_wheeler : Icons.directions_car_filled,
                                        size: 56, color: AppColors.red),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            [asStr(v['brand']), asStr(v['model'])].where((e) => e.isNotEmpty).join(' ').isEmpty
                                                ? asStr(v['type']).toUpperCase()
                                                : [asStr(v['brand']), asStr(v['model'])]
                                                    .where((e) => e.isNotEmpty)
                                                    .join(' '),
                                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                                          ),
                                          const SizedBox(height: 6),
                                          PlateBadge(asStr(v['plate'])),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                ),
              ),
              if (current != null)
                MaxWidth(
                  width: 640,
                  child: SectionCard(
                    title: 'Mi parqueadero',
                    child: Text('Tiene asignada la celda ${asStr(current['spot_code'])} en el '
                        '${asStr(current['cycle_name'])}, hasta el ${fmtLongDate(current['end_date'])}.'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(String label, String value, {Color? valueColor}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                color: valueColor ?? const Color(0xFFDADADA),
                child: Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black)),
              ),
            ),
          ],
        ),
      );
}
