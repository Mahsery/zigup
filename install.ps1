# ZigUp PowerShell Installation Script
# This script installs ZigUp to $env:USERPROFILE\.local\bin\

# Check if running as administrator and request elevation if not
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Requesting administrator privileges to modify PATH..." -ForegroundColor Yellow
    Write-Host "Please allow the UAC prompt to continue installation." -ForegroundColor Cyan
    $process = Start-Process PowerShell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -PassThru -Wait
    if ($process.ExitCode -eq 0) {
        Write-Host "Installation completed successfully!" -ForegroundColor Green
    } else {
        Write-Host "Installation failed or was cancelled." -ForegroundColor Red
    }
    exit $process.ExitCode
}

Write-Host "Installing ZigUp for Windows..." -ForegroundColor Green

# Create .local\bin directory
$installDir = Join-Path $env:USERPROFILE ".local\bin"
if (-not (Test-Path $installDir)) {
    Write-Host "Creating directory: $installDir" -ForegroundColor Yellow
    try {
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    }
    catch {
        Write-Host "Error: Failed to create directory. Please check permissions." -ForegroundColor Red
        exit 1
    }
}

# Function to download and setup temporary Zig
function Setup-TempZig {
    $tempDir = [System.IO.Path]::GetTempPath() + [System.Guid]::NewGuid().ToString()
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    
    Write-Host "Downloading Zig for Windows..." -ForegroundColor Yellow
    
    # Get latest stable version info
    $indexUrl = "https://ziglang.org/download/index.json"
    try {
        $zigInfo = Invoke-RestMethod -Uri $indexUrl
        $version = "0.14.1"
        $platform = "x86_64-windows"
        $tarballUrl = $zigInfo.$version.$platform.tarball
        
        if (-not $tarballUrl) {
            throw "Could not find Zig download for $platform"
        }
        
        Write-Host "Downloading from: $tarballUrl" -ForegroundColor Green
        $zipPath = Join-Path $tempDir "zig.zip"
        Invoke-WebRequest -Uri $tarballUrl -OutFile $zipPath
        
        # Extract zip
        Expand-Archive -Path $zipPath -DestinationPath $tempDir
        $zigDir = Get-ChildItem -Path $tempDir -Directory | Select-Object -First 1
        $zigExe = Join-Path $zigDir.FullName "zig.exe"
        
        if (Test-Path $zigExe) {
            Write-Host "Temporary Zig installed to: $($zigDir.FullName)" -ForegroundColor Green
            return $zigExe
        } else {
            throw "zig.exe not found in extracted archive"
        }
    }
    catch {
        Write-Host "Error downloading Zig: $_" -ForegroundColor Red
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        exit 1
    }
}

# Check if zig is installed
$zigCommand = $null
$tempZigDir = $null

try {
    $zigCommand = Get-Command zig -ErrorAction Stop
    Write-Host "Found Zig compiler: $($zigCommand.Source)" -ForegroundColor Green
}
catch {
    Write-Host "Zig compiler not found." -ForegroundColor Yellow
    Write-Host "Would you like to download Zig temporarily to build ZigUp?" -ForegroundColor Cyan
    $response = Read-Host "(y/N)"
    if ($response -match "^[Yy]") {
        $zigCommand = Setup-TempZig
        $tempZigDir = Split-Path $zigCommand -Parent
    } else {
        Write-Host "Please install Zig first: https://ziglang.org/download/" -ForegroundColor Red
        exit 1
    }
}

# Always build zigup (to update if already exists)
$sourceFile = "zig-out\bin\zigup.exe"
$destFile = Join-Path $installDir "zigup.exe"

Write-Host "Building zigup..." -ForegroundColor Yellow

if ($tempZigDir) {
    & "$zigCommand" build -Doptimize=ReleaseFast
} else {
    & zig build -Doptimize=ReleaseFast
}

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Build failed" -ForegroundColor Red
    if ($tempZigDir) {
        Remove-Item -Path (Split-Path $tempZigDir -Parent) -Recurse -Force -ErrorAction SilentlyContinue
    }
    exit 1
}

# Copy zigup.exe to installation directory
if (Test-Path $sourceFile) {
    if (Test-Path $destFile) {
        Write-Host "Updating existing zigup.exe in $installDir" -ForegroundColor Yellow
    } else {
        Write-Host "Installing zigup.exe to $installDir" -ForegroundColor Yellow
    }
    try {
        Copy-Item $sourceFile $destFile -Force
    }
    catch {
        Write-Host "Error: Failed to copy zigup.exe. Please check permissions." -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "Error: zigup.exe not found after build" -ForegroundColor Red
    exit 1
}

# Clean up temporary Zig if it was downloaded
if ($tempZigDir) {
    Write-Host "Cleaning up temporary Zig installation..." -ForegroundColor Yellow
    Remove-Item -Path (Split-Path $tempZigDir -Parent) -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "ZigUp installed successfully!" -ForegroundColor Green
Write-Host ""

# Check if directory is already in PATH
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($currentPath -notlike "*$installDir*") {
    Write-Host "Adding $installDir to your PATH..." -ForegroundColor Yellow
    try {
        $newPath = "$installDir;$currentPath"
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Host "PATH updated successfully!" -ForegroundColor Green
        Write-Host "Please restart your PowerShell/Command Prompt for changes to take effect." -ForegroundColor Yellow
    }
    catch {
        Write-Host "Error: Failed to update PATH automatically" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "$installDir is already in your PATH." -ForegroundColor Green
}

Write-Host ""
Write-Host "To verify installation, restart your terminal and run: zigup --help" -ForegroundColor Cyan