# Android patches for libwebrtc M156

`libwebrtc-android.yml` applies these with `patch -p1 -d src` after the common patches in `..`. Paths are
relative to `src`; `build/` is a separate repository inside it, which is why they are not applied with `git apply`.

## Kept

| Patch | Why |
|---|---|
| `add_jni_zero_classes_to_libwebrtc_jar.patch` | New. M156 uses JNI Zero: `org.webrtc.DataChannel` calls `DataChannelJni`, which calls `J.N` (natives with hashed names, `Java_J_N_M...` in `libwebrtc.a`). An APK gets `J.N` from the `__jni_registration` target of its shared library; the `libwebrtc` dist_jar (`direct_deps_only`) had none of these classes, so every Java-to-native call threw `NoClassDefFoundError`. The patch adds a `generate_final_jni` target for the jar's Java targets and puts it, the `generated_*_jni_java` targets and jni_zero's `gendeps_java` and `generate_jni_java` (made visible to `//sdk/android`) into the jar. `BuildScripts~/libwebrtc/check_android_jar.py` checks the result. |
| `add_nooutlineatomics_flag.patch` | Chromium no longer passes `-mno-outline-atomics` on arm64, so the code calls the `__aarch64_*` atomics helpers from compiler-rt. Unity failed to `dlopen` a plugin built that way (M112 regression). Moved from `compiler_cpu_abi` (now generated from `compiler_cpu_abi.gn`) into `compiler_codegen`, next to `-mno-outline`. |
| `fix_adaptedvideotracksource.patch` | Received video was not displayed because the inline `video_adapter()` returned a different address in the plugin than inside libwebrtc (the class layout depends on defines such as `RTC_DCHECK_IS_ON`, which a Debug plugin build sets differently). Defining it out of line keeps the address right. The class moved from `media/base/` to `api/video/adapted_video_track_source.h` and `cricket::VideoAdapter` became `webrtc::VideoAdapter`. |
| `set_java_release_17.patch` | New, replaces the JDK 8 downgrade: M156 compiles Java with `--release 25` (class file version 69). Unity 6 builds with JDK 17 and its javac/D8 reject newer class files, so `compile_java.py` and `turbine.py` target 17. The build checks the class file version in `classes.jar`. |

## Dropped

| Patch | Why |
|---|---|
| `add_visibility_libunwind.patch`, `add_deps_libunwind.patch` | Only needed for `use_custom_libcxx=false`. The package uses Chromium's libc++ and ships its libunwind objects in `libwebrtc.a`. |
| `fix_android_videoencoder.patch` | Upstream: `NativeToJavaVideoFrame` returns null when `ToI420()` fails, and `VideoEncoderWrapper::Encode` drops such frames (`sdk/android/src/jni/video_frame.cc`, `video_encoder_wrapper.cc`). |
| `support_16kb_pagesizes_android.patch` | Upstream: `build/config/android/BUILD.gn` links every 64-bit Android shared library with `-z max-page-size=16384`. The build checks `libjingle_peerconnection_so.so` in the AAR; the plugin's own shared library sets the flag in its CMake preset. |
| `downgradeJDKto8_compile_java.patch`, `downgradeJDKto8_turbine.patch` | Obsolete: Unity 6 uses JDK 17 (see `set_java_release_17.patch`), and the lines they patched now say `25`. |
| `fetch_exclude_examples.patch` | `fetch.sh` writes its own `.gclient` and syncs with `--no-history --shallow`; the depot_tools fetch config it patched is not used. The Gradle checkout it excluded is small when shallow. |
