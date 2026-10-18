#include "pch.h"

#include "PeerConnectionObject.h"
#include "PeerConnectionStatsCollectorCallback.h"

namespace unity
{
namespace webrtc
{
    DelegateCollectStats PeerConnectionStatsCollectorCallback::s_collectStatsCallback = nullptr;

    ::webrtc::scoped_refptr<PeerConnectionStatsCollectorCallback>
    PeerConnectionStatsCollectorCallback::Create(PeerConnectionObject* connection)
    {
        return ::webrtc::make_ref_counted<PeerConnectionStatsCollectorCallback>(connection);
    }
    void PeerConnectionStatsCollectorCallback::OnStatsDelivered(
        const ::webrtc::scoped_refptr<const webrtc::RTCStatsReport>& report)
    {
        m_owner->ReceiveStatsReport(report);
        s_collectStatsCallback(m_owner, this, report.get());
    }
} // end namespace webrtc
} // end namespace unity
