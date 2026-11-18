# 產生要上傳到市府 repo（taipei-doit/townpass2026-PopPal）的「乾淨版本」：
#   - 只有目前的檔案，沒有任何 git 歷史（舊 commit 裡的私人位址、Email 都不會帶過去）
#   - 不含提案文件夾、worktree、本機設定；Gemma 權重改放 GitHub Release，不走 Git LFS
#   - 匯出後掃一次敏感字串，有命中就停下來
#   - 只做到 git init，不 commit、不 push（由你手動）
#
#   .\scripts\make-clean-export.ps1                          # 匯出到 ..\townpass2026-PopPal
#   .\scripts\make-clean-export.ps1 -Dest D:\out\PopPal
#   .\scripts\make-clean-export.ps1 -Force                   # 目的資料夾已存在時先清空
param(
  [string]$Dest = '',
  [switch]$Force
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $Dest) { $Dest = Join-Path (Split-Path -Parent $root) 'townpass2026-PopPal' }

if (Test-Path $Dest) {
  if (-not $Force) { throw "目的資料夾已存在：$Dest（加 -Force 會先清空）" }
  if (Test-Path (Join-Path $Dest '.git')) { throw "目的資料夾裡已經有 .git：$Dest。為了不蓋掉你手動做的 commit，請自己刪掉或換一個 -Dest" }
  Remove-Item -Recurse -Force $Dest
}
New-Item -ItemType Directory -Force $Dest | Out-Null

# 1) 檔案清單：git 追蹤的檔案 + 尚未 commit 的新檔（遵守 .gitignore）
Push-Location $root
try {
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $files = & git -c core.quotepath=false ls-files --cached --others --exclude-standard
  $ErrorActionPreference = $prev
} finally { Pop-Location }

$excludePrefix = @('submission/', 'worktrees/', '.claude/', 'release/')
$excludeExt = @('.gguf', '.apk')
$copied = 0
foreach ($f in $files) {
  if (-not $f) { continue }
  if ($excludePrefix | Where-Object { $f.StartsWith($_) }) { continue }
  if ($excludeExt -contains [IO.Path]::GetExtension($f).ToLower()) { continue }
  $src = Join-Path $root $f
  if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { continue }   # 已刪除但尚未 commit 的檔案
  $dst = Join-Path $Dest $f
  New-Item -ItemType Directory -Force (Split-Path -Parent $dst) | Out-Null
  Copy-Item -LiteralPath $src -Destination $dst
  $copied++
}

# 2) 不再使用 Git LFS（權重改放 Release；ONNX 28 MB 直接進 git）
$ga = Join-Path $Dest '.gitattributes'
if (Test-Path $ga) {
  $lines = Get-Content -Encoding utf8 $ga | Where-Object { $_ -notmatch 'filter=lfs' -and $_ -notmatch 'Git LFS' }
  [IO.File]::WriteAllLines($ga, $lines, (New-Object Text.UTF8Encoding($false)))
}
# 原本的 LFS 指標檔若沒有被換成實體檔，代表本機沒有 git lfs pull 過
Get-ChildItem -Recurse -File $Dest -Filter *.onnx | ForEach-Object {
  if ($_.Length -lt 1024 -and (Get-Content -Raw $_.FullName) -match 'git-lfs') { throw "$($_.FullName) 只是 LFS 指標，請先在原 repo 執行 git lfs pull" }
}

# 3) 敏感字串掃描（文字檔）
#    通用規則寫在這裡；私人的字串（伺服器位址、Email、本機路徑、舊 repo 名稱…）放在 release\sensitive-patterns.txt，
#    一行一個「原樣字串」（不是 regex）。那個資料夾被 .gitignore 排除，所以私人字串不會跟著這支腳本一起公開。
$patterns = @('\bgh[pousr]_[A-Za-z0-9]{30,}', '\bAKIA[0-9A-Z]{16}\b', '-----BEGIN [A-Z ]*PRIVATE KEY-----', '(?i)\bsk-[A-Za-z0-9]{32,}')
$private = Join-Path $root 'release\sensitive-patterns.txt'
if (Test-Path $private) {
  $patterns += Get-Content -Encoding utf8 $private | Where-Object { $_.Trim() -and -not $_.StartsWith('#') } | ForEach-Object { [regex]::Escape($_.Trim()) }
} else {
  Write-Host "提醒：沒有 $private，只掃通用規則" -ForegroundColor Yellow
}
$textExt = @('.md', '.txt', '.ps1', '.sh', '.mjs', '.js', '.ts', '.vue', '.py', '.dart', '.kt', '.json', '.jsonl', '.yml', '.yaml', '.xml', '.html', '.css', '.gradle', '.properties', '.dot', '.conf', '.example')
$hits = @()
# tokenizer.json 是詞表，裡面有大量看起來像金鑰的隨機字串，不掃
Get-ChildItem -Recurse -File $Dest | Where-Object { $textExt -contains $_.Extension.ToLower() -and $_.Length -lt 20MB -and $_.Name -ne 'tokenizer.json' -and $_.FullName -notlike '*\.git\*' } | ForEach-Object {
  $file = $_
  foreach ($p in $patterns) {
    $m = Select-String -LiteralPath $file.FullName -Pattern $p -List
    if ($m) { $hits += '{0}:{1}  [{2}]' -f $file.FullName.Substring($Dest.Length + 1), $m.LineNumber, $p }
  }
}
if ($hits.Count) {
  Write-Host '找到敏感字串，請先處理再上傳：' -ForegroundColor Red
  $hits | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
  exit 1
}

# 4) 只 init，不 commit
Push-Location $Dest
try {
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  & git init -b main 2>&1 | Out-Null
  $ErrorActionPreference = $prev
} finally { Pop-Location }

$mb = [math]::Round(((Get-ChildItem -Recurse -File $Dest | Where-Object { $_.FullName -notlike '*\.git\*' } | Measure-Object Length -Sum).Sum) / 1MB, 1)
Write-Host "完成：$copied 個檔案、$mb MB → $Dest" -ForegroundColor Green
Write-Host '敏感字串掃描：0 筆' -ForegroundColor Green
Write-Host '接下來（手動）：見 release\UPLOAD_CHECKLIST.md' -ForegroundColor Cyan
