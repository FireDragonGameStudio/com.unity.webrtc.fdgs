# Builds the plugin for Android with Chromium's clang instead of the NDK's.
#
# libwebrtc M156 is built with Chromium's libc++ (std::__Cr), whose headers need a newer clang than the NDK
# has, so the plugin is compiled with the clang that built libwebrtc (CLANG_REVISION in webrtc/VERSIONS)
# against the NDK's sysroot. Chromium ships the Android compiler-rt builtins in a separate package
# (clang-android-runtime-library-<revision>.tar.xz), which must be unpacked into the same directory.
#
# Inputs (cache variables or environment variables):
#   CHROMIUM_CLANG          root of Chromium's clang (contains bin/clang)
#   ANDROID_NDK             root of the Android NDK (ANDROID_NDK_VERSION in webrtc/VERSIONS)
#   CMAKE_ANDROID_ARCH_ABI  arm64-v8a or x86_64
#   ANDROID_PLATFORM        minimum API level, default 24: the OpenGL ES path calls glCopyImageSubData
#                           (OpenGL ES 3.2, API 24). libwebrtc itself supports ANDROID_MIN_SDK in webrtc/VERSIONS.

# CMake's own Android support always uses the NDK's compiler. CMAKE_SYSTEM_VERSION 1 turns it off, like the
# NDK's legacy toolchain file does; this file sets the compiler, target and sysroot itself.
set(CMAKE_SYSTEM_NAME Android)
set(CMAKE_SYSTEM_VERSION 1)

foreach(_var CHROMIUM_CLANG ANDROID_NDK)
  if(NOT ${_var} AND DEFINED ENV{${_var}})
    file(TO_CMAKE_PATH "$ENV{${_var}}" ${_var})
  endif()
  if(NOT ${_var})
    message(FATAL_ERROR "Set ${_var} (cache or environment variable).")
  endif()
  set(${_var} "${${_var}}" CACHE PATH "" FORCE)
endforeach()
if(NOT ANDROID_PLATFORM)
  set(ANDROID_PLATFORM 24)
endif()
set(ANDROID_PLATFORM "${ANDROID_PLATFORM}" CACHE STRING "Minimum Android API level" FORCE)

# Try-compile projects need these too.
list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES CHROMIUM_CLANG ANDROID_NDK ANDROID_PLATFORM
     CMAKE_ANDROID_ARCH_ABI)

if(CMAKE_ANDROID_ARCH_ABI STREQUAL "arm64-v8a")
  set(CMAKE_SYSTEM_PROCESSOR aarch64)
elseif(CMAKE_ANDROID_ARCH_ABI STREQUAL "x86_64")
  set(CMAKE_SYSTEM_PROCESSOR x86_64)
else()
  message(FATAL_ERROR "Unsupported CMAKE_ANDROID_ARCH_ABI: '${CMAKE_ANDROID_ARCH_ABI}'")
endif()
set(_triple "${CMAKE_SYSTEM_PROCESSOR}-linux-android${ANDROID_PLATFORM}")

if(CMAKE_HOST_WIN32)
  set(_exe ".exe")
endif()
set(CMAKE_C_COMPILER "${CHROMIUM_CLANG}/bin/clang${_exe}")
set(CMAKE_CXX_COMPILER "${CHROMIUM_CLANG}/bin/clang++${_exe}")
set(CMAKE_ASM_COMPILER "${CHROMIUM_CLANG}/bin/clang${_exe}")
set(CMAKE_C_COMPILER_TARGET ${_triple})
set(CMAKE_CXX_COMPILER_TARGET ${_triple})
set(CMAKE_ASM_COMPILER_TARGET ${_triple})
set(CMAKE_AR "${CHROMIUM_CLANG}/bin/llvm-ar${_exe}" CACHE FILEPATH "")
set(CMAKE_NM "${CHROMIUM_CLANG}/bin/llvm-nm${_exe}" CACHE FILEPATH "")
set(CMAKE_STRIP "${CHROMIUM_CLANG}/bin/llvm-strip${_exe}" CACHE FILEPATH "")
set(CMAKE_OBJCOPY "${CHROMIUM_CLANG}/bin/llvm-objcopy${_exe}" CACHE FILEPATH "")
set(CMAKE_READELF "${CHROMIUM_CLANG}/bin/llvm-readelf${_exe}" CACHE FILEPATH "")
# Chromium's clang package has no llvm-ranlib; "llvm-ar s" does the same.
set(CMAKE_C_ARCHIVE_FINISH "<CMAKE_AR> s <TARGET>")
set(CMAKE_CXX_ARCHIVE_FINISH "<CMAKE_AR> s <TARGET>")

if(CMAKE_HOST_APPLE)
  set(_ndk_host darwin-x86_64)
elseif(CMAKE_HOST_WIN32)
  set(_ndk_host windows-x86_64)
else()
  set(_ndk_host linux-x86_64)
endif()
set(CMAKE_SYSROOT "${ANDROID_NDK}/toolchains/llvm/prebuilt/${_ndk_host}/sysroot")
set(CMAKE_RANLIB "${ANDROID_NDK}/toolchains/llvm/prebuilt/${_ndk_host}/bin/llvm-ranlib${_exe}" CACHE FILEPATH "")
if(NOT EXISTS "${CMAKE_SYSROOT}/usr/include/android/api-level.h")
  message(FATAL_ERROR "No NDK sysroot at ${CMAKE_SYSROOT}")
endif()

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# The flags the NDK's toolchain uses. The C++ library and the unwinder come from libwebrtc.a (Chromium's
# libc++, libc++abi and libunwind), so neither the NDK's libc++ nor its libunwind is linked.
set(CMAKE_C_FLAGS_INIT "-fPIC -ffunction-sections -fdata-sections -funwind-tables -fstack-protector-strong -no-canonical-prefixes -D_FORTIFY_SOURCE=2")
# libwebrtc is built with -mno-outline-atomics (BuildScripts~/patches/m156/android/add_nooutlineatomics_flag.patch):
# Unity failed to load a plugin that calls compiler-rt's __aarch64_* atomics helpers.
if(CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64")
  string(APPEND CMAKE_C_FLAGS_INIT " -mno-outline-atomics")
endif()
set(CMAKE_CXX_FLAGS_INIT "${CMAKE_C_FLAGS_INIT}")
# Chromium builds Android arm64 with the relative vtable ABI (use_relative_vtables_abi, see gn_cflags_cc.txt in
# the package). Classes the plugin derives from libwebrtc's must use the same vtable layout.
if(CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64")
  string(APPEND CMAKE_CXX_FLAGS_INIT " -fexperimental-relative-c++-abi-vtables")
endif()
set(CMAKE_ASM_FLAGS_INIT "-fPIC")
set(_link_flags "-fuse-ld=lld -rtlib=compiler-rt --unwindlib=none -Wl,--build-id=sha1 -Wl,--no-rosegment -Wl,--no-undefined-version -Wl,-z,max-page-size=16384 -Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,now")
# --no-undefined: every symbol must come from libwebrtc.a or the NDK's system libraries at ANDROID_PLATFORM.
set(CMAKE_SHARED_LINKER_FLAGS_INIT "${_link_flags} -Wl,--no-undefined")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "${_link_flags} -Wl,--no-undefined")
set(CMAKE_EXE_LINKER_FLAGS_INIT "${_link_flags}")

# The NDK's toolchain defines ANDROID; some code checks it instead of __ANDROID__.
set(ANDROID TRUE)
