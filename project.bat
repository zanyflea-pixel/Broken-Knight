@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\project.ps1" %*
exit /b %ERRORLEVEL%
