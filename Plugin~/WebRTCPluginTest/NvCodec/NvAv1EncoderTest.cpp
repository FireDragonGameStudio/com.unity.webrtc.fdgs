#include "pch.h"

#include <iomanip>
#include <sstream>

#include <api/environment/environment_factory.h>
#include <modules/video_coding/codecs/av1/dav1d_decoder.h>

#include "Codec/NvCodec/NvCodec.h"
#include "Codec/NvCodec/NvEncoderImpl.h"
#include "FrameGenerator.h"
#include "GraphicsDevice/IGraphicsDevice.h"
#include "GraphicsDeviceContainer.h"
#include "VideoCodecTest.h"

namespace unity
{
namespace webrtc
{
    // NVENC encodes AV1 (Ada Lovelace and newer); dav1d, the decoder receivers use, decodes it.
    class NvAv1EncoderTest : public VideoCodecTest
    {
    public:
        NvAv1EncoderTest()
            : container_(CreateGraphicsDeviceContainer(GetParam()))
            , device_(container_->device())
        {
        }
        ~NvAv1EncoderTest() override
        {
            // Release the encoder and decoder before the graphics device and its CUDA context.
            encoder_ = nullptr;
            decoder_ = nullptr;
        }

        void SetUp() override
        {
            if (!device_)
                GTEST_SKIP() << "The graphics driver is not installed on the device.";
            if (!device_->IsCudaSupport())
                GTEST_SKIP() << "CUDA is not supported on this device.";
            context_ = device_->GetCUcontext();
            if (!NvEncoder::IsSupported(context_))
                GTEST_SKIP() << "Current Driver Version does not support this NvEncodeAPI version.";
            if (!IsNvEncAv1Supported(context_))
                GTEST_SKIP() << "NVENC cannot encode AV1 on this GPU.";
            VideoCodecTest::SetUp();
        }

    protected:
        std::unique_ptr<VideoEncoder> CreateEncoder() override
        {
            ::webrtc::Codec codec = ::webrtc::CreateVideoCodec(SdpVideoFormat::AV1Profile0());
            return NvEncoder::Create(codec, context_, CU_MEMORYTYPE_ARRAY, NV_ENC_BUFFER_FORMAT_ARGB, nullptr);
        }
        std::unique_ptr<VideoDecoder> CreateDecoder() override { return CreateDav1dDecoder(CreateEnvironment()); }
        std::unique_ptr<FrameGeneratorInterface> CreateFrameGenerator(
            int width,
            int height,
            std::optional<FrameGeneratorInterface::OutputType> type,
            std::optional<int> num_squares) override
        {
            return CreateVideoFrameGenerator(device_, width, height, type, num_squares);
        }
        void ModifyCodecSettings(VideoCodec* codec_settings) override
        {
            SetDefaultSettings(codec_settings);
            codec_settings->codecType = kVideoCodecAV1;
        }

        void EncodeAndDecode(int width, int height)
        {
            codecSettings_.width = width;
            codecSettings_.height = height;
            codecSettings_.maxBitrate = 40000;
            ChangeFrameResolution(width, height);
            decoderSettings_.set_codec_type(kVideoCodecAV1);
            decoderSettings_.set_max_render_resolution({ width, height });

            ASSERT_EQ(WEBRTC_VIDEO_CODEC_OK, encoder_->Release());
            ASSERT_EQ(WEBRTC_VIDEO_CODEC_OK, encoder_->InitEncode(&codecSettings_, kSettings()));
            VideoBitrateAllocation allocation;
            allocation.SetBitrate(0, 0, 20000000);
            encoder_->SetRates(VideoEncoder::RateControlParameters(allocation, 30.0));
            ASSERT_EQ(WEBRTC_VIDEO_CODEC_OK, decoder_->Release());
            ASSERT_TRUE(decoder_->Configure(decoderSettings_));

            for (int i = 0; i < 2; i++)
            {
                const bool key = i == 0;
                std::vector<VideoFrameType> frameTypes = { key ? VideoFrameType::kVideoFrameKey
                                                               : VideoFrameType::kVideoFrameDelta };
                ASSERT_EQ(WEBRTC_VIDEO_CODEC_OK, encoder_->Encode(NextInputFrame(), &frameTypes));
                EncodedImage encoded;
                CodecSpecificInfo info;
                ASSERT_TRUE(WaitForEncodedFrame(&encoded, &info));

                EXPECT_EQ(kVideoCodecAV1, info.codecType);
                EXPECT_EQ(key ? VideoFrameType::kVideoFrameKey : VideoFrameType::kVideoFrameDelta, encoded._frameType)
                    << "first bytes: " << HexPrefix(encoded);
                EXPECT_EQ(static_cast<uint32_t>(width), encoded._encodedWidth);
                EXPECT_EQ(static_cast<uint32_t>(height), encoded._encodedHeight);
                // The AV1 RTP packetizer needs the dependency descriptor data, with the structure on key frames.
                ASSERT_TRUE(info.generic_frame_info.has_value());
                ASSERT_EQ(key, info.template_structure.has_value());
                if (key)
                {
                    ASSERT_EQ(1u, info.template_structure->resolutions.size());
                    EXPECT_EQ(width, info.template_structure->resolutions[0].Width());
                    EXPECT_EQ(height, info.template_structure->resolutions[0].Height());
                }

                ASSERT_EQ(WEBRTC_VIDEO_CODEC_OK, decoder_->Decode(encoded, false, 0));
                std::unique_ptr<VideoFrame> decoded;
                std::optional<uint8_t> qp;
                ASSERT_TRUE(WaitForDecodedFrame(&decoded, &qp));
                ASSERT_TRUE(decoded);
                EXPECT_EQ(width, decoded->width());
                EXPECT_EQ(height, decoded->height());
            }
        }

        static std::string HexPrefix(const EncodedImage& image)
        {
            std::ostringstream out;
            for (size_t i = 0; i < std::min<size_t>(image.size(), 24); i++)
                out << std::hex << std::setw(2) << std::setfill('0') << static_cast<int>(image.data()[i]) << " ";
            return out.str();
        }

        CUcontext context_;
        std::unique_ptr<GraphicsDeviceContainer> container_;
        IGraphicsDevice* device_;
    };

    TEST_P(NvAv1EncoderTest, EncodeDecode1920x1080) { EncodeAndDecode(1920, 1080); }

    // 360° video, 2:1 equirectangular: above H.264's limits.
    TEST_P(NvAv1EncoderTest, EncodeDecode5760x2880) { EncodeAndDecode(5760, 2880); }

    TEST_P(NvAv1EncoderTest, EncodeDecode7680x3840) { EncodeAndDecode(7680, 3840); }

    INSTANTIATE_TEST_SUITE_P(GfxDevice, NvAv1EncoderTest, testing::ValuesIn(supportedGfxDevices));

    TEST(NvAv1KeyFrameTest, DetectsTheSequenceHeader)
    {
        // Temporal delimiter (type 2, has_size_field, size 0), sequence header (type 1, size 2), frame (type 6).
        const std::vector<uint8_t> key = { 0x12, 0x00, 0x0A, 0x02, 0xAA, 0xBB, 0x32, 0x01, 0xCC };
        EXPECT_TRUE(NvEncoderImpl::IsAv1KeyFrame(key));

        const std::vector<uint8_t> delta = { 0x12, 0x00, 0x32, 0x03, 0x01, 0x02, 0x03 };
        EXPECT_FALSE(NvEncoderImpl::IsAv1KeyFrame(delta));

        // An OBU with an extension header and a two-byte leb128 size (130) before the sequence header.
        std::vector<uint8_t> extended = { 0x36, 0x00, 0x82, 0x01 };
        extended.resize(extended.size() + 130, 0);
        extended.insert(extended.end(), { 0x0A, 0x00 });
        EXPECT_TRUE(NvEncoderImpl::IsAv1KeyFrame(extended));

        EXPECT_FALSE(NvEncoderImpl::IsAv1KeyFrame({}));
    }
} // end namespace webrtc
} // end namespace unity
