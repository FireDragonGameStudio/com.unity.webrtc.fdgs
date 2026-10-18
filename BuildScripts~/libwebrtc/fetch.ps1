# Fetches libwebrtc branch-heads/<branch> with its Windows dependencies into $env:WEBRTC_ROOT
# (default: $env:RUNNER_TEMP\webrtc, or .\webrtc). Windows counterpart of fetch.sh.
# Usage: fetch.ps1 <branch>   e.g. fetch.ps1 8078

param([Parameter(Mandatory)][string]$Branch)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$root = $env:WEBRTC_ROOT
if (-not $root) { $root = Join-Path ($env:RUNNER_TEMP ?? $PWD) 'webrtc' }

# Use the installed Visual Studio and Windows SDK instead of Google's internal toolchain package.
$env:DEPOT_TOOLS_WIN_TOOLCHAIN = '0'

New-Item -ItemType Directory -Force $root | Out-Null
Set-Location $root
if (-not (Test-Path depot_tools)) {
  git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git
}
$env:PATH = "$root\depot_tools;$env:PATH"
# Bootstraps depot_tools (its Python, Git and tool wrappers) on first use.
& "$root\depot_tools\update_depot_tools.bat"
python3 --version

@"
solutions = [{
  "name": "src",
  "url": "https://webrtc.googlesource.com/src.git@refs/branch-heads/$Branch",
  "deps_file": "DEPS",
  "managed": False,
  "custom_deps": {},
}]
target_os = ["win"]
"@ | Set-Content -Encoding ascii .gclient

gclient sync --no-history --shallow --with_branch_heads -D
Write-Host "libwebrtc: $(git -C src log -1 --format='%H %s')"
Get-PSDrive -PSProvider FileSystem | Format-Table -AutoSize
