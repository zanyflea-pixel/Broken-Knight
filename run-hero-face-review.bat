@echo off
setlocal
set "ROOT=%~dp0"
powershell -ExecutionPolicy Bypass -File "%ROOT%run-hero-face-review.ps1"
endlocal
