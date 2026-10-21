# High resolutions

Video tracks are not limited to a fixed resolution. Whether a size can be streamed depends on the codec that is negotiated and on the hardware. This page explains the limits, the bitrate and how to keep the resolution, for example for 4K, cubemap or 360° video.

## Size limits

[`WebRTC.enableLimitTextureSize`](../api/Unity.WebRTC.WebRTC.html#Unity_WebRTC_WebRTC_enableLimitTextureSize) (enabled by default) only rejects textures larger than [`SystemInfo.maxTextureSize`](https://docs.unity3d.com/ScriptReference/SystemInfo-maxTextureSize.html) and smaller than the minimum sizes some encoders and devices need. The encoder checks every other limit when it is initialized. If it cannot encode the size, it logs why, and WebRTC switches to the next codec that was negotiated with the remote peer.

| Codec | Encoder | Maximum size |
| ----- | ------- | ------------ |
| H.264 | NVIDIA hardware encoder (Windows, Linux) | H.264 level 5.2: 36,864 macroblocks of 16x16 pixels per frame, e.g. 3840x2160 or 4096x2304, and at most 4096 pixels per side. |
| H.264 | VideoToolbox (macOS, iOS), MediaCodec (Android) | H.264 level 5.2 as above; the hardware of the device may support less. |
| VP8 | Software (libvpx) | 16383 pixels per side. Encoding above 1080p needs a fast CPU. |
| VP9 | Software (libvpx) | 65535 pixels per side. Encoding above 1080p needs a fast CPU. |
| AV1 | Software (libaom) | 65535 pixels per side. The most CPU intensive of the codecs. |

The receiver needs a decoder for the size, too. The NVIDIA hardware decoder handles H.264 up to 4096x4096; the software decoders for VP8, VP9 and AV1 have no practical limit. Browsers decode H.264 up to level 5.2.

To stream above 4096 pixels per side or above 36,864 macroblocks, use VP9 or AV1 with [`RTCRtpTransceiver.SetCodecPreferences`](../api/Unity.WebRTC.RTCRtpTransceiver.html#Unity_WebRTC_RTCRtpTransceiver_SetCodecPreferences_Unity_WebRTC_RTCRtpCodecCapability___) and make sure the sending machine can encode it in real time.

## Bitrate

A video encoding without [`maxBitrate`](../api/Unity.WebRTC.RTCRtpEncodingParameters.html#Unity_WebRTC_RTCRtpEncodingParameters_maxBitrate) gets a default based on the track size: 0.07 bits per pixel and frame at the encoding's `maxFramerate` (60 if not set), at most 100 Mbps. For example:

| Size | 30 fps | 60 fps |
| ---- | ------ | ------ |
| 1920x1080 | 4.4 Mbps | 8.7 Mbps |
| 3840x2160 | 17.4 Mbps | 34.8 Mbps |
| 4096x2048 | 17.6 Mbps | 35.2 Mbps |

Small tracks keep WebRTC's own default (at most 2.5 Mbps). The default is a maximum: the actual bitrate follows the bandwidth WebRTC measures between the peers. To use another maximum, set `maxBitrate` yourself; the package never replaces a bitrate set by the application.

```CSharp
var parameters = sender.GetParameters();
foreach (var encoding in parameters.encodings)
{
    encoding.maxBitrate = 40_000_000; // 40 Mbps
    encoding.maxFramerate = 30;
}
sender.SetParameters(parameters);
```

## Keeping the resolution

When the CPU or the network cannot keep up, WebRTC lowers the resolution of a video track by default. For cubemaps and 360° video, a lower frame rate is usually better than a lower resolution. Set [`RTCRtpSendParameters.degradationPreference`](../api/Unity.WebRTC.RTCRtpSendParameters.html#Unity_WebRTC_RTCRtpSendParameters_degradationPreference) to `MaintainResolution`:

```CSharp
var parameters = sender.GetParameters();
parameters.degradationPreference = RTCDegradationPreference.MaintainResolution;
sender.SetParameters(parameters);
```

`MaintainResolution` also keeps WebRTC from starting with a downscaled stream while the bandwidth estimate ramps up after connecting.

## Layouts for 360° and cubemap video

Pick a layout that fits the limits of the codec you need. For H.264, which every browser can decode, the frame must stay within 36,864 macroblocks and 4096 pixels per side:

| Layout | Example size | Fits H.264 level 5.2 |
| ------ | ------------ | -------------------- |
| Equirectangular, 2:1 | 4096x2048 | Yes |
| Equirectangular stereo, top-bottom 1:1 | 2880x2880 | Yes |
| Equirectangular stereo, top-bottom 1:1 | 4096x4096 | No, use VP9 or AV1 |
| Cubemap, 3x2 faces of 1216x1216 | 3648x2432 | Yes |
| Cubemap, 3x2 faces of 1280x1280 | 3840x2560 | No (38,400 macroblocks) |
