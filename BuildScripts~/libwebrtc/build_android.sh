#!/bin/bash
# Builds libwebrtc for Android arm64-v8a and x86_64 with Chromium's libc++ and writes the package to
# <package dir>: a static libwebrtc.a per ABI and libwebrtc.aar with the Java classes for both ABIs.
# Usage: build_android.sh <webrtc root (contains src and depot_tools)> <package dir>

set -euo pipefail

root="$1"
package="$2"
export PATH="$root/depot_tools:$PATH"
cd "$root/src"

# Lowest Android API level the package supports; the plugin is built with the same level (CMAKE_ANDROID_API).
min_sdk=24

ar="third_party/llvm-build/Release+Asserts/bin/llvm-ar"
nm="third_party/llvm-build/Release+Asserts/bin/llvm-nm"
readelf="third_party/llvm-build/Release+Asserts/bin/llvm-readelf"

# <gn cpu>:<Android ABI>. The out directories are named after the ABI.
abis="arm64:arm64-v8a x64:x86_64"
first_out=

for pair in $abis; do
  cpu="${pair%%:*}"
  abi="${pair##*:}"
  out="out/android/$abi"
  first_out="${first_out:-$out}"

  gn gen "$out" --args="
    target_os=\"android\"
    target_cpu=\"$cpu\"
    is_debug=false
    is_java_debug=false
    is_component_build=false
    symbol_level=0
    treat_warnings_as_errors=false
    android_static_analysis=\"off\"
    default_min_sdk_version=$min_sdk
    rtc_include_tests=false
    rtc_build_examples=false
    rtc_use_h264=false
    use_rtti=true
    use_custom_libcxx=true
  "
  test -f "$out/args.gn" || { echo "gn gen did not create $out"; exit 1; }

  # libc++, libc++abi and libunwind are source sets that executables link implicitly; build them explicitly
  # so their objects can be added to the static library.
  runtime_targets=$(gn ls "$out" | grep -E '^//buildtools/third_party/(libc\+\+(abi)?:libc\+\+(abi)?|libunwind:libunwind)$' | sed 's#^//##' || true)
  echo "C++ runtime targets ($abi): $runtime_targets"
  echo "$runtime_targets" | grep -q 'libc++abi' || { echo "No libc++ targets found:"; gn ls "$out" | grep -i -E 'libc\+\+|unwind' | head -20; exit 1; }
  # sdk/android:libwebrtc is the Java library, libjingle_peerconnection_so the JNI library of the AAR.
  autoninja -C "$out" webrtc $runtime_targets sdk/android:libwebrtc sdk/android:libjingle_peerconnection_so

  lib="$package/lib/$cpu/libwebrtc.a"
  mkdir -p "$(dirname "$lib")"
  cp "$out/obj/libwebrtc.a" "$lib"
  runtime_objects=$(find "$out/obj/buildtools/third_party/libc++" "$out/obj/buildtools/third_party/libc++abi" \
    "$out/obj/buildtools/third_party/libunwind" -name '*.o' 2>/dev/null | sort)
  echo "Adding $(echo "$runtime_objects" | wc -l) libc++/libc++abi/libunwind objects to $lib"
  test -n "$runtime_objects" || { echo "No libc++ objects found"; exit 1; }
  "$ar" rs "$lib" $runtime_objects

  size=$(stat -c %s "$lib")
  test "$size" -gt 50000000 || { echo "$lib is only $size bytes"; exit 1; }
  cxx_symbols=$("$nm" -C "$lib" 2>/dev/null | grep -c ' T std::__Cr::' || true)
  echo "$lib: $size bytes, $cxx_symbols defined std::__Cr text symbols"
  test "$cxx_symbols" -gt 100 || { echo "$lib does not contain libc++ (std::__Cr) symbols"; exit 1; }

  # Chromium links Android 64-bit shared libraries with 16 KB pages by default (build/config/android/BUILD.gn).
  "$readelf" -lW "$out/libjingle_peerconnection_so.so" | awk '$1 == "LOAD" { print "LOAD align " $NF; if ($NF != "0x4000") bad = 1 } END { exit bad }' \
    || { echo "libjingle_peerconnection_so.so ($abi) is not 16 KB aligned"; exit 1; }
done

# The AAR, assembled like tools_webrtc/android/build_aar.py does but from the builds above.
aar_dir=$(mktemp -d)
cp sdk/android/AndroidManifest.xml "$aar_dir/AndroidManifest.xml"
cp "$first_out/lib.java/sdk/android/libwebrtc.jar" "$aar_dir/classes.jar"
for pair in $abis; do
  abi="${pair##*:}"
  mkdir -p "$aar_dir/jni/$abi"
  cp "out/android/$abi/libjingle_peerconnection_so.so" "$aar_dir/jni/$abi/"
done
(cd "$aar_dir" && zip -qr "$package/lib/libwebrtc.aar" .)
rm -rf "$aar_dir"
unzip -l "$package/lib/libwebrtc.aar"
for entry in classes.jar AndroidManifest.xml jni/arm64-v8a/libjingle_peerconnection_so.so jni/x86_64/libjingle_peerconnection_so.so; do
  unzip -l "$package/lib/libwebrtc.aar" "$entry" > /dev/null || { echo "libwebrtc.aar has no $entry"; exit 1; }
done
# Unity 6 builds with JDK 17, which reads class files up to version 61.
unzip -p "$package/lib/libwebrtc.aar" classes.jar > "$root/classes.jar"
class_file=$(unzip -Z1 "$root/classes.jar" | awk '/^org\/webrtc\/.*\.class$/ && !found { print; found = 1 }')
class_version=$(unzip -p "$root/classes.jar" "$class_file" | od -An -j6 -N2 -tu1 | awk '{ print $1 * 256 + $2 }')
echo "$class_file"
echo "classes.jar class file version: $class_version"
test "$class_version" -le 61 || { echo "classes.jar targets class file version $class_version, newer than Java 17"; exit 1; }

# Headers: every libwebrtc header (and .inc file, e.g. abseil int128), plus the complete libc++ and libc++abi include directories
# (libc++ headers such as <vector> have no extension).
find . \( -name '*.h' -o -name '*.inc' \) -not -path './out/*' -not -path './third_party/llvm-build/*' \
  -not -path './third_party/android_sdk/*' -not -path './third_party/android_toolchain/*' \
  -not -path './third_party/jdk/*' | cpio -pdm --quiet "$package/include"
for dir in third_party/libc++/src/include third_party/libc++abi/src/include buildtools/third_party/libc++; do
  mkdir -p "$package/include/$dir"
  cp -R "$dir/." "$package/include/$dir/"
done
find "$package/include/buildtools/third_party/libc++" -name '*.gn' -delete

# Compiler flags for code that uses this package. ${WEBRTC_INCLUDE_DIR} is replaced by the consumer.
defines=$(gn desc "$first_out" //api:rtc_error defines | grep -E '^\s*(_LIBCPP|_LIBCXXABI|CR_)' | sed 's/^\s*/-D/' | tr '\n' ' ' || true)
cat > "$package/cxx_flags.txt" <<FLAGS
-nostdinc++ -isystem \${WEBRTC_INCLUDE_DIR}/buildtools/third_party/libc++ -isystem \${WEBRTC_INCLUDE_DIR}/third_party/libc++/src/include -isystem \${WEBRTC_INCLUDE_DIR}/third_party/libc++abi/src/include $defines
FLAGS
gn desc "$first_out" //api:rtc_error cflags_cc > "$package/gn_cflags_cc.txt"
# args.gn of the arm64 build; the x64 build differs only in target_cpu.
cp "$first_out/args.gn" "$package/args.gn"

cat > "$package/VERSIONS" <<VERSIONS
WEBRTC_BRANCH=branch-heads/${WEBRTC_BRANCH:-unknown}
WEBRTC_COMMIT=$(git rev-parse HEAD)
LIBCXX_COMMIT=$(git -C third_party/libc++/src rev-parse HEAD)
CLANG_REVISION=$(python3 tools/clang/scripts/update.py --print-revision)
ANDROID_NDK_VERSION=$(grep -E '^Pkg.Revision' third_party/android_toolchain/ndk/source.properties | sed 's/.*= *//')
ANDROID_MIN_SDK=$min_sdk
VERSIONS

python3 tools_webrtc/libs/generate_licenses.py --target :webrtc "$first_out" "$first_out"
cp "$first_out/LICENSE.md" "$package/LICENSE.md"

echo "Package:"
cat "$package/VERSIONS" "$package/cxx_flags.txt"
du -sh "$package/include" "$package"/lib/*/libwebrtc.a "$package/lib/libwebrtc.aar"
