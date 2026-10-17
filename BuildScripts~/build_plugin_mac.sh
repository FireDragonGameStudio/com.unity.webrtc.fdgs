#!/bin/bash -eu

export LIBWEBRTC_DOWNLOAD_URL=https://github.com/FireDragonGameStudio/com.unity.webrtc.fdgs/releases/download/libwebrtc-M116/webrtc-mac.zip
export LIBWEBRTC_SHA256=4b25237c4928c48587b71e545255f21af19fd6d18f290fdcd76d6129f7d93f86
export SOLUTION_DIR=$(pwd)/Plugin~
export DYLIB_FILE=$(pwd)/Runtime/Plugins/macOS/libwebrtc.dylib

BUILD_TYPE="${1:-release}"
if [ "$BUILD_TYPE" = "debug" ]; then
  CMAKE_BUILD_TYPE="Debug"
else
  CMAKE_BUILD_TYPE="Release"
fi

# Install cmake (preinstalled on GitHub-hosted macOS runners)
if ! command -v cmake > /dev/null; then
  export HOMEBREW_NO_AUTO_UPDATE=1
  brew install cmake
fi

# Download LibWebRTC 
curl -fL "$LIBWEBRTC_DOWNLOAD_URL" -o webrtc.zip || exit 1
echo "$LIBWEBRTC_SHA256  webrtc.zip" | shasum -a 256 --check || exit 1
unzip -o -d $SOLUTION_DIR/webrtc webrtc.zip 

# Remove old dylib file
rm -rf "$DYLIB_FILE"

# Build UnityRenderStreaming Plugin
cd "$SOLUTION_DIR"
cmake --preset=macos -DCMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE
cmake --build --preset=release-macos --target=WebRTCPlugin
