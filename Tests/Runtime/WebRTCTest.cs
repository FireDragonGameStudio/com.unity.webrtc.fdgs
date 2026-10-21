using NUnit.Framework;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.TestTools;

namespace Unity.WebRTC.RuntimeTest
{
    class WebRTCTest
    {
        [TearDown]
        public void TearDown()
        {
            WebRTC.Logger = Debug.unityLogger;
        }

        [Test]
        [ConditionalIgnore(ConditionalIgnore.NoGraphicsDevice, "Requires a graphics device to create textures")]
        public void GraphicsFormat()
        {
            var graphicsFormat = WebRTC.GetSupportedGraphicsFormat(SystemInfo.graphicsDeviceType);
            var renderTextureFormat = WebRTC.GetSupportedRenderTextureFormat(SystemInfo.graphicsDeviceType);
            var textureFormat = WebRTC.GetSupportedTextureFormat(SystemInfo.graphicsDeviceType);

            var rt = new RenderTexture(10, 10, 0, renderTextureFormat);
            rt.Create();
            Assert.That(rt.format, Is.EqualTo(renderTextureFormat),
                $"RenderTexture.format:{rt.format} not equal to supportedFormat:{renderTextureFormat}");
            Assert.That(rt.graphicsFormat, Is.EqualTo(graphicsFormat),
                $"RenderTexture.graphicsFormat:{rt.graphicsFormat} not equal to supportedFormat:{graphicsFormat}");

            var tx = new Texture2D(10, 10, textureFormat, false);
            Assert.That(tx.format, Is.EqualTo(textureFormat),
                $"RenderTexture.format:{tx.format} not equal to supportedFormat:{textureFormat}");
            Assert.That(tx.graphicsFormat, Is.EqualTo(graphicsFormat),
                $"RenderTexture.graphicsFormat:{tx.format} not equal to supportedFormat:{graphicsFormat}");

            Object.DestroyImmediate(rt);
            Object.DestroyImmediate(tx);
        }

#if WEBRTC_TEST_PROJECT
        [Test]
        [UnityPlatform(exclude = new[] {RuntimePlatform.Android, RuntimePlatform.IPhonePlayer})]
        [ConditionalIgnore(ConditionalIgnore.UnsupportedPlatformOpenGL,
            "Not support VideoStreamTrack for OpenGL or without a graphics device")]
        public void WebCamTextureFormat()
        {
            var webCam = new WebCamTexture(10, 10);
            Assert.That(() => WebRTC.ValidateGraphicsFormat(webCam.graphicsFormat), Throws.Nothing);
            Object.DestroyImmediate(webCam);
        }
#endif

        [Test]
        [TestCase(256, 256)]
        [TestCase(640, 360)]
        [TestCase(1280, 720)]
        [TestCase(1920, 1080)]
        [TestCase(3840, 2160)]
        [TestCase(360, 640)]
        [TestCase(720, 1280)]
        [TestCase(1080, 1920)]
        [TestCase(2160, 3840)]
        [TestCase(4096, 2048)]
        [TestCase(4096, 4096)]
        [TestCase(7680, 4320)]
        public void ValidateTextureSize(int width, int height)
        {
            if (!WebRTC.enableLimitTextureSize)
                WebRTC.enableLimitTextureSize = true;

            var platform = Application.platform;
            var error = WebRTC.ValidateTextureSize(width, height, platform);
            Assert.That(error.errorType, Is.EqualTo(RTCErrorType.None));
        }

        [TestCase(1920, 1080)]
        [TestCase(3841, 2161)] // over max count
        public void DisableLimitTextureSize(int width, int height)
        {
            if (WebRTC.enableLimitTextureSize)
                WebRTC.enableLimitTextureSize = false;

            var platform = Application.platform;
            var error = WebRTC.ValidateTextureSize(width, height, platform);
            Assert.That(error.errorType, Is.EqualTo(RTCErrorType.None));
        }

        [Test]
        [TestCase(1, 0)]
        [TestCase(0, 1)]
        public void ErrorOnValidateTextureSizeOverMaxTextureSize(int widthOver, int heightOver)
        {
            if (SystemInfo.maxTextureSize <= 0)
                Assert.Ignore("The graphics device reports no maximum texture size.");
            if (!WebRTC.enableLimitTextureSize)
                WebRTC.enableLimitTextureSize = true;

            int width = Mathf.Min(SystemInfo.maxTextureSize, 1920) + widthOver * SystemInfo.maxTextureSize;
            int height = Mathf.Min(SystemInfo.maxTextureSize, 1080) + heightOver * SystemInfo.maxTextureSize;
            var error = WebRTC.ValidateTextureSize(width, height, Application.platform);
            Assert.That(error.errorType, Is.EqualTo(RTCErrorType.InvalidRange));
        }

        [Test]
        [ConditionalIgnore(ConditionalIgnore.NoGraphicsDevice, "Requires a graphics device to create textures")]
        public void ValidateGraphicsFormat()
        {
            var format = WebRTC.GetSupportedGraphicsFormat(SystemInfo.graphicsDeviceType);
            Assert.That(() => WebRTC.ValidateGraphicsFormat(format), Throws.Nothing);
        }

        [Test]
        [TestCase((GraphicsFormat)87)] //LegacyARGB32_sRGB
        [TestCase((GraphicsFormat)88)] //LegacyARGB32_UNorm
        public void ValidateLegacyGraphicsFormat(GraphicsFormat format)
        {
            Assert.That(() => WebRTC.ValidateGraphicsFormat(format), Throws.Nothing);
        }

        [Test]
        public void EnableLogging()
        {
            Assert.DoesNotThrow(() => WebRTC.ConfigureNativeLogging(true, NativeLoggingSeverity.Verbose));
            Assert.DoesNotThrow(() => WebRTC.ConfigureNativeLogging(false, NativeLoggingSeverity.None));
        }

        [Test]
        public void Logger()
        {
            Assert.NotNull(WebRTC.Logger);
            Assert.AreEqual(WebRTC.Logger, Debug.unityLogger);

            Assert.That(() => WebRTC.Logger = null, Throws.ArgumentNullException);

            MockLogger logger = new MockLogger();
            Assert.That(() => WebRTC.Logger = logger, Throws.Nothing);
            Assert.AreEqual(logger, WebRTC.Logger);

            Assert.That(() => WebRTC.Logger = Debug.unityLogger, Throws.Nothing);
        }

        [Test]
        public void UpdateWithoutContext()
        {
            var update = WebRTC.Update();
            // Runs to the first yield.
            Assert.That(update.MoveNext(), Is.True);

            WebRTC.DisposeInternal();
            try
            {
                Assert.That(() => update.MoveNext(), Throws.Nothing);
            }
            finally
            {
                WebRTC.InitializeInternal();
            }
            Assert.That(() => update.MoveNext(), Throws.Nothing);
        }

        [Test]
        public void SyncTimeout()
        {
            Assert.DoesNotThrow(() => WebRTC.SetGraphicsSyncTimeout(1));
            Assert.DoesNotThrow(() => WebRTC.SetGraphicsSyncTimeout(60 * 1000 * 1000));
        }
    }
}
