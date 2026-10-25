# Instala y configura el backend en Windows.
# Uso: doble clic en INSTALAR.bat  (o: powershell -ExecutionPolicy Bypass -File instalar_backend.ps1)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

function Fail($msg) {
    Write-Host ""
    Write-Host "ERROR: $msg" -ForegroundColor Red
    exit 1
}

Write-Host "=== Instalacion del backend - Parqueadero Comunitario ===" -ForegroundColor Cyan

# 1. Node.js
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { Fail "No se encontro Node.js. Instalelo desde https://nodejs.org (version LTS), cierre esta ventana y vuelva a intentar." }
$ver = (node -v)
Write-Host "Node.js $ver encontrado."
if ([int]($ver.TrimStart('v').Split('.')[0]) -lt 20) { Fail "Se necesita Node.js 20 o superior (tiene $ver)." }

# 2. Datos de conexion a PostgreSQL
Write-Host ""
Write-Host "Datos de PostgreSQL (los mismos que usa en pgAdmin)."
$user = Read-Host "Usuario de PostgreSQL [postgres]"
if ([string]::IsNullOrWhiteSpace($user)) { $user = "postgres" }
$sec = Read-Host "Contrasena de PostgreSQL" -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
$pass = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
$port = Read-Host "Puerto [5432]"
if ([string]::IsNullOrWhiteSpace($port)) { $port = "5432" }

$u = [uri]::EscapeDataString($user)
$p = [uri]::EscapeDataString($pass)
$secret = [guid]::NewGuid().ToString("N") + [guid]::NewGuid().ToString("N")

$envText = @"
DATABASE_URL=postgres://${u}:${p}@localhost:${port}/parqueadero
DATABASE_SSL=false
PORT=3000
JWT_SECRET=$secret
JWT_EXPIRES_HOURS=12
BACKUP_DIR=backups
BACKUP_INTERVAL_HOURS=24
BACKUP_KEEP=30
MAX_FAILED_LOGINS=5
PLATE_READER_KEY=
"@
Set-Content -Path ".env" -Value $envText -Encoding Ascii
Write-Host "Archivo .env creado."

# 3. Dependencias
Write-Host ""
Write-Host "Instalando dependencias (npm install)..."
npm install
if ($LASTEXITCODE -ne 0) { Fail "npm install fallo. Revise su conexion a internet." }

# 4. Base de datos + datos de demostracion
Write-Host ""
Write-Host "Creando la base 'parqueadero', las tablas y los datos de demostracion..."
node scripts/migrate.js --reset
if ($LASTEXITCODE -ne 0) { Fail "No se pudo preparar la base de datos (vea el mensaje de arriba). Ejecute INSTALAR.bat de nuevo." }
node scripts/seed.js --force
if ($LASTEXITCODE -ne 0) { Fail "No se pudieron cargar los datos de demostracion." }

# 5. IP local (para probar desde un celular real)
$ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
    Select-Object -ExpandProperty IPAddress

Write-Host ""
Write-Host "=== LISTO ===" -ForegroundColor Green
Write-Host "Para encender la API: doble clic en INICIAR.bat (deje esa ventana abierta)."
Write-Host "Usuarios: admin/admin123  guarda/guarda123  mpinilla/residente123"
Write-Host "Direccion del servidor en la app:"
Write-Host "   Emulador Android : http://10.0.2.2:3000"
Write-Host "   Windows          : http://localhost:3000"
foreach ($ip in $ips) { Write-Host "   Celular (Wi-Fi)  : http://${ip}:3000" }
