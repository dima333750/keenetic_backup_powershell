# Keenetic Backup with ZIP and smart rotation
# Run: powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File backup.ps1 -Password "BASE64"

param(
    [string]$RouterIp = "192.168.0.1 or *.netcraze.io",
    [string]$Login = "backup",
    [string]$Password = "",
    [string]$BackupDir = "C:\Backups\Keenetic"
)

$ErrorActionPreference = "Continue"

function Log {
    param([string]$Text)
    $time = Get-Date -Format "HH:mm:ss"
    Write-Host "[$time] $Text"
}

# Decode password
if ($Password -eq "") {
    Log "ERROR: No password"
    exit 1
}

try {
    $bytes = [Convert]::FromBase64String($Password)
    $RealPassword = [System.Text.Encoding]::UTF8.GetString($bytes)
    Log "Password loaded: ****"
} catch {
    Log "ERROR: Invalid Base64 password"
    exit 1
}

# Create folder
if (!(Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
}

# Auth
Log "=== AUTH ==="
$AuthUrl = "http://$RouterIp/auth"
$Session = $null

try {
    Invoke-WebRequest -Uri $AuthUrl -Method GET -SessionVariable Session -TimeoutSec 10 | Out-Null
} catch {
    if ($_.Exception.Response.StatusCode -eq 401) {
        $headers = $_.Exception.Response.Headers
        $Realm = $headers['X-NDM-Realm']
        $Challenge = $headers['X-NDM-Challenge']
        Log "Got challenge"
    } else {
        Log "Auth error: $_"
        exit 1
    }
}

$md5Input = "$Login`:$Realm`:$RealPassword"
$md5Bytes = [System.Text.Encoding]::UTF8.GetBytes($md5Input)
$md5Hash = [BitConverter]::ToString([System.Security.Cryptography.MD5]::Create().ComputeHash($md5Bytes)).Replace("-", "").ToLower()
$shaInput = "$Challenge$md5Hash"
$shaBytes = [System.Text.Encoding]::UTF8.GetBytes($shaInput)
$shaHash = [BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($shaBytes)).Replace("-", "").ToLower()

$body = ([PSCustomObject]@{login = $Login; password = $shaHash} | ConvertTo-Json)
try {
    $auth = Invoke-WebRequest -Uri $AuthUrl -Method POST -Body $body -ContentType "application/json" -WebSession $Session -TimeoutSec 10
    Log "Auth OK: $($auth.StatusCode)"
} catch {
    Log "Auth failed: $_"
    exit 1
}

# Download
$now = Get-Date
$timestamp = $now.ToString("yyyyMMdd-HHmmss")
$ConfigUrl = "http://$RouterIp/ci/startup-config.txt"
$tempFile = Join-Path $BackupDir "temp-$timestamp.txt"

Log "Downloading..."
try {
    Invoke-WebRequest -Uri $ConfigUrl -WebSession $Session -OutFile $tempFile -TimeoutSec 30
    $size = (Get-Item $tempFile).Length
    Log "Downloaded: $size bytes"
} catch {
    Log "ERROR download: $_"
    exit 1
}

# Determine archive type
$day = $now.Day
$month = $now.Month
$year = $now.Year
$dayOfWeek = $now.DayOfWeek

# Daily (every day)
$archiveName = "daily-$timestamp.zip"

# Weekly (every Sunday, keep 4)
if ($dayOfWeek -eq "Sunday") {
    $archiveName = "weekly-$timestamp.zip"
}

# Monthly (1st day of month, keep 12)
if ($day -eq 1) {
    $archiveName = "monthly-$timestamp.zip"
}

# Yearly (Jan 1, keep 20)
if ($month -eq 1 -and $day -eq 1) {
    $archiveName = "yearly-$timestamp.zip"
}

$archivePath = Join-Path $BackupDir $archiveName

# Create ZIP
try {
    Compress-Archive -Path $tempFile -DestinationPath $archivePath -Force
    Remove-Item $tempFile -Force
    $zipSize = (Get-Item $archivePath).Length
    Log "ZIP created: $archiveName ($zipSize bytes)"
} catch {
    Log "ERROR creating ZIP: $_"
    Remove-Item $tempFile -Force
    exit 1
}

# Rotation
Log "=== ROTATION ==="

# Daily: keep 7
$dailies = Get-ChildItem $BackupDir -Filter "daily-*.zip" | Sort-Object Name -Descending
if ($dailies.Count -gt 7) {
    $toDelete = $dailies | Select-Object -Skip 7
    foreach ($file in $toDelete) {
        Remove-Item $file.FullName -Force
        Log "Deleted old daily: $($file.Name)"
    }
}

# Weekly: keep 4
$weeklies = Get-ChildItem $BackupDir -Filter "weekly-*.zip" | Sort-Object Name -Descending
if ($weeklies.Count -gt 4) {
    $toDelete = $weeklies | Select-Object -Skip 4
    foreach ($file in $toDelete) {
        Remove-Item $file.FullName -Force
        Log "Deleted old weekly: $($file.Name)"
    }
}

# Monthly: keep 12
$monthlies = Get-ChildItem $BackupDir -Filter "monthly-*.zip" | Sort-Object Name -Descending
if ($monthlies.Count -gt 12) {
    $toDelete = $monthlies | Select-Object -Skip 12
    foreach ($file in $toDelete) {
        Remove-Item $file.FullName -Force
        Log "Deleted old monthly: $($file.Name)"
    }
}

# Yearly: keep 20
$yearlies = Get-ChildItem $BackupDir -Filter "yearly-*.zip" | Sort-Object Name -Descending
if ($yearlies.Count -gt 20) {
    $toDelete = $yearlies | Select-Object -Skip 20
    foreach ($file in $toDelete) {
        Remove-Item $file.FullName -Force
        Log "Deleted old yearly: $($file.Name)"
    }
}

Log "Done"