# Genera las carpetas de plataforma (android, windows) del proyecto Flutter en Windows.
# Ejecutar UNA sola vez desde la carpeta "app" (en la Terminal de Android Studio):
#     powershell -ExecutionPolicy Bypass -File scripts\configurar_plataformas.ps1
#
# "flutter create" no sobrescribe archivos existentes: conserva lib/, pubspec.yaml y el
# AndroidManifest.xml ya preparado (permiso de INTERNET y tráfico http para pruebas).

$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

Write-Host "==> Verificando Flutter..."
flutter --version

Write-Host "==> Generando plataformas android y windows..."
flutter create --org co.edu.umb --project-name parqueadero_app --platforms=android,windows .

Write-Host "==> Descargando dependencias..."
flutter pub get

Write-Host ""
Write-Host "Listo. Ahora puede:"
Write-Host "  - Android:  elegir un emulador en Android Studio y pulsar Run (o: flutter run)"
Write-Host "  - Windows:  flutter run -d windows   |   flutter build windows"
Write-Host "  - APK:      flutter build apk --release"
Write-Host "  (iOS solo se puede generar en un Mac: scripts/configurar_plataformas.sh)"
