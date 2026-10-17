#!/bin/bash -eu

export LIBWEBRTC_DOWNLOAD_URL=https://github.com/FireDragonGameStudio/com.unity.webrtc.fdgs/releases/download/libwebrtc-M116/webrtc-android.zip
export LIBWEBRTC_SHA256=f561153cf06dc5d0c95cb7272168582df9cb37a960c8fb7907dd775547766d4a
export SOLUTION_DIR=$(pwd)/Plugin~
export ARCH_ABI=arm64-v8a

# Download LibWebRTC 
curl -fL "$LIBWEBRTC_DOWNLOAD_URL" -o webrtc.zip || exit 1
echo "$LIBWEBRTC_SHA256  webrtc.zip" | sha256sum --check --strict || exit 1
unzip -d $SOLUTION_DIR/webrtc webrtc.zip 

# Build UnityRenderStreaming Plugin 
pushd "$SOLUTION_DIR"
cmake . \
  -B build \
  -D CMAKE_SYSTEM_NAME=Android \
  -D CMAKE_ANDROID_API_MIN=24 \
  -D CMAKE_ANDROID_API=24 \
  -D CMAKE_ANDROID_ARCH_ABI=$ARCH_ABI \
  -D CMAKE_ANDROID_NDK=$ANDROID_NDK \
  -D CMAKE_BUILD_TYPE=Debug \
  -D CMAKE_ANDROID_STL_TYPE=c++_static

cmake --build build --target WebRTCLibTest
popd

# Copy test runner
cp $SOLUTION_DIR/build/WebRTCPluginTest/WebRTCLibTest .