# Building libwebrtc

The native plugin links a static libwebrtc that this repository builds in GitHub Actions, one workflow per
platform: `.github/workflows/libwebrtc-<platform>.yml`. All of them build the same WebRTC branch
(`WEBRTC_BRANCH`, currently `8078` = M156) with the patches in `BuildScripts~/patches/m156/`, and with
**Chromium's own libc++** (`use_custom_libcxx=true`, the upstream default). The plugin is compiled against
the libc++ headers shipped in the package and gets the libc++ runtime from the library, so it must be built
with clang (clang-cl on Windows), ideally the exact Chromium clang listed in `VERSIONS`.

## Scripts

- `fetch.sh <branch> <target_os>`: checks out `branch-heads/<branch>` with `gclient` into `$RUNNER_TEMP/webrtc`.
- `fetch.ps1 <branch>`: the same on Windows (PowerShell 7), into `$env:WEBRTC_ROOT`.
- `build_<platform>.sh` (or `.ps1`): runs `gn gen` and the build, then writes the package directory.

## Package format

Every platform produces `webrtc-<platform>.zip` with this layout, which `Plugin~/cmake/FindWebRTC.cmake`
reads (`<cpu>` is `x64` or `arm64`):

| Path | Content |
|---|---|
| `include/` | every libwebrtc header and textual include (`*.h`, `*.inc`), plus the complete libc++ and libc++abi include directories: `third_party/libc++/src/include`, `third_party/libc++abi/src/include`, `buildtools/third_party/libc++` (`__config_site`, `__assertion_handler`) |
| `lib/x64/libwebrtc.a` | Linux |
| `lib/x64/webrtc.lib` | Windows (MSVC-compatible archive built by clang-cl) |
| `lib/libwebrtc.a` | macOS (universal: x86_64 + arm64) and iOS (arm64) |
| `lib/<cpu>/libwebrtc.a` | Android (`arm64`, `x64`), plus `lib/libwebrtc.aar` with the Java classes |
| `cxx_flags.txt` | flags for compiling against the bundled libc++: `-nostdinc++`, the three include directories as `-isystem ${WEBRTC_INCLUDE_DIR}/...`, and Chromium's `_LIBCPP_*`/`CR_*` defines. Windows (clang-cl syntax): `/external:I${WEBRTC_INCLUDE_DIR}/...` for the libc++ directories and `/D` defines; there is no `-nostdinc++`, because the MSVC include directory holds both the CRT and the MSVC STL, and the libc++ directories come first instead (as in Chromium) |
| `VERSIONS` | `WEBRTC_BRANCH`, `WEBRTC_COMMIT`, `LIBCXX_COMMIT`, `CLANG_REVISION`; on Windows also `MSVC_RUNTIME` (`/MT` or `/MD`, which the plugin must use too) and `WINDOWS_SDK` |
| `args.gn`, `gn_cflags_cc.txt` | the GN arguments and C++ flags of the build, for reference (Windows also has `gn_defines.txt`) |
| `system_libs.txt` | Windows: the system libraries (`ws2_32.lib`, ...) to link together with `webrtc.lib` |
| `LICENSE.md` | licenses of libwebrtc and its third-party code |

Each static library contains the libc++ and libc++abi objects (`llvm-ar` adds them after the build), so
consumers link with `-nostdlib++` and do not link a system C++ library. Windows uses the MSVC C++ ABI
(vcruntime) instead of libc++abi, so `webrtc.lib` contains only libc++ (added with `llvm-lib`).

The Windows build uses the runner's Visual Studio (`DEPOT_TOOLS_WIN_TOOLCHAIN=0`) and installs the Windows SDK
that `build/vs_toolchain.py` asks for (`SDK_VERSION`, 10.0.28000.0 for M156), since no runner image has it. A debug library (`libwebrtcd.a` /
`webrtcd.lib`) is optional; `FindWebRTC.cmake` falls back to the release library.

## Releases and logs

Started manually with **publish**, a workflow uploads its zip and `.sha256` to the pre-release
`libwebrtc-M<milestone>` (created by the first workflow that publishes). The build scripts in `BuildScripts~`
and the `native-<platform>.yml` workflows download from there and check the SHA-256.

Workflow logs on GitHub need a login to read. Every run therefore pushes its log tail and a description of
the package (`package.txt`) to the branch `ci-logs/libwebrtc-<platform>-<run id>`. These branches can be
deleted at any time.
