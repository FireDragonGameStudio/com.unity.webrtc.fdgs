# Build Native Plugin

This guide will cover building and deploying the native plugin `com.fdgs.webrtc` depends on.

## Developing environment

Install dependencies to make development environment.

### Windows

libwebrtc M156 is built with Chromium's own libc++, so the plugin is compiled with the same Chromium `clang-cl` (`CLANG_REVISION` in `Plugin~/webrtc/VERSIONS`) against the libc++ headers in the package, and linked with `lld-link`. MSVC cannot build it. Visual Studio still provides the C runtime (`/MT`), the Windows SDK and `cl.exe`, which `nvcc` uses as host compiler for the CUDA kernels.

Install the following:

- **Visual Studio 2022 or 2026** with the *Desktop development with C++* workload
- **CUDA Toolkit** 12.x or 13.x (`winget install Nvidia.CUDA`)
- **Vulkan SDK** (`winget install KhronosGroup.VulkanSDK`)
- **7-Zip** and **curl** (used by the build script)

Then run from the repository root:

```bat
BuildScripts~\build_plugin_win.cmd
```

It downloads the libwebrtc package (SHA-256 checked) and Chromium's clang into `Plugin~\out`, sets up the Visual Studio x64 environment unless it is already set, and builds `Runtime\Plugins\x86_64\webrtc.dll` with the `x64-windows` preset (Ninja, Release; the package has no debug library). Pass `WebRTCLibTest` to build the native tests instead. From a *x64 Native Tools Command Prompt* the preset can also be used directly, with Chromium's `clang-cl.exe` and `lld-link.exe` first in `PATH`:

```bat
cd Plugin~
cmake --preset=x64-windows
cmake --build out/build/x64-windows --config Release --target WebRTCPlugin
```

### Ubuntu

The below commands set up the build environment on **Ubuntu 22.04** (the same environment as the [GitHub Actions workflow](../.github/workflows/native-linux.yml)). The plugin requires the glibc version of the distribution it is built on, so build on the oldest Ubuntu you want to support; libstdc++ is linked statically.

```bash
# Install clang and lld (any recent version works; CI uses 18)
wget https://apt.llvm.org/llvm.sh
sudo bash llvm.sh 18

# Install other packages
sudo apt install -y ninja-build pkg-config libvulkan-dev libx11-dev libgl-dev libglfw3-dev python3-pip

# Install glad2
python3 -m pip install --user glad2==2.0.8

# Install CUDA Toolkit 12
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt update
sudo apt install -y cuda-nvcc-12-9 cuda-cudart-dev-12-9
export PATH=/usr/local/cuda-12.9/bin:$PATH

# CMake 3.22 or newer is required (Ubuntu 22.04 ships 3.22).
sudo apt install -y cmake

# Build Runtime/Plugins/x86_64/libwebrtc.so
CC=clang-18 CXX=clang++-18 BuildScripts~/build_plugin_linux.sh
```

### macOS

Building requires a Mac with **Xcode 16 or newer** and CMake 3.22 or newer (the same environment as the [GitHub Actions workflow](../.github/workflows/native-macos.yml), which uses the `macos-15` runner). The prebuilt libwebrtc is a universal library, so the build produces a universal (arm64 + x86_64) `Runtime/Plugins/macOS/libwebrtc.dylib`. The minimum deployment target is macOS 11.0, the minimum supported by Unity 6.

```bash
# Install CMake (if not installed yet)
brew install cmake

# Build Runtime/Plugins/macOS/libwebrtc.dylib
BuildScripts~/build_plugin_mac.sh
```

### iOS

The requirements are the same as for macOS ([workflow](../.github/workflows/native-ios.yml)). The script builds `Runtime/Plugins/iOS/webrtc.framework` for devices (arm64) with a minimum deployment target of iOS 13.0, the minimum supported by Unity 6. The framework is not code signed; Xcode signs it when it embeds the framework into the Unity iOS app.

```bash
BuildScripts~/build_plugin_ios.sh
```

### Android

On Ubuntu (**WSL2** on Windows also works), with the same environment as the [GitHub Actions workflow](../.github/workflows/native-android.yml). Android NDK **r28c** is tested; NDK r28 and newer align shared libraries to 16 KB pages by default, which Google Play requires for Android 15+ devices. The CMake project also passes `-z max-page-size=16384` to the linker, so older NDKs produce 16 KB aligned libraries too.

```bash
# Install the Android NDK r28c with sdkmanager (from the Android SDK command-line tools) ...
sdkmanager --install "ndk;28.2.13676358"
export ANDROID_NDK=$ANDROID_SDK_ROOT/ndk/28.2.13676358

# ... or download it directly
wget https://dl.google.com/android/repository/android-ndk-r28c-linux.zip
unzip android-ndk-r28c-linux.zip -d ~/
export ANDROID_NDK=~/android-ndk-r28c

# CMake 3.22 or newer is required (Ubuntu 22.04 and newer ship it), plus curl, unzip and zip
sudo apt install -y cmake curl unzip zip

# Build Runtime/Plugins/Android/libwebrtc.aar (arm64-v8a and x86_64)
BuildScripts~/build_plugin_android.sh
```

## Build plugin

To build plugin, you need to execute command in the `BuildScripts~` folder.

- [BuildScripts~/build_plugin_android.sh](../BuildScripts~/build_plugin_android.sh)
- [BuildScripts~/build_plugin_mac.sh](../BuildScripts~/build_plugin_mac.sh)
- [BuildScripts~/build_plugin_ios.sh](../BuildScripts~/build_plugin_ios.sh)
- [BuildScripts~/build_plugin_linux.sh](../BuildScripts~/build_plugin_linux.sh)
- [BuildScripts~/build_plugin_win.cmd](../BuildScripts~/build_plugin_win.cmd)
    - Note: If you encounter `LNK1120`, `LNK2001` or `LNK2019` errors while running this build script, it's possible that you may need to open `Plugin~/build64/webrtc.sln` and build from within Visual Studio 2019 instead. You can also use it for development. ([#441](https://github.com/Unity-Technologies/com.unity.webrtc/issues/441))

Alternatively, after the script has been run, a project ready for your IDE or other build tools is ready for you to use/build with (the name of the folder differs based on the target platform, check the script for more details).

### Deploying the Plugin

When you run the build, `webrtc.dll` will be placed in `Runtime\Plugins\x86_64` of this package. You should then be able to verify the following settings in the Unity Inspector window.

**WARNING:** If "Load on startup" is not ticked, your editor will crash when running your project. This may become unticked after you make a change to the plugin. ([#444](https://github.com/Unity-Technologies/com.unity.webrtc/issues/444))

<img src="../Documentation~/images/inspector_webrtc_plugin.png" width=400 align=center>

## Debug

The `WebRTC` project properties must be adjusted to match your environment in order to build the plugin. 

Set the Unity.exe path under `Command` and the project path under `Command Arguments`. Once set, during debugging the Unity Editor will run and breakpoints will be enabled.  

<img src="../Documentation~/images/command_config_vs2017.png" width=600 align=center>
