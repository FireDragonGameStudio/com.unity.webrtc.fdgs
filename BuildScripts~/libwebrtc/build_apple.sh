#!/bin/bash
# Builds libwebrtc for macOS (universal arm64 + x86_64) or iOS (arm64 device) with Chromium's libc++ and
# writes the package to <package dir>.
# Usage: build_apple.sh <webrtc root (contains src and depot_tools)> <package dir> <mac|ios>

set -euo pipefail

root="$1"
package="$2"
platform="$3"
export PATH="$root/depot_tools:$PATH"
cd "$root/src"

case "$platform" in
  mac)
    cpus="arm64 x64"
    # Unity 6 supports macOS 11 and later; Chromium defaults to 13.0.
    os_args='target_os="mac" mac_deployment_target="11.0" mac_min_system_version="11.0"'
    sdk=macosx
    min_version=-mmacosx-version-min=11.0
    frameworks="AppKit ApplicationServices AudioToolbox AVFoundation CoreAudio CoreFoundation CoreGraphics CoreMedia
      CoreServices CoreVideo Foundation IOKit IOSurface Metal MetalKit OpenGL QuartzCore ScreenCaptureKit Security
      SystemConfiguration VideoToolbox"
    ;;
  ios)
    cpus="arm64"
    # Unity 6 supports iOS 13 and later; Chromium defaults to 18.0. Device build only.
    os_args='target_os="ios" ios_deployment_target="13.0" target_environment="device" ios_enable_code_signing=false'
    sdk=iphoneos
    min_version=-miphoneos-version-min=13.0
    frameworks="AudioToolbox AVFoundation CoreAudio CoreFoundation CoreGraphics CoreMedia CoreTelephony CoreVideo
      Foundation GLKit IOSurface Metal MetalKit Network OpenGLES QuartzCore Security SystemConfiguration UIKit
      VideoToolbox"
    ;;
  *) echo "Unknown platform $platform"; exit 1 ;;
esac

ar="third_party/llvm-build/Release+Asserts/bin/llvm-ar"
mkdir -p "$package/lib"
libs=()
for cpu in $cpus; do
  out="out/Release-$cpu"
  gn gen "$out" --args="
    $os_args
    target_cpu=\"$cpu\"
    is_debug=false
    is_component_build=false
    symbol_level=0
    treat_warnings_as_errors=false
    rtc_include_tests=false
    rtc_build_examples=false
    rtc_use_h264=false
    use_rtti=true
    use_custom_libcxx=true
    use_clang_modules=false
    rtc_rust=false
  "
  test -f "$out/args.gn" || { echo "gn gen did not create $out"; exit 1; }

  # libc++ and libc++abi are source sets that executables link implicitly; build them explicitly so their
  # objects can be added to the static library.
  libcxx_targets=$(gn ls "$out" | grep -E '^//buildtools/third_party/libc\+\+(abi)?:libc\+\+(abi)?$' | sed 's#^//##' || true)
  echo "libc++ targets: $libcxx_targets"
  test -n "$libcxx_targets" || { echo "No libc++ targets found:"; gn ls "$out" | grep -i 'libc++' | head -20; exit 1; }
  autoninja -C "$out" webrtc $libcxx_targets

  lib="$root/libwebrtc-$cpu.a"
  cp "$out/obj/libwebrtc.a" "$lib"
  libcxx_objects=$(find "$out/obj/buildtools/third_party/libc++" "$out/obj/buildtools/third_party/libc++abi" -name '*.o' | sort)
  echo "Adding $(echo "$libcxx_objects" | wc -l) libc++/libc++abi objects to $cpu"
  test -n "$libcxx_objects" || { echo "No libc++ objects found"; exit 1; }
  # Append with "q", not "r": "r" replaces members with the same name, and libc++'s random.o, vector.o or
  # algorithm.o would overwrite libwebrtc's (rtc_base, libaom, BoringSSL) objects of the same name.
  "$ar" q "$lib" $libcxx_objects
  "$ar" s "$lib"
  size=$(stat -f %z "$lib")
  test "$size" -gt 30000000 || { echo "libwebrtc.a ($cpu) is only $size bytes"; exit 1; }

  # Every symbol used inside libwebrtc.a must be defined in it or in the system libraries and frameworks:
  # link all of it into a dynamic library without the system C++ library and refuse unresolved symbols.
  arch=$([ "$cpu" = x64 ] && echo x86_64 || echo "$cpu")
  framework_flags=$(for f in $frameworks; do printf -- '-framework %s ' "$f"; done)
  xcrun --sdk "$sdk" clang -dynamiclib -arch "$arch" "$min_version" -o "$out/libwebrtc_link_check.dylib"     -Wl,-all_load "$lib" -nostdlib++ -lobjc $framework_flags -Wl,-undefined,error
  echo "Link check passed: libwebrtc.a ($arch) has no unresolved symbols"
  libs+=("$lib")
done
# The first build (arm64) describes the package.
out="out/Release-arm64"

if [ "${#libs[@]}" -gt 1 ]; then
  lipo -create -output "$package/lib/libwebrtc.a" "${libs[@]}"
else
  cp "${libs[0]}" "$package/lib/libwebrtc.a"
fi
lipo -info "$package/lib/libwebrtc.a"

# Headers: every libwebrtc header and .inc file (including the ObjC SDK in sdk/objc; abseil's int128.h
# includes an .inc), plus the complete libc++ and libc++abi include directories (libc++ headers such as
# <vector> have no extension).
find . \( -name '*.h' -o -name '*.inc' \) -not -path './out/*' -not -path './third_party/llvm-build/*' | cpio -pdm --quiet "$package/include"
for dir in third_party/libc++/src/include third_party/libc++abi/src/include buildtools/third_party/libc++; do
  mkdir -p "$package/include/$dir"
  cp -R "$dir/." "$package/include/$dir/"
done
find "$package/include/buildtools/third_party/libc++" -name '*.gn' -delete

# Compiler flags for code that uses this package. ${WEBRTC_INCLUDE_DIR} is replaced by the consumer.
defines=$(gn desc "$out" //api:rtc_error defines | grep -E '^[[:space:]]*(_LIBCPP|_LIBCXXABI|CR_|WEBRTC_|RTC_|ABSL_)' | sed -E 's/^[[:space:]]*/-D/' | tr '\n' ' ' || true)
cat > "$package/cxx_flags.txt" <<FLAGS
-nostdinc++ -isystem \${WEBRTC_INCLUDE_DIR}/buildtools/third_party/libc++ -isystem \${WEBRTC_INCLUDE_DIR}/third_party/libc++/src/include -isystem \${WEBRTC_INCLUDE_DIR}/third_party/libc++abi/src/include $defines
FLAGS
gn desc "$out" //api:rtc_error cflags_cc > "$package/gn_cflags_cc.txt"
cp "$out/args.gn" "$package/args.gn"

cat > "$package/VERSIONS" <<VERSIONS
WEBRTC_BRANCH=branch-heads/${WEBRTC_BRANCH:-unknown}
WEBRTC_COMMIT=$(git rev-parse HEAD)
LIBCXX_COMMIT=$(git -C third_party/libc++/src rev-parse HEAD)
CLANG_REVISION=$(python3 tools/clang/scripts/update.py --print-revision)
XCODE=$(xcodebuild -version | tr '\n' ' ')
VERSIONS

python3 tools_webrtc/libs/generate_licenses.py --target :webrtc "$out" "$out"
cp "$out/LICENSE.md" "$package/LICENSE.md"

echo "Package:"
cat "$package/VERSIONS" "$package/cxx_flags.txt"
du -sh "$package/include" "$package/lib/libwebrtc.a"
for cpu in $cpus; do
  arch=$([ "$cpu" = x64 ] && echo x86_64 || echo "$cpu")
  count=$(nm -arch "$arch" -C "$package/lib/libwebrtc.a" 2>/dev/null | grep -c ' T std::__Cr::' || true)
  echo "$arch: $count defined std::__Cr text symbols"
  test "$count" -gt 100 || { echo "libwebrtc.a ($arch) does not contain libc++"; exit 1; }
done
