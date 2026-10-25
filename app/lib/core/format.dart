// Utilidades para leer JSON de forma segura y formatear fechas/valores.

int asInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.toInt() ?? fallback;
  return fallback;
}

double asDouble(dynamic v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

String asStr(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  return v.toString();
}

bool asBool(dynamic v) => v == true || v == 'true' || v == 1;

Map<String, dynamic> asMap(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> asList(dynamic v) =>
    v is List ? v.map((e) => asMap(e)).toList() : <Map<String, dynamic>>[];

const _months = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
];
const _weekdays = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];

DateTime? parseDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  // Fechas "AAAA-MM-DD" se interpretan como fecha local (sin hora)
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
    final p = s.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }
  return DateTime.tryParse(s)?.toLocal();
}

String two(int n) => n.toString().padLeft(2, '0');

/// 2026-04-29 -> "29/04/2026"
String fmtDate(dynamic v) {
  final d = parseDate(v);
  if (d == null) return '—';
  return '${two(d.day)}/${two(d.month)}/${d.year}';
}

/// -> "miércoles, 29 de abril de 2026" (como en el mockup de Sorteos)
String fmtLongDate(dynamic v) {
  final d = parseDate(v);
  if (d == null) return '—';
  return '${_weekdays[d.weekday - 1]}, ${d.day} de ${_months[d.month - 1]} de ${d.year}';
}

String fmtDateTime(dynamic v) {
  final d = parseDate(v);
  if (d == null) return '—';
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

String fmtTime(dynamic v) {
  final d = parseDate(v);
  if (d == null) return '—';
  return '${two(d.hour)}:${two(d.minute)}';
}

/// 150000 -> "$150.000"
String fmtMoney(dynamic v) {
  final n = asDouble(v).round();
  final s = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return '${n < 0 ? '-' : ''}\$$buf';
}

/// DateTime -> "AAAA-MM-DD" para la API
String isoDate(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

String normalizePlate(String p) => p.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

String roleLabel(String role) {
  switch (role) {
    case 'admin':
      return 'Administrador';
    case 'guarda':
      return 'Guarda de seguridad';
    case 'residente':
      return 'Residente';
    default:
      return role;
  }
}
