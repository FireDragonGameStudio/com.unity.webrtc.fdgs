#!/bin/bash -eu
# Builds libwebrtc.so for arm64-v8a and x86_64 against the libwebrtc M156 package and adds it to libwebrtc.aar.
# Same steps as .github/workflows/native-android.yml. Needs a Linux x86_64 host with cmake, make, curl, unzip and zip.
#
# ANDROID_NDK must point to an Android NDK (ANDROID_NDK_VERSION in the package's VERSIONS); only its sysroot is
# used. The compiler is Chromium's clang of CLANG_REVISION in VERSIONS, downloaded to CHROMIUM_CLANG
# (default: Plugin~/out/clang): libwebrtc is built with Chromium's libc++, whose headers the NDK's clang cannot use.

export LIBWEBRTC_DOWNLOAD_URL=https://github.com/FireDragonGameStudio/com.unity.webrtc.fdgs/releases/download/libwebrtc-M156/webrtc-android.zip
export LIBWEBRTC_SHA256=7096abd6019bb083296324cd68861e864e4f7763eff6a69b1ef2aa80232ab65e
export SOLUTION_DIR=$(pwd)/Plugin~
export PLUGIN_DIR=$(pwd)/Runtime/Plugins/Android

BUILD_TYPE="${1:-release}"
if [ "$BUILD_TYPE" = "debug" ]; then
  CMAKE_BUILD_TYPE="Debug"
else
  CMAKE_BUILD_TYPE="Release"
fi

if [ -z "${ANDROID_NDK:-}" ] || [ ! -f "$ANDROID_NDK/source.properties" ]; then
  echo "Set ANDROID_NDK to the Android NDK root directory." >&2
  exit 1
fi

# Download LibWebRTC
curl -fL "$LIBWEBRTC_DOWNLOAD_URL" -o webrtc.zip || exit 1
echo "$LIBWEBRTC_SHA256  webrtc.zip" | sha256sum --check --strict || exit 1
unzip -o -d $SOLUTION_DIR/webrtc webrtc.zip
cp -f $SOLUTION_DIR/webrtc/lib/libwebrtc.aar $PLUGIN_DIR

# Chromium's clang and its Android compiler-rt builtins (a separate package)
CLANG_REVISION=$(sed -n 's/^CLANG_REVISION=//p' $SOLUTION_DIR/webrtc/VERSIONS)
export CHROMIUM_CLANG="${CHROMIUM_CLANG:-$SOLUTION_DIR/out/clang}"
if [ ! -f "$CHROMIUM_CLANG/clang-revision" ] || [ "$(cat "$CHROMIUM_CLANG/clang-revision")" != "$CLANG_REVISION" ]; then
  rm -rf "$CHROMIUM_CLANG" && mkdir -p "$CHROMIUM_CLANG"
  CLANG_URL=https://commondatastorage.googleapis.com/chromium-browser-clang/Linux_x64
  curl -fsSL "$CLANG_URL/clang-$CLANG_REVISION.tar.xz" | tar -xJ -C "$CHROMIUM_CLANG"
  curl -fsSL "$CLANG_URL/clang-android-runtime-library-$CLANG_REVISION.tar.xz" | tar -xJ -C "$CHROMIUM_CLANG"
  echo "$CLANG_REVISION" > "$CHROMIUM_CLANG/clang-revision"
fi

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
  if [ "$BUILD_TYPE" = "debug" ]; then
    mv libwebrtc.so jni/$ARCH_ABI
  else
    "$CHROMIUM_CLANG/bin/llvm-strip" --strip-unneeded -o jni/$ARCH_ABI/libwebrtc.so libwebrtc.so
    rm libwebrtc.so
  fi
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
