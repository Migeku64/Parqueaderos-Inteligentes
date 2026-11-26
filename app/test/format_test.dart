import 'package:flutter_test/flutter_test.dart';
import 'package:parqueadero_app/core/format.dart';

void main() {
  test('formatea dinero en pesos', () {
    expect(fmtMoney(150000), '\$150.000');
    expect(fmtMoney('85000.00'), '\$85.000');
    expect(fmtMoney(0), '\$0');
  });

  test('normaliza placas', () {
    expect(normalizePlate('abc-123'), 'ABC123');
    expect(normalizePlate(' klm 12f '), 'KLM12F');
  });

  test('fechas en español', () {
    expect(fmtDate('2026-04-29'), '29/04/2026');
    expect(fmtLongDate('2026-04-29'), 'miércoles, 29 de abril de 2026');
    expect(isoDate(DateTime(2026, 1, 5)), '2026-01-05');
    // Cuenta regresiva hasta el sorteo
    final hoy = DateTime(2026, 11, 26, 15, 30);
    expect(countdown('2026-11-26', hoy), 'Es hoy');
    expect(countdown('2026-11-27', hoy), 'Falta 1 día');
    expect(countdown('2026-12-01', hoy), 'Faltan 5 días');
    expect(countdown('2026-11-20', hoy), isNull);
  });

  test('valores vacíos y nombres de rol', () {
    expect(fmtDate(null), '—');
    expect(fmtDateTime(''), '—');
    expect(roleLabel('guarda'), 'Guarda de seguridad');
    expect(roleLabel('residente'), 'Residente');
    expect(fmtMoney(-2500), '-\$2.500');
  });

  test('lectura segura de JSON', () {
    expect(asInt('14.000'), 14);
    expect(asDouble('14.500'), 14.5);
    expect(asBool(true), isTrue);
    expect(asList(null), isEmpty);
  });
}
