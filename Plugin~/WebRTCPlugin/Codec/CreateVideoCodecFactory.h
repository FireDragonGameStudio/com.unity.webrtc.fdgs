#pragma once

#include <api/video_codecs/video_decoder_factory.h>
#include <api/video_codecs/video_encoder_factory.h>
#include <string>

namespace unity
{
namespace webrtc
{
    using namespace ::webrtc;

    constexpr char kInternalImpl[] = "Internal";
    constexpr char kNvCodecImpl[] = "NvCodec";
    constexpr char kAndroidMediaCodecImpl[] = "MediaCodec";
    constexpr char kVideoToolboxImpl[] = "VideoToolbox";

    constexpr char kSdpKeyNameCodecImpl[] = "implementation_name";

    class IGraphicsDevice;
    class ProfilerMarkerFactory;
    VideoEncoderFactory*
    CreateVideoEncoderFactory(const std::string& impl, IGraphicsDevice* gfxDevice, ProfilerMarkerFactory* profiler);
    VideoDecoderFactory*
    CreateVideoDecoderFactory(const std::string& impl, IGraphicsDevice* gfxDevice, ProfilerMarkerFactory* profiler);

    // Returns the factory that supports the codec of `format`, preferring hardware implementations over the
    // internal (software) one, e.g. NVENC AV1 over libaom. The format's implementation_name is not used: in a
    // negotiated format it comes from the remote peer's answer and names that peer's decoder (or is missing for
    // browsers), not the local encoder.
    template<typename Factory>
    Factory* FindCodecFactory(
        const std::map<std::string, std::unique_ptr<Factory>>& factories, const webrtc::SdpVideoFormat& format)
    {
        Factory* internal = nullptr;
        for (const auto& pair : factories)
        {
            for (const webrtc::SdpVideoFormat& other : pair.second->GetSupportedFormats())
            {
                if (!format.IsSameCodec(other))
                    continue;
                if (pair.first != kInternalImpl)
                    return pair.second.get();
                internal = pair.second.get();
                break;
            }
        }
        return internal;
    }

    template<typename Factory>
    std::vector<webrtc::SdpVideoFormat>
    GetSupportedFormatsInFactories(const std::map<std::string, std::unique_ptr<Factory>>& factories)
    {
        std::vector<SdpVideoFormat> supported_codecs;
        for (const auto& pair : factories)
        {
            for (const webrtc::SdpVideoFormat& format : pair.second->GetSupportedFormats())
            {
                webrtc::SdpVideoFormat newFormat = format;
                if (!pair.first.empty())
                    newFormat.parameters.emplace(kSdpKeyNameCodecImpl, pair.first);
                supported_codecs.push_back(newFormat);
            }
        }
        return supported_codecs;
    }
}
}
