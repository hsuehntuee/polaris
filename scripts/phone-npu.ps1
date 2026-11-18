# 手機上的決策器模型與評測連線。App 會自己啟動 llama-server，這裡只負責放模型與轉接埠。
#   .\scripts\phone-npu.ps1 -PushModel    # 把模型放到 App 的外部資料夾，App 重啟後使用（只有 debug 版或 build-release.ps1 -DevTools 的測試版會讀；正式版只用 APK 內建的模型）
#   .\scripts\phone-npu.ps1 -Forward      # 電腦 127.0.0.1:18080 轉到手機上的 llama-server
#   .\scripts\phone-npu.ps1 -Uninstall    # 解除安裝 TownPass
param(
  [switch]$PushModel, [switch]$Forward, [switch]$Uninstall,
  [string]$Model = 'tools/llm/out/gemma-3-270m-decider-Q8_0.gguf'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'tools\env.ps1')
$ext = '/sdcard/Android/data/com.example.townpass/files/gguf'

if ($PushModel) {
  & $Adb shell "mkdir -p $ext"
  & $Adb push (Join-Path $root $Model) "$ext/$(Split-Path -Leaf $Model)"
  & $Adb shell "ls -la $ext/"
}
if ($Forward) {
  & $Adb forward tcp:18080 tcp:8080
  Write-Host 'http://127.0.0.1:18080 → 手機上的 llama-server'
}
if ($Uninstall) {
  & $Adb uninstall com.example.townpass
}
