// Nombres de la base de datos en español.
//
// Las tablas y columnas de PostgreSQL están en español (ver db/schema.sql). La API REST
// conserva los nombres de campo de su contrato JSON (los que usa la app Flutter), por lo
// que db.js traduce automáticamente los nombres de columna en ambos sentidos:
//   * resultados de las consultas: columna en español  -> campo de la API
//   * inserciones con sql(objeto): campo de la API      -> columna en español
// Las consultas SQL del backend se escriben directamente con los nombres en español.

/** Tablas: nombre anterior (inglés) -> nombre en la base de datos. */
export const TABLES = {
  house: 'vivienda',
  resident: 'residente',
  vehicle: 'vehiculo',
  parking_spot: 'celda',
  cycle: 'ciclo',
  parking_assignment: 'asignacion',
  user_account: 'cuenta_usuario',
  vehicle_movement: 'movimiento_vehiculo',
  notification: 'notificacion',
  audit_log: 'auditoria',
  backup_record: 'respaldo',
};

/** Columnas: campo de la API -> columna en la base de datos. */
export const COLUMNS = {
  block: 'bloque',
  number: 'numero',
  is_owner_occupied: 'habitada_por_propietario',
  house_id: 'vivienda_id',
  full_name: 'nombre_completo',
  document_type: 'tipo_documento',
  document_number: 'numero_documento',
  phone: 'telefono',
  email: 'correo',
  status: 'estado',
  debt: 'deuda',
  admin_score: 'puntaje_administrativo',
  has_disability: 'tiene_discapacidad',
  created_at: 'creado_en',
  updated_at: 'actualizado_en',
  resident_id: 'residente_id',
  plate: 'placa',
  type: 'tipo',
  brand: 'marca',
  model: 'modelo',
  is_active: 'activo',
  code: 'codigo',
  is_disabled_spot: 'para_discapacidad',
  is_occupied: 'ocupada',
  notes: 'observaciones',
  name: 'nombre',
  start_date: 'fecha_inicio',
  end_date: 'fecha_fin',
  draw_date: 'fecha_sorteo',
  cycle_id: 'ciclo_id',
  vehicle_id: 'vehiculo_id',
  parking_spot_id: 'celda_id',
  method: 'metodo',
  ipa_score: 'puntaje_ipa',
  assigned_at: 'asignado_en',
  released_at: 'liberado_en',
  username: 'usuario',
  password_hash: 'hash_contrasena',
  role: 'rol',
  is_blocked: 'bloqueado',
  failed_attempts: 'intentos_fallidos',
  must_change_password: 'debe_cambiar_contrasena',
  last_login_at: 'ultimo_ingreso_en',
  assignment_id: 'asignacion_id',
  authorized: 'autorizado',
  source: 'origen',
  reason: 'motivo',
  recorded_by: 'registrado_por',
  recorded_at: 'registrado_en',
  user_account_id: 'cuenta_usuario_id',
  target_role: 'rol_destino',
  title: 'titulo',
  body: 'cuerpo',
  kind: 'categoria',
  read_at: 'leido_en',
  action: 'accion',
  entity_name: 'entidad',
  entity_id: 'entidad_id',
  performed_at: 'realizado_en',
  details: 'detalles',
  file_name: 'nombre_archivo',
  size_bytes: 'tamano_bytes',
  trigger: 'disparador',
  emailed_at: 'correo_enviado_en',
};

const TO_API = Object.fromEntries(Object.entries(COLUMNS).map(([api, db]) => [db, api]));

/** Columna de la base de datos -> campo de la API. */
export const toApi = (column) => TO_API[column] ?? column;
/** Campo de la API -> columna de la base de datos. */
export const toDb = (field) => COLUMNS[field] ?? field;
/** Nombre de entidad para la auditoría (tabla en español). */
export const entity = (name) => TABLES[name] ?? name;
