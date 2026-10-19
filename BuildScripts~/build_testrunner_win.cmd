@echo off

rem Builds the native test runner WebRTCLibTest.exe against libwebrtc M156 (see build_plugin_win.cmd).
set SOLUTION_DIR=%cd%\Plugin~

call "%~dp0build_plugin_win.cmd" WebRTCLibTest || exit /b 1

echo -------------------
echo Copy test runner

copy %SOLUTION_DIR%\out\build\x64-windows\WebRTCPluginTest\Release\WebRTCLibTest.exe .
