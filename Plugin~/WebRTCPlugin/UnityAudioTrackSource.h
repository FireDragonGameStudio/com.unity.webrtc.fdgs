#pragma once

#include <mutex>

#include <api/media_stream_interface.h>
#include <pc/local_audio_source.h>

namespace unity
{
namespace webrtc
{
    using namespace ::webrtc;

    class UnityAudioTrackSource : public LocalAudioSource
    {
    public:
        static ::webrtc::scoped_refptr<UnityAudioTrackSource> Create();
        static ::webrtc::scoped_refptr<UnityAudioTrackSource> Create(const ::webrtc::AudioOptions& audio_options);

        const ::webrtc::AudioOptions options() const override { return _options; }
        void AddSink(AudioTrackSinkInterface* sink) override;
        void RemoveSink(AudioTrackSinkInterface* sink) override;

        void PushAudioData(const float* pAudioData, int nSampleRate, size_t nNumChannels, size_t nNumFrames);

    protected:
        UnityAudioTrackSource();
        UnityAudioTrackSource(const ::webrtc::AudioOptions& audio_options);

        ~UnityAudioTrackSource() override;

    private:
        std::vector<int16_t> _convertedAudioData;
        std::vector<AudioTrackSinkInterface*> _arrSink;
        std::mutex _mutex;
        ::webrtc::AudioOptions _options;
        int _sampleRate = 0;
        size_t _numChannels = 0;
        size_t _numFrames = 0;
    };
} // end namespace webrtc
} // end namespace unity
