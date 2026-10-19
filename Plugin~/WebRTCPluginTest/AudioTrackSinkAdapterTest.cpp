#include "pch.h"

#include <cmath>

#include <common_audio/include/audio_util.h>

#include "AudioTrackSinkAdapter.h"

namespace unity
{
namespace webrtc
{
    namespace
    {
        constexpr double kPi = 3.14159265358979323846;

        // 10 ms of a 1 kHz tone, interleaved.
        std::vector<int16_t> Tone(int sampleRate, size_t channels, size_t offset)
        {
            const size_t frames = static_cast<size_t>(sampleRate / 100);
            std::vector<int16_t> data(frames * channels);
            for (size_t i = 0; i < frames; i++)
            {
                const double t = static_cast<double>(offset + i) / sampleRate;
                const auto value = static_cast<int16_t>(10000 * std::sin(2 * kPi * 1000 * t));
                for (size_t c = 0; c < channels; c++)
                    data[i * channels + c] = value;
            }
            return data;
        }

        size_t CountNonZero(const std::vector<float>& data)
        {
            size_t count = 0;
            for (float value : data)
                count += value != 0.0f;
            return count;
        }
    } // namespace

    // Unity reads stereo at 48 kHz, 1024 frames per OnAudioFilterRead call.
    constexpr size_t kUnityChannels = 2;
    constexpr int32_t kUnitySampleRate = 48000;
    constexpr size_t kUnityLength = 1024 * kUnityChannels;

    TEST(AudioTrackSinkAdapterTest, OnDataBeforeProcessAudioIsDropped)
    {
        AudioTrackSinkAdapter adapter;
        const auto tone = Tone(48000, 2, 0);
        adapter.OnData(tone.data(), 16, 48000, 2, tone.size() / 2);

        std::vector<float> out(kUnityLength, 1.0f);
        adapter.ProcessAudio(out.data(), out.size(), kUnityChannels, kUnitySampleRate);
        EXPECT_EQ(CountNonZero(out), 0u);
    }

    TEST(AudioTrackSinkAdapterTest, CopiesAudioInUnityFormat)
    {
        AudioTrackSinkAdapter adapter;
        std::vector<float> out(kUnityLength);
        adapter.ProcessAudio(out.data(), out.size(), kUnityChannels, kUnitySampleRate);

        const auto tone = Tone(kUnitySampleRate, kUnityChannels, 0);
        adapter.OnData(tone.data(), 16, kUnitySampleRate, kUnityChannels, tone.size() / kUnityChannels);

        adapter.ProcessAudio(out.data(), out.size(), kUnityChannels, kUnitySampleRate);
        for (size_t i = 0; i < tone.size(); i++)
            ASSERT_FLOAT_EQ(out[i], S16ToFloat(tone[i])) << "sample " << i;
        for (size_t i = tone.size(); i < out.size(); i++)
            ASSERT_EQ(out[i], 0.0f) << "sample " << i;
    }

    // Resampling into an AudioFrame without a sample count aborted the process (M156 regression).
    TEST(AudioTrackSinkAdapterTest, ResamplesAndUpmixesMonoAudio)
    {
        AudioTrackSinkAdapter adapter;
        std::vector<float> out(kUnityLength);
        adapter.ProcessAudio(out.data(), out.size(), kUnityChannels, kUnitySampleRate);

        constexpr int kSampleRate = 16000;
        constexpr size_t kChunks = 5;
        for (size_t chunk = 0; chunk < kChunks; chunk++)
        {
            const auto tone = Tone(kSampleRate, 1, chunk * kSampleRate / 100);
            adapter.OnData(tone.data(), 16, kSampleRate, 1, tone.size());
        }

        adapter.ProcessAudio(out.data(), out.size(), kUnityChannels, kUnitySampleRate);
        // 50 ms at 48 kHz stereo; the resampler delays the start a little.
        EXPECT_GT(CountNonZero(out), kUnityLength / 2);
        for (size_t i = 0; i < out.size(); i += kUnityChannels)
            ASSERT_EQ(out[i], out[i + 1]) << "frame " << i / kUnityChannels;
    }

    TEST(AudioTrackSinkAdapterTest, IgnoresChunksThatAreNot10ms)
    {
        AudioTrackSinkAdapter adapter;
        std::vector<float> out(kUnityLength);
        adapter.ProcessAudio(out.data(), out.size(), kUnityChannels, kUnitySampleRate);

        const auto tone = Tone(kUnitySampleRate, kUnityChannels, 0);
        adapter.OnData(tone.data(), 16, kUnitySampleRate, kUnityChannels, tone.size() / kUnityChannels / 2);

        adapter.ProcessAudio(out.data(), out.size(), kUnityChannels, kUnitySampleRate);
        EXPECT_EQ(CountNonZero(out), 0u);
    }
} // end namespace webrtc
} // end namespace unity
