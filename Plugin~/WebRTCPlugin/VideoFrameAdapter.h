#pragma once

#include <api/array_view.h>
#include <api/video/video_frame.h>
#include <vector>

#include "VideoFrame.h"

namespace unity
{
namespace webrtc
{

    using namespace ::webrtc;

    class ScalableBufferInterface : public VideoFrameBuffer
    {
    public:
        virtual bool scaled() const = 0;

    protected:
        ~ScalableBufferInterface() override { }
    };

    class VideoFrameAdapter : public ScalableBufferInterface
    {
    public:
        class ScaledBuffer : public ScalableBufferInterface
        {
        public:
            ScaledBuffer(::webrtc::scoped_refptr<VideoFrameAdapter> parent, int width, int height);
            ~ScaledBuffer() override;

            VideoFrameBuffer::Type type() const override;
            int width() const override { return width_; }
            int height() const override { return height_; }
            bool scaled() const final { return true; }

            ::webrtc::scoped_refptr<webrtc::I420BufferInterface> ToI420() override;
            const webrtc::I420BufferInterface* GetI420() const override;

            ::webrtc::scoped_refptr<webrtc::VideoFrameBuffer>
            GetMappedFrameBuffer(::webrtc::ArrayView<webrtc::VideoFrameBuffer::Type> types) override;

            ::webrtc::scoped_refptr<VideoFrame> GetVideoFrame() const { return parent_->frame_; }

            ::webrtc::scoped_refptr<webrtc::VideoFrameBuffer> CropAndScale(
                int offset_x, int offset_y, int crop_width, int crop_height, int scaled_width, int scaled_height)
                override;

        private:
            const ::webrtc::scoped_refptr<VideoFrameAdapter> parent_;
            const int width_;
            const int height_;
        };

        explicit VideoFrameAdapter(::webrtc::scoped_refptr<VideoFrame> frame);

        static ::webrtc::VideoFrame CreateVideoFrame(::webrtc::scoped_refptr<VideoFrame> frame);

        ::webrtc::scoped_refptr<VideoFrame> GetVideoFrame() const { return frame_; }

        VideoFrameBuffer::Type type() const override;
        int width() const override { return size_.width(); }
        int height() const override { return size_.height(); }
        bool scaled() const override { return false; }

        const I420BufferInterface* GetI420() const override;
        ::webrtc::scoped_refptr<I420BufferInterface> ToI420() override;
        ::webrtc::scoped_refptr<webrtc::VideoFrameBuffer> CropAndScale(
            int offset_x, int offset_y, int crop_width, int crop_height, int scaled_width, int scaled_height) override;

    protected:
        ~VideoFrameAdapter() override { }

    private:
        ::webrtc::scoped_refptr<webrtc::VideoFrameBuffer> GetOrCreateFrameBufferForSize(const Size& size);
        ::webrtc::scoped_refptr<I420BufferInterface>
        ConvertToVideoFrameBuffer(::webrtc::scoped_refptr<VideoFrame> video_frame) const;
        // todo(kazuki):
        // Need this buffer because the type() method returns kI420.
        mutable ::webrtc::scoped_refptr<I420BufferInterface> i420Buffer_;
        std::vector<::webrtc::scoped_refptr<VideoFrameBuffer>> scaledI40Buffers_;
        const ::webrtc::scoped_refptr<VideoFrame> frame_;
        const Size size_;
        mutable std::mutex scaleLock_;
        mutable std::mutex convertLock_;
    };
}
}
