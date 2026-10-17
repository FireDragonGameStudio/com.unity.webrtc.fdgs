#include "pch.h"

#if SUPPORT_OPENGL_ES
#include <EGL/egl.h>
#endif

#include "OpenGLContext.h"

namespace unity
{
namespace webrtc
{
#if SUPPORT_OPENGL_ES
    class EGLContextImpl : public OpenGLContext
    {
    public:
        EGLContextImpl(EGLContext sharedCtx = 0)
            : context_(EGL_NO_CONTEXT)
            , created_(false)
        {
            // Return if the context is already created.
            context_ = eglGetCurrentContext();
            if (context_ != EGL_NO_CONTEXT)
                return;

            if (display == EGL_NO_DISPLAY)
            {
                RTC_LOG(LS_ERROR) << "EGL display is not initialized.";
                return;
            }

            int count = 0;
            if (!eglGetConfigs(display, 0, 0, &count) || count <= 0)
            {
                RTC_LOG(LS_ERROR) << "eglGetConfigs failed:" << eglGetError();
                return;
            }
            std::vector<EGLConfig> configs(count);
            eglGetConfigs(display, configs.data(), count, &count);
            EGLint contextAttr[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
            EGLContext context = eglCreateContext(display, configs[0], sharedCtx, contextAttr);
            if (context == EGL_NO_CONTEXT)
            {
                RTC_LOG(LS_ERROR) << "eglCreateContext failed:" << eglGetError();
                return;
            }

            if (!eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, context))
            {
                RTC_LOG(LS_ERROR) << "eglMakeCurrent failed:" << eglGetError();
                eglDestroyContext(display, context);
                return;
            }
            context_ = context;
            created_ = true;
        }
        ~EGLContextImpl() override
        {
            if (created_)
            {
                eglDestroyContext(display, context_);
            }
        }
        bool IsValid() const override { return context_ != EGL_NO_CONTEXT; }
        EGLContext context() const { return context_; }

        static EGLDisplay display;

    private:
        EGLContext context_;
        // In Unity, this flag is false because the context already created which rely on the render thread.
        bool created_;
    };
    EGLDisplay EGLContextImpl::display = EGL_NO_DISPLAY;
#endif

#if SUPPORT_OPENGL_CORE && UNITY_LINUX
    class GLXContextImpl : public OpenGLContext
    {
    public:
        GLXContextImpl(GLXContext sharedCtx = 0)
            : pbuffer_(0)
            , context_(nullptr)
            , created_(false)
        {
            // Return if the context is already created.
            context_ = glXGetCurrentContext();
            if (context_ != nullptr)
                return;

            if (display == nullptr)
            {
                RTC_LOG(LS_ERROR) << "X display is not initialized.";
                return;
            }

            static int dblBuf[] = { GLX_RGBA, GLX_DEPTH_SIZE, 16, GLX_DOUBLEBUFFER, None };
            XVisualInfo* vi = glXChooseVisual(display, DefaultScreen(display), dblBuf);
            if (vi == nullptr)
            {
                RTC_LOG(LS_ERROR) << "glXChooseVisual failed";
                return;
            }
            GLXContext context = glXCreateContext(display, vi, sharedCtx, GL_TRUE);
            XFree(vi);
            if (context == nullptr)
            {
                RTC_LOG(LS_ERROR) << "glXCreateContext failed";
                return;
            }

            const int visualAttrs[] = { None };
            const int attrs[] = { GLX_PBUFFER_WIDTH, 1, GLX_PBUFFER_HEIGHT, 1, None };

            int returnedElements = 0;
            GLXFBConfig* configs = glXChooseFBConfig(display, DefaultScreen(display), visualAttrs, &returnedElements);
            if (configs == nullptr || returnedElements <= 0)
            {
                RTC_LOG(LS_ERROR) << "glXChooseFBConfig failed";
                if (configs != nullptr)
                    XFree(configs);
                glXDestroyContext(display, context);
                return;
            }
            GLXPbuffer pbuffer = glXCreatePbuffer(display, configs[0], attrs);
            XFree(configs);
            if (pbuffer == 0)
            {
                RTC_LOG(LS_ERROR) << "glXCreatePbuffer failed";
                glXDestroyContext(display, context);
                return;
            }
            if (!glXMakeContextCurrent(display, pbuffer, pbuffer, context))
            {
                RTC_LOG(LS_ERROR) << "glXMakeContextCurrent failed";
                glXDestroyPbuffer(display, pbuffer);
                glXDestroyContext(display, context);
                return;
            }
            pbuffer_ = pbuffer;
            context_ = context;
            created_ = true;
        }
        ~GLXContextImpl() override
        {
            // Only destroy what this object created; never the context owned by Unity's render thread.
            if (created_)
            {
                glXDestroyPbuffer(display, pbuffer_);
                glXDestroyContext(display, context_);
            }
        }

        bool IsValid() const override { return context_ != nullptr; }
        GLXContext context() const { return context_; }

        static Display* display;

    private:
        GLXPbuffer pbuffer_;
        GLXContext context_;
        // In Unity, this flag is false because the context already created which rely on the render thread.
        bool created_;
    };
    Display* GLXContextImpl::display = nullptr;

#endif

    bool OpenGLContext::Init()
    {
#if SUPPORT_OPENGL_ES
        EGLDisplay display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
        if (display == EGL_NO_DISPLAY)
        {
            RTC_LOG(LS_ERROR) << "eglGetDisplay failed:" << eglGetError();
            return false;
        }
        EGLint major, minor;
        if (!eglInitialize(display, &major, &minor))
        {
            RTC_LOG(LS_ERROR) << "eglInitialize failed:" << eglGetError();
            return false;
        }
        EGLContextImpl::display = display;
        return true;
#elif SUPPORT_OPENGL_CORE && UNITY_LINUX
        int version = gladLoaderLoadGL();
        if (!version)
        {
            RTC_LOG(LS_ERROR) << "gladLoaderLoadGL failed";
            return false;
        }

        Display* display = XOpenDisplay(nullptr);
        if (display == nullptr)
        {
            RTC_LOG(LS_ERROR) << "XOpenDisplay failed";
            return false;
        }

        int screen = DefaultScreen(display);
        int result = gladLoaderLoadGLX(display, screen);
        if (!result)
        {
            RTC_LOG(LS_ERROR) << "gladLoaderLoadGLX failed";
            XCloseDisplay(display);
            return false;
        }

        GLXContextImpl::display = display;
        return true;
#else
        return true;
#endif
    }

    std::unique_ptr<OpenGLContext> OpenGLContext::CurrentContext()
    {
#if SUPPORT_OPENGL_ES
        if (eglGetCurrentContext())
            return CreateGLContext();
        return nullptr;
#endif
#if SUPPORT_OPENGL_CORE && UNITY_LINUX
        if (glXGetCurrentContext())
            return CreateGLContext();
        return nullptr;
#endif
    }

    std::unique_ptr<OpenGLContext> OpenGLContext::CreateGLContext(const OpenGLContext* shared)
    {
        std::unique_ptr<OpenGLContext> created;
#if SUPPORT_OPENGL_ES
        const EGLContextImpl* context = static_cast<const EGLContextImpl*>(shared);
        EGLContext eglContext = context ? context->context() : EGL_NO_CONTEXT;
        created = std::make_unique<EGLContextImpl>(eglContext);
#endif
#if SUPPORT_OPENGL_CORE && UNITY_LINUX
        const GLXContextImpl* context = static_cast<const GLXContextImpl*>(shared);
        GLXContext glxContext = context ? context->context() : nullptr;
        created = std::make_unique<GLXContextImpl>(glxContext);
#endif
        if (!created || !created->IsValid())
            return nullptr;
        return created;
    }

}
}
