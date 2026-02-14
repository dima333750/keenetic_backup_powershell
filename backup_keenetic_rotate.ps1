# File: backup_keenetic.ps1 — Keenetic backup via HTTP Proxy API with Basic Auth, JSON to TXT conversion, retry logic
param(
    [string]$RouterDomain = "rci.адрес.netcraze.link",
    [string]$Login = "backup",
    [string]$Password = "",
    [string]$BackupDir = "C:\Backups\Keenetic"
)

$ErrorActionPreference = "Stop"

function Log {
    param([string]$Text)
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$time] $Text"
}

# Decode Base64 password
if ($Password -eq "") {
    Log "ERROR: No password provided"
    exit 1
}

try {
    $bytes = [Convert]::FromBase64String($Password)
    $RealPassword = [System.Text.Encoding]::UTF8.GetString($bytes)
    Log "Password decoded successfully"
} catch {
    Log "ERROR: Invalid Base64 password"
    exit 1
}

# Create backup directory
if (!(Test-Path $BackupDir)) {
    try {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
        Log "Created backup directory: $BackupDir"
    } catch {
        Log "ERROR: Failed to create backup directory: $_"
        exit 1
    }
}

# Build API URL
$ConfigUrl = "https://$RouterDomain/rci/show/running-config"
Log "API URL: $ConfigUrl"

# Prepare Basic Auth header
$authString = "$Login`:$RealPassword"
$authBytes = [System.Text.Encoding]::UTF8.GetBytes($authString)
$authBase64 = [Convert]::ToBase64String($authBytes)
$headers = @{
    "Authorization" = "Basic $authBase64"
}

# Function to download config with retry
function Get-KeeneticConfig {
    param([int]$MaxRetries = 3)
    
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        Log "=== ATTEMPT $attempt/$MaxRetries ==="
        
        try {
            # Stage 1: API Request
            Log "[STAGE 1] Sending request to API..."
            $response = Invoke-WebRequest -Uri $ConfigUrl -Headers $headers -Method GET -TimeoutSec 30 -UseBasicParsing
            
            Log "[STAGE 1] Response received: HTTP $($response.StatusCode), Length: $($response.RawContentLength) bytes"
            
            # Stage 2: Parse JSON
            Log "[STAGE 2] Parsing JSON response..."
            $json = $response.Content | ConvertFrom-Json
            
            if (-not $json.message) {
                throw "Invalid JSON format: 'message' field not found"
            }
            
            Log "[STAGE 2] JSON parsed successfully, message array count: $($json.message.Count)"
            
            # Stage 3: Convert to text
            Log "[STAGE 3] Converting JSON to text format..."
            $textContent = $json.message -join "`r`n"
            
            Log "[STAGE 3] Conversion complete, text length: $($textContent.Length) characters"
            
            return $textContent
            
        } catch {
            Log "[ERROR] Attempt $attempt failed: $_"
            
            if ($attempt -lt $MaxRetries) {
                Log "[RETRY] Waiting 2 seconds before next attempt..."
                Start-Sleep -Seconds 2
            } else {
                Log "[ERROR] All $MaxRetries attempts exhausted"
                throw "Failed to download config after $MaxRetries attempts: $_"
            }
        }
    }
}

# Main execution
try {
    Log "=== STARTING BACKUP ==="
    
    # Get config content
    $configContent = Get-KeeneticConfig -MaxRetries 3
    
    # Generate filename with timestamp
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $year = Get-Date -Format "yyyy"
    $month = Get-Date -Format "MM"
    $week = (Get-Date -UFormat %V)
    
    # Determine what backups to create
    $toCreate = @()
    
    # Daily backup always
    $toCreate += @{Type = "daily"; Name = "daily-$timestamp"}
    
    # Yearly check
    $yearlyName = "yearly-$year"
    if (!(Test-Path (Join-Path $BackupDir "$yearlyName.zip"))) {
        $toCreate += @{Type = "yearly"; Name = $yearlyName}
    }
    
    # Monthly check
    $monthlyName = "monthly-$year$month"
    if (!(Test-Path (Join-Path $BackupDir "$monthlyName.zip"))) {
        $toCreate += @{Type = "monthly"; Name = $monthlyName}
    }
    
    # Weekly check
    $weeklyName = "weekly-$year$week"
    if (!(Test-Path (Join-Path $BackupDir "$weeklyName.zip"))) {
        $toCreate += @{Type = "weekly"; Name = $weeklyName}
    }
    
    Log "=== CREATING $($toCreate.Count) BACKUP(S) ==="
    
    foreach ($item in $toCreate) {
        $tempFile = Join-Path $BackupDir "temp-$([Guid]::NewGuid().ToString().Substring(0,8)).txt"
        $zipFile = Join-Path $BackupDir "$($item.Name).zip"
        
        try {
            Log "Creating $($item.Name)..."
            
            # Save text content to temp file
            $configContent | Out-File -FilePath $tempFile -Encoding UTF8 -Force
            
            # Create ZIP
            Compress-Archive -Path $tempFile -DestinationPath $zipFile -Force
            
            # Cleanup temp file
            Remove-Item $tempFile -Force
            
            $size = (Get-Item $zipFile).Length
            Log "Created $($item.Name).zip ($size bytes)"
            
        } catch {
            Log "ERROR creating $($item.Name): $_"
            if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
        }
    }
    
    # Rotation
    Log "=== ROTATION ==="
    
    # Daily: keep 7
    $dailies = Get-ChildItem $BackupDir -Filter "daily-*.zip" | Sort-Object Name -Descending
    if ($dailies.Count -gt 7) {
        $dailies | Select-Object -Skip 7 | ForEach-Object {
            Remove-Item $_.FullName -Force
            Log "Deleted old daily: $($_.Name)"
        }
    }
    
    # Weekly: keep 4
    $weeklies = Get-ChildItem $BackupDir -Filter "weekly-*.zip" | Sort-Object Name -Descending
    if ($weeklies.Count -gt 4) {
        $weeklies | Select-Object -Skip 4 | ForEach-Object {
            Remove-Item $_.FullName -Force
            Log "Deleted old weekly: $($_.Name)"
        }
    }
    
    # Monthly: keep 12
    $monthlies = Get-ChildItem $BackupDir -Filter "monthly-*.zip" | Sort-Object Name -Descending
    if ($monthlies.Count -gt 12) {
        $monthlies | Select-Object -Skip 12 | ForEach-Object {
            Remove-Item $_.FullName -Force
            Log "Deleted old monthly: $($_.Name)"
        }
    }
    
    # Yearly: keep 20
    $yearlies = Get-ChildItem $BackupDir -Filter "yearly-*.zip" | Sort-Object Name -Descending
    if ($yearlies.Count -gt 20) {
        $yearlies | Select-Object -Skip 20 | ForEach-Object {
            Remove-Item $_.FullName -Force
            Log "Deleted old yearly: $($_.Name)"
        }
    }
    
    Log "=== BACKUP COMPLETED SUCCESSFULLY ==="
    
} catch {
    Log "CRITICAL ERROR: $_"
    Log "Backup failed"
    exit 1
}
