using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.Rendering;
using UnityEngine.SceneManagement;
#if ENABLE_INPUT_SYSTEM && WEBRTC_SAMPLES_INPUT_SYSTEM
using UnityEngine.InputSystem.UI;
#endif

namespace Unity.WebRTC.Samples
{
    /// <summary>
    /// Adapts each sample scene to the project when it is loaded, so the samples work in projects that use the
    /// Input System package or a scriptable render pipeline (URP, HDRP) without editing the scenes:
    /// <list type="bullet">
    /// <item>Replaces StandaloneInputModule with InputSystemUIInputModule when only the Input System is enabled.</item>
    /// <item>Replaces the built-in default material, which renders pink in a scriptable render pipeline,
    /// with the default material of the active render pipeline.</item>
    /// </list>
    /// </summary>
    internal static class SampleSceneSetup
    {
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
        static void Initialize()
        {
            SceneManager.sceneLoaded -= OnSceneLoaded;
            SceneManager.sceneLoaded += OnSceneLoaded;
        }

        static void OnSceneLoaded(Scene scene, LoadSceneMode mode)
        {
            if (!IsSampleScene(scene))
                return;

            foreach (var root in scene.GetRootGameObjects())
            {
                ReplaceInputModules(root);
                ReplaceBuiltinMaterials(root);
            }
        }

        // Only touch the scenes of these samples, never other scenes of the project.
        static bool IsSampleScene(Scene scene)
        {
            foreach (var root in scene.GetRootGameObjects())
            {
                if (root.GetComponentInChildren<BackButton>(true) != null ||
                    root.GetComponentInChildren<SceneSelectUI>(true) != null)
                    return true;
            }
            return false;
        }

        static void ReplaceInputModules(GameObject root)
        {
#if ENABLE_INPUT_SYSTEM && !ENABLE_LEGACY_INPUT_MANAGER && WEBRTC_SAMPLES_INPUT_SYSTEM
            foreach (var module in root.GetComponentsInChildren<StandaloneInputModule>(true))
            {
                var gameObject = module.gameObject;
                Object.DestroyImmediate(module);
                if (gameObject.GetComponent<InputSystemUIInputModule>() == null)
                    gameObject.AddComponent<InputSystemUIInputModule>();
            }
#endif
        }

        static void ReplaceBuiltinMaterials(GameObject root)
        {
            var pipeline = GraphicsSettings.currentRenderPipeline;
            if (pipeline == null || pipeline.defaultMaterial == null)
                return;

            foreach (var renderer in root.GetComponentsInChildren<MeshRenderer>(true))
            {
                var materials = renderer.sharedMaterials;
                var changed = false;
                for (var i = 0; i < materials.Length; i++)
                {
                    if (IsBuiltinMaterial(materials[i]))
                    {
                        materials[i] = pipeline.defaultMaterial;
                        changed = true;
                    }
                }
                if (changed)
                    renderer.sharedMaterials = materials;
            }
        }

        // The scenes use the built-in "Default-Material" with the built-in render pipeline's "Standard" shader.
        static bool IsBuiltinMaterial(Material material)
        {
            return material == null || material.shader == null || !material.shader.isSupported ||
                material.shader.name == "Standard";
        }
    }
}
