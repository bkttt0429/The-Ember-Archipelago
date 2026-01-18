@echo off
set GODOT_EXE=

if not "%GODOT_EXE%"=="" goto run

where godot >nul 2>nul
if errorlevel 1 (
  echo Godot not found in PATH.
  echo Set GODOT_EXE in this file to your Godot executable path.
  exit /b 1
)

set GODOT_EXE=godot

:run
"%GODOT_EXE%" --headless -s "Scripts\Tests\Test_Geopolitics_Phase2_Scene.gd"
