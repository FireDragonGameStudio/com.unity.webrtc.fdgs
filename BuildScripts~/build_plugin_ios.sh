#!/bin/bash -eu

export LIBWEBRTC_DOWNLOAD_URL=https://github.com/FireDragonGameStudio/com.unity.webrtc.fdgs/releases/download/libwebrtc-M116/webrtc-ios.zip
export LIBWEBRTC_SHA256=1a7001ad093a9ae9ed8ab85d15b021f5fae2a00f5377359b03264232ff739409
export SOLUTION_DIR=$(pwd)/Plugin~
export WEBRTC_FRAMEWORK_DIR=$(pwd)/Runtime/Plugins/iOS
export WEBRTC_ARCHIVE_DIR=build/webrtc.xcarchive
export WEBRTC_SIM_ARCHIVE_DIR=build/webrtc-sim.xcarchive

BUILD_TYPE="${1:-release}"
if [ "$BUILD_TYPE" = "debug" ]; then
  CMAKE_BUILD_TYPE="Debug"
else
  CMAKE_BUILD_TYPE="Release"
fi

# Install cmake
export HOMEBREW_NO_AUTO_UPDATE=1
brew install cmake

# Download webrtc 
curl -fL "$LIBWEBRTC_DOWNLOAD_URL" -o webrtc.zip || exit 1
echo "$LIBWEBRTC_SHA256  webrtc.zip" | shasum -a 256 --check || exit 1
unzip -d $SOLUTION_DIR/webrtc webrtc.zip 

# Build webrtc Unity plugin 
cd "$SOLUTION_DIR"
cmake . \
  -G Xcode \
  -D CMAKE_SYSTEM_NAME=iOS \
  -D "CMAKE_OSX_ARCHITECTURES=arm64;x86_64" \
  -D CMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH=NO \
  -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE \
  -B build

xcodebuild \
  -sdk iphonesimulator \
  -arch 'x86_64' \
  -project build/webrtc.xcodeproj \
  -target WebRTCLib \
  -configuration Release

xcodebuild archive \
  -sdk iphonesimulator \
  -arch 'x86_64' \
  -scheme WebRTCPlugin \
  -project build/webrtc.xcodeproj \
  -configuration Release \
  -archivePath "$WEBRTC_SIM_ARCHIVE_DIR"

xcodebuild \
  -sdk iphoneos \
  -project build/webrtc.xcodeproj \
  -target WebRTCLib \
  -configuration Release

xcodebuild archive \
  -sdk iphoneos \
  -scheme WebRTCPlugin \
  -project build/webrtc.xcodeproj \
  -configuration Release \
  -archivePath "$WEBRTC_ARCHIVE_DIR"

rm -rf "$WEBRTC_FRAMEWORK_DIR/webrtc.framework"
cp -r "$WEBRTC_ARCHIVE_DIR/Products/@rpath/webrtc.framework" "$WEBRTC_FRAMEWORK_DIR/webrtc.framework"

# todo(kazuki): The command below combines two libraries for supporting iOS and iOS simulator.
# But currently this is commented out because the combined binary adds a troublesome task to developer 
# when building iOS app on XCode. We need to support it using XCFramework or another way.
# 
# lipo -create -o "$WEBRTC_FRAMEWORK_DIR/webrtc.framework/webrtc" \
#   "$WEBRTC_ARCHIVE_DIR/Products/@rpath/webrtc.framework/webrtc" \
#   "$WEBRTC_SIM_ARCHIVE_DIR/Products/@rpath/webrtc.framework/webrtc"