#!/bin/bash -eu

export LIBWEBRTC_DOWNLOAD_URL=https://github.com/FireDragonGameStudio/com.unity.webrtc.fdgs/releases/download/libwebrtc-M116/webrtc-android.zip
export LIBWEBRTC_SHA256=f561153cf06dc5d0c95cb7272168582df9cb37a960c8fb7907dd775547766d4a
export SOLUTION_DIR=$(pwd)/Plugin~
export PLUGIN_DIR=$(pwd)/Runtime/Plugins/Android

BUILD_TYPE="${1:-release}"
if [ "$BUILD_TYPE" = "debug" ]; then
  CMAKE_BUILD_TYPE="Debug"
else
  CMAKE_BUILD_TYPE="Release"
fi

# ANDROID_NDK must point to the Android NDK (r28 or newer is tested).
if [ -z "${ANDROID_NDK:-}" ] || [ ! -f "$ANDROID_NDK/build/cmake/android.toolchain.cmake" ]; then
  echo "Set ANDROID_NDK to the Android NDK root directory." >&2
  exit 1
fi

# Download LibWebRTC
curl -fL "$LIBWEBRTC_DOWNLOAD_URL" -o webrtc.zip || exit 1
echo "$LIBWEBRTC_SHA256  webrtc.zip" | sha256sum --check --strict || exit 1
unzip -o -d $SOLUTION_DIR/webrtc webrtc.zip
cp -f $SOLUTION_DIR/webrtc/lib/libwebrtc.aar $PLUGIN_DIR

# If debug build, download android-binaries that contains Vulkan validation layer
if [ "$BUILD_TYPE" = "debug" ]; then
  if [ ! -d "$SOLUTION_DIR/android-binaries" ]; then
    wget -q --show-progress https://github.com/KhronosGroup/Vulkan-ValidationLayers/releases/download/vulkan-sdk-1.4.321.0/android-binaries-1.4.321.0.zip
    unzip -d "$(pwd)" android-binaries-1.4.321.0.zip
    mv "$(pwd)/android-binaries-1.4.321.0" $SOLUTION_DIR/android-binaries
  fi
fi

# Build UnityRenderStreaming Plugin
cd "$SOLUTION_DIR"
for ARCH_ABI in "arm64-v8a" "x86_64"
do
  case $ARCH_ABI in
    arm64-v8a) PRESET=arm64-android ;;
    x86_64) PRESET=x86_64-android ;;
  esac

  cmake --preset=$PRESET -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE

  cmake \
    --build out/build/$PRESET \
    --target WebRTCPlugin

  # libwebrtc.so move into libwebrtc.aar
  pushd $PLUGIN_DIR
  mkdir -p jni/$ARCH_ABI
  mv libwebrtc.so jni/$ARCH_ABI
  zip -g libwebrtc.aar jni/$ARCH_ABI/libwebrtc.so
  # If debug build, add Vulkan validation layer
  if [ "$BUILD_TYPE" = "debug" ]; then
    cp $SOLUTION_DIR/android-binaries/$ARCH_ABI/libVkLayer_khronos_validation.so jni/$ARCH_ABI
    zip -g libwebrtc.aar jni/$ARCH_ABI/libVkLayer_khronos_validation.so
  fi
  rm -r jni
  popd
  rm -rf out/build/$PRESET
done
