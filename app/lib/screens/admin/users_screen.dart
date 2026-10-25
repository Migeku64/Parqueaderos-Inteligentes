import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'residents_screen.dart' show pickResident;

/// Gestión de usuarios y roles (RF07), bloqueo (RF18) y restablecer contraseña (RF12).
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  int _version = 0;
  String _role = 'todos';
  String _q = '';

  void _refresh() => setState(() => _version++);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PageHeader(
          title: 'Usuarios y roles',
          subtitle: 'Cuentas de administración, guardas y residentes',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.person_add),
              label: const Text('Nuevo usuario'),
              onPressed: () async {
                if (await _userForm(context)) _refresh();
              },
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final r in const ['todos', 'admin', 'guarda', 'residente'])
                ChoiceChip(
                  label: Text(r == 'todos' ? 'Todos' : roleLabel(r)),
                  selected: _role == r,
                  onSelected: (_) => setState(() => _role = r),
                ),
              SizedBox(
                width: 220,
                child: TextField(
                  decoration: inputDeco('Buscar usuario', icon: Icons.search),
                  onChanged: (v) => setState(() => _q = v.toLowerCase()),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Loader<List<Map<String, dynamic>>>(
            key: ValueKey(_version),
            load: () async => asList(await session.api.get('/users')),
            reloadOn: const {'notification'},
            builder: (context, users, reload) {
              final list = users.where((u) {
                if (_role != 'todos' && asStr(u['role']) != _role) return false;
                if (_q.isEmpty) return true;
                return asStr(u['username']).toLowerCase().contains(_q) ||
                    asStr(u['full_name']).toLowerCase().contains(_q);
              }).toList();
              if (list.isEmpty) return const EmptyView(message: 'Sin usuarios');
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                itemCount: list.length,
                itemBuilder: (context, i) => _userTile(context, list[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _userTile(BuildContext context, Map<String, dynamic> u) {
    final blocked = asBool(u['is_blocked']);
    final active = asBool(u['is_active']);
    final isMe = asInt(u['id']) == session.user!.id;
    final role = asStr(u['role']);
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: blocked ? AppColors.redSoft : AppColors.greySoft,
          child: Icon(
            role == 'admin'
                ? Icons.admin_panel_settings
                : role == 'guarda'
                    ? Icons.security
                    : Icons.home,
            color: blocked ? AppColors.red : AppColors.blue,
          ),
        ),
        title: Text('${asStr(u['username'])}${isMe ? ' (usted)' : ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('${asStr(u['full_name'])} · ${roleLabel(role)}'),
            if (blocked) const Pill('Bloqueado', color: AppColors.red),
            if (!active) const Pill('Inactivo', color: AppColors.grey),
            if (asInt(u['failed_attempts']) > 0 && !blocked)
              Pill('${asInt(u['failed_attempts'])} intentos fallidos', color: AppColors.amber),
          ],
        ),
        trailing: isMe
            ? null
            : PopupMenuButton<String>(
                onSelected: (op) => _action(context, op, u),
                itemBuilder: (_) => [
                  PopupMenuItem(value: blocked ? 'unblock' : 'block', child: Text(blocked ? 'Desbloquear' : 'Bloquear')),
                  const PopupMenuItem(value: 'reset', child: Text('Restablecer contraseña')),
                  if (role != 'residente') const PopupMenuItem(value: 'role', child: Text('Cambiar rol')),
                  PopupMenuItem(value: 'active', child: Text(active ? 'Desactivar' : 'Activar')),
                ],
              ),
      ),
    );
  }

  Future<void> _action(BuildContext context, String op, Map<String, dynamic> u) async {
    final id = asInt(u['id']);
    final name = asStr(u['username']);
    switch (op) {
      case 'block':
        if (await confirm(context, 'Bloquear usuario', '¿Bloquear a $name? No podrá iniciar sesión.', danger: true, ok: 'Bloquear')) {
          if (!context.mounted) return;
          await runAction(context, () => session.api.post('/users/$id/block', {'reason': 'Bloqueo manual'}),
              success: 'Usuario bloqueado');
        }
        break;
      case 'unblock':
        await runAction(context, () => session.api.post('/users/$id/unblock'), success: 'Usuario desbloqueado');
        break;
      case 'reset':
        if (!await confirm(context, 'Restablecer contraseña',
            'Se generará una contraseña temporal para $name y se le pedirá cambiarla al ingresar.')) {
          return;
        }
        if (!context.mounted) return;
        final r = await runAction(context, () => session.api.post('/users/$id/reset-password', {}));
        if (r != null && context.mounted) {
          final pw = asStr(asMap(r)['temporary_password']);
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Contraseña temporal'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Entregue esta contraseña a $name:'),
                  const SizedBox(height: 12),
                  SelectableText(pw, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 2)),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Clipboard.setData(ClipboardData(text: pw)),
                  child: const Text('Copiar'),
                ),
                FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Listo')),
              ],
            ),
          );
        }
        break;
      case 'role':
        final role = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text('Rol de $name'),
            children: [
              for (final r in const ['admin', 'guarda'])
                SimpleDialogOption(onPressed: () => Navigator.pop(ctx, r), child: Text(roleLabel(r))),
            ],
          ),
        );
        if (role != null && context.mounted) {
          await runAction(context, () => session.api.patch('/users/$id', {'role': role}), success: 'Rol actualizado');
        }
        break;
      case 'active':
        await runAction(context, () => session.api.patch('/users/$id', {'is_active': !asBool(u['is_active'])}),
            success: 'Usuario actualizado');
        break;
    }
    _refresh();
  }

  Future<bool> _userForm(BuildContext context) async {
    final username = TextEditingController();
    final fullName = TextEditingController();
    final password = TextEditingController();
    String role = 'guarda';
    Map<String, dynamic>? resident;
    String? error;
    bool saved = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Nuevo usuario'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LabeledDropdown<String>(
                  label: 'Rol',
                  value: role,
                  items: const {'admin': 'Administrador', 'guarda': 'Guarda de seguridad', 'residente': 'Residente'},
                  onChanged: (v) => setState(() => role = v),
                ),
                const SizedBox(height: 10),
                if (role == 'residente')
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.home),
                    title: Text(resident == null ? 'Elegir residente *' : asStr(resident!['full_name'])),
                    subtitle: resident == null ? null : Text('Casa ${asStr(resident!['house'])}'),
                    trailing: const Icon(Icons.search),
                    onTap: () async {
                      final r = await pickResident(ctx);
                      if (r != null) setState(() => resident = r);
                    },
                  )
                else
                  TextField(controller: fullName, decoration: inputDeco('Nombre completo')),
                const SizedBox(height: 10),
                TextField(controller: username, decoration: inputDeco('Usuario *')),
                const SizedBox(height: 10),
                TextField(
                    controller: password,
                    decoration: inputDeco('Contraseña temporal *', helper: 'Mínimo 6 caracteres; se pedirá cambiarla')),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(error!, style: const TextStyle(color: AppColors.red)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                try {
                  await session.api.post('/users', {
                    'username': username.text.trim(),
                    'full_name': fullName.text.trim(),
                    'password': password.text,
                    'role': role,
                    if (role == 'residente' && resident != null) 'resident_id': resident!['id'],
                  });
                  saved = true;
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  setState(() => error = e.toString());
                }
              },
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
    if (saved && context.mounted) showSnack(context, 'Usuario creado');
    return saved;
  }
}
