@echo off
rem Starts Azeroth Survivors with the WoW Data folder chosen at install time.
chcp 65001 >nul
setlocal
set /p WOW_DATA=<"%~dp0wow-data-path.txt"
cd /d "%~dp0repo"
"%~dp0repo\target\release\warcraft-survivors.exe"
