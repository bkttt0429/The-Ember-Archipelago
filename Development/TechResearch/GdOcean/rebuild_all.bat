@echo off
echo Cleaning old build artifacts...
if exist bin\gd_ocean.dll del bin\gd_ocean.dll
if exist bin\gd_ocean.lib del bin\gd_ocean.lib
if exist bin\gd_ocean.exp del bin\gd_ocean.exp

echo Building GDExtension...
call scons target=template_debug dev_build=yes

if %ERRORLEVEL% NEQ 0 (
    echo Build Failed!
    exit /b %ERRORLEVEL%
)
echo Build Success!
