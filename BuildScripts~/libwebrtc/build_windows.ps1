# Builds libwebrtc for Windows x64 with clang-cl and Chromium's libc++ and writes the package to <package dir>.
# Usage: build_windows.ps1 <webrtc root (contains src and depot_tools)> <package dir>

param(
  [Parameter(Mandatory)][string]$Root,
  [Parameter(Mandatory)][string]$Package
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$env:PATH = "$Root\depot_tools;$env:PATH"
$env:DEPOT_TOOLS_WIN_TOOLCHAIN = '0'
Set-Location "$Root\src"
New-Item -ItemType Directory -Force $Package | Out-Null
$Package = (Resolve-Path $Package).Path

# gn reads args.gn from the output directory; writing it avoids quoting the args through gn.bat.
$out = 'out/Release-x64'
New-Item -ItemType Directory -Force $out | Out-Null
@'
target_os = "win"
target_cpu = "x64"
is_debug = false
is_component_build = false
symbol_level = 0
treat_warnings_as_errors = false
rtc_include_tests = false
rtc_build_examples = false
rtc_use_h264 = false
use_rtti = true
use_custom_libcxx = true
'@ | Set-Content -Encoding ascii "$out/args.gn"
gn gen $out

# libc++ is a source set that executables link implicitly; build it explicitly so its objects can be added
# to the static library. Windows uses the MSVC C++ ABI (vcruntime) instead of libc++abi.
$libcxxTargets = @(gn ls $out | Where-Object { $_ -match '^//buildtools/third_party/libc\+\+(abi)?:libc\+\+(abi)?$' } |
  ForEach-Object { $_.Substring(2) })
Write-Host "libc++ targets: $libcxxTargets"
if (-not $libcxxTargets) {
  gn ls $out | Select-String 'libc\+\+' | Select-Object -First 20
  throw 'No libc++ targets found'
}
autoninja -C $out webrtc @libcxxTargets

$llvmBin = (Resolve-Path 'third_party/llvm-build/Release+Asserts/bin').Path
$lib = "$Package\lib\x64\webrtc.lib"
New-Item -ItemType Directory -Force (Split-Path $lib) | Out-Null
$libcxxObjects = @(Get-ChildItem "$out/obj/buildtools/third_party/libc++" -Recurse -Filter *.obj | Sort-Object FullName)
Write-Host "Adding $($libcxxObjects.Count) libc++ objects"
if (-not $libcxxObjects) { throw 'No libc++ objects found' }
# Chromium links with lld-link, whose /lib mode is llvm-lib; it merges the members of webrtc.lib with the objects.
$rsp = "$out/libcxx_objects.rsp"
$libcxxObjects | ForEach-Object { '"' + ($_.FullName -replace '\\', '/') + '"' } | Set-Content -Encoding ascii $rsp
if (Test-Path "$llvmBin\llvm-lib.exe") {
  & "$llvmBin\llvm-lib.exe" "/out:$lib" "$out/obj/webrtc.lib" "@$rsp"
} else {
  & "$llvmBin\lld-link.exe" /lib "/out:$lib" "$out/obj/webrtc.lib" "@$rsp"
}
$size = (Get-Item $lib).Length
if ($size -lt 50000000) { throw "webrtc.lib is only $size bytes" }

# Headers: every libwebrtc header (*.h, and the *.inc files some of them include, e.g. abseil's int128), plus
# the complete libc++ include directories (libc++ headers such as <vector> have no extension). libc++abi is
# not used on Windows but shipped like on the other platforms.
$src = (Get-Location).Path
$PSNativeCommandUseErrorActionPreference = $false
robocopy $src "$Package\include" *.h *.inc /S /XD "$src\out" "$src\third_party\llvm-build" /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed with $LASTEXITCODE" }
$PSNativeCommandUseErrorActionPreference = $true
foreach ($dir in 'third_party/libc++/src/include', 'third_party/libc++abi/src/include', 'buildtools/third_party/libc++') {
  New-Item -ItemType Directory -Force "$Package\include\$dir" | Out-Null
  Copy-Item -Recurse -Force "$dir\*" "$Package\include\$dir\"
}
Get-ChildItem "$Package\include\buildtools\third_party\libc++" -Recurse -Filter *.gn | Remove-Item

# Compiler flags for code that uses this package, in clang-cl syntax. ${WEBRTC_INCLUDE_DIR} is replaced by the
# consumer. Chromium puts the libc++ headers in front of the MSVC include directories (which hold both the CRT
# and the MSVC STL, so there is no -nostdinc++ equivalent); /external:I does the same as -isystem.
$defines = @(gn desc $out //api:rtc_error defines | ForEach-Object { $_.Trim() } |
  Where-Object { $_ -match '^(_LIBCPP|_LIBCXXABI|CR_)' } | ForEach-Object { "/D$_" })
$flags = @(
  '/external:I${WEBRTC_INCLUDE_DIR}/buildtools/third_party/libc++'
  '/external:I${WEBRTC_INCLUDE_DIR}/third_party/libc++/src/include'
) + $defines
($flags -join ' ') | Set-Content -Encoding ascii "$Package\cxx_flags.txt"
gn desc $out //api:rtc_error cflags_cc | Set-Content -Encoding ascii "$Package\gn_cflags_cc.txt"
gn desc $out //api:rtc_error defines | Set-Content -Encoding ascii "$Package\gn_defines.txt"
Copy-Item "$out/args.gn" "$Package\args.gn"

# The plugin must use the same C runtime (/MT = static, /MD = DLL).
$crt = @(gn desc $out //api:rtc_error cflags | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^/M[TD]d?$' })
if ($crt.Count -ne 1) { throw "Could not determine the C runtime: $crt" }
$sdk = (Select-String -Path build/vs_toolchain.py -Pattern "^SDK_VERSION = '(.+)'").Matches[0].Groups[1].Value

@"
WEBRTC_BRANCH=branch-heads/$($env:WEBRTC_BRANCH ?? 'unknown')
WEBRTC_COMMIT=$(git rev-parse HEAD)
LIBCXX_COMMIT=$(git -C third_party/libc++/src rev-parse HEAD)
CLANG_REVISION=$(python3 tools/clang/scripts/update.py --print-revision)
MSVC_RUNTIME=$($crt[0])
WINDOWS_SDK=$sdk
"@ | Set-Content -Encoding ascii "$Package\VERSIONS"

python3 tools_webrtc/libs/generate_licenses.py --target :webrtc $out $out
Copy-Item "$out/LICENSE.md" "$Package\LICENSE.md"

Write-Host 'Package:'
Get-Content "$Package\VERSIONS", "$Package\cxx_flags.txt"
Write-Host "webrtc.lib: $size bytes"
