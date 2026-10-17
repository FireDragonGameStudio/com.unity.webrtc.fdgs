#!/bin/bash -eu

export LIBWEBRTC_DOWNLOAD_URL=https://github.com/FireDragonGameStudio/com.unity.webrtc.fdgs/releases/download/libwebrtc-M116/webrtc-ios.zip
export LIBWEBRTC_SHA256=1a7001ad093a9ae9ed8ab85d15b021f5fae2a00f5377359b03264232ff739409
export SOLUTION_DIR=$(pwd)/Plugin~
export WEBRTC_FRAMEWORK_DIR=$(pwd)/Runtime/Plugins/iOS
export BUILD_DIR=out/build/ios
export WEBRTC_ARCHIVE_DIR=$BUILD_DIR/webrtc.xcarchive

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

# Download webrtc
curl -fL "$LIBWEBRTC_DOWNLOAD_URL" -o webrtc.zip || exit 1
echo "$LIBWEBRTC_SHA256  webrtc.zip" | shasum -a 256 --check || exit 1
unzip -o -d $SOLUTION_DIR/webrtc webrtc.zip

# Build webrtc Unity plugin for iOS devices (arm64). The prebuilt libwebrtc.a also contains an x86_64
# simulator slice, but Unity only ships the device framework.
cd "$SOLUTION_DIR"
cmake --preset=ios \
  -D CMAKE_OSX_ARCHITECTURES=arm64 \
  -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE

# The framework is not signed here; Xcode signs it when it is embedded into the Unity iOS app.
XCODEBUILD_FLAGS=(
  -sdk iphoneos
  -arch arm64
  -project "$BUILD_DIR/webrtc.xcodeproj"
  -configuration $CMAKE_BUILD_TYPE
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
)

# Build the static library first: the archive links WebRTCPlugin against it from the regular build folder.
xcodebuild "${XCODEBUILD_FLAGS[@]}" -target WebRTCLib

xcodebuild archive "${XCODEBUILD_FLAGS[@]}" \
  -scheme WebRTCPlugin \
  -archivePath "$WEBRTC_ARCHIVE_DIR"

rm -rf "$WEBRTC_FRAMEWORK_DIR/webrtc.framework"
cp -r "$WEBRTC_ARCHIVE_DIR/Products/@rpath/webrtc.framework" "$WEBRTC_FRAMEWORK_DIR/webrtc.framework"
