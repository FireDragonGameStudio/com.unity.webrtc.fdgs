#!/bin/bash
# Builds libwebrtc for Linux x64 with Chromium's libc++ and writes the package to <package dir>.
# Usage: build_linux.sh <webrtc root (contains src and depot_tools)> <package dir>

set -euo pipefail

root="$1"
package="$2"
export PATH="$root/depot_tools:$PATH"
cd "$root/src"

out=out/Release-x64
gn gen "$out" --args='
  target_os="linux"
  target_cpu="x64"
  is_debug=false
  is_component_build=false
  symbol_level=0
  treat_warnings_as_errors=false
  rtc_include_tests=false
  rtc_build_examples=false
  rtc_use_h264=false
  rtc_use_x11=false
  rtc_use_pipewire=false
  use_rtti=true
  use_custom_libcxx=true
  rtc_rust=false
'
test -f "$out/args.gn" || { echo "gn gen did not create $out"; exit 1; }

# libc++ and libc++abi are source sets that executables link implicitly; build them explicitly so their
# objects can be added to the static library.
libcxx_targets=$(gn ls "$out" | grep -E '^//buildtools/third_party/libc\+\+(abi)?:libc\+\+(abi)?$' | sed 's#^//##' || true)
echo "libc++ targets: $libcxx_targets"
test -n "$libcxx_targets" || { echo "No libc++ targets found:"; gn ls "$out" | grep -i 'libc++' | head -20; exit 1; }
autoninja -C "$out" webrtc $libcxx_targets

ar="third_party/llvm-build/Release+Asserts/bin/llvm-ar"
mkdir -p "$package/lib/x64"
cp "$out/obj/libwebrtc.a" "$package/lib/x64/libwebrtc.a"
libcxx_objects=$(find "$out/obj/buildtools/third_party/libc++" "$out/obj/buildtools/third_party/libc++abi" -name '*.o' | sort)
echo "Adding $(echo "$libcxx_objects" | wc -l) libc++/libc++abi objects"
test -n "$libcxx_objects" || { echo "No libc++ objects found"; exit 1; }
# Append with "q", not "r": "r" replaces members with the same name, and libc++'s random.o, vector.o or
# algorithm.o would overwrite libwebrtc's (rtc_base, libaom, BoringSSL) objects of the same name.
"$ar" q "$package/lib/x64/libwebrtc.a" $libcxx_objects
"$ar" s "$package/lib/x64/libwebrtc.a"
size=$(stat -c %s "$package/lib/x64/libwebrtc.a")
test "$size" -gt 50000000 || { echo "libwebrtc.a is only $size bytes"; exit 1; }

# Every symbol used inside libwebrtc.a must be defined in it or in the system C libraries: link all of it
# into a shared library without the system C++ library and refuse unresolved symbols.
clang="third_party/llvm-build/Release+Asserts/bin/clang"
"$clang" -shared -fuse-ld=lld -o "$out/libwebrtc_link_check.so" \
  -Wl,--whole-archive "$package/lib/x64/libwebrtc.a" -Wl,--no-whole-archive \
  -nostdlib++ -Wl,--no-undefined -Wl,--error-limit=0 -lm -ldl -lpthread -lrt
echo "Link check passed: libwebrtc.a has no unresolved symbols"

# Headers: every libwebrtc header and textual include (*.inc, e.g. abseil's int128_have_intrinsic.inc), plus the
# complete libc++ and libc++abi include directories (libc++ headers such as <vector> have no extension).
find . \( -name '*.h' -o -name '*.inc' \) -not -path './out/*' -not -path './third_party/llvm-build/*' | cpio -pdm --quiet "$package/include"
for dir in third_party/libc++/src/include third_party/libc++abi/src/include buildtools/third_party/libc++; do
  mkdir -p "$package/include/$dir"
  cp -R "$dir/." "$package/include/$dir/"
done
find "$package/include/buildtools/third_party/libc++" -name '*.gn' -delete

# Compiler flags for code that uses this package. ${WEBRTC_INCLUDE_DIR} is replaced by the consumer.
# The defines are libc++'s and libwebrtc's own configuration (e.g. WEBRTC_WITHOUT_RUST, RTC_ENABLE_VP9), so code
# that includes the headers sees the same declarations as the library.
defines=$(gn desc "$out" //api:rtc_error defines | grep -E '^\s*(_LIBCPP|_LIBCXXABI|CR_|WEBRTC_|RTC_|ABSL_)' | sed 's/^\s*/-D/' | tr '\n' ' ' || true)
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
VERSIONS

python3 tools_webrtc/libs/generate_licenses.py --target :webrtc "$out" "$out"
cp "$out/LICENSE.md" "$package/LICENSE.md"

echo "Package:"
cat "$package/VERSIONS" "$package/cxx_flags.txt"
du -sh "$package/include" "$package/lib/x64/libwebrtc.a"
