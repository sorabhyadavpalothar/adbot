#Requires -Version 5.1

$ErrorActionPreference = "Stop"

# ============================================================
# AdBot Windows Installer
# ============================================================

$Repo = "sorabhyadavpalothar/adbot"
$Version = "v3.1.3"

$BaseUrl = "https://github.com/$Repo/releases/download/$Version"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$DistDir = Join-Path $ScriptDir "dist"
$EnvFile = Join-Path $ScriptDir ".env"

$TempDir = Join-Path `
    $env:TEMP `
    ("adbot-installer-" + [Guid]::NewGuid())

# ============================================================
# Console
# ============================================================

function Write-Info {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warn {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Err {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Stop-Installer {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Err $Message

    Remove-TemporaryFiles

    exit 1
}

function Remove-TemporaryFiles {

    if (Test-Path $TempDir) {

        Remove-Item `
            -Path $TempDir `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }
}

# ============================================================
# Banner
# ============================================================

function Show-Banner {

    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "              AdBot Installer" -ForegroundColor White
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "Repository : $Repo"
    Write-Host "Version    : $Version"
    Write-Host ""
}

# ============================================================
# Host Architecture
# ============================================================

function Get-HostArchitecture {

    $architecture = $env:PROCESSOR_ARCHITECTURE

    if ($env:PROCESSOR_ARCHITEW6432) {

        $architecture = $env:PROCESSOR_ARCHITEW6432
    }

    switch ($architecture.ToUpper()) {

        "AMD64" {
            return "amd64"
        }

        "ARM64" {
            return "arm64"
        }

        default {
            Stop-Installer `
                "Unsupported Windows architecture: $architecture"
        }
    }
}

# ============================================================
# Docker Detection
# ============================================================

function Test-Docker {

    try {

        $dockerCommand = Get-Command `
            docker `
            -ErrorAction Stop

        if (-not $dockerCommand) {

            Write-Warn "Docker is not installed."

            return $false
        }

        Write-Ok "Docker detected"

        $dockerVersion = docker --version 2>$null

        if ($dockerVersion) {

            Write-Info $dockerVersion
        }

        return $true
    }
    catch {

        Write-Warn "Docker is not installed."

        return $false
    }
}

# ============================================================
# Docker Platform
# ============================================================

function Get-DockerPlatform {

    param(
        [Parameter(Mandatory = $true)]
        [bool]$DockerAvailable
    )

    if (-not $DockerAvailable) {

        return $null
    }

    try {

        docker info *> $null

        if ($LASTEXITCODE -ne 0) {

            Write-Warn "Docker daemon is not running."

            return $null
        }

        $platform = docker version `
            --format "{{.Server.Os}} {{.Server.Arch}}" `
            2>$null

        if ([string]::IsNullOrWhiteSpace($platform)) {

            Write-Warn "Unable to detect Docker platform."

            return $null
        }

        $parts = $platform.Trim() -split "\s+"

        if ($parts.Count -lt 2) {

            Write-Warn "Invalid Docker platform response."

            return $null
        }

        $dockerOS = $parts[0]
        $dockerArch = $parts[1]

        switch ($dockerArch) {

            "x86_64" {
                $dockerArch = "amd64"
            }

            "aarch64" {
                $dockerArch = "arm64"
            }

            "arm64" {
                $dockerArch = "arm64"
            }

            "amd64" {
                $dockerArch = "amd64"
            }
        }

        Write-Ok "Docker OS: $dockerOS"
        Write-Ok "Docker architecture: $dockerArch"

        return @{
            OS = $dockerOS
            Arch = $dockerArch
        }
    }
    catch {

        Write-Warn "Unable to query Docker platform."

        return $null
    }
}

# ============================================================
# Target Selection
# ============================================================

function Select-ReleaseTarget {

    param(
        [Parameter(Mandatory = $true)]
        [string]$HostArchitecture,

        [Parameter(Mandatory = $false)]
        $DockerPlatform
    )

    $targetOS = ""
    $targetArch = ""

    if ($null -ne $DockerPlatform) {

        $targetOS = $DockerPlatform.OS
        $targetArch = $DockerPlatform.Arch

        Write-Info `
            "Docker platform selected as release target."
    }
    else {

        $targetOS = "windows"
        $targetArch = $HostArchitecture

        Write-Info `
            "Windows host selected as release target."
    }

    if ($targetOS -notin @(
        "windows",
        "linux",
        "darwin"
    )) {

        Stop-Installer `
            "Unsupported target OS: $targetOS"
    }

    if ($targetArch -notin @(
        "amd64",
        "arm64"
    )) {

        Stop-Installer `
            "Unsupported target architecture: $targetArch"
    }

    $asset = "adbot-$targetOS-$targetArch"

    if ($targetOS -eq "windows") {

        $asset += ".exe"
    }

    return @{
        OS = $targetOS
        Arch = $targetArch
        Asset = $asset
    }
}

# ============================================================
# Required Tools
# ============================================================

function Test-RequiredTools {

    try {

        $null = Get-Command `
            Invoke-WebRequest `
            -ErrorAction Stop

        Write-Ok "PowerShell download support available"
    }
    catch {

        Stop-Installer `
            "Invoke-WebRequest is not available."
    }

    try {

        $null = Get-Command `
            Get-FileHash `
            -ErrorAction Stop

        Write-Ok "SHA256 support available"
    }
    catch {

        Stop-Installer `
            "Get-FileHash is not available."
    }
}

# ============================================================
# Create Temporary Directory
# ============================================================

function New-TemporaryDirectory {

    if (-not (Test-Path $TempDir)) {

        New-Item `
            -ItemType Directory `
            -Path $TempDir `
            -Force | Out-Null
    }

    Write-Ok "Temporary directory created"
}

# ============================================================
# Get File
# ============================================================

function Get-File {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    Write-Info "Downloading:"
    Write-Host "  $Url"

    try {

        Invoke-WebRequest `
            -Uri $Url `
            -OutFile $Destination `
            -UseBasicParsing
    }
    catch {

        Stop-Installer `
            "Failed to download: $Url"
    }

    if (-not (Test-Path $Destination)) {

        Stop-Installer `
            "Downloaded file does not exist: $Destination"
    }

    Write-Ok "Download complete"
}

# ============================================================
# Confirm SHA256
# ============================================================

function Confirm-SHA256 {

    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$ChecksumFile,

        [Parameter(Mandatory = $true)]
        [string]$Asset
    )

    Write-Info "Verifying SHA256..."

    if (-not (Test-Path $FilePath)) {

        Stop-Installer `
            "Binary file not found: $FilePath"
    }

    if (-not (Test-Path $ChecksumFile)) {

        Stop-Installer `
            "SHA256SUMS not found: $ChecksumFile"
    }

    $expected = $null

    $lines = Get-Content `
        -Path $ChecksumFile

    foreach ($line in $lines) {

        $trimmedLine = $line.Trim()

        if ([string]::IsNullOrWhiteSpace($trimmedLine)) {
            continue
        }

        $parts = $trimmedLine -split "\s+"

        if ($parts.Count -lt 2) {
            continue
        }

        $filename = $parts[1].TrimStart("*")

        if ($filename -eq $Asset) {

            $expected = $parts[0].ToLower()

            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($expected)) {

        Stop-Installer `
            "Checksum for $Asset was not found."
    }

    $actual = (
        Get-FileHash `
            -Path $FilePath `
            -Algorithm SHA256
    ).Hash.ToLower()

    if ($actual -ne $expected) {

        Write-Err "SHA256 verification failed."

        Write-Host ""
        Write-Host "Expected:"
        Write-Host $expected

        Write-Host ""
        Write-Host "Actual:"
        Write-Host $actual

        Stop-Installer `
            "Binary checksum mismatch."
    }

    Write-Ok "SHA256 verification passed"
}

# ============================================================
# Install Binary
# ============================================================

function Install-Binary {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$TargetOS
    )

    if (-not (Test-Path $DistDir)) {

        New-Item `
            -ItemType Directory `
            -Path $DistDir `
            -Force | Out-Null
    }

    if ($TargetOS -eq "windows") {

        $destination = Join-Path `
            $DistDir `
            "adbot.exe"
    }
    else {

        $destination = Join-Path `
            $DistDir `
            "adbot"
    }

    Write-Info "Installing binary"

    Copy-Item `
        -Path $Source `
        -Destination $destination `
        -Force

    if (-not (Test-Path $destination)) {

        Stop-Installer `
            "Binary installation failed."
    }

    Write-Ok "Binary installed:"
    Write-Host "  $destination"

    return $destination
}

# ============================================================
# New Encryption Key
# ============================================================

function New-EncryptionKey {

    $bytes = New-Object byte[] 32

    $randomNumberGenerator = `
        [System.Security.Cryptography.RandomNumberGenerator]::Create()

    try {

        $randomNumberGenerator.GetBytes($bytes)
    }
    finally {

        $randomNumberGenerator.Dispose()
    }

    return [Convert]::ToBase64String($bytes)
}

# ============================================================
# Read Configuration
# ============================================================

function Read-Configuration {

    Write-Host ""
    Write-Host "=============================================="
    Write-Host "             AdBot Configuration"
    Write-Host "=============================================="
    Write-Host ""

    $dbName = Read-Host `
        "PostgreSQL database name [mybot_db]"

    if ([string]::IsNullOrWhiteSpace($dbName)) {

        $dbName = "mybot_db"
    }

    $dbUser = Read-Host `
        "PostgreSQL username [mybot_user]"

    if ([string]::IsNullOrWhiteSpace($dbUser)) {

        $dbUser = "mybot_user"
    }

    $dbPasswordSecure = Read-Host `
        "PostgreSQL password" `
        -AsSecureString

    $dbPasswordPointer = `
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
            $dbPasswordSecure
        )

    try {

        $dbPassword =
            [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
                $dbPasswordPointer
            )
    }
    finally {

        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR(
            $dbPasswordPointer
        )
    }

    if ([string]::IsNullOrWhiteSpace($dbPassword)) {

        Stop-Installer `
            "PostgreSQL password cannot be empty."
    }

    $botToken = Read-Host `
        "Telegram bot token"

    if ([string]::IsNullOrWhiteSpace($botToken)) {

        Stop-Installer `
            "Telegram bot token cannot be empty."
    }

    $adminIDs = Read-Host `
        "Admin Telegram ID(s)"

    if ([string]::IsNullOrWhiteSpace($adminIDs)) {

        Stop-Installer `
            "Admin IDs cannot be empty."
    }

    Write-Host ""
    Write-Host "Encryption Key"
    Write-Host "--------------"
    Write-Host "1) Auto generate"
    Write-Host "2) Manual"
    Write-Host ""

    $encryptionOption = Read-Host `
        "Select option [1]"

    if ([string]::IsNullOrWhiteSpace($encryptionOption)) {

        $encryptionOption = "1"
    }

    switch ($encryptionOption) {

        "1" {

            $encryptionKey = New-EncryptionKey

            Write-Host ""
            Write-Ok "Encryption key generated"
        }

        "2" {

            $encryptionKey = Read-Host `
                "Enter encryption key"

            if ([string]::IsNullOrWhiteSpace($encryptionKey)) {

                Stop-Installer `
                    "Encryption key cannot be empty."
            }
        }

        default {

            Stop-Installer `
                "Invalid encryption option."
        }
    }

    return @{
        DBName = $dbName
        DBUser = $dbUser
        DBPassword = $dbPassword
        BotToken = $botToken
        AdminIDs = $adminIDs
        EncryptionKey = $encryptionKey
    }
}

# ============================================================
# New .env
# ============================================================

function New-EnvFile {

    param(
        [Parameter(Mandatory = $true)]
        $Configuration
    )

    Write-Info "Creating .env"

    $content = @"
# ============================================================
# AdBot Configuration
# Generated by install.ps1
# ============================================================

DEBUG=False

MAX_CONCURRENT_WORKERS=2000
SCHEDULER_INTERVAL=60

# PostgreSQL
POSTGRES_DB=$($Configuration.DBName)
POSTGRES_USER=$($Configuration.DBUser)
POSTGRES_PASSWORD=$($Configuration.DBPassword)
POSTGRES_HOST=postgres
POSTGRES_PORT=5432

# Redis
REDIS_HOST=redis
REDIS_PORT=6379

# Telegram
TELEGRAM_BOT_TOKEN=$($Configuration.BotToken)
ADMIN_ID=$($Configuration.AdminIDs)

# Auto Delete
AUTO_DELETE=false
AUTO_DELETE_TIME=120

# Encryption
ENCRYPTION_KEY=$($Configuration.EncryptionKey)
"@

    Set-Content `
        -Path $EnvFile `
        -Value $content `
        -Encoding UTF8

    if (-not (Test-Path $EnvFile)) {

        Stop-Installer `
            "Failed to create .env"
    }

    Write-Ok ".env created"
}

# ============================================================
# Test Docker Compose
# ============================================================

function Test-DockerCompose {

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {

        return $false
    }

    try {

        docker compose version *> $null

        return ($LASTEXITCODE -eq 0)
    }
    catch {

        return $false
    }
}

# ============================================================
# Start Docker Compose
# ============================================================

function Start-DockerCompose {

    if (-not (Test-DockerCompose)) {

        Write-Warn "Docker Compose is not available."

        Write-Host ""
        Write-Host "Run manually:"
        Write-Host "  docker compose up -d --build"
        Write-Host ""

        return
    }

    $composeFile = Join-Path `
        $ScriptDir `
        "docker-compose.yml"

    $composeFileAlt = Join-Path `
        $ScriptDir `
        "docker-compose.yaml"

    if (
        -not (Test-Path $composeFile) -and
        -not (Test-Path $composeFileAlt)
    ) {

        Write-Warn "docker-compose.yml was not found."

        Write-Host ""
        Write-Host "Run this after adding your Docker Compose file:"
        Write-Host "  docker compose up -d --build"
        Write-Host ""

        return
    }

    Write-Host ""
    Write-Host "=============================================="
    Write-Host "          Starting Docker Compose"
    Write-Host "=============================================="
    Write-Host ""

    Push-Location $ScriptDir

    try {

        docker compose up -d --build

        if ($LASTEXITCODE -ne 0) {

            Stop-Installer `
                "Docker Compose failed."
        }

        Write-Ok "Docker Compose started"
    }
    finally {

        Pop-Location
    }
}

# ============================================================
# Show Summary
# ============================================================

function Show-Summary {

    param(
        [Parameter(Mandatory = $true)]
        $Target,

        [Parameter(Mandatory = $true)]
        [string]$BinaryPath
    )

    Write-Host ""
    Write-Host "=============================================="
    Write-Host "          Installation Complete"
    Write-Host "=============================================="
    Write-Host ""

    Write-Host "Version : $Version"
    Write-Host "Target  : $($Target.OS)/$($Target.Arch)"
    Write-Host "Asset   : $($Target.Asset)"
    Write-Host "Binary  : $BinaryPath"
    Write-Host "Config  : $EnvFile"

    Write-Host ""
}

# ============================================================
# Main
# ============================================================

try {

    Show-Banner

    Test-RequiredTools

    New-TemporaryDirectory

    Write-Host ""
    Write-Host "System Detection"
    Write-Host "----------------"

    $hostArchitecture = Get-HostArchitecture

    Write-Ok `
        "Windows architecture: $hostArchitecture"

    $dockerAvailable = Test-Docker

    $dockerPlatform = Get-DockerPlatform `
        -DockerAvailable $dockerAvailable

    $target = Select-ReleaseTarget `
        -HostArchitecture $hostArchitecture `
        -DockerPlatform $dockerPlatform

    Write-Host ""
    Write-Host "Release Target"
    Write-Host "--------------"

    Write-Host "OS   : $($target.OS)"
    Write-Host "Arch : $($target.Arch)"
    Write-Host "Asset: $($target.Asset)"

    Write-Host ""

    $binaryTemp = Join-Path `
        $TempDir `
        $target.Asset

    $checksumTemp = Join-Path `
        $TempDir `
        "SHA256SUMS"

    Get-File `
        -Url "$BaseUrl/$($target.Asset)" `
        -Destination $binaryTemp

    Get-File `
        -Url "$BaseUrl/SHA256SUMS" `
        -Destination $checksumTemp

    Confirm-SHA256 `
        -FilePath $binaryTemp `
        -ChecksumFile $checksumTemp `
        -Asset $target.Asset

    $binaryPath = Install-Binary `
        -Source $binaryTemp `
        -TargetOS $target.OS

    $configuration = Read-Configuration

    New-EnvFile `
        -Configuration $configuration

    Show-Summary `
        -Target $target `
        -BinaryPath $binaryPath

    if ($dockerAvailable) {

        try {

            docker info *> $null

            if ($LASTEXITCODE -eq 0) {

                Write-Host ""

                $start = Read-Host `
                    "Start Docker Compose now? [Y/n]"

                if (
                    [string]::IsNullOrWhiteSpace($start) -or
                    $start -match "^(Y|y|Yes|yes)$"
                ) {

                    Start-DockerCompose
                }
                else {

                    Write-Host ""
                    Write-Host "Skipped Docker Compose."
                    Write-Host ""
                    Write-Host "Run later:"
                    Write-Host "  docker compose up -d --build"
                }
            }
            else {

                Write-Warn "Docker daemon is not running."

                Write-Host ""
                Write-Host "Start Docker Desktop and run:"
                Write-Host "  docker compose up -d --build"
            }
        }
        catch {

            Write-Warn "Unable to communicate with Docker."
        }
    }
    else {

        Write-Warn "Docker is not installed."

        Write-Host ""
        Write-Host "Install Docker Desktop and run:"
        Write-Host "  docker compose up -d --build"
    }

    Write-Host ""
    Write-Ok "AdBot installation finished."
    Write-Host ""
}
catch {

    Write-Err $_.Exception.Message

    Remove-TemporaryFiles

    exit 1
}
finally {

    Remove-TemporaryFiles
}
