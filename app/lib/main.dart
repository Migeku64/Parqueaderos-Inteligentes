import 'package:flutter/material.dart';

import 'core/session.dart';
import 'core/theme.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await session.init();
  await themeController.load();
  runApp(const ParqueaderoApp());
}

class ParqueaderoApp extends StatelessWidget {
  const ParqueaderoApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Se reconstruye al cambiar entre modo claro y oscuro
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeController,
      builder: (context, mode, _) => MaterialApp(
        title: 'Nueva Castilla Etapa 3 Parking',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        darkTheme: buildTheme(brightness: Brightness.dark),
        themeMode: mode,
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
      ),
    );
  }
}
