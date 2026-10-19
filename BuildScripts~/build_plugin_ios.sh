#!/bin/bash -eu

# Builds Runtime/Plugins/iOS/webrtc.framework (arm64 devices) against the libwebrtc M156 package with the
# Chromium clang listed in its VERSIONS (the plugin shares C++ standard library types with libwebrtc, which
# was built with Chromium's libc++). Needs Xcode (for the iPhoneOS SDK), cmake and ninja.
# Same steps as .github/workflows/native-ios.yml.

export LIBWEBRTC_DOWNLOAD_URL=https://github.com/FireDragonGameStudio/com.unity.webrtc.fdgs/releases/download/libwebrtc-M156/webrtc-ios.zip
export LIBWEBRTC_SHA256=78e4a68e0d7226a74e4dc84ad00cb66c1408a1e48361002a8c08cdae5498f811
export SOLUTION_DIR=$(pwd)/Plugin~
export WEBRTC_FRAMEWORK=$(pwd)/Runtime/Plugins/iOS/webrtc.framework
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

# Download webrtc
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

# Build webrtc Unity plugin for iOS devices (arm64, set by the preset); Unity only ships the device framework.
# The framework is written to Runtime/Plugins/iOS directly. It is not signed here; Xcode signs it when it is
# embedded into the Unity iOS app.
rm -rf "$WEBRTC_FRAMEWORK"
cd "$SOLUTION_DIR"
cmake --preset=ios \
  -D CMAKE_C_COMPILER="$CLANG_DIR/bin/clang" \
  -D CMAKE_CXX_COMPILER="$CLANG_DIR/bin/clang++"
cmake --build out/build/ios --config "$CMAKE_BUILD_TYPE" --target WebRTCPlugin

# Keep the exported symbols only
if [ "$CMAKE_BUILD_TYPE" = "Release" ]; then
  strip -x "$WEBRTC_FRAMEWORK/webrtc"
fi
lipo -info "$WEBRTC_FRAMEWORK/webrtc"
