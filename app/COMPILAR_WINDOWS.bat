@echo off
title Compilar app Parqueadero (Windows)
cd /d "%~dp0"

where flutter >nul 2>nul
if errorlevel 1 (
  echo ERROR: no se encontro Flutter. Instale Flutter y vuelva a intentar.
  pause
  exit /b 1
)

rem Primera vez: generar las carpetas android y windows
if not exist "windows\CMakeLists.txt" (
  echo === Preparando el proyecto por primera vez ===
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\configurar_plataformas.ps1"
)

rem Titulo de la ventana de Windows
powershell -NoProfile -Command "$f='windows\runner\main.cpp'; if (Test-Path $f) { (Get-Content $f -Raw) -replace 'L\"parqueadero_app\"','L\"Parqueadero Comunitario\"' | Set-Content $f -NoNewline }"

echo.
echo === Compilando la app para Windows (puede tardar unos minutos) ===
call flutter build windows --release
if errorlevel 1 (
  echo.
  echo ERROR: la compilacion fallo. Tome una captura de los mensajes en rojo.
  pause
  exit /b 1
)

echo.
echo === LISTO ===
echo La app quedo en: %~dp0build\windows\x64\runner\Release\parqueadero_app.exe
echo Recuerde tener abierta la API (backend\INICIAR.bat).
start "" "%~dp0build\windows\x64\runner\Release\parqueadero_app.exe"
pause
