#pragma once

#include <optional>
#include <api/video_codecs/h264_profile_level_id.h>

namespace unity
{
namespace webrtc
{
    using namespace ::webrtc;

    // Returns the minumum level which can supports given parameters.
    // webrtc::H264SupportedLevel function is defined in libwebrtc, but that is for decoder.
    std::optional<H264Level> H264SupportedLevel(int width, int height, int maxFramerate, int maxBitrate);

    // Returns the max framerate of the level for frames of the given size, or 0 if the frame does not fit the level.
    int SupportedMaxFramerate(H264Level level, int width, int height);

} // end namespace webrtc
} // end namespace unity
