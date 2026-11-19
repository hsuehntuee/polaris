# 一鍵產生 GitHub Release 用的檔案：離線版 APK + Gemma 決策器權重 + SHA256。
# 網頁、模型、llama-server 全部打包進 APK，手機不需要連電腦或網路。
#
#   .\scripts\build-release.ps1                 # 產出到 release\
#   .\scripts\build-release.ps1 -SkipWeb        # 網頁已經 build 過，只重包 APK
#   .\scripts\build-release.ps1 -DevTools       # 自己實機測試用：開 WebView 遠端除錯與 /sdcard 覆蓋資料夾（phone-probe、phone-push-web 需要）；不要拿去發布
#
# 前置：Node 20 + pnpm、Flutter 3.47.6（fvm）、JDK 17、Android SDK；
#       tools\llama-android\snapdragon\llama-b12180\（llama.cpp 官方 Snapdragon release，解壓即可）；
#       tools\llm\out\gemma-3-270m-decider-Q8_0.gguf（Release 附件或 tools\llm\finetune_gemma.py 產生）。
param(
  [switch]$SkipWeb,
  [switch]$DevTools,
  [string]$OutDir = ''
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'tools\env.ps1')
Require-Flutter
if (-not $OutDir) { $OutDir = Join-Path $root 'release' }
$gguf = Join-Path $root 'tools\llm\out\gemma-3-270m-decider-Q8_0.gguf'
if (-not (Test-Path $gguf)) { throw "找不到模型：$gguf" }

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Run($exe, [string[]]$argv, $cwd) {
  # 外部程式（vite、gradle）會把進度寫到 stderr；Windows PowerShell 5.1 在 Stop 模式下會把它當成錯誤，所以這裡只看結束碼
  Push-Location $cwd
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { & $exe @argv 2>&1 | ForEach-Object { "$_" }; if ($LASTEXITCODE -ne 0) { throw "$exe $($argv -join ' ') 失敗（$LASTEXITCODE）" } }
  finally { $ErrorActionPreference = $prev; Pop-Location }
}

# pubspec.yaml 會被 bundle-web.mjs 改寫 assets 清單；結束後還原，避免 git 出現無關的差異
$pubspec = Join-Path $root 'TownPass\pubspec.yaml'
$pubspecBackup = Get-Content -Raw -Encoding utf8 $pubspec

try {
  if (-not $SkipWeb) {
    Step 'build TownPass-Services'
    Run 'pnpm' @('install', '--frozen-lockfile') (Join-Path $root 'TownPass-Services')
    Run 'pnpm' @('build-only') (Join-Path $root 'TownPass-Services')
    Step 'build assistant + overlay'
    Run 'pnpm' @('install', '--frozen-lockfile') (Join-Path $root 'assistant')
    Run 'pnpm' @('build-only') (Join-Path $root 'assistant')
  }
  Step 'generate Dart code (flutter_gen, json_serializable)'
  # lib/gen/*.gen.dart 與 *.g.dart 不在 repo 裡：乾淨 clone 要先產生（在 bundle-web 改 pubspec 之前跑，產生的內容才跟原本的 assets 清單一致）
  Run $FlutterBat @('pub', 'get') (Join-Path $root 'TownPass')
  Run $DartBat @('run', 'build_runner', 'build', '--delete-conflicting-outputs') (Join-Path $root 'TownPass')
  Step 'bundle web into the APK assets'
  Run 'node' @('scripts/bundle-web.mjs') $root
  Step 'copy llama-server (Snapdragon build) + model into the APK'
  Run 'node' @('scripts/prepare-llama-jni.mjs') $root
  Step 'flutter build apk --release'
  $defines = @('--dart-define=LLM_URL=http://localhost:8080', '--dart-define=OFFLINE_WEB=true')
  if ($DevTools) { $defines += '--dart-define=DEV_TOOLS=true'; Write-Host '  DEV_TOOLS=true：這是測試版，不要上傳到 Release' -ForegroundColor Yellow }
  Run $FlutterBat (@('build', 'apk', '--release') + $defines) (Join-Path $root 'TownPass')
}
finally {
  [System.IO.File]::WriteAllText($pubspec, $pubspecBackup, (New-Object System.Text.UTF8Encoding($false)))
}

Step "collect release files → $OutDir"
New-Item -ItemType Directory -Force $OutDir | Out-Null
$apk = Join-Path $root 'TownPass\build\app\outputs\flutter-apk\app-release.apk'
if ($DevTools) {
  # 測試版：另外取名，不碰要發布的 Polaris-offline.apk、build-info.json 與 SHA256SUMS.txt
  $devApk = Join-Path $OutDir 'Polaris-offline-DEVTOOLS.apk'
  Copy-Item $apk $devApk -Force
  Write-Host "測試版（DEV_TOOLS）→ $devApk；不要上傳。" -ForegroundColor Yellow
  return
}
Copy-Item $apk (Join-Path $OutDir 'Polaris-offline.apk') -Force
Copy-Item $gguf (Join-Path $OutDir 'gemma-3-270m-decider-Q8_0.gguf') -Force
# 正式版的出處：final-upload.ps1 會核對 devTools=false 而且雜湊跟 APK 一致
$apkHash = (Get-FileHash -Algorithm SHA256 (Join-Path $OutDir 'Polaris-offline.apk')).Hash.ToLower()
$commit = ''
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'   # git 寫到 stderr 的提示（例如 CRLF 警告）不能讓腳本在寫 build-info 之前中斷
try {
  $commit = "$(& git -C $root rev-parse --short HEAD 2>$null)".Trim()
  if ($LASTEXITCODE -ne 0) { $commit = 'unknown' }
  elseif ("$(& git -C $root status --porcelain 2>$null)".Trim()) { $commit = "$commit+dirty" }   # 有未 commit 的修改：APK 不完全等於這個 commit
} catch { $commit = 'unknown' }
finally { $ErrorActionPreference = $prevEap }
$global:LASTEXITCODE = 0   # 沒有 git 歷史（例如乾淨匯出版）時 git 會留下 128，不能讓整支腳本看起來像失敗
$info = [ordered]@{ apk = 'Polaris-offline.apk'; sha256 = $apkHash; devTools = $false; commit = "$commit"; builtAt = (Get-Date).ToString('s') }
[System.IO.File]::WriteAllText((Join-Path $OutDir 'build-info.json'), ($info | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
# SHA256 只列要上傳的三個附件（資料夾裡其他 APK，例如測試版，不列）
$sums = @('Polaris-offline.apk', 'gemma-3-270m-decider-Q8_0.gguf', 'walkthrough-screenshots.zip') | Where-Object { Test-Path (Join-Path $OutDir $_) } | ForEach-Object {
  '{0}  {1}' -f (Get-FileHash -Algorithm SHA256 (Join-Path $OutDir $_)).Hash.ToLower(), $_
}
[System.IO.File]::WriteAllLines((Join-Path $OutDir 'SHA256SUMS.txt'), $sums, (New-Object System.Text.UTF8Encoding($false)))
Get-ChildItem $OutDir -File | Format-Table Name, @{ n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) } } -AutoSize
