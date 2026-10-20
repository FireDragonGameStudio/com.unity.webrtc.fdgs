#include "pch.h"

#if SUPPORT_VULKAN

#include <string>

#include "GraphicsDevice/Vulkan/UnityVulkanInitCallback.h"

namespace unity
{
namespace webrtc
{
    static std::vector<std::string> ToStrings(const std::vector<const char*>& names)
    {
        return std::vector<std::string>(names.begin(), names.end());
    }

    // Unity's names are other pointers than the plugin's string literals: they must still count as the same
    // extension (duplicates made vkCreateInstance fail on some Android devices, #1120).
    TEST(VulkanExtensionNamesTest, KeepsEachNameOnce)
    {
        std::string surface = VK_KHR_SURFACE_EXTENSION_NAME;
        std::string properties2 = VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME;
        const char* enabled[] = { surface.c_str(), properties2.c_str() };
        std::vector<const char*> requested = { VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME,
                                               VK_KHR_EXTERNAL_MEMORY_CAPABILITIES_EXTENSION_NAME };

        auto names = MergeExtensionNames(enabled, 2, requested);

        EXPECT_EQ(
            ToStrings(names),
            (std::vector<std::string> { VK_KHR_SURFACE_EXTENSION_NAME,
                                        VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME,
                                        VK_KHR_EXTERNAL_MEMORY_CAPABILITIES_EXTENSION_NAME }));
        // Unity's own strings are passed on unchanged.
        EXPECT_EQ(names[1], enabled[1]);
    }

    TEST(VulkanExtensionNamesTest, WorksWithoutEnabledNames)
    {
        std::vector<const char*> requested = { VK_KHR_EXTERNAL_MEMORY_CAPABILITIES_EXTENSION_NAME };
        EXPECT_EQ(MergeExtensionNames(nullptr, 0, requested), requested);
    }
} // end namespace webrtc
} // end namespace unity

#endif
