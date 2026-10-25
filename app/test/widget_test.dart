import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parqueadero_app/core/theme.dart';
import 'package:parqueadero_app/widgets/common.dart';

void main() {
  testWidgets('muestra el logo y una placa', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(children: [BrandLogo(size: 100), PlateBadge('ABC123')]),
      ),
    ));
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('ABC 123'), findsOneWidget);
  });
}
