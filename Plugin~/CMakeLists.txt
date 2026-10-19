cmake_minimum_required(VERSION 3.22)

# Minimum OS versions supported by Unity 6. CMAKE_OSX_DEPLOYMENT_TARGET applies
# to iOS as well, so it must be set per platform before project().
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
  set(CMAKE_OSX_DEPLOYMENT_TARGET
      "13.0"
      CACHE STRING "Minimum iOS deployment version")
else()
  set(CMAKE_OSX_DEPLOYMENT_TARGET
      "11.0"
      CACHE STRING "Minimum macOS deployment version")
endif()

project(
  webrtc
  VERSION 2.4.0
  LANGUAGES C CXX ASM)

cmake_policy(SET CMP0076 NEW)

# Enable unit testing
enable_testing()

# Define flags to determine the build target platform Windows, Linux, macOS,
# iOS, Android
if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
  set(Windows TRUE)
endif()
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
  set(iOS TRUE)
endif()
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  set(Linux TRUE)
endif()
if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
  set(macOS TRUE)
endif()
if(CMAKE_SYSTEM_NAME STREQUAL "Android")
  set(Android TRUE)
endif()

set(CMAKE_C_STANDARD 17)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Use lld linker instead of GNU ld. Link libstdc++ statically so the plugin
# does not depend on the GLIBCXX version of the user's distribution; the
# required glibc version is set by the distribution the plugin is built on.
if(Linux)
  set(CMAKE_CXX_FLAG "${CMAKE_CXX_FLAG} -static-libstdc++")
  add_link_options(-static-libstdc++ -fuse-ld=lld)
endif()

# enable debug output
set(CMAKE_VERBOSE_MAKEFILE ON)

# set iterator debug level and compiler flags.
if(Windows AND CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
  set(CMAKE_CXX_FLAGS_DEBUG
      "${CMAKE_CXX_FLAGS_DEBUG} -D_ITERATOR_DEBUG_LEVEL=0 /Zi /Od")
else()
  set(CMAKE_CXX_FLAGS_DEBUG
      "${CMAKE_CXX_FLAGS_DEBUG} -D_ITERATOR_DEBUG_LEVEL=0")
endif()

set(CMAKE_THREAD_PREFER_PTHREAD TRUE)
find_package(Threads REQUIRED)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake")

find_package(WebRTC REQUIRED)

if(WEBRTC_USES_BUNDLED_LIBCXX)
  # libwebrtc was built with Chromium's libc++ (namespace std::__Cr). All C++ code that shares standard
  # library types with it must be compiled against the same headers, and the C++ runtime comes from
  # libwebrtc.a instead of the system. The CUDA kernels do not use the standard library.
  add_compile_options("$<$<COMPILE_LANGUAGE:CXX,OBJCXX>:${WEBRTC_CXX_FLAGS}>")
  if(NOT MSVC)
    add_link_options(-nostdlib++)
  endif()
  if(Linux)
    # Without a C++ library the driver does not link libm either, which libc++ needs. The plugin does not
    # export the symbols of libwebrtc.a and its libc++.
    link_libraries(m)
    add_link_options(-Wl,--exclude-libs,libwebrtc.a)
  endif()
  if(Windows)
    # webrtc.lib contains libc++ and uses the MSVC C++ ABI (vcruntime). The libc++ include directories in
    # cxx_flags.txt come before the MSVC include directory, which holds both the CRT and the MSVC STL, so
    # only clang-cl can compile the plugin: MSVC cannot use libc++.
    if(NOT CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
      message(FATAL_ERROR "libwebrtc uses Chromium's libc++: build the plugin with clang-cl")
    endif()
    if(NOT WEBRTC_MSVC_RUNTIME STREQUAL "/MT")
      message(FATAL_ERROR "The plugin links the static C runtime (/MT), libwebrtc uses ${WEBRTC_MSVC_RUNTIME}")
    endif()
  endif()
endif()

if(iOS OR macOS)
  find_package(Framework REQUIRED)
endif()

if(Windows OR Linux)
  find_package(Vulkan REQUIRED)

  find_package(CUDA REQUIRED)

  # nvcc does not support clang-cl as host compiler
  # (https://gitlab.kitware.com/cmake/cmake/-/issues/20776). With the Ninja generator the CUDA kernels are
  # compiled with MSVC instead (CMAKE_CUDA_HOST_COMPILER=cl); they do not use the C++ standard library.
  if(Linux OR (Windows AND (CMAKE_CXX_COMPILER_ID STREQUAL "MSVC" OR NOT CMAKE_GENERATOR MATCHES "Visual Studio")))
    enable_language(CUDA)
  else()
    add_compile_definitions(NO_CUDA_KERNEL=1)
  endif()
  add_subdirectory(NvCodec)
endif()

add_subdirectory(WebRTCPlugin)
add_subdirectory(WebRTCPluginTest)
