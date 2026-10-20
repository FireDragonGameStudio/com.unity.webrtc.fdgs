#pragma once

#include <vector>
#include <vulkan/vulkan.h>

namespace unity
{
namespace webrtc
{
    /// Returns `enabled` followed by each name of `requested` that is not in `enabled` yet. Names are compared as
    /// strings: Vulkan rejects a create info that names an extension twice on some drivers.
    std::vector<const char*>
    MergeExtensionNames(const char* const* enabled, uint32_t enabledCount, const std::vector<const char*>& requested);

    /// <summary>
    ///
    /// </summary>
    /// <param name="getInstanceProcAddr"></param>
    /// <param name="userdata"></param>
    /// <returns></returns>
    PFN_vkGetInstanceProcAddr
    InterceptVulkanInitialization(PFN_vkGetInstanceProcAddr getInstanceProcAddr, void* userdata);

} // namespace webrtc
} // namespace unity
