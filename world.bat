@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\world.ps1" %*
exit /b %ERRORLEVEL%
