#!/bin/bash -eu

# Builds Runtime/Plugins/macOS/libwebrtc.dylib (arm64 + x86_64) against the libwebrtc M156 package with the
# Chromium clang listed in its VERSIONS (the plugin shares C++ standard library types with libwebrtc, which
# was built with Chromium's libc++). Needs Xcode (for the macOS SDK), cmake and ninja.
# Same steps as .github/workflows/native-macos.yml.

export LIBWEBRTC_DOWNLOAD_URL=https://github.com/FireDragonGameStudio/com.unity.webrtc.fdgs/releases/download/libwebrtc-M156/webrtc-mac.zip
export LIBWEBRTC_SHA256=c0bc1f73dda783ded2e6d7d3361c981f91130aa20649db2b0a97491b63ee5e74
export SOLUTION_DIR=$(pwd)/Plugin~
export DYLIB_FILE=$(pwd)/Runtime/Plugins/macOS/libwebrtc.dylib
export CLANG_DIR=$SOLUTION_DIR/out/clang

BUILD_TYPE="${1:-release}"
if [ "$BUILD_TYPE" = "debug" ]; then
  CMAKE_BUILD_TYPE="Debug"
else
  CMAKE_BUILD_TYPE="Release"
fi

# Install cmake and ninja (cmake is preinstalled on GitHub-hosted macOS runners)
export HOMEBREW_NO_AUTO_UPDATE=1
command -v cmake > /dev/null || brew install cmake
command -v ninja > /dev/null || brew install ninja

# Download LibWebRTC
curl -fL "$LIBWEBRTC_DOWNLOAD_URL" -o webrtc.zip
echo "$LIBWEBRTC_SHA256  webrtc.zip" | shasum -a 256 --check --strict
unzip -q -o -d "$SOLUTION_DIR/webrtc" webrtc.zip

# Install the Chromium clang that built libwebrtc
CLANG_REVISION=$(sed -n 's/^CLANG_REVISION=//p' "$SOLUTION_DIR/webrtc/VERSIONS")
case "$(uname -m)" in arm64) CLANG_HOST=Mac_arm64 ;; *) CLANG_HOST=Mac ;; esac
if [ "$(cat "$CLANG_DIR/REVISION" 2> /dev/null)" != "$CLANG_REVISION" ]; then
  rm -rf "$CLANG_DIR" && mkdir -p "$CLANG_DIR"
  curl -fL "https://commondatastorage.googleapis.com/chromium-browser-clang/$CLANG_HOST/clang-$CLANG_REVISION.tar.xz" \
    | tar -xJ -C "$CLANG_DIR"
  echo "$CLANG_REVISION" > "$CLANG_DIR/REVISION"
fi

# Remove old dylib file
rm -rf "$DYLIB_FILE"

# Build UnityRenderStreaming Plugin
cd "$SOLUTION_DIR"
cmake --preset=macos \
  -D CMAKE_C_COMPILER="$CLANG_DIR/bin/clang" \
  -D CMAKE_CXX_COMPILER="$CLANG_DIR/bin/clang++"
cmake --build out/build/macos --config "$CMAKE_BUILD_TYPE" --target WebRTCPlugin

# Keep the exported symbols only
if [ "$CMAKE_BUILD_TYPE" = "Release" ]; then
  strip -x "$DYLIB_FILE"
fi
lipo -info "$DYLIB_FILE"
