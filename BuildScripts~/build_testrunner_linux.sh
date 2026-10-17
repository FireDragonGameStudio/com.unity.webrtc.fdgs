#!/bin/bash -eu

export LIBWEBRTC_DOWNLOAD_URL=https://github.com/FireDragonGameStudio/com.unity.webrtc.fdgs/releases/download/libwebrtc-M116/webrtc-linux.zip
export LIBWEBRTC_SHA256=d7ca2f66f1ac7d70b2f859497c127e15050c19a0bc431ad8b7d892d6ca2be819
export SOLUTION_DIR=$(pwd)/Plugin~

source ~/.profile

# Download LibWebRTC 
curl -fL "$LIBWEBRTC_DOWNLOAD_URL" -o webrtc.zip || exit 1
echo "$LIBWEBRTC_SHA256  webrtc.zip" | sha256sum --check --strict || exit 1
unzip -d $SOLUTION_DIR/webrtc webrtc.zip 

# Build UnityRenderStreaming Plugin 
pushd "$SOLUTION_DIR"
cmake --preset=x86_64-linux
cmake --build --preset=debug-linux --target WebRTCLibTest
popd

# Copy test runner
cp "$SOLUTION_DIR/out/build/x86_64-linux/WebRTCPluginTest/Debug/WebRTCLibTest" .