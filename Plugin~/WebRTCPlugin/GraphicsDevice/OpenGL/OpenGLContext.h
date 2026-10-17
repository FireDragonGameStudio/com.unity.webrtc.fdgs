#pragma once

namespace unity
{
namespace webrtc
{
    class OpenGLContext
    {
    public:
        virtual ~OpenGLContext() = default;

        // Call the function on the render thread in Unity.
        // Returns false when the display could not be initialized.
        static bool Init();

        // Create the context related the thread.
        // Returns nullptr when the context could not be created.
        static std::unique_ptr<OpenGLContext> CreateGLContext(const OpenGLContext* shared = nullptr);

        // Whether the context has been created on the thread.
        static std::unique_ptr<OpenGLContext> CurrentContext();

        virtual bool IsValid() const = 0;
    };
}
}
