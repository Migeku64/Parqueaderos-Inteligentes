# Compila e instala "Nueva Castilla Etapa 3 Parking" en este PC:
#   1. Pone el nombre nuevo en la app de Windows.
#   2. Compila la version Release.
#   3. La copia a  %LOCALAPPDATA%\Programs\Nueva Castilla Etapa 3 Parking
#   4. Crea accesos directos en el Escritorio y en el menu Inicio.
#   5. Borra los accesos directos de la version anterior (los que apuntan a otro parqueadero_app.exe).
#
# Uso (desde la carpeta "app"):
#     powershell -ExecutionPolicy Bypass -File scripts\instalar_windows.ps1

$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
$nombre  = "Nueva Castilla Etapa 3 Parking"
$destino = Join-Path $env:LOCALAPPDATA "Programs\$nombre"

if (-not (Test-Path "windows\CMakeLists.txt")) {
  Write-Host "==> Preparando el proyecto por primera vez..."
  & (Join-Path $PSScriptRoot "configurar_plataformas.ps1")
}

Write-Host "==> Poniendo el nombre de la app..."
& (Join-Path $PSScriptRoot "nombre_windows.ps1")

Write-Host "==> Compilando (puede tardar unos minutos)..."
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "La compilacion fallo. Tome una captura de los mensajes en rojo." }

$release = "build\windows\x64\runner\Release"
$exe = Get-ChildItem $release -Filter *.exe | Select-Object -First 1
if (-not $exe) { throw "No se encontro el .exe en $release" }

Write-Host "==> Cerrando la app si esta abierta..."
Get-Process -Name $exe.BaseName -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1

Write-Host "==> Instalando en $destino ..."
if (Test-Path $destino) { Remove-Item $destino -Recurse -Force }
New-Item -ItemType Directory -Path $destino | Out-Null
Copy-Item "$release\*" $destino -Recurse -Force
# carpeta de una instalacion previa con el nombre anterior
$viejo = Join-Path $env:LOCALAPPDATA "Programs\Nueva Castilla Parking"
if (Test-Path $viejo) { Remove-Item $viejo -Recurse -Force }
$exeFinal = Join-Path $destino $exe.Name

$shell = New-Object -ComObject WScript.Shell
$carpetas = @([Environment]::GetFolderPath("Desktop"), [Environment]::GetFolderPath("Programs"))

Write-Host "==> Quitando accesos directos de la version anterior..."
foreach ($c in $carpetas) {
  Get-ChildItem $c -Filter *.lnk -ErrorAction SilentlyContinue | ForEach-Object {
    $t = $shell.CreateShortcut($_.FullName).TargetPath
    if ($t -and ($t -like "*parqueadero_app.exe") -and ($t -ne $exeFinal)) {
      Write-Host "    borrado: $($_.Name)"
      Remove-Item $_.FullName -Force
    }
  }
}

Write-Host "==> Creando accesos directos..."
foreach ($c in $carpetas) {
  $lnk = $shell.CreateShortcut((Join-Path $c "$nombre.lnk"))
  $lnk.TargetPath = $exeFinal
  $lnk.WorkingDirectory = $destino
  $lnk.IconLocation = "$exeFinal,0"
  $lnk.Description = $nombre
  $lnk.Save()
}

Write-Host ""
Write-Host "LISTO. '$nombre' quedo instalada en: $destino"
Write-Host "Tiene acceso directo en el Escritorio y en el menu Inicio."
Start-Process $exeFinal
