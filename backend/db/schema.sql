-- =====================================================================
--  Parqueadero Comunitario - Conjunto Residencial Nueva Castilla Etapa 3
--  Esquema PostgreSQL (Anexo 2 "Diseño de la base de datos")
--  Ejecutar sobre una base vacía:  psql -d parqueadero -f db/schema.sql
--
--  Tablas: vivienda, residente, vehiculo, celda, ciclo, asignacion,
--          cuenta_usuario, movimiento_vehiculo, notificacion, auditoria, respaldo
-- =====================================================================


-- ---------------------------------------------------------------------
--  Viviendas del conjunto
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS vivienda (
  id                        SERIAL PRIMARY KEY,
  bloque                    VARCHAR(20)  NOT NULL DEFAULT '',
  numero                    VARCHAR(20)  NOT NULL,
  habitada_por_propietario  BOOLEAN      NOT NULL DEFAULT TRUE,
  CONSTRAINT vivienda_bloque_numero_uk UNIQUE (bloque, numero)
);

-- ---------------------------------------------------------------------
--  Residentes
--  deuda / puntaje_administrativo / tiene_discapacidad alimentan las reglas del sorteo:
--   * deuda = 0                -> "haber pagado la administración"
--   * puntaje_administrativo   -> Pa (puntaje administrativo) del IPA
--   * tiene_discapacidad       -> prioridad sobre celdas para discapacidad
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS residente (
  id                      SERIAL PRIMARY KEY,
  vivienda_id             INT           NOT NULL REFERENCES vivienda(id) ON DELETE RESTRICT,
  nombre_completo         VARCHAR(120)  NOT NULL,
  tipo_documento          VARCHAR(10)   NOT NULL DEFAULT 'CC'
                          CHECK (tipo_documento IN ('CC','CE','TI','PA','NIT')),
  numero_documento        VARCHAR(30)   NOT NULL UNIQUE,
  telefono                VARCHAR(30),
  correo                  VARCHAR(120),
  estado                  VARCHAR(20)   NOT NULL DEFAULT 'activo'
                          CHECK (estado IN ('activo','inactivo')),
  deuda                   NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (deuda >= 0),
  puntaje_administrativo  SMALLINT      NOT NULL DEFAULT 0 CHECK (puntaje_administrativo BETWEEN 0 AND 5),
  tiene_discapacidad      BOOLEAN       NOT NULL DEFAULT FALSE,
  creado_en               TIMESTAMPTZ   NOT NULL DEFAULT now(),
  actualizado_en          TIMESTAMPTZ   NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS residente_vivienda_idx ON residente(vivienda_id);

-- ---------------------------------------------------------------------
--  Vehículos
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS vehiculo (
  id            SERIAL PRIMARY KEY,
  residente_id  INT          NOT NULL REFERENCES residente(id) ON DELETE CASCADE,
  placa         VARCHAR(10)  NOT NULL UNIQUE CHECK (placa ~ '^[A-Z0-9]{5,7}$'),
  tipo          VARCHAR(20)  NOT NULL DEFAULT 'carro' CHECK (tipo IN ('carro','moto','camioneta','otro')),
  marca         VARCHAR(40),
  modelo        VARCHAR(40),
  color         VARCHAR(30),
  activo        BOOLEAN      NOT NULL DEFAULT TRUE,
  creado_en     TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS vehiculo_residente_idx ON vehiculo(residente_id);

-- ---------------------------------------------------------------------
--  Celdas del parqueadero comunitario
--  ocupada refleja la ocupación física (entradas / salidas)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS celda (
  id                 SERIAL PRIMARY KEY,
  codigo             VARCHAR(10)  NOT NULL UNIQUE,
  para_discapacidad  BOOLEAN      NOT NULL DEFAULT FALSE,
  activo             BOOLEAN      NOT NULL DEFAULT TRUE,
  ocupada            BOOLEAN      NOT NULL DEFAULT FALSE,
  observaciones      TEXT
);

-- ---------------------------------------------------------------------
--  Ciclos de rotación (2 a 6 meses)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ciclo (
  id            SERIAL PRIMARY KEY,
  nombre        VARCHAR(60)  NOT NULL,
  fecha_inicio  DATE         NOT NULL,
  fecha_fin     DATE         NOT NULL,
  fecha_sorteo  DATE,
  estado        VARCHAR(20)  NOT NULL DEFAULT 'planeado'
                CHECK (estado IN ('planeado','activo','cerrado')),
  creado_en     TIMESTAMPTZ  NOT NULL DEFAULT now(),
  CONSTRAINT ciclo_fechas_ck CHECK (fecha_fin > fecha_inicio),
  CONSTRAINT ciclo_duracion_ck CHECK (fecha_fin <= fecha_inicio + INTERVAL '6 months 1 day')
);
-- Solo puede existir un ciclo activo a la vez
CREATE UNIQUE INDEX IF NOT EXISTS ciclo_un_activo_uk ON ciclo(estado) WHERE estado = 'activo';

-- ---------------------------------------------------------------------
--  Asignaciones de celdas por ciclo
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS asignacion (
  id             SERIAL PRIMARY KEY,
  ciclo_id       INT           NOT NULL REFERENCES ciclo(id) ON DELETE RESTRICT,
  residente_id   INT           NOT NULL REFERENCES residente(id) ON DELETE RESTRICT,
  vehiculo_id    INT           NOT NULL REFERENCES vehiculo(id) ON DELETE RESTRICT,
  celda_id       INT           NOT NULL REFERENCES celda(id) ON DELETE RESTRICT,
  metodo         VARCHAR(20)   NOT NULL DEFAULT 'sorteo' CHECK (metodo IN ('sorteo','manual')),
  puntaje_ipa    NUMERIC(8,3),
  asignado_en    TIMESTAMPTZ   NOT NULL DEFAULT now(),
  liberado_en    TIMESTAMPTZ,
  estado         VARCHAR(20)   NOT NULL DEFAULT 'vigente'
                 CHECK (estado IN ('vigente','finalizada','cancelada')),
  observaciones  TEXT
);
-- Una celda y un residente solo pueden tener una asignación vigente por ciclo
CREATE UNIQUE INDEX IF NOT EXISTS asignacion_celda_ciclo_uk
  ON asignacion(ciclo_id, celda_id) WHERE estado = 'vigente';
CREATE UNIQUE INDEX IF NOT EXISTS asignacion_residente_ciclo_uk
  ON asignacion(ciclo_id, residente_id) WHERE estado = 'vigente';
CREATE INDEX IF NOT EXISTS asignacion_residente_idx ON asignacion(residente_id);

-- ---------------------------------------------------------------------
--  Cuentas de usuario y roles
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cuenta_usuario (
  id                       SERIAL PRIMARY KEY,
  residente_id             INT          UNIQUE REFERENCES residente(id) ON DELETE SET NULL,
  usuario                  VARCHAR(60)  NOT NULL UNIQUE,
  nombre_completo          VARCHAR(120) NOT NULL DEFAULT '',
  hash_contrasena          TEXT         NOT NULL,
  rol                      VARCHAR(20)  NOT NULL CHECK (rol IN ('admin','guarda','residente')),
  activo                   BOOLEAN      NOT NULL DEFAULT TRUE,
  bloqueado                BOOLEAN      NOT NULL DEFAULT FALSE,
  intentos_fallidos        SMALLINT     NOT NULL DEFAULT 0,
  debe_cambiar_contrasena  BOOLEAN      NOT NULL DEFAULT FALSE,
  ultimo_ingreso_en        TIMESTAMPTZ,
  creado_en                TIMESTAMPTZ  NOT NULL DEFAULT now(),
  CONSTRAINT cuenta_residente_rol_ck CHECK (rol <> 'residente' OR residente_id IS NOT NULL)
);

-- ---------------------------------------------------------------------
--  Entradas y salidas de vehículos
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS movimiento_vehiculo (
  id              SERIAL PRIMARY KEY,
  placa           VARCHAR(10)  NOT NULL,
  vehiculo_id     INT          REFERENCES vehiculo(id) ON DELETE SET NULL,
  celda_id        INT          REFERENCES celda(id) ON DELETE SET NULL,
  asignacion_id   INT          REFERENCES asignacion(id) ON DELETE SET NULL,
  tipo            VARCHAR(10)  NOT NULL CHECK (tipo IN ('entrada','salida')),
  autorizado      BOOLEAN      NOT NULL,
  origen          VARCHAR(20)  NOT NULL DEFAULT 'manual' CHECK (origen IN ('manual','lector')),
  motivo          TEXT,
  registrado_por  INT          REFERENCES cuenta_usuario(id) ON DELETE SET NULL,
  registrado_en   TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS movimiento_registrado_idx ON movimiento_vehiculo(registrado_en DESC);
CREATE INDEX IF NOT EXISTS movimiento_placa_idx ON movimiento_vehiculo(placa);

-- ---------------------------------------------------------------------
--  Notificaciones
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS notificacion (
  id                 SERIAL PRIMARY KEY,
  cuenta_usuario_id  INT          REFERENCES cuenta_usuario(id) ON DELETE CASCADE,
  rol_destino        VARCHAR(20)  CHECK (rol_destino IN ('admin','guarda','residente')),
  titulo             VARCHAR(120) NOT NULL,
  cuerpo             TEXT         NOT NULL DEFAULT '',
  categoria          VARCHAR(30)  NOT NULL DEFAULT 'info',
  creado_en          TIMESTAMPTZ  NOT NULL DEFAULT now(),
  leido_en           TIMESTAMPTZ,
  CONSTRAINT notificacion_destino_ck CHECK (cuenta_usuario_id IS NOT NULL OR rol_destino IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS notificacion_usuario_idx ON notificacion(cuenta_usuario_id, creado_en DESC);

-- ---------------------------------------------------------------------
--  Auditoría de movimientos del sistema
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS auditoria (
  id                 SERIAL PRIMARY KEY,
  cuenta_usuario_id  INT          REFERENCES cuenta_usuario(id) ON DELETE SET NULL,
  accion             VARCHAR(60)  NOT NULL,
  entidad            VARCHAR(60),
  entidad_id         INT,
  realizado_en       TIMESTAMPTZ  NOT NULL DEFAULT now(),
  detalles           JSONB
);
CREATE INDEX IF NOT EXISTS auditoria_realizado_idx ON auditoria(realizado_en DESC);

-- ---------------------------------------------------------------------
--  Registro de respaldos automáticos y manuales
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS respaldo (
  id              SERIAL PRIMARY KEY,
  nombre_archivo  VARCHAR(200) NOT NULL,
  tamano_bytes    BIGINT       NOT NULL DEFAULT 0,
  estado          VARCHAR(20)  NOT NULL CHECK (estado IN ('ok','error')),
  error           TEXT,
  disparador      VARCHAR(20)  NOT NULL DEFAULT 'automatico' CHECK (disparador IN ('automatico','manual')),
  creado_en       TIMESTAMPTZ  NOT NULL DEFAULT now()
);
