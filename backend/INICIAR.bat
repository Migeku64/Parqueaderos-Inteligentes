@echo off
title API Parqueadero Comunitario
cd /d "%~dp0"
if not exist ".env" (
  echo Primero ejecute INSTALAR.bat
  pause
  exit /b 1
)

rem Si quedo una API anterior (node.exe) ocupando el puerto 3000, se cierra automaticamente
for /f "tokens=5" %%p in ('netstat -ano ^| findstr /R /C:":3000 .*LISTENING"') do (
  tasklist /FI "PID eq %%p" | find /I "node.exe" >nul && (
    echo Cerrando una API anterior que seguia abierta [PID %%p]...
    taskkill /PID %%p /F >nul
  )
)
timeout /t 1 /nobreak >nul

echo Iniciando la API en http://localhost:3000  (cierre esta ventana para apagarla)
echo.
node src/server.js
echo.
pause
