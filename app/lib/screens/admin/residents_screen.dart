import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Gestión de residentes y vehículos (RF01, RF02, UC-02).
class ResidentsScreen extends StatefulWidget {
  const ResidentsScreen({super.key});

  @override
  State<ResidentsScreen> createState() => _ResidentsScreenState();
}

class _ResidentsScreenState extends State<ResidentsScreen> {
  String _query = '';
  Timer? _debounce;
  int _version = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _refresh() => setState(() => _version++);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PageHeader(
          title: 'Residentes del conjunto',
          subtitle: 'Registro de residentes, vehículos y estado de pago',
          actions: [
            FilledButton.icon(
              onPressed: () async {
                final saved = await showResidentForm(context);
                if (saved != null) _refresh();
              },
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Agregar'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            decoration: inputDeco('Buscar por cédula, nombre, casa o placa...', icon: Icons.search),
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 350), () => setState(() => _query = v));
            },
          ),
        ),
        Expanded(
          child: Loader<List<Map<String, dynamic>>>(
            key: ValueKey('$_query#$_version'),
            load: () async => asList(await session.api.get('/residents', query: {'q': _query})),
            reloadOn: const {'assignments'},
            builder: (context, list, reload) {
              if (list.isEmpty) return const EmptyView(message: 'No se encontraron residentes');
              return RefreshIndicator(
                onRefresh: reload,
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: list.length,
                  itemBuilder: (context, i) => _ResidentTile(
                    r: list[i],
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ResidentDetailScreen(residentId: asInt(list[i]['id'])),
                      ));
                      reload();
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ResidentTile extends StatelessWidget {
  const _ResidentTile({required this.r, required this.onTap});

  final Map<String, dynamic> r;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vehicles = asList(r['vehicles']);
    final debt = asDouble(r['debt']);
    final inactive = asStr(r['status']) != 'activo';
    final current = r['current_assignment'] == null ? null : asMap(r['current_assignment']);
    final warnings = <Widget>[
      if (inactive) const Pill('Inactivo', color: AppColors.grey),
      if (debt > 0) Pill('Deuda ${fmtMoney(debt)}', color: AppColors.red),
      if (vehicles.isEmpty) const Pill('Sin vehículo', color: AppColors.amber),
      if (current != null) Pill('Celda ${asStr(current['spot_code'])}', color: AppColors.green),
    ];
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: debt > 0 ? AppColors.redSoft : AppColors.greenSoft,
          child: Text(
            asStr(r['house_number']),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.text),
          ),
        ),
        title: Text('${asStr(r['full_name'])} · Casa ${asStr(r['house'])}',
            style: TextStyle(color: inactive ? AppColors.muted : AppColors.text, fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('${asStr(r['document_type'])} ${asStr(r['document_number'])}'),
              for (final v in vehicles) PlateBadge(asStr(v['plate'])),
              ...warnings,
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

/// Detalle del residente: datos, vehículos, cuenta e historial de asignaciones.
class ResidentDetailScreen extends StatefulWidget {
  const ResidentDetailScreen({super.key, required this.residentId});

  final int residentId;

  @override
  State<ResidentDetailScreen> createState() => _ResidentDetailScreenState();
}

class _ResidentDetailScreenState extends State<ResidentDetailScreen> {
  int _version = 0;

  void _refresh() => setState(() => _version++);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Residente'),
        backgroundColor: AppColors.blue,
        foregroundColor: Colors.white,
      ),
      body: Loader<Map<String, dynamic>>(
        key: ValueKey(_version),
        load: () async => asMap(await session.api.get('/residents/${widget.residentId}')),
        builder: (context, r, reload) {
          final vehicles = asList(r['vehicles']);
          final history = asList(r['history']);
          final account = r['account'] == null ? null : asMap(r['account']);
          return MaxWidth(
            width: 900,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                PageHeader(
                  title: asStr(r['full_name']),
                  subtitle: 'Casa ${asStr(r['house'])} · ${asStr(r['document_type'])} ${asStr(r['document_number'])}',
                  actions: [
                    IconButton(
                      tooltip: 'Editar',
                      icon: const Icon(Icons.edit),
                      onPressed: () async {
                        if (await showResidentForm(context, existing: r) != null) _refresh();
                      },
                    ),
                  ],
                ),
                SectionCard(
                  title: 'Datos',
                  child: Wrap(
                    spacing: 24,
                    runSpacing: 12,
                    children: [
                      _info('Estado', asStr(r['status'])),
                      _info('Teléfono', asStr(r['phone'], '—')),
                      _info('Correo', asStr(r['email'], '—')),
                      _info('Deuda administración', fmtMoney(r['debt'])),
                      _info('Puntaje administrativo (Pa)', '${asInt(r['admin_score'])} / 5'),
                      _info('Requiere celda de discapacidad', asBool(r['has_disability']) ? 'Sí' : 'No'),
                      _info('Usuario de la app',
                          account == null ? 'Sin cuenta' : '${asStr(account['username'])}${asBool(account['is_blocked']) ? ' (bloqueado)' : ''}'),
                    ],
                  ),
                ),
                SectionCard(
                  title: 'Vehículos',
                  trailing: TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar'),
                    onPressed: () async {
                      if (await _vehicleForm(context, residentId: asInt(r['id'])) == true) _refresh();
                    },
                  ),
                  child: vehicles.isEmpty
                      ? const Text('No tiene vehículos activos registrados.')
                      : Column(
                          children: [
                            for (final v in vehicles)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(asStr(v['type']) == 'moto' ? Icons.two_wheeler : Icons.directions_car),
                                title: Row(children: [PlateBadge(asStr(v['plate']))]),
                                subtitle: Text([
                                  asStr(v['type']),
                                  asStr(v['brand']),
                                  asStr(v['model']),
                                  asStr(v['color']),
                                ].where((e) => e.isNotEmpty).join(' · ')),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (op) async {
                                    if (op == 'edit') {
                                      if (await _vehicleForm(context, vehicle: v) == true) _refresh();
                                    } else if (op == 'delete') {
                                      if (await confirm(context, 'Retirar vehículo',
                                          '¿Retirar el vehículo ${asStr(v['plate'])}? Se conservará su historial.',
                                          danger: true, ok: 'Retirar')) {
                                        if (!context.mounted) return;
                                        await runAction(context, () => session.api.delete('/vehicles/${asInt(v['id'])}'));
                                        _refresh();
                                      }
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: 'edit', child: Text('Editar')),
                                    PopupMenuItem(value: 'delete', child: Text('Retirar')),
                                  ],
                                ),
                              ),
                          ],
                        ),
                ),
                SectionCard(
                  title: 'Historial de asignaciones',
                  child: history.isEmpty
                      ? const Text('Nunca ha tenido parqueadero asignado.')
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
                                subtitle: Text('${fmtDate(h['start_date'])} – ${fmtDate(h['end_date'])} · '
                                    '${asStr(h['method'])} · ${asStr(h['plate'])}'
                                    '${h['ipa_score'] != null ? ' · IPA ${asDouble(h['ipa_score']).toStringAsFixed(2)}' : ''}'),
                                trailing: Pill(asStr(h['status']),
                                    color: asStr(h['status']) == 'vigente' ? AppColors.green : AppColors.grey),
                              ),
                          ],
                        ),
                ),
                if (asStr(r['status']) == 'activo')
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
                      icon: const Icon(Icons.person_off_outlined),
                      label: const Text('Inactivar residente'),
                      onPressed: () async {
                        if (await confirm(context, 'Inactivar residente',
                            'El residente no participará en sorteos y su usuario quedará desactivado. Se conserva el historial.',
                            danger: true, ok: 'Inactivar')) {
                          if (!context.mounted) return;
                          await runAction(context, () => session.api.delete('/residents/${asInt(r['id'])}'),
                              success: 'Residente inactivado');
                          _refresh();
                        }
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _info(String label, String value) => SizedBox(
        width: 240,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

const _vehicleTypes = {'carro': 'Carro', 'moto': 'Moto', 'camioneta': 'Camioneta', 'otro': 'Otro'};

Future<bool?> _vehicleForm(BuildContext context, {int? residentId, Map<String, dynamic>? vehicle}) async {
  final plate = TextEditingController(text: asStr(vehicle?['plate']));
  final brand = TextEditingController(text: asStr(vehicle?['brand']));
  final model = TextEditingController(text: asStr(vehicle?['model']));
  final color = TextEditingController(text: asStr(vehicle?['color']));
  String type = vehicle == null ? 'carro' : asStr(vehicle['type'], 'carro');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(vehicle == null ? 'Agregar vehículo' : 'Editar vehículo'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: plate,
                  textCapitalization: TextCapitalization.characters,
                  decoration: inputDeco('Placa *', icon: Icons.pin, hint: 'ABC123')),
              const SizedBox(height: 10),
              LabeledDropdown<String>(
                  label: 'Tipo', value: type, items: _vehicleTypes, onChanged: (v) => setState(() => type = v)),
              const SizedBox(height: 10),
              TextField(controller: brand, decoration: inputDeco('Marca')),
              const SizedBox(height: 10),
              TextField(controller: model, decoration: inputDeco('Modelo / línea')),
              const SizedBox(height: 10),
              TextField(controller: color, decoration: inputDeco('Color')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return false;
  final body = {
    'plate': normalizePlate(plate.text),
    'type': type,
    'brand': brand.text.trim(),
    'model': model.text.trim(),
    'color': color.text.trim(),
  };
  final res = await runAction(
    context,
    () => vehicle == null
        ? session.api.post('/residents/$residentId/vehicles', body)
        : session.api.put('/vehicles/${asInt(vehicle['id'])}', body),
    success: 'Vehículo guardado',
  );
  return res != null;
}

/// Formulario de creación / edición de residente (como el diálogo "Agregar Residente" del prototipo).
Future<Map<String, dynamic>?> showResidentForm(BuildContext context, {Map<String, dynamic>? existing}) async {
  final isNew = existing == null;
  final name = TextEditingController(text: asStr(existing?['full_name']));
  final doc = TextEditingController(text: asStr(existing?['document_number']));
  final house = TextEditingController(text: asStr(existing?['house_number']));
  final phone = TextEditingController(text: asStr(existing?['phone']));
  final email = TextEditingController(text: asStr(existing?['email']));
  final debt = TextEditingController(text: existing == null ? '0' : asDouble(existing['debt']).round().toString());
  final plate = TextEditingController();
  final username = TextEditingController();
  final password = TextEditingController(text: 'residente123');
  String docType = asStr(existing?['document_type'], 'CC');
  String vehicleType = 'carro';
  String status = asStr(existing?['status'], 'activo');
  int score = asInt(existing?['admin_score']);
  bool disability = asBool(existing?['has_disability']);
  bool hasVehicle = isNew;
  bool createAccount = isNew;
  String? error;

  Map<String, dynamic>? result;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(isNew ? 'Agregar residente' : 'Editar residente'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 110,
                      child: LabeledDropdown<String>(
                        label: 'Tipo doc.',
                        value: docType,
                        items: const {'CC': 'CC', 'CE': 'CE', 'TI': 'TI', 'PA': 'PA', 'NIT': 'NIT'},
                        onChanged: (v) => setState(() => docType = v),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                          controller: doc, keyboardType: TextInputType.number, decoration: inputDeco('Cédula *')),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(controller: name, decoration: inputDeco('Nombre completo *')),
                const SizedBox(height: 10),
                TextField(
                  controller: house,
                  keyboardType: TextInputType.number,
                  decoration: inputDeco('Número de casa *', hint: '150', helper: 'Del 1 al 300'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                        child: TextField(
                            controller: phone, keyboardType: TextInputType.phone, decoration: inputDeco('Teléfono'))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: TextField(
                            controller: email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: inputDeco('Correo'))),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: debt,
                  keyboardType: TextInputType.number,
                  decoration: inputDeco('Deuda con la administración (\$)',
                      helper: 'Con deuda mayor a 0 no participa en el sorteo'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Expanded(child: Text('Puntaje administrativo (Pa)')),
                    DropdownButton<int>(
                      value: score,
                      items: [for (var i = 0; i <= 5; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                      onChanged: (v) => setState(() => score = v ?? 0),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Requiere celda para persona con discapacidad'),
                  value: disability,
                  onChanged: (v) => setState(() => disability = v),
                ),
                if (!isNew)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Residente activo'),
                    value: status == 'activo',
                    onChanged: (v) => setState(() => status = v ? 'activo' : 'inactivo'),
                  ),
                if (isNew) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('¿Tiene vehículo?'),
                    value: hasVehicle,
                    onChanged: (v) => setState(() => hasVehicle = v),
                  ),
                  if (hasVehicle)
                    Row(
                      children: [
                        SizedBox(
                          width: 150,
                          child: LabeledDropdown<String>(
                            label: 'Tipo de vehículo',
                            value: vehicleType,
                            items: _vehicleTypes,
                            onChanged: (v) => setState(() => vehicleType = v),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: plate,
                            textCapitalization: TextCapitalization.characters,
                            decoration: inputDeco('Placa', hint: 'ABC123'),
                          ),
                        ),
                      ],
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Crear usuario para la app'),
                    value: createAccount,
                    onChanged: (v) => setState(() => createAccount = v),
                  ),
                  if (createAccount)
                    Row(
                      children: [
                        Expanded(child: TextField(controller: username, decoration: inputDeco('Usuario', hint: 'casa150'))),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: password,
                            decoration: inputDeco('Clave temporal', helper: 'Se pedirá cambiarla'),
                          ),
                        ),
                      ],
                    ),
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(error!, style: const TextStyle(color: AppColors.red)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty || doc.text.trim().isEmpty || house.text.trim().isEmpty) {
                setState(() => error = 'Complete los campos obligatorios (*)');
                return;
              }
              final houseNum = int.tryParse(house.text.trim());
              if (houseNum == null || houseNum < 1 || houseNum > 300) {
                setState(() => error = 'El número de casa debe estar entre 1 y 300');
                return;
              }
              final body = <String, dynamic>{
                'full_name': name.text.trim(),
                'document_type': docType,
                'document_number': doc.text.trim(),
                'house_block': '',
                'house_number': house.text.trim(),
                'phone': phone.text.trim(),
                'email': email.text.trim(),
                'debt': double.tryParse(debt.text.replaceAll('.', '').replaceAll(',', '.')) ?? 0,
                'admin_score': score,
                'has_disability': disability,
                if (!isNew) 'status': status,
                if (isNew && hasVehicle && plate.text.trim().isNotEmpty)
                  'vehicle': {'plate': normalizePlate(plate.text), 'type': vehicleType},
                if (isNew && createAccount && username.text.trim().isNotEmpty)
                  'account': {'username': username.text.trim(), 'password': password.text},
              };
              try {
                final res = isNew
                    ? await session.api.post('/residents', body)
                    : await session.api.put('/residents/${asInt(existing!['id'])}', body);
                result = asMap(res);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                setState(() => error = e.toString());
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
  if (result != null && context.mounted) {
    showSnack(context, isNew ? 'Residente registrado' : 'Cambios guardados');
  }
  return result;
}

/// Diálogo para buscar y elegir un residente (usado en asignaciones manuales).
Future<Map<String, dynamic>?> pickResident(BuildContext context, {String title = 'Elegir residente'}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => _ResidentPicker(title: title),
  );
}

class _ResidentPicker extends StatefulWidget {
  const _ResidentPicker({required this.title});

  final String title;

  @override
  State<_ResidentPicker> createState() => _ResidentPickerState();
}

class _ResidentPickerState extends State<_ResidentPicker> {
  String _q = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: inputDeco('Buscar nombre, casa o placa', icon: Icons.search),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), () => setState(() => _q = v));
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Loader<List<Map<String, dynamic>>>(
                key: ValueKey(_q),
                load: () async =>
                    asList(await session.api.get('/residents', query: {'q': _q, 'status': 'activo'})),
                builder: (context, list, _) => ListView(
                  children: [
                    for (final r in list)
                      ListTile(
                        title: Text(asStr(r['full_name'])),
                        subtitle: Text('Casa ${asStr(r['house'])} · '
                            '${asList(r['vehicles']).map((v) => asStr(v['plate'])).join(', ')}'
                            '${asDouble(r['debt']) > 0 ? ' · con deuda' : ''}'
                            '${r['current_assignment'] != null ? ' · ya tiene celda' : ''}'),
                        enabled: asList(r['vehicles']).isNotEmpty,
                        onTap: () => Navigator.pop(context, r),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar'))],
    );
  }
}
