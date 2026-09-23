<#
  Siyue Workbench - session-independent deploy script
  - No dependency on any conversation/session; callable by Windows Task Scheduler
  - Commits the static PWA and pushes it to the GitHub Pages repo
  - Pre-push health check: verifies today's 7 active board reports exist
  - ASCII only (PowerShell 5.1 reads .ps1 as the system codepage, not UTF-8)
#>

$ErrorActionPreference = "Stop"

$RepoDir = "E:\workbudy\2026-07-30-10-46-33"
# git absolute path (the scheduled task runs non-interactively; PATH lacks PortableGit)
$GitExe  = "C:\Users\liusiyuan\.workbuddy\binaries\PortableGit\versions\1.2.0\mingw64\bin\git.exe"
if (-not (Test-Path $GitExe)) { $GitExe = "git" }

# 7 active boards (aivideo is paused, excluded from the health check)
$Boards = @("business","elderly-care","hotel","interviews","real-estate","tourism","trending")

# load local config (remote / PAT)
$ConfigPath = Join-Path $RepoDir "deploy.config.ps1"
if (Test-Path $ConfigPath) { . $ConfigPath } else {
  Write-Warning "deploy.config.ps1 not found. Copy the template and fill REMOTE / PAT."
  exit 2
}
if ($global:DEPLOY_REMOTE -like "*__USER__*") {
  Write-Warning "DEPLOY_REMOTE still has the __USER__ placeholder. Fill it in deploy.config.ps1 first."
  exit 4
}

$today = Get-Date -Format "yyyy-MM-dd"
$log = @()

# ---- health check: today's 7 board reports ----
$missing = @()
foreach ($b in $Boards) {
  $f = Join-Path $RepoDir ("reports\$b\$today.md")
  if (-not (Test-Path $f)) { $missing += $b }
}
if ($missing.Count -gt 0) {
  $log += "[WARN] today ($today) missing board reports: $($missing -join ', ') -- deploying current state anyway; check the generation automation."
} else {
  $log += "[OK] today ($today) all 7 board reports present."
}

Set-Location $RepoDir

# ---- init repo if needed ----
if (-not (Test-Path (Join-Path $RepoDir ".git"))) {
  & $GitExe init | Out-Null
  & $GitExe checkout -b main 2>$null
  & $GitExe remote remove origin 2>$null
  & $GitExe remote add origin $global:DEPLOY_REMOTE
}

# ---- remote check ----
$origin = & $GitExe remote get-url origin 2>$null
if ([string]::IsNullOrWhiteSpace($origin)) {
  & $GitExe remote add origin $global:DEPLOY_REMOTE
}

# ---- commit ----
& $GitExe add -A
$status = & $GitExe status --porcelain
if ([string]::IsNullOrWhiteSpace($status)) {
  $log += "[INFO] no local changes to commit."
} else {
  & $GitExe commit -m "auto-deploy $today $(Get-Date -Format HH:mm)" | Out-Null
  $log += "[INFO] committed local changes ($(($status -split "`n" | Where-Object {$_ -ne ''}).Count) files)."
}

# ---- push (PAT embedded in URL for this process only; never written to .git/config) ----
if ([string]::IsNullOrWhiteSpace($global:DEPLOY_PAT)) {
  Write-Warning "DEPLOY_PAT empty; attempting credential-less push (works if a system credential helper is configured)."
  $pushOut = & $GitExe push origin $global:DEPLOY_BRANCH 2>&1
} else {
  $pushUrl = $global:DEPLOY_REMOTE -replace "https://", "https://$($global:DEPLOY_PAT)@"
  $pushOut = & $GitExe push $pushUrl $global:DEPLOY_BRANCH 2>&1
}
$log += ($pushOut | Out-String)

$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$final = @("[deploy.ps1] $ts") + $log
$final | Out-File -Encoding utf8 (Join-Path $RepoDir "deploy.log") -Append
Write-Output ($final -join "`n")
