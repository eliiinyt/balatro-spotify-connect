# Script de compilación para el daemon Rust de Balatro Spotify Connect (Windows)
$ErrorActionPreference = "Stop"

Write-Host "==> Verificando entorno de Rust..." -ForegroundColor Cyan
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: 'cargo' no fue encontrado en PATH." -ForegroundColor Red
    Write-Host "Por favor instala Rust desde https://rustup.rs/ o agrega Cargo a tu PATH." -ForegroundColor Yellow
    exit 1
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DaemonDir = Join-Path $ScriptDir "daemon"
$BinDir = Join-Path $ScriptDir "bin"

if (-not (Test-Path $BinDir)) {
    New-Item -ItemType Directory -Path $BinDir | Out-Null
}

Write-Host "==> Compilando balatro-spotify-daemon en modo Release..." -ForegroundColor Cyan
Push-Location $DaemonDir
try {
    cargo build --release
} finally {
    Pop-Location
}

$SourceExe = Join-Path $DaemonDir "target\release\balatro-spotify-daemon.exe"
$TargetExe = Join-Path $BinDir "daemon-x86_64-windows.exe"

if (Test-Path $SourceExe) {
    Copy-Item -Path $SourceExe -Destination $TargetExe -Force
    Write-Host "==> ¡Compilación exitosa! Binario copiado a $TargetExe" -ForegroundColor Green
} else {
    Write-Host "ERROR: No se encontró el binario compilado en $SourceExe" -ForegroundColor Red
    exit 1
}
