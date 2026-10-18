# Find WebRTC include path

set(WEBRTC_DIR "${CMAKE_SOURCE_DIR}/webrtc")

set(WEBRTC_INCLUDE_DIR
  ${WEBRTC_DIR}/include
  ${WEBRTC_DIR}/include/third_party/abseil-cpp
  ${WEBRTC_DIR}/include/third_party/jsoncpp/source/include
  ${WEBRTC_DIR}/include/third_party/jsoncpp/generated
  ${WEBRTC_DIR}/include/third_party/libyuv/include
)

set(WEBRTC_OBJC_INCLUDE_DIR
  ${WEBRTC_DIR}/include/sdk/objc
  ${WEBRTC_DIR}/include/sdk/objc/base
)

set(WEBRTC_LIBRARY_DIR
  ${WEBRTC_DIR}/lib
)

# There is only `x64` on Windows, macOS, and Linux
# iOS and macOS use universal binary contains `x64` and `arm64`
if(Windows OR Linux)
  set(SYSTEM_PROCESSOR x64)
  set(WEBRTC_LIBRARY_DIR ${WEBRTC_LIBRARY_DIR}/${SYSTEM_PROCESSOR})
endif()
if(Android)
  if(CMAKE_ANDROID_ARCH_ABI STREQUAL "x86_64")
    set(CMAKE_ANDROID_ARCH "x64")
  endif()
  set(WEBRTC_LIBRARY_DIR ${WEBRTC_LIBRARY_DIR}/${CMAKE_ANDROID_ARCH})
endif()

find_library(WEBRTC_LIBRARY_DEBUG
  NAMES webrtcd
  PATHS ${WEBRTC_LIBRARY_DIR}
  NO_CMAKE_FIND_ROOT_PATH
)

find_library(WEBRTC_LIBRARY_RELEASE
  NAMES webrtc
  PATHS ${WEBRTC_LIBRARY_DIR}
  NO_CMAKE_FIND_ROOT_PATH
)

# Packages that contain only a release library use it for debug builds as well.
if(NOT WEBRTC_LIBRARY_DEBUG)
  set(WEBRTC_LIBRARY_DEBUG ${WEBRTC_LIBRARY_RELEASE})
endif()

set(WEBRTC_LIBRARY
  debug ${WEBRTC_LIBRARY_DEBUG}
  optimized ${WEBRTC_LIBRARY_RELEASE}
  CACHE STRING "WebRTC library"
)

# Packages built with Chromium's libc++ (use_custom_libcxx=true) ship cxx_flags.txt: the flags that point
# the compiler at the libc++ headers in the package. libwebrtc.a then also contains libc++ and libc++abi.
set(WEBRTC_CXX_FLAGS)
set(WEBRTC_USES_BUNDLED_LIBCXX FALSE)
if(EXISTS "${WEBRTC_DIR}/cxx_flags.txt")
  file(READ "${WEBRTC_DIR}/cxx_flags.txt" _webrtc_cxx_flags)
  string(STRIP "${_webrtc_cxx_flags}" _webrtc_cxx_flags)
  string(REPLACE "\${WEBRTC_INCLUDE_DIR}" "${WEBRTC_DIR}/include" _webrtc_cxx_flags "${_webrtc_cxx_flags}")
  separate_arguments(_webrtc_cxx_flags UNIX_COMMAND "${_webrtc_cxx_flags}")
  # CMake de-duplicates compile options, so join "-isystem <dir>" into a single "-isystem<dir>".
  set(_webrtc_join_next FALSE)
  foreach(_flag IN LISTS _webrtc_cxx_flags)
    if(_webrtc_join_next)
      list(APPEND WEBRTC_CXX_FLAGS "-isystem${_flag}")
      set(_webrtc_join_next FALSE)
    elseif(_flag STREQUAL "-isystem")
      set(_webrtc_join_next TRUE)
    else()
      list(APPEND WEBRTC_CXX_FLAGS "${_flag}")
    endif()
  endforeach()
  set(WEBRTC_USES_BUNDLED_LIBCXX TRUE)
  message(STATUS "libwebrtc uses its bundled libc++: ${WEBRTC_CXX_FLAGS}")
endif()

# Windows packages list the libraries to link together with webrtc.lib in libs.txt, by file name: system
# libraries and clang's builtins, which the package ships next to webrtc.lib.
set(WEBRTC_SYSTEM_LIBRARIES)
if(EXISTS "${WEBRTC_DIR}/libs.txt")
  file(STRINGS "${WEBRTC_DIR}/libs.txt" _webrtc_libs)
  foreach(_lib IN LISTS _webrtc_libs)
    string(STRIP "${_lib}" _lib)
    if(_lib STREQUAL "")
      continue()
    elseif(EXISTS "${WEBRTC_LIBRARY_DIR}/${_lib}")
      list(APPEND WEBRTC_SYSTEM_LIBRARIES "${WEBRTC_LIBRARY_DIR}/${_lib}")
    else()
      list(APPEND WEBRTC_SYSTEM_LIBRARIES "${_lib}")
    endif()
  endforeach()
endif()

# The C runtime the Windows package was built with (/MT or /MD); the plugin must use the same.
set(WEBRTC_MSVC_RUNTIME)
if(EXISTS "${WEBRTC_DIR}/VERSIONS")
  file(STRINGS "${WEBRTC_DIR}/VERSIONS" _webrtc_runtime REGEX "^MSVC_RUNTIME=")
  string(REGEX REPLACE "^MSVC_RUNTIME=" "" WEBRTC_MSVC_RUNTIME "${_webrtc_runtime}")
endif()

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(WebRTC
  DEFAULT_MSG
  WEBRTC_LIBRARY
  WEBRTC_LIBRARY_RELEASE
  WEBRTC_INCLUDE_DIR
)
