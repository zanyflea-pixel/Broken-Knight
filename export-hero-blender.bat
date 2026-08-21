@echo off
setlocal
set "ROOT=%~dp0"
set "BLENDER=C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
set "BLEND=%ROOT%blender\BrokenKnight_Hero_Master.blend"
set "SCRIPT=%ROOT%blender\scripts\export_current_hero.py"

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

if not exist "%SCRIPT%" (
  echo Export script not found:
  echo %SCRIPT%
  pause
  exit /b 1
)

"%BLENDER%" -b "%BLEND%" --python "%SCRIPT%"
endlocal
