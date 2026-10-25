import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Ayuda para residentes (mockup "Ayuda").
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const _faq = [
    (
      '¿Cómo se asignan los parqueaderos?',
      'Por ciclos de 2 a 6 meses. Antes de cada ciclo se hace un sorteo entre los residentes que cumplen los '
          'requisitos. El sistema calcula un Índice de Prioridad (IPA) para que quien más ha esperado tenga más '
          'oportunidad.'
    ),
    (
      '¿Qué necesito para participar en el sorteo?',
      '1) Estar al día con la administración.\n2) Tener un vehículo registrado.\n'
          '3) No haber usado el parqueadero en el ciclo anterior.'
    ),
    (
      '¿Qué es el IPA?',
      'IPA = (Te + Pa + Hn) / (Cu + 1). Te es el tiempo de espera en meses, Pa el puntaje administrativo, '
          'Hn los ciclos recientes sin parqueadero y Cu los ciclos que ya ha usado. Puede ver su IPA en "Sorteos".'
    ),
    (
      '¿Cómo entro al parqueadero?',
      'El guarda registra su placa al ingresar. Si tiene celda asignada en el ciclo actual, el sistema autoriza '
          'la entrada y le indica su celda. Al salir, el guarda registra la salida.'
    ),
    (
      'Cambié de carro, ¿qué hago?',
      'Acérquese a la administración para actualizar la placa. Sin el vehículo registrado el sistema no '
          'autoriza el ingreso.'
    ),
    (
      'Olvidé mi contraseña',
      'En la pantalla de inicio pulse "¿Olvidó su contraseña?". La administración recibirá la solicitud y le '
          'entregará una contraseña temporal.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return MaxWidth(
      width: 760,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const PageHeader(title: 'Ayuda', subtitle: 'Preguntas frecuentes sobre el parqueadero comunitario'),
          for (final f in _faq)
            SectionCard(
              padding: 4,
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  leading: const Icon(Icons.help_outline, color: AppColors.blue),
                  title: Text(f.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text(f.$2)],
                ),
              ),
            ),
          const SectionCard(
            title: 'Contacto',
            child: Text('Administración Conjunto Residencial Nueva Castilla Etapa 3.\n'
                'Portería: atención 24 horas.'),
          ),
        ],
      ),
    );
  }
}
