#include "pch.h"

#include <iterator>

#include "H264ProfileLevelId.h"

using namespace ::webrtc;

namespace unity
{
namespace webrtc
{
    struct LevelConstraint
    {
        const int max_macroblocks_per_second;
        const int max_macroblock_frame_size;
        const int max_video_bitrate;
        const H264Level level;
    };

    static constexpr LevelConstraint kLevelConstraints[] = {
        { 1485, 99, 64, H264Level::kLevel1 },
        { 1485, 99, 128, H264Level::kLevel1_b },
        { 3000, 396, 192, H264Level::kLevel1_1 },
        { 6000, 396, 384, H264Level::kLevel1_2 },
        { 11880, 396, 768, H264Level::kLevel1_3 },
        { 11880, 396, 2000, H264Level::kLevel2 },
        { 19800, 792, 4000, H264Level::kLevel2_1 },
        { 20250, 1620, 4000, H264Level::kLevel2_2 },
        { 40500, 1620, 10000, H264Level::kLevel3 },
        { 108000, 3600, 14000, H264Level::kLevel3_1 },
        { 216000, 5120, 20000, H264Level::kLevel3_2 },
        { 245760, 8192, 20000, H264Level::kLevel4 },
        { 245760, 8192, 50000, H264Level::kLevel4_1 },
        { 522240, 8704, 50000, H264Level::kLevel4_2 },
        { 589824, 22080, 135000, H264Level::kLevel5 },
        { 983040, 36864, 240000, H264Level::kLevel5_1 },
        { 2073600, 36864, 240000, H264Level::kLevel5_2 },
    };

    static const int kMacroblockSize = 16;
    static const int kUnitMaxBRWithNAL = 1200;

    // The encoder codes whole 16x16 macroblocks, so a partial macroblock at the right or bottom edge counts.
    static int MacroblockCount(int pixels) { return (pixels + kMacroblockSize - 1) / kMacroblockSize; }

    // H.264 Annex A.3.1: the frame size in macroblocks is limited by MaxFS, and so are both dimensions
    // (width and height in macroblocks <= sqrt(8 * MaxFS)).
    static bool FitsFrameSize(const LevelConstraint& constraint, int widthInMbs, int heightInMbs)
    {
        const int64_t maxDimension = 8LL * constraint.max_macroblock_frame_size;
        return static_cast<int64_t>(widthInMbs) * heightInMbs <= constraint.max_macroblock_frame_size &&
            static_cast<int64_t>(widthInMbs) * widthInMbs <= maxDimension &&
            static_cast<int64_t>(heightInMbs) * heightInMbs <= maxDimension;
    }

    std::optional<webrtc::H264Level> H264SupportedLevel(int width, int height, int maxFramerate, int maxBitrate)
    {
        if (width <= 0 || height <= 0 || maxFramerate <= 0 || maxBitrate <= 0)
            return std::nullopt;

        const int widthInMbs = MacroblockCount(width);
        const int heightInMbs = MacroblockCount(height);
        const int64_t macroblocksPerSecond = static_cast<int64_t>(widthInMbs) * heightInMbs * maxFramerate;

        for (size_t i = 0; i < std::size(kLevelConstraints); i++)
        {
            const LevelConstraint& level_constraint = kLevelConstraints[i];
            if (FitsFrameSize(level_constraint, widthInMbs, heightInMbs) &&
                level_constraint.max_macroblocks_per_second >= macroblocksPerSecond &&
                level_constraint.max_video_bitrate * kUnitMaxBRWithNAL >= maxBitrate)
            {
                return level_constraint.level;
            }
        }

        // No level supported.
        return std::nullopt;
    }

    int SupportedMaxFramerate(H264Level level, int width, int height)
    {
        if (width <= 0 || height <= 0)
            return 0;

        const int widthInMbs = MacroblockCount(width);
        const int heightInMbs = MacroblockCount(height);
        for (size_t i = 0; i < std::size(kLevelConstraints); i++)
        {
            const LevelConstraint& level_constraint = kLevelConstraints[i];
            if (level_constraint.level == level)
            {
                if (!FitsFrameSize(level_constraint, widthInMbs, heightInMbs))
                    return 0;
                return level_constraint.max_macroblocks_per_second / (widthInMbs * heightInMbs);
            }
        }

        // target level not found.
        return 0;
    }
}
}
