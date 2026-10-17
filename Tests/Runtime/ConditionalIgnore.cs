using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.TestTools;

namespace Unity.WebRTC.RuntimeTest
{
    [AttributeUsage(AttributeTargets.All, AllowMultiple = true)]
    class ConditionalIgnoreMultipleAttribute : ConditionalIgnoreAttribute
    {
        public ConditionalIgnoreMultipleAttribute(string conditionKey, string ignoreReason)
            : base(conditionKey, ignoreReason)
        {
        }
    }


    internal class ConditionalIgnore
    {
        /// <summary>
        /// On Direct3D12 platform, CommandBuffer.IssuePluginCustomTextureUpdateV2 method doesn't work.
        /// </summary>
        public const string UnsupportedPlatformVideoDecoder = "IgnoreUnsupportedPlatformVideoDecoder";

        /// <summary>
        /// On Windows and macOS platform, VideoStreamTrack class doesn't work with OpenGL.
        /// It also doesn't work without a graphics device (-nographics).
        /// </summary>
        public const string UnsupportedPlatformOpenGL = "IgnoreUnsupportedPlatformOpenGL";

        /// <summary>
        /// Textures can't be created without a graphics device, e.g. on CI runners started with -nographics.
        /// </summary>
        public const string NoGraphicsDevice = "IgnoreNoGraphicsDevice";

        static bool s_loaded = false;

        // The test framework may build the PlayMode test tree in the Editor before entering Play Mode,
        // so register the mappings on Editor load too.
#if UNITY_EDITOR
        [UnityEditor.InitializeOnLoadMethod]
#endif
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
        static void OnLoad()
        {
            if (s_loaded)
                return;
            s_loaded = true;

#if !UNITY_2020_1_OR_NEWER
            ConditionalIgnoreAttribute.AddConditionalIgnoreMapping(UnsupportedPlatformVideoDecoder,
                SystemInfo.graphicsDeviceType == GraphicsDeviceType.Direct3D12);
#endif
            ConditionalIgnoreAttribute.AddConditionalIgnoreMapping(UnsupportedPlatformOpenGL,
                !VideoStreamTrack.IsSupported(Application.platform, SystemInfo.graphicsDeviceType));
            ConditionalIgnoreAttribute.AddConditionalIgnoreMapping(NoGraphicsDevice,
                SystemInfo.graphicsDeviceType == GraphicsDeviceType.Null);
        }
    }
}
