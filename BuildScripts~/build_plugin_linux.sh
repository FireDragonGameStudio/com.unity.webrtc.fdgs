#!/bin/bash -eu

export LIBWEBRTC_DOWNLOAD_URL=https://github.com/FireDragonGameStudio/com.unity.webrtc.fdgs/releases/download/libwebrtc-M156/webrtc-linux.zip
# Keep in sync with LIBWEBRTC_SHA256 in .github/workflows/native-linux.yml.
export LIBWEBRTC_SHA256=7d6b95035fb9c978d528170e875c843dc644e70e3aca8ab0e0422067bd809b33
export SOLUTION_DIR=$(pwd)/Plugin~
export OUTPUT_FILEPATH=$(pwd)/Runtime/Plugins/x86_64/libwebrtc.so

BUILD_TYPE="${1:-release}"
if [ "$BUILD_TYPE" = "debug" ]; then
  CMAKE_BUILD_TYPE="Debug"
else
  CMAKE_BUILD_TYPE="Release"
fi

# libwebrtc M156 is built with Chromium's libc++, so compile with the same clang: download
# https://commondatastorage.googleapis.com/chromium-browser-clang/Linux_x64/clang-<CLANG_REVISION>.tar.xz
# (CLANG_REVISION is in Plugin~/webrtc/VERSIONS) and pass it with CC/CXX, as .github/workflows/native-linux.yml does.
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
