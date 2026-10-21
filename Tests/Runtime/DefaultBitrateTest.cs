using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace Unity.WebRTC.RuntimeTest
{
    class DefaultBitrateTest
    {
        [Test]
        public void SmallSizesKeepTheLibwebrtcDefault()
        {
            Assert.That(RTCRtpSender.DefaultMaxBitrate(256, 256, null), Is.Null);
            Assert.That(RTCRtpSender.DefaultMaxBitrate(640, 360, null), Is.Null);
            Assert.That(RTCRtpSender.DefaultMaxBitrate(1280, 720, 15), Is.Null);
            Assert.That(RTCRtpSender.DefaultMaxBitrate(0, 1080, null), Is.Null);
        }

        [Test]
        public void ScalesWithSizeAndFramerate()
        {
            // 0.07 bits per pixel and frame, 60 fps when the encoding has no maxFramerate.
            Assert.That(RTCRtpSender.DefaultMaxBitrate(1920, 1080, null), Is.EqualTo(8709120));
            Assert.That(RTCRtpSender.DefaultMaxBitrate(3840, 2160, 30), Is.EqualTo(17418240));
            Assert.That(RTCRtpSender.DefaultMaxBitrate(4096, 2048, 60), Is.EqualTo(35232153));
        }

        [Test]
        public void IsCapped()
        {
            Assert.That(RTCRtpSender.DefaultMaxBitrate(7680, 4320, 60), Is.EqualTo(RTCRtpSender.MaxDefaultBitrate));
        }

        static RenderTexture CreateTexture(int width, int height)
        {
            var format = WebRTC.GetSupportedRenderTextureFormat(SystemInfo.graphicsDeviceType);
            var rt = new RenderTexture(width, height, 0, format);
            rt.Create();
            return rt;
        }

        [Test]
        [ConditionalIgnore(ConditionalIgnore.UnsupportedPlatformOpenGL, "Not support VideoStreamTrack for OpenGL or without a graphics device")]
        public void AddTrackSetsTheDefault()
        {
            var peer = new RTCPeerConnection();
            var rt = CreateTexture(1920, 1080);
            var track = new VideoStreamTrack(rt);
            var sender = peer.AddTrack(track);

            Assert.That(sender.GetParameters().encodings[0].maxBitrate, Is.EqualTo(8709120));

            track.Dispose();
            peer.Dispose();
            Object.DestroyImmediate(rt);
        }

        [Test]
        [ConditionalIgnore(ConditionalIgnore.UnsupportedPlatformOpenGL, "Not support VideoStreamTrack for OpenGL or without a graphics device")]
        public void ReplaceTrackUpdatesOnlyTheDefault()
        {
            var peer = new RTCPeerConnection();
            var rt1 = CreateTexture(1920, 1080);
            var rt2 = CreateTexture(3840, 2160);
            var track1 = new VideoStreamTrack(rt1);
            var track2 = new VideoStreamTrack(rt2);
            var transceiver = peer.AddTransceiver(track1);
            var sender = transceiver.Sender;

            Assert.That(sender.ReplaceTrack(track2), Is.True);
            Assert.That(sender.GetParameters().encodings[0].maxBitrate, Is.EqualTo(34836480));

            // A bitrate set by the application is kept.
            var parameters = sender.GetParameters();
            parameters.encodings[0].maxBitrate = 5000000;
            Assert.That(sender.SetParameters(parameters).errorType, Is.EqualTo(RTCErrorType.None));
            Assert.That(sender.ReplaceTrack(track1), Is.True);
            Assert.That(sender.GetParameters().encodings[0].maxBitrate, Is.EqualTo(5000000));

            // Setting it back to null restores the default.
            parameters = sender.GetParameters();
            parameters.encodings[0].maxBitrate = null;
            Assert.That(sender.SetParameters(parameters).errorType, Is.EqualTo(RTCErrorType.None));
            Assert.That(sender.GetParameters().encodings[0].maxBitrate, Is.EqualTo(8709120));

            track1.Dispose();
            track2.Dispose();
            peer.Dispose();
            Object.DestroyImmediate(rt1);
            Object.DestroyImmediate(rt2);
        }
    }
}
