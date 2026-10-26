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

    // Returns the factory that supports the codec of `format`. When the format names an implementation
    // (implementation_name, added by GetSupportedFormatsInFactories) that supports the codec, that factory is used,
    // so that e.g. "AV1 (NvCodec)" gets the hardware encoder even though the internal factory also has AV1.
    // Otherwise the first factory supporting the codec is used: a remote peer's implementation_name may name an
    // implementation this device does not have.
    template<typename Factory>
    Factory* FindCodecFactory(
        const std::map<std::string, std::unique_ptr<Factory>>& factories, const webrtc::SdpVideoFormat& format)
    {
        auto impl = format.parameters.find(kSdpKeyNameCodecImpl);
        if (impl != format.parameters.end())
        {
            auto named = factories.find(impl->second);
            if (named != factories.end())
            {
                for (const webrtc::SdpVideoFormat& other : named->second->GetSupportedFormats())
                {
                    if (format.IsSameCodec(other))
                        return named->second.get();
                }
            }
        }
        for (const auto& pair : factories)
        {
            for (const webrtc::SdpVideoFormat& other : pair.second->GetSupportedFormats())
            {
                if (format.IsSameCodec(other))
                    return pair.second.get();
            }
        }
        return nullptr;
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
