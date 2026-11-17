@echo off
title Instalar Nueva Castilla Etapa 3 Parking
cd /d "%~dp0"

where flutter >nul 2>nul
if errorlevel 1 (
  echo ERROR: no se encontro Flutter. Instale Flutter y vuelva a intentar.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\instalar_windows.ps1"
if errorlevel 1 (
  echo.
  echo ERROR: la instalacion fallo. Tome una captura de los mensajes en rojo.
)
pause
