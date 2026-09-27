# VVC / H.266 playback

IINA supports software playback of Versatile Video Coding (VVC), also known as
H.266, through the native VVC decoder in FFmpeg and IINA's libmpv playback
stack. This support requires the FFmpeg 9.0.1 and mpv 0.41.0 dependencies used
by IINA 1.5 and later.

IINA's continuous integration test decodes the first frame of a VVC video in
an MP4 container. Other containers and stream formats depend on the demuxing
support provided by FFmpeg and mpv.

## Hardware decoding

VVC decoding on macOS currently uses the CPU. As of Xcode 27, Apple's CoreMedia
and VideoToolbox SDKs do not expose a VVC codec type, and FFmpeg does not
provide a VVC VideoToolbox decoder. Enabling IINA's hardware decoder setting
therefore does not accelerate VVC playback.

Software decoding can use substantial CPU resources, especially for
high-resolution or high-frame-rate video. Playback performance depends on the
video and the Mac.

## Confirming the active decoder

While the video is open, choose **Window > Inspector** and select **General**.
The video codec is shown as **H.266 / VVC (Versatile Video Coding)**. The
**Hw Decoder** field reports whether hardware decoding is active; it currently
reports **no** for VVC.
