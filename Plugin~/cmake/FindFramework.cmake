# System frameworks that libwebrtc.a and the plugin link against. The lists match the link check of the
# libwebrtc package (BuildScripts~/libwebrtc/build_apple.sh); -ObjC loads every Objective-C object of
# libwebrtc.a, so the plugin needs all of them.
if(iOS)
  set(FRAMEWORK_LIBS
    "-framework AudioToolbox"
    "-framework AVFoundation"
    "-framework CoreAudio"
    "-framework CoreFoundation"
    "-framework CoreGraphics"
    "-framework CoreMedia"
    "-framework CoreServices"
    "-framework CoreTelephony"
    "-framework CoreVideo"
    "-framework Foundation"
    "-framework GLKit"
    "-framework IOSurface"
    "-framework Metal"
    "-framework MetalKit"
    "-framework Network"
    "-framework OpenGLES"
    "-framework QuartzCore"
    "-framework Security"
    "-framework SystemConfiguration"
    "-framework UIKit"
    "-framework VideoToolbox"
    objc
  )
else()
  set(FRAMEWORK_LIBS
    "-framework AppKit"
    "-framework ApplicationServices"
    "-framework AudioToolbox"
    "-framework AVFoundation"
    "-framework CoreAudio"
    "-framework CoreFoundation"
    "-framework CoreGraphics"
    "-framework CoreMedia"
    "-framework CoreServices"
    "-framework CoreVideo"
    "-framework Foundation"
    "-framework IOKit"
    "-framework IOSurface"
    "-framework Metal"
    "-framework MetalKit"
    "-framework OpenGL"
    "-framework QuartzCore"
    "-framework Security"
    "-framework SystemConfiguration"
    "-framework VideoToolbox"
    # ScreenCaptureKit exists since macOS 12.3; the plugin supports macOS 11.
    "-Wl,-weak_framework,ScreenCaptureKit"
    objc
  )
endif()
