# ZigUp PowerShell Installation Script
# This script installs ZigUp to $env:USERPROFILE\.local\bin\

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

# Copy zigup.exe to installation directory
$sourceFile = "zig-out\bin\zigup.exe"
$destFile = Join-Path $installDir "zigup.exe"

if (Test-Path $sourceFile) {
    Write-Host "Copying zigup.exe to $installDir" -ForegroundColor Yellow
    try {
        Copy-Item $sourceFile $destFile -Force
    }
    catch {
        Write-Host "Error: Failed to copy zigup.exe. Please check permissions." -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "Error: zigup.exe not found. Please build first with: zig build" -ForegroundColor Red
    exit 1
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
        Write-Host "Warning: Could not automatically update PATH. Please add manually:" -ForegroundColor Yellow
        Write-Host "  1. Press Win+R, type 'sysdm.cpl' and press Enter" -ForegroundColor White
        Write-Host "  2. Click 'Environment Variables...'" -ForegroundColor White
        Write-Host "  3. Under 'User variables', select 'Path' and click 'Edit...'" -ForegroundColor White
        Write-Host "  4. Click 'New' and add: $installDir" -ForegroundColor White
        Write-Host "  5. Click 'OK' to save changes" -ForegroundColor White
    }
}
else {
    Write-Host "$installDir is already in your PATH." -ForegroundColor Green
}

Write-Host ""
Write-Host "To verify installation, restart your terminal and run: zigup --help" -ForegroundColor Cyan