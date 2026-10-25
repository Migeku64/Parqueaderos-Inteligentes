import 'package:flutter/material.dart';

import 'core/session.dart';
import 'core/theme.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await session.init();
  runApp(const ParqueaderoApp());
}

class ParqueaderoApp extends StatelessWidget {
  const ParqueaderoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Parqueadero Comunitario',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          if (!session.ready) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          final user = session.user;
          if (user == null) return const LoginScreen();
          // La clave cambia con el usuario para reiniciar la navegación al cambiar de cuenta
          return HomeShell(key: ValueKey('home-${user.id}'));
        },
      ),
    );
  }
}
