@echo off
REM ZigUp Windows Installation Script
REM This script installs ZigUp to %USERPROFILE%\.local\bin\

echo Installing ZigUp for Windows...

REM Create .local\bin directory
if not exist "%USERPROFILE%\.local\bin" (
    echo Creating directory: %USERPROFILE%\.local\bin
    mkdir "%USERPROFILE%\.local\bin"
    if errorlevel 1 (
        echo Error: Failed to create directory. Please check permissions.
        exit /b 1
    )
)

REM Copy zigup.exe to installation directory
if exist "zig-out\bin\zigup.exe" (
    echo Copying zigup.exe to %USERPROFILE%\.local\bin\
    copy "zig-out\bin\zigup.exe" "%USERPROFILE%\.local\bin\zigup.exe"
    if errorlevel 1 (
        echo Error: Failed to copy zigup.exe. Please check permissions.
        exit /b 1
    )
) else (
    echo Error: zigup.exe not found. Please build first with: zig build
    exit /b 1
)

echo.
echo ZigUp installed successfully!
echo.
echo To use ZigUp, add %USERPROFILE%\.local\bin to your PATH:
echo.
echo   1. Press Win+R, type "sysdm.cpl" and press Enter
echo   2. Click "Environment Variables..."
echo   3. Under "User variables", select "Path" and click "Edit..."
echo   4. Click "New" and add: %USERPROFILE%\.local\bin
echo   5. Click "OK" to save changes
echo.
echo Or run this command as Administrator:
echo   setx PATH "%USERPROFILE%\.local\bin;%%PATH%%"
echo.
echo Then restart your command prompt and run: zigup --help
pause