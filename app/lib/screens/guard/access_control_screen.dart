import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Control de acceso del guarda (UC-05, RF05/RF06): ingresa la placa, el sistema valida
/// si el residente tiene asignación vigente y registra la entrada o la salida.
class AccessControlScreen extends StatefulWidget {
  const AccessControlScreen({super.key});

  @override
  State<AccessControlScreen> createState() => _AccessControlScreenState();
}

class _AccessControlScreenState extends State<AccessControlScreen> {
  final _plate = TextEditingController();
  final _focus = FocusNode();
  Map<String, dynamic>? _check;
  Map<String, dynamic>? _last;
  bool _busy = false;
  int _version = 0;

  @override
  void dispose() {
    _plate.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _plateValue => normalizePlate(_plate.text);

  Future<void> _lookup() async {
    if (_plateValue.length < 5) {
      showSnack(context, 'Escriba una placa válida (ej. ABC123)', error: true);
      return;
    }
    setState(() => _busy = true);
    final r = await runAction(context, () => session.api.get('/movements/check/$_plateValue'));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _check = r == null ? null : asMap(r);
      _last = null;
    });
  }

  Future<void> _register(String type) async {
    if (_plateValue.length < 5) {
      showSnack(context, 'Escriba una placa válida (ej. ABC123)', error: true);
      return;
    }
    setState(() => _busy = true);
    final r = await runAction(context, () => session.api.post('/movements', {'plate': _plateValue, 'type': type}));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r != null) {
        _last = asMap(r);
        _check = null;
        _plate.clear();
        _version++;
      }
    });
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final panel = _controlPanel();
    final recent = _recentList();
    return wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: SingleChildScrollView(child: panel)),
              Expanded(flex: 4, child: recent),
            ],
          )
        : ListView(children: [panel, SizedBox(height: 420, child: recent)]);
  }

  Widget _controlPanel() {
    final check = _check;
    final last = _last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(title: 'Control de acceso', subtitle: 'Registre la entrada y salida de vehículos'),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _plate,
                focusNode: _focus,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9 -]')),
                  LengthLimitingTextInputFormatter(8),
                ],
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 4),
                textAlign: TextAlign.center,
                decoration: inputDeco('Placa del vehículo', hint: 'ABC123'),
                onSubmitted: (_) => _lookup(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.green),
                        onPressed: _busy ? null : () => _register('entrada'),
                        icon: const Icon(Icons.login),
                        label: const Text('ENTRADA', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: Colors.black),
                        onPressed: _busy ? null : () => _register('salida'),
                        icon: const Icon(Icons.logout),
                        label: const Text('SALIDA', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _lookup,
                icon: const Icon(Icons.search),
                label: const Text('Solo consultar placa'),
              ),
              if (_busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
            ],
          ),
        ),
        if (last != null) _resultCard(last),
        if (check != null) _checkCard(check),
      ],
    );
  }

  Widget _resultCard(Map<String, dynamic> r) {
    final ok = asBool(r['authorized']);
    final resident = r['resident'] == null ? null : asMap(r['resident']);
    final movement = asMap(r['movement']);
    return Card(
      elevation: 0,
      color: ok ? AppColors.greenSoft : AppColors.redSoft,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: ok ? AppColors.green : AppColors.red, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(ok ? Icons.verified : Icons.gpp_bad, size: 56, color: ok ? AppColors.green : AppColors.red),
            const SizedBox(height: 8),
            PlateBadge(asStr(movement['plate']), big: true),
            const SizedBox(height: 10),
            Text(asStr(r['message']),
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            if (resident != null)
              Text('${asStr(resident['full_name'])} · Casa ${asStr(resident['house'])}',
                  style: const TextStyle(color: AppColors.muted)),
            if (ok && r['spot_code'] != null && asStr(movement['type']) == 'entrada') ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                decoration: BoxDecoration(color: AppColors.green, borderRadius: BorderRadius.circular(8)),
                child: Text(asStr(r['spot_code']),
                    style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _checkCard(Map<String, dynamic> c) {
    final v = c['vehicle'] == null ? null : asMap(c['vehicle']);
    final a = c['assignment'] == null ? null : asMap(c['assignment']);
    final canEnter = asBool(c['can_enter']);
    return SectionCard(
      title: 'Consulta de placa',
      child: v == null
          ? Row(
              children: [
                PlateBadge(asStr(c['plate'])),
                const SizedBox(width: 10),
                const Expanded(child: Text('Vehículo NO registrado en el conjunto.')),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  PlateBadge(asStr(v['plate'])),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text([asStr(v['brand']), asStr(v['model']), asStr(v['color'])]
                        .where((e) => e.isNotEmpty)
                        .join(' ')),
                  ),
                ]),
                const SizedBox(height: 8),
                Text('${asStr(v['full_name'])} · Casa ${asStr(v['house'])}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  a == null
                      ? const Pill('Sin parqueadero en el ciclo actual', color: AppColors.red)
                      : Pill('Celda ${asStr(a['spot_code'])} hasta ${fmtDate(a['end_date'])}', color: AppColors.green),
                  if (asBool(c['inside'])) const Pill('Está dentro del conjunto', color: AppColors.amber),
                  if (canEnter) const Pill('Puede ingresar', color: AppColors.green),
                ]),
              ],
            ),
    );
  }

  Widget _recentList() {
    return Loader<List<Map<String, dynamic>>>(
      key: ValueKey(_version),
      load: () async => asList(await session.api.get('/movements', query: {'limit': 30})),
      reloadOn: const {'movement'},
      builder: (context, list, reload) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Movimientos recientes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: list.isEmpty
                ? const EmptyView(message: 'Aún no hay movimientos')
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) => movementTile(list[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

Widget movementTile(Map<String, dynamic> m) {
  final ok = asBool(m['authorized']);
  final entry = asStr(m['type']) == 'entrada';
  return ListTile(
    dense: true,
    leading: CircleAvatar(
      backgroundColor: ok ? (entry ? AppColors.greenSoft : AppColors.greySoft) : AppColors.redSoft,
      child: Icon(entry ? Icons.login : Icons.logout, color: ok ? (entry ? AppColors.green : AppColors.text) : AppColors.red),
    ),
    title: Row(children: [
      PlateBadge(asStr(m['plate'])),
      const SizedBox(width: 8),
      Flexible(
        child: Text(asStr(m['resident_name'], ok ? '' : 'No registrado'), overflow: TextOverflow.ellipsis),
      ),
    ]),
    subtitle: Text(ok
        ? '${entry ? 'Entrada' : 'Salida'}${m['spot_code'] != null ? ' · celda ${asStr(m['spot_code'])}' : ''}'
            '${m['source'] == 'lector' ? ' · lector automático' : ''}'
        : 'Rechazado: ${asStr(m['reason'])}'),
    trailing: Text(fmtDateTime(m['recorded_at']), style: const TextStyle(fontSize: 12)),
  );
}
