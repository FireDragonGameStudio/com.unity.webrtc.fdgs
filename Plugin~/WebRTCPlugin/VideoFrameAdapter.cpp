#include "pch.h"

#include <api/video/video_frame.h>

#include "VideoFrameAdapter.h"

namespace unity
{
namespace webrtc
{
    template<typename T>
    bool Contains(::webrtc::ArrayView<T> arr, T value)
    {
        for (auto e : arr)
        {
            if (e == value)
                return true;
        }
        return false;
    }

    ::webrtc::VideoFrame VideoFrameAdapter::CreateVideoFrame(::webrtc::scoped_refptr<VideoFrame> frame)
    {
        ::webrtc::scoped_refptr<VideoFrameAdapter> adapter(new ::webrtc::RefCountedObject<VideoFrameAdapter>(std::move(frame)));

        return ::webrtc::VideoFrame::Builder().set_video_frame_buffer(adapter).build();
    }

    VideoFrameAdapter::ScaledBuffer::ScaledBuffer(::webrtc::scoped_refptr<VideoFrameAdapter> parent, int width, int height)
        : parent_(parent)
        , width_(width)
        , height_(height)
    {
    }

    VideoFrameAdapter::ScaledBuffer::~ScaledBuffer() { }

    VideoFrameBuffer::Type VideoFrameAdapter::ScaledBuffer::type() const { return parent_->type(); }

    ::webrtc::scoped_refptr<webrtc::I420BufferInterface> VideoFrameAdapter::ScaledBuffer::ToI420()
    {
        auto buffer = parent_->GetOrCreateFrameBufferForSize(Size(width_, height_));
        return buffer ? buffer->ToI420() : nullptr;
    }

    const I420BufferInterface* VideoFrameAdapter::ScaledBuffer::GetI420() const
    {
        auto buffer = parent_->GetOrCreateFrameBufferForSize(Size(width_, height_));
        return buffer ? buffer->GetI420() : nullptr;
    }

    ::webrtc::scoped_refptr<VideoFrameBuffer>
    VideoFrameAdapter::ScaledBuffer::GetMappedFrameBuffer(::webrtc::ArrayView<VideoFrameBuffer::Type> types)
    {
        auto buffer = parent_->GetOrCreateFrameBufferForSize(Size(width_, height_));
        return buffer && Contains(types, buffer->type()) ? buffer : nullptr;
    }

    ::webrtc::scoped_refptr<VideoFrameBuffer> VideoFrameAdapter::ScaledBuffer::CropAndScale(
        int offset_x, int offset_y, int crop_width, int crop_height, int scaled_width, int scaled_height)
    {
        return ::webrtc::make_ref_counted<ScaledBuffer>(
            ::webrtc::scoped_refptr<VideoFrameAdapter>(parent_), scaled_width, scaled_height);
    }

    VideoFrameAdapter::VideoFrameAdapter(::webrtc::scoped_refptr<VideoFrame> frame)
        : frame_(std::move(frame))
        , size_(frame_->size())
    {
    }

    VideoFrameBuffer::Type VideoFrameAdapter::type() const
    {
#if UNITY_IOS || UNITY_OSX || UNITY_ANDROID
        // todo(kazuki): support for kNative type for mobile platform and macOS.
        // Need to pass ObjCFrameBuffer instead of VideoFrameAdapter on macOS/iOS.
        // Need to pass AndroidVideoBuffer instead of VideoFrameAdapter on Android.
        return VideoFrameBuffer::Type::kI420;
#else
        return VideoFrameBuffer::Type::kNative;
#endif
    }

    const I420BufferInterface* VideoFrameAdapter::GetI420() const
    {
        auto buffer = ConvertToVideoFrameBuffer(frame_);
        return buffer ? buffer->GetI420() : nullptr;
    }

    ::webrtc::scoped_refptr<I420BufferInterface> VideoFrameAdapter::ToI420()
    {
        auto buffer = ConvertToVideoFrameBuffer(frame_);
        return buffer ? buffer->ToI420() : nullptr;
    }

    ::webrtc::scoped_refptr<VideoFrameBuffer> VideoFrameAdapter::CropAndScale(
        int offset_x, int offset_y, int crop_width, int crop_height, int scaled_width, int scaled_height)
    {
        return ::webrtc::make_ref_counted<ScaledBuffer>(
            ::webrtc::scoped_refptr<VideoFrameAdapter>(this), scaled_width, scaled_height);
    }

    ::webrtc::scoped_refptr<VideoFrameBuffer> VideoFrameAdapter::GetOrCreateFrameBufferForSize(const Size& size)
    {
        std::unique_lock<std::mutex> guard(scaleLock_);

        for (auto scaledI420buffer : scaledI40Buffers_)
        {
            Size bufferSize(scaledI420buffer->width(), scaledI420buffer->height());
            if (size == bufferSize)
            {
                return scaledI420buffer;
            }
        }
        // The GPU readback can fail (e.g. WaitSync timeout), so don't scale or cache a missing frame.
        if (!ToI420())
            return nullptr;
        auto buffer = VideoFrameBuffer::CropAndScale(0, 0, width(), height(), size.width(), size.height());
        scaledI40Buffers_.push_back(buffer);
        return buffer;
    }

    ::webrtc::scoped_refptr<I420BufferInterface>
    VideoFrameAdapter::ConvertToVideoFrameBuffer(::webrtc::scoped_refptr<VideoFrame> video_frame) const
    {
        std::unique_lock<std::mutex> guard(convertLock_);
        if (i420Buffer_)
            return i420Buffer_;

        RTC_DCHECK(video_frame);
        RTC_DCHECK(video_frame->HasGpuMemoryBuffer());

        auto gmb = video_frame->GetGpuMemoryBuffer();
        i420Buffer_ = gmb->ToI420();
        return i420Buffer_;
    }

}
}
