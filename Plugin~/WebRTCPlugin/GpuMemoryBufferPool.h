#pragma once

#include <limits>
#include <list>
#include <system_wrappers/include/clock.h>

#include "GpuMemoryBuffer.h"
#include "Size.h"
#include "VideoFrame.h"

namespace unity
{
namespace webrtc
{
    class GpuMemoryBufferPool
    {
    public:
        // The pool holds at most maxBufferCount buffers. Once it is full, an unused buffer that is not compatible
        // with a new frame is released to make room for it; if there is none, CreateFrame returns nullptr.
        // A buffer is only reused for frames of the same owner (the video track source): an encoder may still read
        // a returned buffer asynchronously, and another track must not overwrite it.
        GpuMemoryBufferPool(
            IGraphicsDevice* device, Clock* clock, size_t maxBufferCount = std::numeric_limits<size_t>::max());
        GpuMemoryBufferPool(const GpuMemoryBufferPool&) = delete;
        GpuMemoryBufferPool& operator=(const GpuMemoryBufferPool&) = delete;

        virtual ~GpuMemoryBufferPool();

        ::webrtc::scoped_refptr<VideoFrame> CreateFrame(
            NativeTexPtr ptr,
            const Size& size,
            UnityRenderingExtTextureFormat format,
            Timestamp timestamp,
            const void* owner = nullptr);
        void ReleaseStaleBuffers(Timestamp timestamp, TimeDelta timeLimit);

        size_t bufferCount() { return resourcesPool_.size(); }

    private:
        struct FrameResources
        {
            FrameResources(::webrtc::scoped_refptr<GpuMemoryBufferInterface> buffer, const void* owner)
                : buffer_(std::move(buffer))
                , owner_(owner)
                , isUsed_(false)
                , lastUsetime_(Timestamp::Zero())
            {
            }
            ::webrtc::scoped_refptr<GpuMemoryBufferInterface> buffer_;
            const void* const owner_;
            bool IsUsed() { return isUsed_; }
            void MarkUsed(Timestamp timestamp)
            {
                isUsed_ = true;
                lastUsetime_ = timestamp;
            }
            void MarkUnused(Timestamp timestamp)
            {
                isUsed_ = false;
                lastUsetime_ = timestamp;
            }
            Timestamp lastUseTime() { return lastUsetime_; }
            bool isUsed_;
            Timestamp lastUsetime_;
        };
        ::webrtc::scoped_refptr<GpuMemoryBufferInterface>
        GetOrCreateFrameResources(
            NativeTexPtr ptr, const Size& size, UnityRenderingExtTextureFormat format, const void* owner);
        void OnReturnBuffer(::webrtc::scoped_refptr<GpuMemoryBufferInterface> buffer);

        static bool AreFrameResourcesCompatible(
            const FrameResources* resources, const Size& size, UnityRenderingExtTextureFormat format, const void* owner);

        IGraphicsDevice* device_;
        std::mutex mutex_;
        std::list<std::unique_ptr<FrameResources>> resourcesPool_;
        Clock* const clock_;
        const size_t maxBufferCount_;
    };
}
}
