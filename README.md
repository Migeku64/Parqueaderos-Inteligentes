# Parqueadero Comunitario – Nueva Castilla Etapa 3

Sistema para la gestión y asignación de parqueaderos comunitarios (trabajo de grado, Ingeniería de Software – UMB).

| Parte | Tecnología | Carpeta |
|---|---|---|
| App para **Android, iOS y Windows** | Flutter (un solo código) | `app/` |
| API REST + tiempo real (WebSocket) | Node.js 20+ | `backend/` |
| Base de datos | PostgreSQL 14+ | `backend/db/schema.sql` |

Roles: **Administrador**, **Guarda de seguridad** y **Residente** (Tabla 1 del documento).

---

## 1. Requisitos (instalar una vez)

1. **Android Studio** (última versión) → https://developer.android.com/studio
2. **Flutter SDK** → https://docs.flutter.dev/get-started/install/windows
   - Descomprima Flutter en `C:\src\flutter` y agregue `C:\src\flutter\bin` a la variable `Path`.
   - En una terminal ejecute `flutter doctor` y siga lo que indique (aceptar licencias: `flutter doctor --android-licenses`).
3. En Android Studio: **File → Settings → Plugins → Marketplace**, busque **Flutter**, instálelo (instala también Dart) y reinicie.
4. **Node.js 20 o superior** → https://nodejs.org
5. **PostgreSQL** (ustedes ya lo usan con pgAdmin 4).
6. Solo para la versión de Windows: **Visual Studio 2022 Community** con la carga de trabajo *"Desarrollo para el escritorio con C++"*.

---

## 2. Poner a funcionar el backend (API)

**Forma fácil (Windows):**
1. Abra la carpeta `backend` y haga doble clic en **`INSTALAR.bat`**. Le pedirá la contraseña de PostgreSQL
   (la misma de pgAdmin); crea el archivo `.env`, instala dependencias, **crea la base `parqueadero`**, las tablas y los datos de demostración.
2. Doble clic en **`INICIAR.bat`** y deje esa ventana abierta mientras usa la app.
3. Abra http://localhost:3000/health en el navegador: debe responder `{"status":"ok"...}`.
4. En pgAdmin: clic derecho en *Databases* → *Refresh* y verá la base `parqueadero` con sus tablas.

**Forma manual:** copie `backend/.env.example` como `backend/.env`, ponga su clave en `DATABASE_URL` y ejecute
`npm install`, `npm run db:reset` y `npm start` dentro de `backend/`.

Usuarios de prueba:

| Rol | Usuario | Contraseña |
|---|---|---|
| Administradores (autores) | `mpinilla`, `acardona`, `jmontoya` (y `admin`) | `admin123` |
| Guarda | `guarda` | `guarda123` |
| Residentes (casas 1 a 300) | `casa` + número de casa: `casa150` (Miguel), `casa201`, `casa101`… | `residente123` |

> Alternativa con Docker: desde la carpeta raíz, `docker compose up --build` levanta PostgreSQL + la API ya configuradas.

---

## 3. Abrir y ejecutar la app en Android Studio

1. **File → Open…** y seleccione la carpeta **`app`** (no la raíz del proyecto).
2. Abra la **Terminal** de Android Studio (abajo) y ejecute **una sola vez**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\configurar_plataformas.ps1
   ```
   Esto genera las carpetas `android/` y `windows/` que Flutter necesita y descarga las dependencias
   (no borra el código de `lib/`).
3. Cree un emulador: **Tools → Device Manager → Create Device** (por ejemplo Pixel 7, Android 14).
4. Seleccione el emulador en la barra superior y pulse **Run ▶** (o `flutter run` en la terminal).
5. En la pantalla de inicio, el engranaje ⚙ (arriba a la derecha) permite cambiar la dirección del servidor:

| Dónde corre la app | Dirección del servidor |
|---|---|
| Emulador de Android | `http://10.0.2.2:3000` (ya viene por defecto) |
| Windows / simulador iOS | `http://localhost:3000` (por defecto) |
| Celular real en la misma red Wi-Fi | `http://IP-DE-SU-PC:3000` (vea la IP con `ipconfig`) |
| API publicada en la nube | `https://su-api.onrender.com` (por ejemplo) |

> Si usa un celular real, permita el puerto 3000 en el Firewall de Windows.

### Generar el APK (instalador Android)

```bash
flutter build apk --release
```
Queda en `app/build/app/outputs/flutter-apk/app-release.apk`. Cópielo al celular e instálelo.

### Generar la versión de Windows

En Android Studio elija el dispositivo **Windows (desktop)** y pulse Run, o:
```bash
flutter build windows --release
```
El programa queda en `app/build/windows/x64/runner/Release/` (comparta esa carpeta completa; el `.exe` necesita los archivos que lo acompañan).

### Generar la versión de iOS

Apple solo permite compilar apps de iPhone en un **Mac con Xcode**:
```bash
cd app
bash scripts/configurar_plataformas.sh   # genera ios/ y ajusta permisos
open ios/Runner.xcworkspace              # en Xcode: Signing & Capabilities → elegir su Apple ID
flutter run                              # con el iPhone conectado
```
Para instalarla en un iPhone hace falta firmarla con una cuenta de Apple (gratis para pruebas personales, o la cuenta de desarrollador para publicarla en la App Store).

**Sin Mac:** suba el proyecto a GitHub (ya tienen el repositorio `Parqueaderos-Inteligentes`). El flujo
`.github/workflows/build-apps.yml` compila automáticamente el **APK**, la versión de **Windows** y un **.ipa de iOS sin firmar**
y ejecuta las pruebas del backend. Los archivos se descargan en la pestaña **Actions → (ejecución) → Artifacts**.

---

## 4. Qué hace cada rol en la app

**Administrador**
- *Inicio*: celdas libres/ocupadas, entradas del día, ingresos rechazados, avance del ciclo, gráfico de 7 días.
- *Mapa*: las 50 celdas en tiempo real (libre / asignada / ocupada / inactiva); asignar o cancelar manualmente.
- *Residentes*: registrar, editar, buscar por cédula, nombre, casa o placa; vehículos; deuda; puntaje administrativo; historial.
- *Ciclos y sorteos*: crear ciclos de 2 a 6 meses, **simular el sorteo**, revisar/ajustar y confirmar, activar y finalizar ciclos.
- *Control de acceso* y *Movimientos*: igual que el guarda, más el historial completo.
- *Reportes*: ocupación, cumplimiento de ciclos, historial de asignaciones, entradas y salidas; **exportar a CSV (Excel)**.
- *Usuarios*: crear cuentas, cambiar roles, bloquear/desbloquear, restablecer contraseñas.
- *Auditoría y respaldos*: registro de todas las acciones y copias de seguridad automáticas.

**Guarda de seguridad**
- Escribe la placa y pulsa **ENTRADA** o **SALIDA**. El sistema valida si el residente tiene celda vigente en el ciclo actual,
  le indica el número de celda y, si no está autorizado, registra el intento y alerta a la administración.

**Residente**
- *Mi parqueadero*: estado, casa, vehículo, turno (ACTIVO / PRÓXIMO / INACTIVO) y celda (como el mockup).
- *Sorteos*: turno actual, fecha del próximo sorteo, lote en uso, **su IPA y posición estimada**, historial.
- *Disponibilidad*: mapa de celdas sin datos personales de otros residentes.
- *Ayuda*: preguntas frecuentes.

---

## 5. El sorteo y la fórmula IPA (Ecuación 1)

```
IPA = (Te + Pa + Hn) / (Cu + 1)
```
- **Te**: meses de espera desde su último uso (o desde su registro), máximo 24.
- **Pa**: puntaje administrativo 0–5 (lo define la administración en la ficha del residente).
- **Hn**: de los últimos 6 ciclos, en cuántos **no** tuvo parqueadero.
- **Cu**: ciclos en los que ya usó el parqueadero.

Reglas de elegibilidad (Capítulo I): residente activo, **al día con la administración** (deuda = 0), con vehículo registrado,
**que no haya usado el parqueadero en el ciclo anterior** y con usuario no bloqueado. Las celdas para personas con discapacidad
se asignan primero a quienes las requieren.

Modos: **ponderado** (rifa con probabilidad proporcional a IPA + 1) o **por prioridad** (orden de IPA, empates al azar).
El administrador primero **simula**, revisa la propuesta (puede quitar personas) y luego **confirma**; los residentes reciben
una notificación con el resultado. Código: `backend/src/services/draw.js`.

---

## 6. Correspondencia con los requerimientos del documento

| Requerimiento | Dónde está |
|---|---|
| RF01 Gestión de residentes | Residentes · `POST/PUT /residents` |
| RF02 Registro de vehículos | Ficha del residente · `/residents/:id/vehicles` |
| RF03 Asignación automática | Ciclos y sorteos · `/cycles/:id/draw` |
| RF04 Disponibilidad en tiempo real | Mapa · `GET /spots` + WebSocket `/ws` |
| RF05 / RF06 Ingreso y salida | Control de acceso · `POST /movements` |
| RF07 Usuarios y roles | Usuarios · `/users` |
| RF08 Reportes administrativos | Reportes · `/reports/:tipo` |
| RF09 Validación de disponibilidad | Restricciones únicas en BD + validación en sorteo y entradas |
| RF10 Historial de asignaciones | Ficha del residente, asignaciones por ciclo · `/assignments` |
| RF11 Autenticación | Login · `/auth/login` (JWT, contraseñas con scrypt) |
| RF12 Recuperación de credenciales | "¿Olvidó su contraseña?" + Restablecer en Usuarios |
| RF13 Notificaciones automáticas | Campana 🔔 · sorteos, fin de ciclo (7 días antes), alertas |
| RF14 Dashboard | Inicio (administrador) · `/dashboard` |
| RF15 Auditoría | Auditoría y respaldos · `/audit` |
| RF16 Monitoreo de ocupados | Mapa + tiempo real |
| RF17 Gestión de ciclos | Ciclos y sorteos · `/cycles` |
| RF18 Bloqueo de usuarios | Automático a los 5 intentos fallidos + manual |
| RF19 Exportación de reportes | Botón "Exportar CSV" |
| RF20 Respaldo automático | Cada 24 h (configurable) + "Respaldar ahora" |
| RNF04 Multiplataforma | Flutter: Android, iOS, Windows |
| RNF09 Control por roles | `requireRole` en la API + menús por rol |
| Lectura automática de placas | `POST /movements/reader` para cámaras ANPR (header `X-Device-Key`) |

---

## 7. Publicar la API en la nube (Render + Neon)

El archivo `render.yaml` permite crear el servicio en Render con *New → Blueprint*. Solo pide `DATABASE_URL` (la cadena de conexión de Neon).

### Pasos manuales (alternativa)

1. Cree una base PostgreSQL gestionada (Neon, Supabase o Render tienen plan gratuito).
2. Cree un *Web Service* en Render (o Railway) apuntando a la carpeta `backend/` con comando de inicio
   `node scripts/migrate.js && node src/server.js` y las variables `DATABASE_URL`, `DATABASE_SSL=true`, `JWT_SECRET`.
3. En la app, en el engranaje del login, ponga la URL `https://...` del servicio.

---

## 8. Pruebas

```bash
cd backend
# usa una base separada para no borrar sus datos
DATABASE_URL=postgres://postgres:CLAVE@localhost:5432/parqueadero_test npm test     # 14 pruebas de integración
cd ../app
flutter test
```
En Windows (PowerShell): `$env:DATABASE_URL="postgres://..."; npm test`.

## Estructura

```
backend/
  db/schema.sql            tablas (house, resident, vehicle, parking_spot, cycle, parking_assignment,
                           user_account, vehicle_movement, notification, audit_log, backup_record)
  src/routes/              endpoints REST por módulo
  src/services/draw.js     sorteo + IPA
  src/ws.js                WebSocket de tiempo real
  scripts/seed.js          datos de demostración
  test/api.test.js         pruebas
app/
  lib/core/                API, sesión, tiempo real, formato, tema
  lib/screens/admin/       pantallas del administrador
  lib/screens/guard/       control de acceso
  lib/screens/resident/    pantallas del residente (mockups)
  lib/screens/shared/      mapa, movimientos, notificaciones
```
