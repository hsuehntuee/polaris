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
Copy-Item $apk (Join-Path $OutDir 'Polaris-offline.apk') -Force
Copy-Item $gguf (Join-Path $OutDir 'gemma-3-270m-decider-Q8_0.gguf') -Force
$sums = Get-ChildItem $OutDir -File | Where-Object { $_.Extension -in '.apk', '.gguf', '.zip' } | ForEach-Object {
  '{0}  {1}' -f (Get-FileHash -Algorithm SHA256 $_.FullName).Hash.ToLower(), $_.Name
}
[System.IO.File]::WriteAllLines((Join-Path $OutDir 'SHA256SUMS.txt'), $sums, (New-Object System.Text.UTF8Encoding($false)))
Get-ChildItem $OutDir -File | Format-Table Name, @{ n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) } } -AutoSize
