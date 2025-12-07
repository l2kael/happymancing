<#
 HappyMancing GCRD Host Automation
 Role: Deployment Commander
 Objective: Fast and clean Chrome Remote Desktop deployment

 CI Usage:
   pwsh -ExecutionPolicy Bypass -File .\GCRD-setup.ps1 -Code "$env:RAW_CODE" -Pin "$env:PIN_INPUT" -Retries "$env:RETRIES_INPUT"

 Local Usage:
   pwsh -ExecutionPolicy Bypass -File .\GCRD-setup.ps1 -Code '4/xxxxxxxxxxx' -Pin '123456' -Retries 3

 Doctrine:
   - Speed and efficiency
   - Clean deployment only
   - GCRD functionality first
#>

[CmdletBinding()]
param(
  [string]$Code,     # Operator authorization code or headless token
  [string]$Pin,      # Enrollment PIN for CRD host
  [int]$Retries = 2  # Reduced retries for faster deployment
)

$ErrorActionPreference = 'Stop'

# --- Utility functions ------------------------------------------------------
function Timestamp { (Get-Date).ToString('yyyy-MM-dd_HH-mm-ss') }

function Log([string]$msg)  { Write-Host "[HAPPYMANCING $(Timestamp)] $msg" }
function GLog([string]$msg) { Write-Host "[GCRD $(Timestamp)] $msg" }
function Fail([string]$msg) { Write-Error "[HAPPYMANCING-ERROR $(Timestamp)] $msg"; exit 1 }

# Mask sensitive strings
function Mask([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return $s }
  try { if ($env:GITHUB_ACTIONS -eq 'true') { Write-Host "::add-mask::$s" } } catch {}
}

# Fast token extraction
function Extract-HeadlessToken([string]$raw) {
  if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
  if ($raw -match '--code\s*=\s*"([^"]+)"')         { return $Matches[1] }
  elseif ($raw -match "--code\s*=\s*'([^']+)'")     { return $Matches[1] }
  elseif ($raw -match '--code\s*=\s*([^\s"''\)]+)') { return $Matches[1] }
  elseif ($raw -match '4\/[A-Za-z0-9_\-\.\~]+')     { return $Matches[0] }
  return $null
}

function Escape-Arg([string]$s) {
  if ($null -eq $s) { return "" }
  return $s -replace '"','\"'
}

# --- Fast Downloads folder resolution --------------------------------------
function Get-DownloadsPath {
  if ($env:USERPROFILE) {
    $p = Join-Path $env:USERPROFILE 'Downloads'
    if (Test-Path $p) { return $p }
  }
  Fail "Downloads directory not found"
}

# --- Input processing ------------------------------------------------------
if (-not $Code)   { $Code   = $env:RAW_CODE }
if (-not $Pin)    { $Pin    = $env:PIN_INPUT }
if ($PSBoundParameters.Keys -notcontains 'Retries' -and $env:RETRIES_INPUT) {
  try { if ([int]$env:RETRIES_INPUT -gt 0) { $Retries = [int]$env:RETRIES_INPUT } } catch {}
}

# Security masking
Mask $Code
Mask $Pin

# --- Token validation ------------------------------------------------------
if (-not $Code) { Fail "Missing Code. Provide -Code or set RAW_CODE." }
$token = Extract-HeadlessToken $Code
if (-not $token) { Fail "No valid headless token found in Code." }
$token = $token.Trim('"').Trim("'").Trim()
Mask $token

# --- PIN setup -------------------------------------------------------------
if ($Pin) { $Pin = $Pin.Trim() }
if ([string]::IsNullOrWhiteSpace($Pin) -or ($Pin -notmatch '^\d{6,}$')) {
  $Pin = "123456"
  GLog "Using default PIN"
} else {
  GLog "Custom PIN configured"
}
Mask $Pin

# --- Fast network check (non-blocking) ------------------------------------
try {
  $hosts = @("remotedesktop-pa.googleapis.com","oauth2.googleapis.com")
  foreach ($h in $hosts) {
    try { 
      $result = Test-NetConnection -ComputerName $h -Port 443 -WarningAction SilentlyContinue -InformationLevel Quiet
      if ($result) { Write-Host "$h : reachable" }
    } catch { Write-Host "$h : check skipped" }
  }
} catch { /* Continue anyway */ }

# ============================================================================
# FAST INSTALLATION
# ============================================================================
$downloads = Get-DownloadsPath
$msiPath = Join-Path $downloads 'crdhost.msi'

if (-not (Test-Path -LiteralPath $msiPath)) { 
  Fail "GCRD installer not found at $msiPath"
}

# Quick install without extensive logging
try {
  GLog "Installing Chrome Remote Desktop..."
  $installArgs = "/i `"$msiPath`" /qn /norestart"
  $proc = Start-Process msiexec.exe -ArgumentList $installArgs -Wait -PassThru
  if ($proc.ExitCode -ne 0) {
    # Quick repair attempt
    $repArgs = "/fvomus `"$msiPath`" /qn /norestart"
    $rep = Start-Process msiexec.exe -ArgumentList $repArgs -Wait -PassThru
    if ($rep.ExitCode -ne 0) { 
      Fail "Installation failed with code $($rep.ExitCode)"
    }
  }
  GLog "Installation completed"
} catch {
  Fail "Installation error: $($_.Exception.Message)"
}

# --- Locate CRD executable -------------------------------------------------
$pf86 = ${env:ProgramFiles(x86)}
$crdPaths = @(
  "$pf86\Google\Chrome Remote Desktop\CurrentVersion\remoting_start_host.exe",
  "${env:ProgramFiles}\Google\Chrome Remote Desktop\CurrentVersion\remoting_start_host.exe"
)

$exePath = $crdPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $exePath) {
  # Fast fallback search
  $searchPaths = @("$pf86\Google\Chrome Remote Desktop", "${env:ProgramFiles}\Google\Chrome Remote Desktop")
  $exePath = Get-ChildItem -Path $searchPaths -Filter 'remoting_start_host.exe' -Recurse -ErrorAction SilentlyContinue |
             Select-Object -ExpandProperty FullName -First 1
}

if (-not $exePath) { Fail "Chrome Remote Desktop not found after installation" }
GLog "CRD executable: $exePath"

# --- Skip if already registered -------------------------------------------
$hostJson = Join-Path $env:ProgramData 'Google\Chrome Remote Desktop\host.json'
if (Test-Path -LiteralPath $hostJson) {
  GLog "Already registered to GCRD"
  exit 0
}

# --- Fast registration ----------------------------------------------------
$display = "HappyMancing $(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')"
$redirectUrl = "https://remotedesktop.google.com/_/oauthredirect"

$args = @(
  "--code=`"$(Escape-Arg $token)`"",
  "--redirect-url=`"$redirectUrl`"",
  "--display-name=`"$(Escape-Arg $display)`"",
  "--pin=`"$(Escape-Arg $Pin)`"",
  "--disable-crash-reporting"
) -join ' '

# Quick registration with minimal retries
$success = $false
for ($i = 1; $i -le $Retries; $i++) {
  Log "Registration attempt $i/$Retries"
  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exePath
    $psi.Arguments = $args
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $p = [System.Diagnostics.Process]::Start($psi)
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    if ($p.ExitCode -eq 0) {
      Log "Registration successful"
      $success = $true
      break
    }
    
    # Fast fail on token errors
    if ($stderr -match 'Failed to exchange|OAuth error|invalid_grant') {
      Fail "Token error: $($stderr | Select-String -Pattern 'error|invalid' -CaseSensitive:$false | Select-Object -First 1)"
    }

    if ($i -lt $Retries) { Start-Sleep -Seconds (2 * $i) }
  } catch {
    if ($i -eq $Retries) { Fail "Registration failed: $($_.Exception.Message)" }
    Start-Sleep -Seconds (2 * $i)
  }
}

if (-not $success) { 
  Fail "Registration failed after $Retries attempts" 
}

# --- Quick verification ---------------------------------------------------
Log "GCRD deployment completed successfully"
exit 0
