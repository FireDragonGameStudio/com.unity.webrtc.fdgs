#pragma once

#include <string>

#include "WebRTCPlugin.h"

namespace unity
{
namespace webrtc
{

    class UnityLogStream : public ::webrtc::LogSink
    {
    public:
        UnityLogStream(DelegateDebugLog callback)
            : on_log_message(callback)
        {
        }

        // log format can be defined in this interface
        void OnLogMessage(const std::string& message) override;
        void OnLogMessage(const std::string& message, ::webrtc::LoggingSeverity severity) override;

        static void AddLogStream(DelegateDebugLog callback, ::webrtc::LoggingSeverity minLoggingSeverity);
        static void RemoveLogStream();

    private:
        DelegateDebugLog on_log_message;
        void logMessage(const std::string& message, ::webrtc::LoggingSeverity severity);

        static std::unique_ptr<UnityLogStream> log_stream;
    };

}
}
