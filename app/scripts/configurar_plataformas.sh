#!/usr/bin/env bash
# Genera las carpetas de plataforma del proyecto Flutter en macOS o Linux.
# Ejecutar UNA sola vez desde la carpeta "app":   bash scripts/configurar_plataformas.sh
#
# En macOS genera android + ios y ajusta Info.plist para permitir http en pruebas
# y mostrar los reportes exportados en la app "Archivos".
set -euo pipefail
cd "$(dirname "$0")/.."

PLATFORMS="android"
if [[ "$(uname)" == "Darwin" ]]; then PLATFORMS="android,ios"; fi

echo "==> Generando plataformas: $PLATFORMS"
flutter create --org co.edu.umb --project-name parqueadero_app --platforms="$PLATFORMS" .

PLIST="ios/Runner/Info.plist"
if [[ -f "$PLIST" && "$(uname)" == "Darwin" ]]; then
  echo "==> Ajustando $PLIST"
  PB=/usr/libexec/PlistBuddy
  $PB -c "Delete :NSAppTransportSecurity" "$PLIST" 2>/dev/null || true
  $PB -c "Add :NSAppTransportSecurity dict" "$PLIST"
  $PB -c "Add :NSAppTransportSecurity:NSAllowsArbitraryLoads bool true" "$PLIST"
  $PB -c "Set :UIFileSharingEnabled true" "$PLIST" 2>/dev/null || $PB -c "Add :UIFileSharingEnabled bool true" "$PLIST"
  $PB -c "Set :LSSupportsOpeningDocumentsInPlace true" "$PLIST" 2>/dev/null || $PB -c "Add :LSSupportsOpeningDocumentsInPlace bool true" "$PLIST"
  $PB -c "Set :CFBundleDisplayName Parqueadero" "$PLIST" 2>/dev/null || true
fi

flutter pub get
echo "Listo. Pruebe con: flutter run"
