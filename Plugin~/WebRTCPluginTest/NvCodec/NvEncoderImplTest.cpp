#include "pch.h"

#include "Codec/NvCodec/NvEncoderImpl.h"
#include "GraphicsDevice/IGraphicsDevice.h"
#include "GraphicsDeviceContainer.h"
#include "NvCodecUtils.h"
#include "VideoCodecTest.h"

namespace unity
{
namespace webrtc
{
    using namespace webrtc;
    using testing::Values;

    class NvEncoderImplTest : public testing::TestWithParam<UnityGfxRenderer>
    {
    public:
        NvEncoderImplTest()
            : container_(CreateGraphicsDeviceContainer(GetParam()))
            , device_(container_->device())
        {
        }
        ~NvEncoderImplTest() override { }

    protected:
        void SetUp() override
        {
            if (!device_)
                GTEST_SKIP() << "The graphics driver is not installed on the device.";
            if (!device_->IsCudaSupport())
                GTEST_SKIP() << "CUDA is not supported on this device.";

            context_ = container_->device()->GetCUcontext();
        }
        CUcontext context_;
        std::unique_ptr<GraphicsDeviceContainer> container_;
        IGraphicsDevice* device_;
    };

    TEST_P(NvEncoderImplTest, CanInitializeWithDefaultParameters)
    {
        ::webrtc::Codec codec = ::webrtc::CreateVideoCodec(::webrtc::kH264CodecName);
        codec.SetParam(::webrtc::kH264FmtpProfileLevelId, kProfileLevelIdString());
        NvEncoderImpl encoder(codec, context_, CU_MEMORYTYPE_ARRAY, NV_ENC_BUFFER_FORMAT_ARGB, nullptr);

        VideoCodec codec_settings;
        SetDefaultSettings(&codec_settings);
        EXPECT_EQ(WEBRTC_VIDEO_CODEC_OK, encoder.InitEncode(&codec_settings, kSettings()));
    }

    TEST_P(NvEncoderImplTest, CanInitializeWithProfileLevel51Resolution3840x2160)
    {
        H264ProfileLevelId profileLevelId(H264Profile::kProfileBaseline, H264Level::kLevel5_1);

        ::webrtc::Codec codec = ::webrtc::CreateVideoCodec(::webrtc::kH264CodecName);
        codec.SetParam(::webrtc::kH264FmtpProfileLevelId, *H264ProfileLevelIdToString(profileLevelId));
        NvEncoderImpl encoder(codec, context_, CU_MEMORYTYPE_ARRAY, NV_ENC_BUFFER_FORMAT_ARGB, nullptr);

        VideoCodec codec_settings;
        SetDefaultSettings(&codec_settings);
        codec_settings.width = 3840;
        codec_settings.height = 2160;
        codec_settings.maxFramerate = 30;
        EXPECT_EQ(WEBRTC_VIDEO_CODEC_OK, encoder.InitEncode(&codec_settings, kSettings()));
    }

    TEST_P(NvEncoderImplTest, ThrowInitializeWithProfileLevel51Resolution4000x4000)
    {
        H264ProfileLevelId profileLevelId(H264Profile::kProfileBaseline, H264Level::kLevel5_1);

        ::webrtc::Codec codec = ::webrtc::CreateVideoCodec(::webrtc::kH264CodecName);
        codec.SetParam(::webrtc::kH264FmtpProfileLevelId, *H264ProfileLevelIdToString(profileLevelId));
        NvEncoderImpl encoder(codec, context_, CU_MEMORYTYPE_ARRAY, NV_ENC_BUFFER_FORMAT_ARGB, nullptr);

        VideoCodec codec_settings;
        SetDefaultSettings(&codec_settings);
        codec_settings.width = 4000;
        codec_settings.height = 4000;

        EXPECT_EQ(encoder.InitEncode(&codec_settings, kSettings()), WEBRTC_VIDEO_CODEC_ERR_PARAMETER);
    }

    // Sizes up to H.264 level 5.2 (36864 macroblocks), e.g. 2:1 equirectangular 360° video.
    TEST_P(NvEncoderImplTest, CanInitializeHighResolutionsUpToLevel52)
    {
        const std::pair<int, int> sizes[] = { { 4096, 2048 }, { 4096, 2304 }, { 2048, 4096 } };
        for (const auto& [width, height] : sizes)
        {
            H264ProfileLevelId profileLevelId(H264Profile::kProfileConstrainedBaseline, H264Level::kLevel5_2);
            ::webrtc::Codec codec = ::webrtc::CreateVideoCodec(::webrtc::kH264CodecName);
            codec.SetParam(::webrtc::kH264FmtpProfileLevelId, *H264ProfileLevelIdToString(profileLevelId));
            NvEncoderImpl encoder(codec, context_, CU_MEMORYTYPE_ARRAY, NV_ENC_BUFFER_FORMAT_ARGB, nullptr);

            VideoCodec codec_settings;
            SetDefaultSettings(&codec_settings);
            codec_settings.width = width;
            codec_settings.height = height;
            codec_settings.maxFramerate = 30;
            EXPECT_EQ(WEBRTC_VIDEO_CODEC_OK, encoder.InitEncode(&codec_settings, kSettings()))
                << width << "x" << height;
        }
    }

    // Wider than NVENC's H.264 maximum but within the macroblock count of level 5.2: InitEncode must fail cleanly so
    // that WebRTC switches to another codec.
    TEST_P(NvEncoderImplTest, FailsAboveMaxWidth)
    {
        const auto [maxWidth, maxHeight] = SupportedMaxH264Size(context_);
        H264ProfileLevelId profileLevelId(H264Profile::kProfileConstrainedBaseline, H264Level::kLevel5_2);
        ::webrtc::Codec codec = ::webrtc::CreateVideoCodec(::webrtc::kH264CodecName);
        codec.SetParam(::webrtc::kH264FmtpProfileLevelId, *H264ProfileLevelIdToString(profileLevelId));
        NvEncoderImpl encoder(codec, context_, CU_MEMORYTYPE_ARRAY, NV_ENC_BUFFER_FORMAT_ARGB, nullptr);

        VideoCodec codec_settings;
        SetDefaultSettings(&codec_settings);
        codec_settings.width = maxWidth + 16;
        codec_settings.height = 256;
        codec_settings.maxFramerate = 30;
        EXPECT_EQ(WEBRTC_VIDEO_CODEC_ERR_PARAMETER, encoder.InitEncode(&codec_settings, kSettings()));
    }

    INSTANTIATE_TEST_SUITE_P(GfxDevice, NvEncoderImplTest, testing::ValuesIn(supportedGfxDevices));

} // end namespace webrtc
} // end namespace unity
