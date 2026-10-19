@echo off
setlocal

rem Builds Runtime\Plugins\x86_64\webrtc.dll against libwebrtc M156 with Chromium's clang-cl.
rem Needs Visual Studio 2022 or later with the C++ x64 tools (C runtime, Windows SDK, cl.exe as nvcc host
rem compiler), the CUDA toolkit, the Vulkan SDK, CMake, 7-Zip and curl. Usage: build_plugin_win.cmd [target]

set LIBWEBRTC_DOWNLOAD_URL=https://github.com/FireDragonGameStudio/com.unity.webrtc.fdgs/releases/download/libwebrtc-M156/webrtc-win.zip
set LIBWEBRTC_SHA256=469f828dd72df5097b1dd9c7772cd24624584cf13b755a102a84a65ed86d189b
set SOLUTION_DIR=%cd%\Plugin~

rem The package contains only a release library, built with NDEBUG and /MT: build the plugin in Release.
set CMAKE_BUILD_TYPE=Release
set "TARGET=%~1"
if "%TARGET%"=="" set TARGET=WebRTCPlugin

echo Download LibWebRTC

if not exist %SOLUTION_DIR%\webrtc (
  curl -fL %LIBWEBRTC_DOWNLOAD_URL% -o webrtc.zip || exit /b 1
  powershell -NoProfile -Command "if ((Get-FileHash webrtc.zip -Algorithm SHA256).Hash -ne '%LIBWEBRTC_SHA256%') { Write-Error 'webrtc.zip checksum mismatch'; exit 1 }" || exit /b 1
  7z x -aoa webrtc.zip -o%SOLUTION_DIR%\webrtc || exit /b 1
)

rem The plugin shares standard library types with libwebrtc (Chromium's libc++), so it is compiled with the
rem clang-cl that built libwebrtc: CLANG_REVISION in VERSIONS.
for /f "tokens=1,* delims==" %%a in (%SOLUTION_DIR%\webrtc\VERSIONS) do if "%%a"=="CLANG_REVISION" set CLANG_REVISION=%%b
set CLANG_DIR=%SOLUTION_DIR%\out\clang-%CLANG_REVISION%

echo Download Chromium clang %CLANG_REVISION%

if not exist %CLANG_DIR%\bin\clang-cl.exe (
  curl -fL https://commondatastorage.googleapis.com/chromium-browser-clang/Win/clang-%CLANG_REVISION%.tar.xz -o clang.tar.xz || exit /b 1
  7z x -y clang.tar.xz || exit /b 1
  7z x -y clang.tar -o%CLANG_DIR% || exit /b 1
  del clang.tar clang.tar.xz
)

rem Ninja and clang-cl need a Visual Studio x64 developer environment.
if not defined VCToolsInstallDir (
  for /f "usebackq delims=" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set VS_DIR=%%i
)
if not defined VCToolsInstallDir (
  call "%VS_DIR%\VC\Auxiliary\Build\vcvars64.bat" || exit /b 1
)
set PATH=%CLANG_DIR%\bin;%PATH%

echo Build com.fdgs.webrtc Plugin

cd %SOLUTION_DIR%
cmake --preset=x64-windows -DCMAKE_C_COMPILER=%CLANG_DIR:\=/%/bin/clang-cl.exe -DCMAKE_CXX_COMPILER=%CLANG_DIR:\=/%/bin/clang-cl.exe -DCMAKE_LINKER=%CLANG_DIR:\=/%/bin/lld-link.exe || exit /b 1
cmake --build out/build/x64-windows --config %CMAKE_BUILD_TYPE% --target %TARGET%
