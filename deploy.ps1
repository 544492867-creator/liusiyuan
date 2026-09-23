<#
  泗月工作台 · 会话无关部署脚本
  ---------------------------------------------------------------
  · 不依赖任何对话 / 会话，可由 Windows 任务计划程序定时调用
  · 唯一职责：把当前工作区（静态 PWA）提交并推送到 GitHub Pages 仓库
  · 推送前做"当日 7 板块日报"健康检查：缺失则告警，但仍部署现有内容
  · git 用绝对路径，兼容任务计划程序的非交互环境（PATH 不含 PortableGit）
#>

$ErrorActionPreference = "Stop"

$RepoDir = "E:\workbudy\2026-07-30-10-46-33"
# git 绝对路径（任务计划非交互环境 PATH 不含 PortableGit）
$GitExe  = "C:\Users\liusiyuan\.workbuddy\binaries\PortableGit\versions\1.2.0\mingw64\bin\git.exe"
if (-not (Test-Path $GitExe)) { $GitExe = "git" }

# 7 个活跃板块（aivideo 已暂停，不纳入健康校验）
$Boards = @("business","elderly-care","hotel","interviews","real-estate","tourism","trending")

# 载入本地配置（remote / PAT）
$ConfigPath = Join-Path $RepoDir "deploy.config.ps1"
if (Test-Path $ConfigPath) { . $ConfigPath } else {
  Write-Warning "未找到 deploy.config.ps1，请复制模板并填写 remote 与 PAT。"
  exit 2
}
if ($global:DEPLOY_REMOTE -like "*__USER__*") {
  Write-Error "DEPLOY_REMOTE 仍是占位符 __USER__，请先在 deploy.config.ps1 填写真实仓库地址。"
  exit 4
}

$today = Get-Date -Format "yyyy-MM-dd"
$log = @()

# ---- 健康检查：当日 7 板块日报是否存在 ----
$missing = @()
foreach ($b in $Boards) {
  $f = Join-Path $RepoDir ("reports\$b\$today.md")
  if (-not (Test-Path $f)) { $missing += $b }
}
if ($missing.Count -gt 0) {
  $log += "⚠ 当日($today) 缺失板块日报: $($missing -join ', ') —— 仍在部署现有内容，请检查生成自动化是否运行。"
} else {
  $log += "✓ 当日($today) 7 板块日报齐全。"
}

Set-Location $RepoDir

# ---- 若尚未初始化仓库 ----
if (-not (Test-Path (Join-Path $RepoDir ".git"))) {
  & $GitExe init | Out-Null
  & $GitExe checkout -b main 2>$null
  & $GitExe remote remove origin 2>$null
  & $GitExe remote add origin $global:DEPLOY_REMOTE
}

# ---- remote 检查 ----
$origin = & $GitExe remote get-url origin 2>$null
if ([string]::IsNullOrWhiteSpace($origin)) {
  & $GitExe remote add origin $global:DEPLOY_REMOTE
}

# ---- 提交 ----
& $GitExe add -A
$status = & $GitExe status --porcelain
if ([string]::IsNullOrWhiteSpace($status)) {
  $log += "• 无本地变更，无需提交。"
} else {
  & $GitExe commit -m "auto-deploy $today $(Get-Date -Format HH:mm)" | Out-Null
  $log += "• 已提交本地变更 ($(($status -split "`n").Count) 个文件)。"
}

# ---- 推送（PAT 仅本次进程内嵌入 URL，不写入 .git/config） ----
if ([string]::IsNullOrWhiteSpace($global:DEPLOY_PAT)) {
  Write-Warning "DEPLOY_PAT 为空，尝试无凭证推送（若已配置系统 credential 则可成功）。"
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
