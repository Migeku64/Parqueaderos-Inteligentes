-- =====================================================================
--  Migración: nombres de la base de datos de inglés a español
--  Convierte una base creada con la versión anterior del esquema (tablas house,
--  resident, vehicle, ...) a los nombres en español, CONSERVANDO TODOS LOS DATOS.
--  Es segura de ejecutar varias veces: solo actúa si encuentra las tablas antiguas.
--  scripts/migrate.js la ejecuta automáticamente antes de aplicar schema.sql.
-- =====================================================================
DO $$
BEGIN
  IF to_regclass('public.house') IS NULL OR to_regclass('public.vivienda') IS NOT NULL THEN
    RETURN;  -- nada que migrar
  END IF;


  -- house -> vivienda
  ALTER TABLE house RENAME TO vivienda;
  ALTER TABLE vivienda RENAME COLUMN block TO bloque;
  ALTER TABLE vivienda RENAME COLUMN number TO numero;
  ALTER TABLE vivienda RENAME COLUMN is_owner_occupied TO habitada_por_propietario;
  ALTER SEQUENCE IF EXISTS house_id_seq RENAME TO vivienda_id_seq;

  -- resident -> residente
  ALTER TABLE resident RENAME TO residente;
  ALTER TABLE residente RENAME COLUMN house_id TO vivienda_id;
  ALTER TABLE residente RENAME COLUMN full_name TO nombre_completo;
  ALTER TABLE residente RENAME COLUMN document_type TO tipo_documento;
  ALTER TABLE residente RENAME COLUMN document_number TO numero_documento;
  ALTER TABLE residente RENAME COLUMN phone TO telefono;
  ALTER TABLE residente RENAME COLUMN email TO correo;
  ALTER TABLE residente RENAME COLUMN status TO estado;
  ALTER TABLE residente RENAME COLUMN debt TO deuda;
  ALTER TABLE residente RENAME COLUMN admin_score TO puntaje_administrativo;
  ALTER TABLE residente RENAME COLUMN has_disability TO tiene_discapacidad;
  ALTER TABLE residente RENAME COLUMN created_at TO creado_en;
  ALTER TABLE residente RENAME COLUMN updated_at TO actualizado_en;
  ALTER SEQUENCE IF EXISTS resident_id_seq RENAME TO residente_id_seq;

  -- vehicle -> vehiculo
  ALTER TABLE vehicle RENAME TO vehiculo;
  ALTER TABLE vehiculo RENAME COLUMN resident_id TO residente_id;
  ALTER TABLE vehiculo RENAME COLUMN plate TO placa;
  ALTER TABLE vehiculo RENAME COLUMN type TO tipo;
  ALTER TABLE vehiculo RENAME COLUMN brand TO marca;
  ALTER TABLE vehiculo RENAME COLUMN model TO modelo;
  ALTER TABLE vehiculo RENAME COLUMN is_active TO activo;
  ALTER TABLE vehiculo RENAME COLUMN created_at TO creado_en;
  ALTER SEQUENCE IF EXISTS vehicle_id_seq RENAME TO vehiculo_id_seq;

  -- parking_spot -> celda
  ALTER TABLE parking_spot RENAME TO celda;
  ALTER TABLE celda RENAME COLUMN code TO codigo;
  ALTER TABLE celda RENAME COLUMN is_disabled_spot TO para_discapacidad;
  ALTER TABLE celda RENAME COLUMN is_active TO activo;
  ALTER TABLE celda RENAME COLUMN is_occupied TO ocupada;
  ALTER TABLE celda RENAME COLUMN notes TO observaciones;
  ALTER SEQUENCE IF EXISTS parking_spot_id_seq RENAME TO celda_id_seq;

  -- cycle -> ciclo
  ALTER TABLE cycle RENAME TO ciclo;
  ALTER TABLE ciclo RENAME COLUMN name TO nombre;
  ALTER TABLE ciclo RENAME COLUMN start_date TO fecha_inicio;
  ALTER TABLE ciclo RENAME COLUMN end_date TO fecha_fin;
  ALTER TABLE ciclo RENAME COLUMN draw_date TO fecha_sorteo;
  ALTER TABLE ciclo RENAME COLUMN status TO estado;
  ALTER TABLE ciclo RENAME COLUMN created_at TO creado_en;
  ALTER SEQUENCE IF EXISTS cycle_id_seq RENAME TO ciclo_id_seq;

  -- parking_assignment -> asignacion
  ALTER TABLE parking_assignment RENAME TO asignacion;
  ALTER TABLE asignacion RENAME COLUMN cycle_id TO ciclo_id;
  ALTER TABLE asignacion RENAME COLUMN resident_id TO residente_id;
  ALTER TABLE asignacion RENAME COLUMN vehicle_id TO vehiculo_id;
  ALTER TABLE asignacion RENAME COLUMN parking_spot_id TO celda_id;
  ALTER TABLE asignacion RENAME COLUMN method TO metodo;
  ALTER TABLE asignacion RENAME COLUMN ipa_score TO puntaje_ipa;
  ALTER TABLE asignacion RENAME COLUMN assigned_at TO asignado_en;
  ALTER TABLE asignacion RENAME COLUMN released_at TO liberado_en;
  ALTER TABLE asignacion RENAME COLUMN status TO estado;
  ALTER TABLE asignacion RENAME COLUMN notes TO observaciones;
  ALTER SEQUENCE IF EXISTS parking_assignment_id_seq RENAME TO asignacion_id_seq;

  -- user_account -> cuenta_usuario
  ALTER TABLE user_account RENAME TO cuenta_usuario;
  ALTER TABLE cuenta_usuario RENAME COLUMN resident_id TO residente_id;
  ALTER TABLE cuenta_usuario RENAME COLUMN username TO usuario;
  ALTER TABLE cuenta_usuario RENAME COLUMN full_name TO nombre_completo;
  ALTER TABLE cuenta_usuario RENAME COLUMN password_hash TO hash_contrasena;
  ALTER TABLE cuenta_usuario RENAME COLUMN role TO rol;
  ALTER TABLE cuenta_usuario RENAME COLUMN is_active TO activo;
  ALTER TABLE cuenta_usuario RENAME COLUMN is_blocked TO bloqueado;
  ALTER TABLE cuenta_usuario RENAME COLUMN failed_attempts TO intentos_fallidos;
  ALTER TABLE cuenta_usuario RENAME COLUMN must_change_password TO debe_cambiar_contrasena;
  ALTER TABLE cuenta_usuario RENAME COLUMN last_login_at TO ultimo_ingreso_en;
  ALTER TABLE cuenta_usuario RENAME COLUMN created_at TO creado_en;
  ALTER SEQUENCE IF EXISTS user_account_id_seq RENAME TO cuenta_usuario_id_seq;

  -- vehicle_movement -> movimiento_vehiculo
  ALTER TABLE vehicle_movement RENAME TO movimiento_vehiculo;
  ALTER TABLE movimiento_vehiculo RENAME COLUMN plate TO placa;
  ALTER TABLE movimiento_vehiculo RENAME COLUMN vehicle_id TO vehiculo_id;
  ALTER TABLE movimiento_vehiculo RENAME COLUMN parking_spot_id TO celda_id;
  ALTER TABLE movimiento_vehiculo RENAME COLUMN assignment_id TO asignacion_id;
  ALTER TABLE movimiento_vehiculo RENAME COLUMN type TO tipo;
  ALTER TABLE movimiento_vehiculo RENAME COLUMN authorized TO autorizado;
  ALTER TABLE movimiento_vehiculo RENAME COLUMN source TO origen;
  ALTER TABLE movimiento_vehiculo RENAME COLUMN reason TO motivo;
  ALTER TABLE movimiento_vehiculo RENAME COLUMN recorded_by TO registrado_por;
  ALTER TABLE movimiento_vehiculo RENAME COLUMN recorded_at TO registrado_en;
  ALTER SEQUENCE IF EXISTS vehicle_movement_id_seq RENAME TO movimiento_vehiculo_id_seq;

  -- notification -> notificacion
  ALTER TABLE notification RENAME TO notificacion;
  ALTER TABLE notificacion RENAME COLUMN user_account_id TO cuenta_usuario_id;
  ALTER TABLE notificacion RENAME COLUMN target_role TO rol_destino;
  ALTER TABLE notificacion RENAME COLUMN title TO titulo;
  ALTER TABLE notificacion RENAME COLUMN body TO cuerpo;
  ALTER TABLE notificacion RENAME COLUMN kind TO categoria;
  ALTER TABLE notificacion RENAME COLUMN created_at TO creado_en;
  ALTER TABLE notificacion RENAME COLUMN read_at TO leido_en;
  ALTER SEQUENCE IF EXISTS notification_id_seq RENAME TO notificacion_id_seq;

  -- audit_log -> auditoria
  ALTER TABLE audit_log RENAME TO auditoria;
  ALTER TABLE auditoria RENAME COLUMN user_account_id TO cuenta_usuario_id;
  ALTER TABLE auditoria RENAME COLUMN action TO accion;
  ALTER TABLE auditoria RENAME COLUMN entity_name TO entidad;
  ALTER TABLE auditoria RENAME COLUMN entity_id TO entidad_id;
  ALTER TABLE auditoria RENAME COLUMN performed_at TO realizado_en;
  ALTER TABLE auditoria RENAME COLUMN details TO detalles;
  ALTER SEQUENCE IF EXISTS audit_log_id_seq RENAME TO auditoria_id_seq;

  -- backup_record -> respaldo
  ALTER TABLE backup_record RENAME TO respaldo;
  ALTER TABLE respaldo RENAME COLUMN file_name TO nombre_archivo;
  ALTER TABLE respaldo RENAME COLUMN size_bytes TO tamano_bytes;
  ALTER TABLE respaldo RENAME COLUMN status TO estado;
  ALTER TABLE respaldo RENAME COLUMN trigger TO disparador;
  ALTER TABLE respaldo RENAME COLUMN created_at TO creado_en;
  ALTER SEQUENCE IF EXISTS backup_record_id_seq RENAME TO respaldo_id_seq;

  -- Restricciones e índices con nombre
  ALTER TABLE vivienda RENAME CONSTRAINT house_block_number_uk TO vivienda_bloque_numero_uk;
  ALTER TABLE ciclo RENAME CONSTRAINT cycle_dates_ck TO ciclo_fechas_ck;
  ALTER TABLE ciclo RENAME CONSTRAINT cycle_length_ck TO ciclo_duracion_ck;
  ALTER TABLE cuenta_usuario RENAME CONSTRAINT resident_role_ck TO cuenta_residente_rol_ck;
  ALTER TABLE notificacion RENAME CONSTRAINT notification_target_ck TO notificacion_destino_ck;
  ALTER INDEX IF EXISTS resident_house_idx RENAME TO residente_vivienda_idx;
  ALTER INDEX IF EXISTS vehicle_resident_idx RENAME TO vehiculo_residente_idx;
  ALTER INDEX IF EXISTS cycle_one_active_uk RENAME TO ciclo_un_activo_uk;
  ALTER INDEX IF EXISTS assignment_spot_cycle_uk RENAME TO asignacion_celda_ciclo_uk;
  ALTER INDEX IF EXISTS assignment_resident_cycle_uk RENAME TO asignacion_residente_ciclo_uk;
  ALTER INDEX IF EXISTS assignment_resident_idx RENAME TO asignacion_residente_idx;
  ALTER INDEX IF EXISTS movement_recorded_idx RENAME TO movimiento_registrado_idx;
  ALTER INDEX IF EXISTS movement_plate_idx RENAME TO movimiento_placa_idx;
  ALTER INDEX IF EXISTS notification_user_idx RENAME TO notificacion_usuario_idx;
  ALTER INDEX IF EXISTS audit_performed_idx RENAME TO auditoria_realizado_idx;

  -- Restricciones generadas automáticamente (llaves primarias, foráneas, únicas y CHECK)
  BEGIN ALTER TABLE auditoria RENAME CONSTRAINT audit_log_user_account_id_fkey TO auditoria_cuenta_usuario_id_fkey; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE auditoria RENAME CONSTRAINT audit_log_pkey TO auditoria_pkey; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE respaldo RENAME CONSTRAINT backup_record_status_check TO respaldo_estado_check; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE respaldo RENAME CONSTRAINT backup_record_trigger_check TO respaldo_disparador_check; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE respaldo RENAME CONSTRAINT backup_record_pkey TO respaldo_pkey; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE ciclo RENAME CONSTRAINT cycle_status_check TO ciclo_estado_check; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE ciclo RENAME CONSTRAINT cycle_pkey TO ciclo_pkey; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE vivienda RENAME CONSTRAINT house_pkey TO vivienda_pkey; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE notificacion RENAME CONSTRAINT notification_target_role_check TO notificacion_rol_destino_check; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE notificacion RENAME CONSTRAINT notification_user_account_id_fkey TO notificacion_cuenta_usuario_id_fkey; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE notificacion RENAME CONSTRAINT notification_pkey TO notificacion_pkey; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE asignacion RENAME CONSTRAINT parking_assignment_method_check TO asignacion_metodo_check; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE asignacion RENAME CONSTRAINT parking_assignment_status_check TO asignacion_estado_check; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE asignacion RENAME CONSTRAINT parking_assignment_cycle_id_fkey TO asignacion_ciclo_id_fkey; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE asignacion RENAME CONSTRAINT parking_assignment_parking_spot_id_fkey TO asignacion_celda_id_fkey; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE asignacion RENAME CONSTRAINT parking_assignment_resident_id_fkey TO asignacion_residente_id_fkey; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE asignacion RENAME CONSTRAINT parking_assignment_vehicle_id_fkey TO asignacion_vehiculo_id_fkey; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE asignacion RENAME CONSTRAINT parking_assignment_pkey TO asignacion_pkey; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE celda RENAME CONSTRAINT parking_spot_pkey TO celda_pkey; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE celda RENAME CONSTRAINT parking_spot_code_key TO celda_codigo_key; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE residente RENAME CONSTRAINT resident_admin_score_check TO residente_puntaje_administrativo_check; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE residente RENAME CONSTRAINT resident_debt_check TO residente_deuda_check; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE residente RENAME CONSTRAINT resident_document_type_check TO residente_tipo_documento_check; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE residente RENAME CONSTRAINT resident_status_check TO residente_estado_check; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE residente RENAME CONSTRAINT resident_house_id_fkey TO residente_vivienda_id_fkey; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE residente RENAME CONSTRAINT resident_pkey TO residente_pkey; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE residente RENAME CONSTRAINT resident_document_number_key TO residente_numero_documento_key; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE cuenta_usuario RENAME CONSTRAINT user_account_role_check TO cuenta_usuario_rol_check; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE cuenta_usuario RENAME CONSTRAINT user_account_resident_id_fkey TO cuenta_usuario_residente_id_fkey; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE cuenta_usuario RENAME CONSTRAINT user_account_pkey TO cuenta_usuario_pkey; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE cuenta_usuario RENAME CONSTRAINT user_account_resident_id_key TO cuenta_usuario_residente_id_key; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE cuenta_usuario RENAME CONSTRAINT user_account_username_key TO cuenta_usuario_usuario_key; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE vehiculo RENAME CONSTRAINT vehicle_plate_check TO vehiculo_placa_check; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE vehiculo RENAME CONSTRAINT vehicle_type_check TO vehiculo_tipo_check; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE vehiculo RENAME CONSTRAINT vehicle_resident_id_fkey TO vehiculo_residente_id_fkey; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE vehiculo RENAME CONSTRAINT vehicle_pkey TO vehiculo_pkey; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE vehiculo RENAME CONSTRAINT vehicle_plate_key TO vehiculo_placa_key; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE movimiento_vehiculo RENAME CONSTRAINT vehicle_movement_source_check TO movimiento_vehiculo_origen_check; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE movimiento_vehiculo RENAME CONSTRAINT vehicle_movement_type_check TO movimiento_vehiculo_tipo_check; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE movimiento_vehiculo RENAME CONSTRAINT vehicle_movement_assignment_id_fkey TO movimiento_vehiculo_asignacion_id_fkey; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE movimiento_vehiculo RENAME CONSTRAINT vehicle_movement_parking_spot_id_fkey TO movimiento_vehiculo_celda_id_fkey; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE movimiento_vehiculo RENAME CONSTRAINT vehicle_movement_recorded_by_fkey TO movimiento_vehiculo_registrado_por_fkey; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE movimiento_vehiculo RENAME CONSTRAINT vehicle_movement_vehicle_id_fkey TO movimiento_vehiculo_vehiculo_id_fkey; EXCEPTION WHEN undefined_object THEN NULL; END;
  BEGIN ALTER TABLE movimiento_vehiculo RENAME CONSTRAINT vehicle_movement_pkey TO movimiento_vehiculo_pkey; EXCEPTION WHEN undefined_object THEN NULL; END;

  -- Nombres de entidad registrados en la auditoría
  UPDATE auditoria SET entidad = CASE entidad
      WHEN 'house' THEN 'vivienda'
      WHEN 'resident' THEN 'residente'
      WHEN 'vehicle' THEN 'vehiculo'
      WHEN 'parking_spot' THEN 'celda'
      WHEN 'cycle' THEN 'ciclo'
      WHEN 'parking_assignment' THEN 'asignacion'
      WHEN 'user_account' THEN 'cuenta_usuario'
      WHEN 'vehicle_movement' THEN 'movimiento_vehiculo'
      WHEN 'notification' THEN 'notificacion'
      WHEN 'audit_log' THEN 'auditoria'
      WHEN 'backup_record' THEN 'respaldo'
      ELSE entidad END;

  RAISE NOTICE 'Base de datos migrada a nombres en español.';
END
$$;
