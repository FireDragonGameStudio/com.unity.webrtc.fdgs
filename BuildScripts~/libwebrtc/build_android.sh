#!/bin/bash
# Builds libwebrtc for Android arm64-v8a and x86_64 with Chromium's libc++ and writes the package to
# <package dir>: a static libwebrtc.a per ABI and libwebrtc.aar with the Java classes for both ABIs.
# Usage: build_android.sh <webrtc root (contains src and depot_tools)> <package dir>
# Needs patches/m156/android/add_jni_zero_classes_to_libwebrtc_jar.patch, without which classes.jar lacks the
# JNI Zero classes (check_android_jar.py fails).

set -euo pipefail

root="$1"
package="$2"
script_dir=$(cd "$(dirname "$0")" && pwd)
export PATH="$root/depot_tools:$PATH"
cd "$root/src"

# Lowest Android API level the package supports: Unity's minimum (Editor/BuildProcessor.cs), which is also the
# lowest Chromium allows. The plugin must not be built for a lower level (CMAKE_ANDROID_API).
min_sdk=23

ar="third_party/llvm-build/Release+Asserts/bin/llvm-ar"
nm="third_party/llvm-build/Release+Asserts/bin/llvm-nm"
readelf="third_party/llvm-build/Release+Asserts/bin/llvm-readelf"
clang="third_party/llvm-build/Release+Asserts/bin/clang"
sysroot="third_party/android_toolchain/ndk/toolchains/llvm/prebuilt/linux-x86_64/sysroot"

# <gn cpu>:<Android ABI>. The out directories are named after the ABI.
abis="arm64:arm64-v8a x64:x86_64"
first_out=
# Set when a link check fails; the script still writes the package so the log shows everything.
link_check_failed=

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
    rtc_rust=false
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
  runtime_dirs=
  for dir in libc++ libc++abi libunwind; do
    if [ -d "$out/obj/buildtools/third_party/$dir" ]; then runtime_dirs="$runtime_dirs $out/obj/buildtools/third_party/$dir"; fi
  done
  runtime_objects=$(find $runtime_dirs -name '*.o' | sort)
  echo "Adding $(echo "$runtime_objects" | wc -l) objects from$runtime_dirs to $lib"
  test -n "$runtime_objects" || { echo "No libc++ objects found"; exit 1; }
  # Append with "q", not "r": "r" replaces members with the same name, and libc++'s random.o, vector.o or
  # algorithm.o would overwrite libwebrtc's (rtc_base, libaom, BoringSSL) objects of the same name.
  "$ar" q "$lib" $runtime_objects
  "$ar" s "$lib"

  size=$(stat -c %s "$lib")
  test "$size" -gt 50000000 || { echo "$lib is only $size bytes"; exit 1; }
  cxx_symbols=$("$nm" -C "$lib" 2>/dev/null | grep -c ' T std::__Cr::' || true)
  echo "$lib: $size bytes, $cxx_symbols defined std::__Cr text symbols"
  test "$cxx_symbols" -gt 100 || { echo "$lib does not contain libc++ (std::__Cr) symbols"; exit 1; }

  # Every symbol used inside libwebrtc.a must be defined in it or in the Android system libraries: link all of
  # it into a shared library without a C++ library or unwinder and refuse unresolved symbols.
  case "$cpu" in arm64) triple=aarch64-linux-android ;; x64) triple=x86_64-linux-android ;; esac
  # The system libraries are the "libs" GN collects for //:webrtc from all its dependencies, linked at the API
  # level of the build (GN's android_ndk_api_level), so a library newer than that fails here.
  gn desc "$out" //:webrtc libs > "$out/webrtc_libs.txt" || true
  echo "gn desc //:webrtc libs:"; cat "$out/webrtc_libs.txt"
  system_libs=$(grep -E '^\s*[A-Za-z0-9_+.-]+\s*$' "$out/webrtc_libs.txt" | sed -E 's/^\s*/-l/; s/\s*$//' | sort -u | tr '\n' ' ' || true)
  echo "$system_libs" | grep -q -- '-lOpenSLES' || { echo "Expected -lOpenSLES in the GN libs of //:webrtc"; exit 1; }
  api_level=$(gn args "$out" --list=android_ndk_api_level --short | sed 's/.*= *//')
  echo "System libraries ($abi, API $api_level): $system_libs"
  if "$clang" --target="$triple$api_level" --sysroot="$sysroot" -shared -fuse-ld=lld --unwindlib=none \
      -o "$out/libwebrtc_link_check.so" -Wl,--whole-archive "$lib" -Wl,--no-whole-archive \
      -nostdlib++ -Wl,--no-undefined $system_libs -lm -ldl; then
    echo "Link check passed: $lib has no unresolved symbols"
  else
    echo "Link check failed: $lib"
    link_check_failed="$link_check_failed $cpu"
  fi

  # The Java classes call the natives of libwebrtc.a through J.N (JNI Zero hashed names, Java_J_N_M...).
  "$nm" --defined-only -j "$lib" > "$out/libwebrtc_symbols.txt"
  python3 "$script_dir/check_android_jar.py" --registration-srcjar "$out/gen/sdk/android/libwebrtc_jni_registration.srcjar" \
    "$out/lib.java/sdk/android/libwebrtc.jar" "$out/libwebrtc_symbols.txt"

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
# classes.jar must be complete (JNI Zero classes), match libwebrtc.a of both ABIs and target Java 17 (Unity 6).
unzip -p "$package/lib/libwebrtc.aar" classes.jar > "$root/classes.jar"
symbol_files=
for pair in $abis; do symbol_files="$symbol_files out/android/${pair##*:}/libwebrtc_symbols.txt"; done
python3 "$script_dir/check_android_jar.py" --registration-srcjar "$first_out/gen/sdk/android/libwebrtc_jni_registration.srcjar" \
  "$root/classes.jar" $symbol_files

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
defines=$(gn desc "$first_out" //api:rtc_error defines | grep -E '^\s*(_LIBCPP|_LIBCXXABI|CR_|WEBRTC_|RTC_|ABSL_)' | sed 's/^\s*/-D/' | tr '\n' ' ' || true)
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
ANDROID_NDK_VERSION=$(grep -oE "'android_ndk_version': Str\('[^']+" DEPS | sed "s/.*('//; s/^[0-9]*@//")
ANDROID_MIN_SDK=$api_level
ANDROID_SYSTEM_LIBS=$system_libs
VERSIONS

python3 tools_webrtc/libs/generate_licenses.py --target :webrtc "$first_out" "$first_out"
cp "$first_out/LICENSE.md" "$package/LICENSE.md"

echo "Package:"
cat "$package/VERSIONS" "$package/cxx_flags.txt"
du -sh "$package/include" "$package"/lib/*/libwebrtc.a "$package/lib/libwebrtc.aar"

if [ -n "$link_check_failed" ]; then echo "Link check failed for:$link_check_failed"; exit 1; fi
