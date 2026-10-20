#pragma once

#include "IGraphicsDevice.h"

namespace unity
{
namespace webrtc
{

    // Pointer to pass to IGraphicsDevice::CopyResourceFromNativeV. On Vulkan it owns the UnityVulkanImage that
    // describes the texture and frees it when it goes out of scope; on other APIs it is Unity's own texture handle
    // and is not freed.
    using NativeGraphicsPtr = std::unique_ptr<void, void (*)(void*)>;

    class GraphicsUtility
    {
    public:
        static NativeGraphicsPtr
        TextureHandleToNativeGraphicsPtr(void* textureHandle, IGraphicsDevice* device, UnityGfxRenderer renderer);
    };

} // end namespace webrtc
} // end namespace unity
