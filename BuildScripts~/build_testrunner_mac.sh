#!/bin/bash -eu

export LIBWEBRTC_DOWNLOAD_URL=https://github.com/FireDragonGameStudio/com.unity.webrtc.fdgs/releases/download/libwebrtc-M116/webrtc-mac.zip
export LIBWEBRTC_SHA256=4b25237c4928c48587b71e545255f21af19fd6d18f290fdcd76d6129f7d93f86
export SOLUTION_DIR=$(pwd)/Plugin~

# Install cmake
export HOMEBREW_NO_AUTO_UPDATE=1
brew install cmake

# Download LibWebRTC 
curl -fL "$LIBWEBRTC_DOWNLOAD_URL" -o webrtc.zip || exit 1
echo "$LIBWEBRTC_SHA256  webrtc.zip" | shasum -a 256 --check || exit 1
unzip -d $SOLUTION_DIR/webrtc webrtc.zip

# Build UnityRenderStreaming Plugin 
pushd "$SOLUTION_DIR"
cmake --preset=macos
cmake --build --preset=debug-macos --target=WebRTCLibTest
popd

# Copy test runner
cp "$SOLUTION_DIR/out/build/macos/WebRTCPluginTest/Debug/WebRTCLibTest" .