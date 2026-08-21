@echo off
title Broken Knight AI Runner
cd /d "C:\Users\Jimmy\Desktop\Broken Knight"
powershell.exe -NoProfile -NoExit -STA -ExecutionPolicy Bypass -File "C:\Users\Jimmy\Desktop\Broken Knight\tools\ai-runner\runner.ps1" -ProjectRoot "C:\Users\Jimmy\Desktop\Broken Knight"
