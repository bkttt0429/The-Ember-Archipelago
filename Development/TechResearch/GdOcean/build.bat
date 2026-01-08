@echo off
echo Running SCons...
scons
if %errorlevel% neq 0 (
    echo.
    echo Build Failed! Error code: %errorlevel%
    echo Expected implicit dependency errors since we are using MSVC?
    echo.
) else (
    echo.
    echo Build Successful!
)
pause
