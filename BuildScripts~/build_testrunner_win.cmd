@echo off

set LIBWEBRTC_DOWNLOAD_URL=https://github.com/FireDragonGameStudio/com.unity.webrtc.fdgs/releases/download/libwebrtc-M116/webrtc-win.zip
set LIBWEBRTC_SHA256=e3f2e88746dbd0b9b82ed7cdcab623131252d773712b41798f8be1a8ac948f79
set SOLUTION_DIR=%cd%\Plugin~

echo -------------------
echo Download LibWebRTC 

if not exist %SOLUTION_DIR%\webrtc (
  curl -fL %LIBWEBRTC_DOWNLOAD_URL% -o webrtc.zip || exit /b 1
  powershell -NoProfile -Command "if ((Get-FileHash webrtc.zip -Algorithm SHA256).Hash -ne '%LIBWEBRTC_SHA256%') { Write-Error 'webrtc.zip checksum mismatch'; exit 1 }" || exit /b 1
  7z x -aoa webrtc.zip -o%SOLUTION_DIR%\webrtc
)

echo -------------------
echo Build com.unity.webrtc Plugin

rem Debug build with MSVC compiler crashes. Release build works fine.
rem This issue is reported on the webrtc forum.
rem https://groups.google.com/g/discuss-webrtc/c/N7L6fx784GA

pushd %SOLUTION_DIR%
cmake --preset=x64-windows-msvc
cmake --build --preset=release-windows-msvc --target=WebRTCLibTest
popd

echo -------------------
echo Copy test runner

copy %SOLUTION_DIR%\out\build\x64-windows-msvc\WebRTCPluginTest\Release\WebRTCLibTest.exe .