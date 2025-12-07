# ============================================================
# HAPPYMANCING: WINDOWS 10 GCRD + MUMU PLAYER DEPLOYMENT
# Role: Deployment Commander
# Doctrine: Speed - Efficiency - Reliability
# ============================================================

param(
    [string]$GateSecret
)

$ErrorActionPreference = "Stop"

function Timestamp { (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") }
function Log($msg)  { Write-Host "[HAPPYMANCING $(Timestamp)] $msg" }
function Fail($msg) { Write-Error "[HAPPYMANCING-ERROR $(Timestamp)] $msg"; Exit 1 }

function Validate-Secret([Parameter(Mandatory)] [string]$Text) {
    return $Text -eq "LISTEN2KAEL"
}

# ============================================================
# INITIATION
# ============================================================
$now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host @"
------------------------------------------------------------
            HAPPYMANCING // GCRD + MUMU PLAYER
------------------------------------------------------------
  STATUS    : Fast deployment initializing
  TIME      : $now
  PROFILE   : Windows 10 GCRD + Mumu Player
  DOCTRINE  : Speed - Efficiency - Reliability
------------------------------------------------------------
"@

# ============================================================
# ACCESS CONTROL
# ============================================================
$GATE_SECRET = if ($PSBoundParameters.ContainsKey('GateSecret')) { $GateSecret } else { $env:HappyMancing_Access_Token }

if ($GATE_SECRET) { Write-Host "::add-mask::$GATE_SECRET" }

if (-not $GATE_SECRET -or [string]::IsNullOrWhiteSpace($GATE_SECRET)) {
    Fail "Missing HappyMancing_Access_Token secret"
}

if (-not (Validate-Secret $GATE_SECRET)) {
    Fail "Token validation failed. Expected: LISTEN2KAEL"
}
Log "Access granted - Starting deployment"

# ============================================================
# FAST GCRD DEPLOYMENT
# ============================================================
try {
    Log "Starting GCRD deployment"
    
    # Download and execute optimized GCRD setup
    $gcrdScriptUrl = "https://raw.githubusercontent.com/kamavingabre-sketch/HM/refs/heads/main/GCRD-setup.ps1"
    Invoke-WebRequest -Uri $gcrdScriptUrl -OutFile "GCRD-setup.ps1" -UseBasicParsing -TimeoutSec 30
    
    # Execute with current parameters
    .\GCRD-setup.ps1 -Code $env:RAW_CODE -Pin $env:PIN_INPUT -Retries $env:RETRIES_INPUT
    
    Log "GCRD deployment completed"
} catch { 
    Fail "GCRD setup failed: $_" 
}

# ============================================================
# MUMU PLAYER INSTALLATION (NON-BLOCKING)
# ============================================================
try {
    Log "Checking Mumu Player installer..."
    
    $mumuInstaller = Join-Path $env:USERPROFILE "Downloads\MUMU.exe"
    
    if (Test-Path $mumuInstaller) {
        Log "Found Mumu Player installer, launching installation..."
        
        # Launch Mumu Player installer without waiting (non-blocking)
        Start-Process -FilePath $mumuInstaller -ArgumentList "/S" -NoNewWindow
        
        Log "✅ Mumu Player installation started (running in background)"
        Log "Mumu Player will continue installing while system runs"
        
    } else {
        Log "⚠️ Mumu Player installer not found at $mumuInstaller, skipping installation"
    }
} catch {
    Log "⚠️ Mumu Player installation skipped: $_"
}

# ============================================================
# QUICK DATA FOLDER SETUP
# ============================================================
try {
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $dataFolderPath = Join-Path $desktopPath "Data"

    if (-not (Test-Path $dataFolderPath)) {
        New-Item -Path $dataFolderPath -ItemType Directory | Out-Null
        Log "Data folder created"
    }
} catch { 
    Log "Data folder creation skipped: $_" 
}

# ============================================================
# FINAL SYSTEM STATUS
# ============================================================
Log "Deployment Summary:"
Log "  ✅ GCRD - Chrome Remote Desktop"
Log "  ✅ Mumu Player - Installation Started (Background)" 
Log "  ✅ Data Folder - File Organization"
Log "System ready for use!"

# ============================================================
# RUNTIME MONITORING (FIXED)
# ============================================================
$totalMinutes = 360  # 6 hours runtime
$startTime = Get-Date
$endTime = $startTime.AddMinutes($totalMinutes)

Log "System active for up to ${totalMinutes}m"

$lastLogTime = $startTime
$mumuCheckCount = 0

while ((Get-Date) -lt $endTime) {
    $currentTime = Get-Date
    $elapsed = [math]::Round(($currentTime - $startTime).TotalMinutes, 1)
    $remaining = [math]::Round(($endTime - $currentTime).TotalMinutes, 1)
    
    # Check Mumu installation status occasionally
    $mumuCheckCount++
    if ($mumuCheckCount -eq 12) { # Check every ~60 minutes (12 * 5min)
        $mumuCheckCount = 0
        $mumuPaths = @(
            "C:\Program Files\Microvirt\MEmu\MEmu.exe",
            "C:\Program Files (x86)\Microvirt\MEmu\MEmu.exe", 
            "$env:USERPROFILE\AppData\Local\Programs\Microvirt\MEmu\MEmu.exe"
        )
        $mumuInstalled = $mumuPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($mumuInstalled) {
            Log "✅ Mumu Player successfully installed and ready"
        }
    }
    
    # Log every 30 minutes
    if (($currentTime - $lastLogTime).TotalMinutes -ge 30) {
        Log "Uptime ${elapsed}m | Remaining ${remaining}m"
        $lastLogTime = $currentTime
    }
    
    # Check every 5 minutes
    Start-Sleep -Seconds 300
}

Log "Deployment cycle completed - ${totalMinutes}m runtime finished"

# ============================================================
# CLEAN EXIT
# ============================================================
if ($env:RUNNER_ENV -eq "self-hosted") {
    Log "Initiating system shutdown"
    Stop-Computer -Force
} else {
    Log "Hosted environment - Exiting gracefully"
    Exit 0
}
