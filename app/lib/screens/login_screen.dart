import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

/// Pantalla de inicio de sesión (mockup "Login": BIENVENIDO / USUARIO / CONTRASEÑA / INGRESAR).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'Ingrese usuario y contraseña');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await session.login(_user.text, _pass.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Error inesperado: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _serverDialog() async {
    final ctrl = TextEditingController(text: session.serverUrl);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Servidor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dirección de la API. Ejemplos:\n'
              '• Emulador Android: http://10.0.2.2:3000\n'
              '• Windows / simulador iOS: http://localhost:3000\n'
              '• Celular real: http://IP-DE-SU-PC:3000\n'
              '• En la nube: https://su-api.onrender.com',
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            TextField(controller: ctrl, decoration: inputDeco('URL del servidor', icon: Icons.dns)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, Session.defaultServer), child: const Text('Por defecto')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Guardar')),
        ],
      ),
    );
    if (result != null) {
      await session.setServer(result);
      if (!mounted) return;
      final ok = await runAction(context, () => session.api.get('/health'));
      if (ok != null && mounted) showSnack(context, 'Conectado a ${session.serverUrl}');
    }
  }

  Future<void> _forgot() async {
    final ctrl = TextEditingController(text: _user.text);
    final username = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recuperar contraseña'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'La administración recibirá su solicitud y le entregará una contraseña temporal.'),
            const SizedBox(height: 12),
            TextField(controller: ctrl, decoration: inputDeco('Usuario', icon: Icons.person)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Enviar solicitud')),
        ],
      ),
    );
    if (username == null || username.trim().isEmpty || !mounted) return;
    final res = await runAction(context, () => session.api.post('/auth/forgot', {'username': username}));
    if (res != null && mounted) showSnack(context, asStr(asMap(res)['message']));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.blue, AppColors.blueLight],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      children: [
                        const BrandLogo(size: 230, full: true),
                        const SizedBox(height: 24),
                        const Text(
                          'BIENVENIDO',
                          style: TextStyle(
                              color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 1),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Parqueadero Comunitario',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 28),
                        _label('USUARIO'),
                        TextField(
                          controller: _user,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          decoration: inputDeco('Usuario', icon: Icons.person_outline),
                        ),
                        const SizedBox(height: 16),
                        _label('CONTRASEÑA'),
                        TextField(
                          controller: _pass,
                          obscureText: _obscure,
                          onSubmitted: (_) => _login(),
                          decoration: inputDeco('Contraseña', icon: Icons.lock_outline).copyWith(
                            suffixIcon: IconButton(
                              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                                color: AppColors.redSoft, borderRadius: BorderRadius.circular(8)),
                            child: Text(_error!, style: const TextStyle(color: AppColors.red)),
                          ),
                        ],
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.black,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            onPressed: _busy ? null : _login,
                            child: _busy
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('INGRESAR',
                                    style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _forgot,
                          child: const Text('¿Olvidó su contraseña?', style: TextStyle(color: Colors.white)),
                        ),
                        const SizedBox(height: 8),
                        ListenableBuilder(
                          listenable: session,
                          builder: (context, _) => Text(
                            'Servidor: ${session.serverUrl}',
                            style: const TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  tooltip: 'Configurar servidor',
                  icon: const Icon(Icons.settings, color: Colors.white),
                  onPressed: _serverDialog,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String t) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(t, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        ),
      );
}
