@echo off
setlocal
set "ROOT=%~dp0"
set "GODOT=%ROOT%tools\godot-4.7\Godot_v4.7-stable_win64.exe"
set "PROJECT=%ROOT%godot"

if not exist "%GODOT%" (
  echo Godot executable not found:
  echo %GODOT%
  pause
  exit /b 1
)

if not exist "%PROJECT%\project.godot" (
  echo Godot project not found:
  echo %PROJECT%\project.godot
  pause
  exit /b 1
)

start "" "%GODOT%" --path "%PROJECT%" --scene "res://scenes/Boot.tscn" --single-window
endlocal
