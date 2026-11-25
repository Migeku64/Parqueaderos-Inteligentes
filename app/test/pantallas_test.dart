import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parqueadero_app/widgets/common.dart';

/// Pruebas de las piezas de pantalla que cambian entre el PC y el celular.
void main() {
  testWidgets('tarjeta del Inicio en celular: muestra número, nombre y detalle', (tester) async {
    var tocada = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 170,
            child: StatCard(
              label: 'Ingresos rechazados hoy',
              value: '1',
              icon: Icons.gpp_bad_outlined,
              footnote: 'del día',
              compact: true,
              onTap: () => tocada = true,
            ),
          ),
        ),
      ),
    ));
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Ingresos rechazados hoy'), findsOneWidget);
    expect(find.text('del día'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    await tester.tap(find.text('Ingresos rechazados hoy'));
    expect(tocada, isTrue);
  });

  testWidgets('encabezado en celular: los botones quedan debajo del título', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PageHeader(
          title: 'Reportes',
          subtitle: 'Seleccione el tipo de reporte',
          actions: [FilledButton(onPressed: () {}, child: const Text('Exportar'))],
        ),
      ),
    ));
    final titulo = tester.getBottomLeft(find.text('Seleccione el tipo de reporte'));
    final boton = tester.getTopLeft(find.text('Exportar'));
    expect(boton.dy, greaterThan(titulo.dy));
  });

  testWidgets('encabezado en PC: los botones quedan al lado del título', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PageHeader(
          title: 'Reportes',
          actions: [FilledButton(onPressed: () {}, child: const Text('Exportar'))],
        ),
      ),
    ));
    final titulo = tester.getCenter(find.text('Reportes'));
    final boton = tester.getCenter(find.text('Exportar'));
    expect((boton.dy - titulo.dy).abs(), lessThan(30));
    expect(boton.dx, greaterThan(titulo.dx));
  });

  testWidgets('etiqueta de color muestra su texto', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: Pill('Al día'))),
    ));
    expect(find.text('Al día'), findsOneWidget);
  });
}
