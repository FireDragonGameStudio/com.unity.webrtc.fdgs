#!/bin/bash -eu
# Builds libwebrtc for Linux x64 with Chromium's libc++ and writes the package to <package dir>.
# Usage: build_linux.sh <webrtc root (contains src and depot_tools)> <package dir>

root="$1"
package="$2"
export PATH="$root/depot_tools:$PATH"
export DEPOT_TOOLS_UPDATE=0
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
  use_rtti=true
  use_custom_libcxx=true
'

# libc++ and libc++abi are source sets that executables link implicitly; build them explicitly so their
# objects can be added to the static library.
libcxx_targets=$(gn ls "$out" | grep -E '^//buildtools/third_party/libc\+\+(abi)?:libc\+\+(abi)?$' | sed 's#^//##')
echo "libc++ targets: $libcxx_targets"
autoninja -C "$out" webrtc $libcxx_targets

ar="third_party/llvm-build/Release+Asserts/bin/llvm-ar"
mkdir -p "$package/lib/x64"
cp "$out/obj/libwebrtc.a" "$package/lib/x64/libwebrtc.a"
libcxx_objects=$(find "$out/obj/buildtools/third_party/libc++" "$out/obj/buildtools/third_party/libc++abi" -name '*.o' | sort)
echo "Adding $(echo "$libcxx_objects" | wc -l) libc++/libc++abi objects"
"$ar" rs "$package/lib/x64/libwebrtc.a" $libcxx_objects

# Headers: every libwebrtc header, plus the complete libc++ and libc++abi include directories
# (libc++ headers such as <vector> have no extension).
find . -name '*.h' -not -path './out/*' -not -path './third_party/llvm-build/*' | cpio -pdm --quiet "$package/include"
for dir in third_party/libc++/src/include third_party/libc++abi/src/include buildtools/third_party/libc++; do
  mkdir -p "$package/include/$dir"
  cp -R "$dir/." "$package/include/$dir/"
done
find "$package/include/buildtools/third_party/libc++" -name '*.gn' -delete

# Compiler flags for code that uses this package. ${WEBRTC_INCLUDE_DIR} is replaced by the consumer.
defines=$(gn desc "$out" //api:libjingle_peerconnection_api defines | grep -E '^\s*(_LIBCPP|_LIBCXXABI|CR_)' | sed 's/^\s*/-D/' | tr '\n' ' ')
cat > "$package/cxx_flags.txt" <<FLAGS
-nostdinc++ -isystem \${WEBRTC_INCLUDE_DIR}/buildtools/third_party/libc++ -isystem \${WEBRTC_INCLUDE_DIR}/third_party/libc++/src/include -isystem \${WEBRTC_INCLUDE_DIR}/third_party/libc++abi/src/include $defines
FLAGS
gn desc "$out" //api:libjingle_peerconnection_api cflags_cc > "$package/gn_cflags_cc.txt"
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
