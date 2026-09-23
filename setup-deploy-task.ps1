<#
  Register a Windows scheduled task: run deploy.ps1 daily at 23:50
  Session-independent: scheduled by Windows, not by any WorkBuddy conversation.
  Uses schtasks.exe (always available) instead of the ScheduledTasks module.
#>

$RepoDir  = "E:\workbudy\2026-07-30-10-46-33"
$DeployPs = Join-Path $RepoDir "deploy.ps1"
$TaskName = "SiyueWorkbenchDailyDeploy"
$TaskCmd  = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$DeployPs`""

# Run as SYSTEM so it runs unattended; the script reads deploy.config.ps1 from the repo dir.
schtasks.exe /Create /TN "$TaskName" /TR "$TaskCmd" /SC DAILY /ST 23:50 /RU SYSTEM /RL LIMITED /F
if ($LASTEXITCODE -eq 0) {
  Write-Output "Registered task [$TaskName] (daily 23:50, runs as SYSTEM)."
  Write-Output "It only pushes successfully after you fill deploy.config.ps1 (REMOTE + PAT)."
  Write-Output "Test now: schtasks.exe /Run /TN `"$TaskName`""
} else {
  Write-Output "schtasks failed (code $LASTEXITCODE). Try running this script elevated (Admin)."
}
