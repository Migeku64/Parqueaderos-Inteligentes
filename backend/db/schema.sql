-- =====================================================================
--  Parqueadero Comunitario - Conjunto Residencial Nueva Castilla Etapa 3
--  Esquema PostgreSQL (basado en el Anexo 2 "Diseño de la base de datos")
--  Ejecutar sobre una base vacía:  psql -d parqueadero -f db/schema.sql
-- =====================================================================


-- ---------------------------------------------------------------------
--  Viviendas (house)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS house (
  id                 SERIAL PRIMARY KEY,
  block              VARCHAR(20)  NOT NULL DEFAULT '',
  number             VARCHAR(20)  NOT NULL,
  is_owner_occupied  BOOLEAN      NOT NULL DEFAULT TRUE,
  CONSTRAINT house_block_number_uk UNIQUE (block, number)
);

-- ---------------------------------------------------------------------
--  Residentes (resident)
--  debt / admin_score / has_disability alimentan las reglas del sorteo:
--   * debt = 0  -> "haber pagado la administración"
--   * admin_score -> P_a (puntaje administrativo) del IPA
--   * has_disability -> prioridad sobre celdas para discapacidad
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS resident (
  id               SERIAL PRIMARY KEY,
  house_id         INT          NOT NULL REFERENCES house(id) ON DELETE RESTRICT,
  full_name        VARCHAR(120) NOT NULL,
  document_type    VARCHAR(10)  NOT NULL DEFAULT 'CC'
                   CHECK (document_type IN ('CC','CE','TI','PA','NIT')),
  document_number  VARCHAR(30)  NOT NULL UNIQUE,
  phone            VARCHAR(30),
  email            VARCHAR(120),
  status           VARCHAR(20)  NOT NULL DEFAULT 'activo'
                   CHECK (status IN ('activo','inactivo')),
  debt             NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (debt >= 0),
  admin_score      SMALLINT     NOT NULL DEFAULT 0 CHECK (admin_score BETWEEN 0 AND 5),
  has_disability   BOOLEAN      NOT NULL DEFAULT FALSE,
  created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS resident_house_idx ON resident(house_id);

-- ---------------------------------------------------------------------
--  Vehículos (vehicle)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS vehicle (
  id           SERIAL PRIMARY KEY,
  resident_id  INT          NOT NULL REFERENCES resident(id) ON DELETE CASCADE,
  plate        VARCHAR(10)  NOT NULL UNIQUE CHECK (plate ~ '^[A-Z0-9]{5,7}$'),
  type         VARCHAR(20)  NOT NULL DEFAULT 'carro' CHECK (type IN ('carro','moto','camioneta','otro')),
  brand        VARCHAR(40),
  model        VARCHAR(40),
  color        VARCHAR(30),
  is_active    BOOLEAN      NOT NULL DEFAULT TRUE,
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS vehicle_resident_idx ON vehicle(resident_id);

-- ---------------------------------------------------------------------
--  Celdas del parqueadero comunitario (parking_spot)
--  is_occupied refleja la ocupación física (entradas / salidas)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS parking_spot (
  id                SERIAL PRIMARY KEY,
  code              VARCHAR(10)  NOT NULL UNIQUE,
  is_disabled_spot  BOOLEAN      NOT NULL DEFAULT FALSE,
  is_active         BOOLEAN      NOT NULL DEFAULT TRUE,
  is_occupied       BOOLEAN      NOT NULL DEFAULT FALSE,
  notes             TEXT
);

-- ---------------------------------------------------------------------
--  Ciclos de rotación (2 a 6 meses)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cycle (
  id          SERIAL PRIMARY KEY,
  name        VARCHAR(60)  NOT NULL,
  start_date  DATE         NOT NULL,
  end_date    DATE         NOT NULL,
  draw_date   DATE,
  status      VARCHAR(20)  NOT NULL DEFAULT 'planeado'
              CHECK (status IN ('planeado','activo','cerrado')),
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
  CONSTRAINT cycle_dates_ck CHECK (end_date > start_date),
  CONSTRAINT cycle_length_ck CHECK (end_date <= start_date + INTERVAL '6 months 1 day')
);
-- Solo puede existir un ciclo activo a la vez
CREATE UNIQUE INDEX IF NOT EXISTS cycle_one_active_uk ON cycle(status) WHERE status = 'activo';

-- ---------------------------------------------------------------------
--  Asignaciones (parking_assignment)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS parking_assignment (
  id               SERIAL PRIMARY KEY,
  cycle_id         INT          NOT NULL REFERENCES cycle(id) ON DELETE RESTRICT,
  resident_id      INT          NOT NULL REFERENCES resident(id) ON DELETE RESTRICT,
  vehicle_id       INT          NOT NULL REFERENCES vehicle(id) ON DELETE RESTRICT,
  parking_spot_id  INT          NOT NULL REFERENCES parking_spot(id) ON DELETE RESTRICT,
  method           VARCHAR(20)  NOT NULL DEFAULT 'sorteo' CHECK (method IN ('sorteo','manual')),
  ipa_score        NUMERIC(8,3),
  assigned_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
  released_at      TIMESTAMPTZ,
  status           VARCHAR(20)  NOT NULL DEFAULT 'vigente'
                   CHECK (status IN ('vigente','finalizada','cancelada')),
  notes            TEXT
);
-- Una celda y un residente solo pueden tener una asignación vigente por ciclo
CREATE UNIQUE INDEX IF NOT EXISTS assignment_spot_cycle_uk
  ON parking_assignment(cycle_id, parking_spot_id) WHERE status = 'vigente';
CREATE UNIQUE INDEX IF NOT EXISTS assignment_resident_cycle_uk
  ON parking_assignment(cycle_id, resident_id) WHERE status = 'vigente';
CREATE INDEX IF NOT EXISTS assignment_resident_idx ON parking_assignment(resident_id);

-- ---------------------------------------------------------------------
--  Cuentas de usuario y roles (user_account)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_account (
  id               SERIAL PRIMARY KEY,
  resident_id      INT          UNIQUE REFERENCES resident(id) ON DELETE SET NULL,
  username         VARCHAR(60)  NOT NULL UNIQUE,
  full_name        VARCHAR(120) NOT NULL DEFAULT '',
  password_hash    TEXT         NOT NULL,
  role             VARCHAR(20)  NOT NULL CHECK (role IN ('admin','guarda','residente')),
  is_active        BOOLEAN      NOT NULL DEFAULT TRUE,
  is_blocked       BOOLEAN      NOT NULL DEFAULT FALSE,
  failed_attempts  SMALLINT     NOT NULL DEFAULT 0,
  must_change_password BOOLEAN  NOT NULL DEFAULT FALSE,
  last_login_at    TIMESTAMPTZ,
  created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
  CONSTRAINT resident_role_ck CHECK (role <> 'residente' OR resident_id IS NOT NULL)
);

-- ---------------------------------------------------------------------
--  Entradas y salidas (vehicle_movement)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS vehicle_movement (
  id               SERIAL PRIMARY KEY,
  plate            VARCHAR(10)  NOT NULL,
  vehicle_id       INT          REFERENCES vehicle(id) ON DELETE SET NULL,
  parking_spot_id  INT          REFERENCES parking_spot(id) ON DELETE SET NULL,
  assignment_id    INT          REFERENCES parking_assignment(id) ON DELETE SET NULL,
  type             VARCHAR(10)  NOT NULL CHECK (type IN ('entrada','salida')),
  authorized       BOOLEAN      NOT NULL,
  source           VARCHAR(20)  NOT NULL DEFAULT 'manual' CHECK (source IN ('manual','lector')),
  reason           TEXT,
  recorded_by      INT          REFERENCES user_account(id) ON DELETE SET NULL,
  recorded_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS movement_recorded_idx ON vehicle_movement(recorded_at DESC);
CREATE INDEX IF NOT EXISTS movement_plate_idx ON vehicle_movement(plate);

-- ---------------------------------------------------------------------
--  Notificaciones
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS notification (
  id               SERIAL PRIMARY KEY,
  user_account_id  INT          REFERENCES user_account(id) ON DELETE CASCADE,
  target_role      VARCHAR(20)  CHECK (target_role IN ('admin','guarda','residente')),
  title            VARCHAR(120) NOT NULL,
  body             TEXT         NOT NULL DEFAULT '',
  kind             VARCHAR(30)  NOT NULL DEFAULT 'info',
  created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
  read_at          TIMESTAMPTZ,
  CONSTRAINT notification_target_ck CHECK (user_account_id IS NOT NULL OR target_role IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS notification_user_idx ON notification(user_account_id, created_at DESC);

-- ---------------------------------------------------------------------
--  Auditoría (audit_log)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_log (
  id               SERIAL PRIMARY KEY,
  user_account_id  INT          REFERENCES user_account(id) ON DELETE SET NULL,
  action           VARCHAR(60)  NOT NULL,
  entity_name      VARCHAR(60),
  entity_id        INT,
  performed_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
  details          JSONB
);
CREATE INDEX IF NOT EXISTS audit_performed_idx ON audit_log(performed_at DESC);

-- ---------------------------------------------------------------------
--  Registro de respaldos automáticos
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS backup_record (
  id           SERIAL PRIMARY KEY,
  file_name    VARCHAR(200) NOT NULL,
  size_bytes   BIGINT       NOT NULL DEFAULT 0,
  status       VARCHAR(20)  NOT NULL CHECK (status IN ('ok','error')),
  error        TEXT,
  trigger      VARCHAR(20)  NOT NULL DEFAULT 'automatico' CHECK (trigger IN ('automatico','manual')),
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT now()
);

