# Pone el nombre "Nueva Castilla Etapa 3 Parking" en la app de Windows:
#   - titulo de la ventana (windows\runner\main.cpp)
#   - nombre del programa que muestra Windows (windows\runner\Runner.rc)
# Se puede ejecutar varias veces sin problema.

$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
$nombre = "Nueva Castilla Etapa 3 Parking"

$main = "windows\runner\main.cpp"
if (Test-Path $main) {
  $t = Get-Content $main -Raw
  $t = $t -replace 'window\.Create\(L"[^"]*"', ('window.Create(L"' + $nombre + '"')
  Set-Content $main $t -NoNewline
}

$rc = "windows\runner\Runner.rc"
if (Test-Path $rc) {
  $t = Get-Content $rc -Raw
  $t = $t -replace '"FileDescription", "[^"]*"', ('"FileDescription", "' + $nombre + '"')
  $t = $t -replace '"ProductName", "[^"]*"', ('"ProductName", "' + $nombre + '"')
  Set-Content $rc $t -NoNewline
}

Write-Host "Nombre de la app en Windows: $nombre"
