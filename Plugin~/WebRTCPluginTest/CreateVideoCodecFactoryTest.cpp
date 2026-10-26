#include "pch.h"

#include "Codec/CreateVideoCodecFactory.h"
#include "GraphicsDeviceContainer.h"

namespace unity
{
namespace webrtc
{
    class CreateVideoCodecFactoryTest : public testing::TestWithParam<UnityGfxRenderer>
    {
    public:
        CreateVideoCodecFactoryTest()
            : container_(CreateGraphicsDeviceContainer(GetParam()))
            , device_(container_->device())
        {
            arrayImpl_ = { kInternalImpl, kNvCodecImpl, kAndroidMediaCodecImpl, kVideoToolboxImpl };
        }

    protected:
        void SetUp() override
        {
            if (!device_)
                GTEST_SKIP() << "The graphics driver is not installed on the device.";
        }
        std::unique_ptr<GraphicsDeviceContainer> container_;
        std::vector<std::string> arrayImpl_;
        IGraphicsDevice* device_;
    };

    TEST_P(CreateVideoCodecFactoryTest, CreateVideoEncoderFactory)
    {
        std::map<std::string, std::unique_ptr<VideoEncoderFactory>> factories;
        for (auto impl : arrayImpl_)
        {
            auto factory = CreateVideoEncoderFactory(impl, device_, nullptr);
            if (factory)
                factories.emplace(impl, factory);
        }
        EXPECT_GT(factories.size(), 0);
    }

    TEST_P(CreateVideoCodecFactoryTest, CreateVideoDecoderFactory)
    {
        std::map<std::string, std::unique_ptr<VideoDecoderFactory>> factories;

        for (auto impl : arrayImpl_)
        {
            auto factory = CreateVideoDecoderFactory(impl, device_, nullptr);
            if (factory)
                factories.emplace(impl, factory);
        }
        EXPECT_GT(factories.size(), 0);
    }

    TEST_P(CreateVideoCodecFactoryTest, FindCodecFactory)
    {
        std::map<std::string, std::unique_ptr<VideoEncoderFactory>> factories;
        for (auto impl : arrayImpl_)
        {
            auto factory = CreateVideoEncoderFactory(impl, device_, nullptr);
            if (factory)
                factories.emplace(impl, factory);
        }

        // return nullptr when unknown mimetype
        SdpVideoFormat format("test");
        EXPECT_TRUE(!FindCodecFactory(factories, format));

        // return value when unknown implementation_name
        SdpVideoFormat format2("VP8");
        format.parameters.emplace(kSdpKeyNameCodecImpl, "unknown");
        EXPECT_TRUE(FindCodecFactory(factories, format2));
    }

    TEST_P(CreateVideoCodecFactoryTest, GetSupportedFormatsInFactories)
    {
        std::map<std::string, std::unique_ptr<VideoEncoderFactory>> factories;
        for (auto impl : arrayImpl_)
        {
            auto factory = CreateVideoEncoderFactory(impl, device_, nullptr);
            if (factory)
                factories.emplace(impl, factory);
        }

        std::vector<webrtc::SdpVideoFormat> formats = GetSupportedFormatsInFactories(factories);
        EXPECT_GT(formats.size(), 0);
    }
    class FakeEncoderFactory : public VideoEncoderFactory
    {
    public:
        explicit FakeEncoderFactory(std::vector<SdpVideoFormat> formats)
            : formats_(std::move(formats))
        {
        }
        std::vector<SdpVideoFormat> GetSupportedFormats() const override { return formats_; }
        std::unique_ptr<VideoEncoder> Create(const Environment&, const SdpVideoFormat&) override { return nullptr; }

    private:
        std::vector<SdpVideoFormat> formats_;
    };

    // Two implementations of the same codec: the hardware one is used, whatever implementation_name says (in a
    // negotiated format it names the remote peer's decoder).
    TEST(FindCodecFactoryTest, PrefersHardwareImplementations)
    {
        std::map<std::string, std::unique_ptr<VideoEncoderFactory>> factories;
        factories.emplace(
            kInternalImpl,
            std::make_unique<FakeEncoderFactory>(std::vector<SdpVideoFormat> { SdpVideoFormat::VP8(), SdpVideoFormat::AV1Profile0() }));
        factories.emplace(
            kNvCodecImpl, std::make_unique<FakeEncoderFactory>(std::vector<SdpVideoFormat> { SdpVideoFormat::AV1Profile0() }));
        VideoEncoderFactory* internal = factories[kInternalImpl].get();
        VideoEncoderFactory* nvcodec = factories[kNvCodecImpl].get();

        SdpVideoFormat av1 = SdpVideoFormat::AV1Profile0();
        EXPECT_EQ(FindCodecFactory(factories, av1), nvcodec);
        av1.parameters[kSdpKeyNameCodecImpl] = kInternalImpl;
        EXPECT_EQ(FindCodecFactory(factories, av1), nvcodec);

        // Codecs only the internal factory has.
        EXPECT_EQ(FindCodecFactory(factories, SdpVideoFormat::VP8()), internal);
        EXPECT_EQ(FindCodecFactory(factories, SdpVideoFormat::VP9Profile0()), nullptr);
    }

    INSTANTIATE_TEST_SUITE_P(GfxDevice, CreateVideoCodecFactoryTest, testing::ValuesIn(supportedGfxDevices));
} // namespace webrtc
} // namespace unity
