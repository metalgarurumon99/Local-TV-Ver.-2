@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "TMDB_KEY="
if exist ".env" (
  for /f "usebackq tokens=1,* delims==" %%A in (".env") do (
    if /i "%%A"=="TMDB_API_KEY" set "TMDB_KEY=%%B"
  )
)

if "%TMDB_KEY%"=="" (
  echo [INFO] Building Windows Release without TMDB_API_KEY
  flutter build windows --release
) else (
  echo [INFO] Building Windows Release with TMDB_API_KEY injected from .env
  flutter build windows --release --dart-define=TMDB_API_KEY=%TMDB_KEY%
)
endlocal
