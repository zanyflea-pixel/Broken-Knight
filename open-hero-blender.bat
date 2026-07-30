@echo off
setlocal
set "ROOT=%~dp0"
set "BLENDER=C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
set "BLEND=%ROOT%blender\hero_restart_rigged.blend"

if not exist "%BLENDER%" (
  echo Blender executable not found:
  echo %BLENDER%
  pause
  exit /b 1
)

if not exist "%BLEND%" (
  echo Blender file not found:
  echo %BLEND%
  pause
  exit /b 1
)

start "" "%BLENDER%" "%BLEND%"
endlocal
