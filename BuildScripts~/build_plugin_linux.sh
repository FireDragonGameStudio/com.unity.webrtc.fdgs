#!/bin/bash -eu

export LIBWEBRTC_DOWNLOAD_URL=https://github.com/FireDragonGameStudio/com.unity.webrtc.fdgs/releases/download/libwebrtc-M116/webrtc-linux.zip
# Keep in sync with LIBWEBRTC_SHA256 in .github/workflows/native-linux.yml.
export LIBWEBRTC_SHA256=d7ca2f66f1ac7d70b2f859497c127e15050c19a0bc431ad8b7d892d6ca2be819
export SOLUTION_DIR=$(pwd)/Plugin~
export OUTPUT_FILEPATH=$(pwd)/Runtime/Plugins/x86_64/libwebrtc.so

BUILD_TYPE="${1:-release}"
if [ "$BUILD_TYPE" = "debug" ]; then
  CMAKE_BUILD_TYPE="Debug"
else
  CMAKE_BUILD_TYPE="Release"
fi

# Any clang with lld works (tested with clang 18). Override with CC/CXX, e.g. CC=clang-18 CXX=clang++-18.
CC="${CC:-clang}"
CXX="${CXX:-clang++}"

# Download LibWebRTC
curl -fL "$LIBWEBRTC_DOWNLOAD_URL" -o webrtc.zip
echo "$LIBWEBRTC_SHA256  webrtc.zip" | sha256sum --check --strict
unzip -o -d "$SOLUTION_DIR/webrtc" webrtc.zip

# Build UnityRenderStreaming Plugin
pushd "$SOLUTION_DIR"
cmake --preset=x86_64-linux -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" -DCMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE
cmake --build out/build/x86_64-linux --config $CMAKE_BUILD_TYPE --target WebRTCPlugin
popd

strip --strip-unneeded "$OUTPUT_FILEPATH"
