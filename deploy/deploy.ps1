# 把程式碼打包送到一台有 Docker 的 Linux 主機（預設放在 ~/tmp/tmp/townpass-assistant），然後 docker compose up --build。
# 只會傳需要的資料夾（不含 node_modules / dist / .git / tools/models）。
#
#   .\deploy\deploy.ps1 -Target user@host            # 部署
#   .\deploy\deploy.ps1 -Target user@host -Down      # 停掉
#   .\deploy\deploy.ps1 -Target user@host -Logs      # 看 log
#
# 也可以先設環境變數 TP_DEPLOY_TARGET=user@host，就不用每次帶 -Target。
param(
  [string]$Target = $env:TP_DEPLOY_TARGET,
  [string]$RemoteDir = 'tmp/tmp/townpass-assistant',
  [switch]$Down,
  [switch]$Logs
)
$ErrorActionPreference = 'Stop'
if (-not $Target) { throw '請用 -Target user@host 指定部署主機（或設環境變數 TP_DEPLOY_TARGET）' }
$ssh = (Get-Command ssh -ErrorAction Stop).Source
$scp = (Get-Command scp -ErrorAction Stop).Source
$root = Split-Path -Parent $PSScriptRoot

if ($Down) { & $ssh $Target "cd ~/$RemoteDir && docker compose -f deploy/docker-compose.yml down"; exit $LASTEXITCODE }
if ($Logs) { & $ssh $Target "cd ~/$RemoteDir && docker compose -f deploy/docker-compose.yml logs --tail 100"; exit $LASTEXITCODE }

$tar = Join-Path ([IO.Path]::GetTempPath()) 'townpass-assistant.tgz'
Push-Location $root
try {
  # Windows 內建 bsdtar
  & tar -czf $tar `
    --exclude=node_modules --exclude=dist --exclude=.git --exclude=.vite `
    TownPass-Services assistant deploy scripts eval tools/llm/out/gemma-3-270m-decider-Q8_0.gguf
} finally { Pop-Location }
Write-Host "打包完成: $tar ($([math]::Round((Get-Item $tar).Length/1MB,1)) MB)"

& $ssh $Target "mkdir -p ~/$RemoteDir"
& $scp $tar "${Target}:~/$RemoteDir/src.tgz"
& $ssh $Target "cd ~/$RemoteDir && tar -xzf src.tgz && rm src.tgz && docker compose -f deploy/docker-compose.yml up -d --build && docker compose -f deploy/docker-compose.yml ps"
Write-Host "完成。小幫手: http://$($Target.Split('@')[1]):18080/assistant/" -ForegroundColor Green
