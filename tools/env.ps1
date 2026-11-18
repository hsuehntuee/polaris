# 共用環境：自動找 Flutter、JDK 17、Android SDK。可用環境變數 FLUTTER_HOME、JAVA_HOME、ANDROID_HOME 指定。
$FlutterVersion = '3.47.6'
$OnWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows
$HomeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
$exe = if ($OnWindows) { '.bat' } else { '' }

function First-Existing([string[]]$paths) {
  foreach ($p in $paths) { if ($p -and (Test-Path $p)) { return (Resolve-Path $p).Path } }
  return $null
}

$FlutterHome = First-Existing @(
  $env:FLUTTER_HOME,
  $(if ($env:FVM_CACHE_PATH) { Join-Path $env:FVM_CACHE_PATH "versions\$FlutterVersion" }),
  $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA "fvm\versions\$FlutterVersion" }),
  (Join-Path $HomeDir "fvm/versions/$FlutterVersion"),
  (Join-Path $PSScriptRoot "../TownPass/.fvm/flutter_sdk")
)
if (-not $FlutterHome) {
  $onPath = Get-Command "flutter$exe" -ErrorAction SilentlyContinue
  if ($onPath) { $FlutterHome = Split-Path -Parent (Split-Path -Parent $onPath.Source) }
}
$FlutterBat = if ($FlutterHome) { Join-Path $FlutterHome "bin/flutter$exe" } else { $null }
$DartBat = if ($FlutterHome) { Join-Path $FlutterHome "bin/dart$exe" } else { $null }

function Require-Flutter {
  if (-not $FlutterBat -or -not (Test-Path $FlutterBat)) { throw "找不到 Flutter $FlutterVersion。執行 fvm install $FlutterVersion，或設定 FLUTTER_HOME" }
}

if (-not ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME 'bin')))) {
  $jdkRoots = @('C:\Program Files\Microsoft', 'C:\Program Files\Eclipse Adoptium', 'C:\Program Files\Java', 'C:\Program Files\Zulu', '/Library/Java/JavaVirtualMachines', '/usr/lib/jvm')
  $jdk = foreach ($r in $jdkRoots) { if (Test-Path $r) { Get-ChildItem $r -Directory -Filter '*17*' -ErrorAction SilentlyContinue | Sort-Object Name -Descending } }
  $studioJbr = First-Existing @('C:\Program Files\Android\Android Studio\jbr', '/Applications/Android Studio.app/Contents/jbr/Contents/Home')
  $found = if ($jdk) { @($jdk)[0].FullName } else { $studioJbr }
  if ($found -and (Test-Path (Join-Path $found 'Contents/Home'))) { $found = Join-Path $found 'Contents/Home' }
  if ($found) { $env:JAVA_HOME = $found }
}

$AndroidSdk = First-Existing @(
  $env:ANDROID_HOME, $env:ANDROID_SDK_ROOT,
  $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Android\Sdk' }),
  (Join-Path $HomeDir 'Library/Android/sdk'), (Join-Path $HomeDir 'Android/Sdk')
)
if ($AndroidSdk) { $env:ANDROID_HOME = $AndroidSdk }
$Adb = if ($AndroidSdk) { Join-Path $AndroidSdk ("platform-tools/adb" + $(if ($OnWindows) { '.exe' } else { '' })) } else { 'adb' }

$sep = [IO.Path]::PathSeparator
$extra = @($(if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin' }), $(if ($AndroidSdk) { Join-Path $AndroidSdk 'platform-tools' }), $(if ($FlutterHome) { Join-Path $FlutterHome 'bin' })) | Where-Object { $_ }
$env:Path = (($extra + $env:Path) -join $sep)

function Resolve-TownPassDir([string]$Root, [string]$Worktree) {
  if ($Worktree) {
    $d = Join-Path $Root "worktrees\$Worktree"
    if (-not (Test-Path $d)) { throw "找不到 worktree：$d（用 .\new-worktree.ps1 -Name $Worktree 建立）" }
    return $d
  }
  return (Join-Path $Root 'TownPass')
}

function Get-PhoneSerial {
  $lines = (& $Adb devices) -match "`tdevice$"
  if (-not $lines) {
    Write-Host '找不到 Android 手機。請確認 USB 偵錯已開、手機上已允許這台電腦、傳輸線支援資料傳輸。' -ForegroundColor Red
    & $Adb devices -l
    exit 1
  }
  return (@($lines)[0] -split "`t")[0]
}
