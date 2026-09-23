<#
  注册 Windows 任务计划：每日 23:50 自动运行 deploy.ps1
  ---------------------------------------------------------------
  · 会话无关：由 Windows 系统调度，不依赖 WorkBuddy 对话是否开启
  · 前提：已在 deploy.config.ps1 填好 DEPLOY_REMOTE / DEPLOY_PAT
  · 运行方式：powershell -ExecutionPolicy Bypass -File deploy.ps1
#>

$RepoDir  = "E:\workbudy\2026-07-30-10-46-33"
$DeployPs = Join-Path $RepoDir "deploy.ps1"
$TaskName = "SiyueWorkbenchDailyDeploy"

$Action   = New-ScheduledTaskAction -Execute "powershell.exe" `
             -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$DeployPs`""
$Trigger  = New-ScheduledTaskTrigger -Daily -At "23:50"
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
             -DontStopIfGoingOnBatteries -StartWhenAvailable

# 以当前用户身份运行（保证能读取 deploy.config.ps1 与 PortableGit）
$Principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
              -LogonType S4U -RunLevel Limited

Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger `
                       -Settings $Settings -Principal $Principal -Force

Write-Output "已注册任务 [$TaskName]：每日 23:50 自动部署。"
Write-Output "可在『任务计划程序』中查看 / 手动右键『运行』测试，或删除重建。"
