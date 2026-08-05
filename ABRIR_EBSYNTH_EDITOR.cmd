@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AnimeVideoStudioUnified.ps1" -StartTab ebsynth
