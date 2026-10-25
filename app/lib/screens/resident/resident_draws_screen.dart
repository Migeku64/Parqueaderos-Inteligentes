import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'resident_home_screen.dart' show loadMySummary;

/// Sorteos del residente (mockup "Sorteos"): turno actual, próximo sorteo, lote en uso,
/// prioridad estimada (IPA) e historial.
class ResidentDrawsScreen extends StatelessWidget {
  const ResidentDrawsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Loader<Map<String, dynamic>>(
      load: loadMySummary,
      reloadOn: const {'assignments', 'notification'},
      builder: (context, d, reload) {
        final current = d['current_assignment'] == null ? null : asMap(d['current_assignment']);
        final next = d['next_assignment'] == null ? null : asMap(d['next_assignment']);
        final priority = d['priority'] == null ? null : asMap(d['priority']);
        final history = asList(d['history']);
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
                      const Text('SORTEOS',
                          style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 16),
                      _title('TURNO ACTUAL'),
                      _box(turn, color: turn == 'ACTIVO' ? const Color(0xFF6BE04F) : const Color(0xFFDADADA)),
                      const SizedBox(height: 14),
                      _title('PRÓXIMO SORTEO'),
                      _box(d['next_draw_date'] == null ? 'Por definir' : fmtLongDate(d['next_draw_date']),
                          color: const Color(0xFFDADADA), size: 16),
                      const SizedBox(height: 14),
                      _title('LOTE EN USO'),
                      _box(current == null ? '—' : asStr(current['spot_code']),
                          color: current == null ? const Color(0xFFDADADA) : const Color(0xFF6BE04F), size: 30),
                      if (next != null) ...[
                        const SizedBox(height: 14),
                        _title('PRÓXIMO CICLO'),
                        _box('Celda ${asStr(next['spot_code'])} desde ${fmtDate(next['start_date'])}',
                            color: const Color(0xFFFFE08A), size: 16),
                      ],
                    ],
                  ),
                ),
              ),
              if (priority != null)
                MaxWidth(
                  width: 640,
                  child: SectionCard(
                    title: 'Mi prioridad para el próximo sorteo',
                    child: _priority(priority),
                  ),
                ),
              MaxWidth(
                width: 640,
                child: SectionCard(
                  title: 'Mi historial',
                  child: history.isEmpty
                      ? const Text('Todavía no ha tenido parqueadero asignado.')
                      : Column(
                          children: [
                            for (final h in history)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.greySoft,
                                  child: Text(asStr(h['spot_code']),
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                                ),
                                title: Text(asStr(h['cycle_name'])),
                                subtitle: Text('${fmtDate(h['start_date'])} – ${fmtDate(h['end_date'])}'),
                                trailing: Pill(asStr(h['status']),
                                    color: asStr(h['status']) == 'vigente' ? AppColors.green : AppColors.grey),
                              ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _priority(Map<String, dynamic> p) {
    final c = asMap(p['components']);
    final eligible = asBool(p['eligible']);
    final reasons = p['reasons'] is List ? (p['reasons'] as List).map((e) => e.toString()).toList() : <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(eligible ? Icons.check_circle : Icons.info_outline,
                color: eligible ? AppColors.green : AppColors.amber),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                eligible
                    ? 'Participa en el próximo sorteo. Posición estimada: ${asInt(p['position'])} de ${asInt(p['of'])}.'
                    : 'No participa en el próximo sorteo: ${reasons.join(', ').toLowerCase()}.',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        if (p['ipa'] != null) ...[
          const SizedBox(height: 12),
          Text('Índice de prioridad (IPA): ${asDouble(p['ipa']).toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Pill('Espera: ${asInt(c['te'])} meses'),
              Pill('Puntaje adm.: ${asInt(c['pa'])}'),
              Pill('Ciclos sin uso: ${asInt(c['hn'])}'),
              Pill('Ciclos usados: ${asInt(c['cu'])}'),
            ],
          ),
          const SizedBox(height: 8),
          const Text('IPA = (Te + Pa + Hn) / (Cu + 1). Mientras más tiempo espere, mayor es su prioridad.',
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ],
      ],
    );
  }

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
      );

  Widget _box(String text, {required Color color, double size = 20}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        color: color,
        alignment: Alignment.center,
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: size, color: Colors.black)),
      );
}
