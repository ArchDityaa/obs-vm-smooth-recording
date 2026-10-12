# VM + Wayland + PipeWire + RDP specifics

This is the environment the guide was built for, and the quirks that come with
it. If you run OBS on **real hardware** most of this does not apply to you.

## The setup

- **Host**: QEMU/KVM
- **Guest**: Zorin OS 17 / Ubuntu 24.04, GNOME 46, **Wayland** session
- **Display**: virtual monitor `Virtual-1` (`QEMU Monitor`), 1280×800 @ ~75 Hz
- **GPU** : none — software rendering (`llvmpipe` / `swrast`)
- **Remote access:** `gnome-remote-desktop` (RDP, port 3389)

## No hardware encoder

In a VM like this `vaapi` / `nv12`/`h264_vaapi` are usually **not available**
(the virtual GPU exposes no encode engine). OBS therefore *must* use the
**software x264 encoder**. Don't waste time hunting for VAAPI/NVENC options — the
only lever you have is making the software path cheap:

- don't scale (Base = Output),
- lower the frame rate,
- use a fast preset.

## Screen capture is PipeWire

On Wayland, OBS captures the screen through the **PipeWire screencast portal**.
The source is `pipewire-desktop-capture-source` and the negotiated format is
typically **BGRA** at the monitor's native size:

```
info: [pipewire] Negotiated format:
info: [pipewire]     Format: 12 (Spa:Enum:VideoFormat:BGRA)
info: [pipewire]     Size: 1280x800
info: [pipewire]     Framerate: 0/1
info: [pipewire] Stream ... state: "streaming" (error: none)
```

Notes:

- On first run you must **pick the monitor** in a dialog; OBS stores a
  `RestoreToken` for next time. If the monitor changes, re-select it.
- The reported `Framerate: 0/1` means "variable / as fast as damage occurs" —
  it is not an error.
- Under Wayland the capture mirrors the compositor's output; when the session is
  idle and the screen doesn't change, few frames arrive.

## RDP does not have to be disconnected

A common assumption is that RDP steals CPU and must be dropped while recording.
In this case study the final measurement (**0.0 % lagged frames, 30 fps**) was
taken **with RDP connected**. The compositor (`gnome-shell`) does raise CPU usage
while mirroring, but once OBS's render path is cheap enough it has plenty of
headroom.

So: **try recording with RDP connected first.** Disconnect only if you still see
lag after applying the settings.

## Screen blanking

Before recording, stop the screen from blanking/locking or you may record a black
screen:

```bash
gsettings set org.gnome.desktop.session idle-delay 0
gsettings set org.gnome.desktop.screensaver idle-activation-enabled false
```

## Animations

GNOME animations are a handy way to *see* whether the recording is smooth. They
are enabled by default:

```bash
gsettings get org.gnome.desktop.interface enable-animations   # -> true
```

OBS itself is sometimes started with `--force-animations`; that only affects
OBS's own UI, not the compositor.

## Display refresh rate

The virtual monitor reported ~75 Hz. Capture/encode FPS is independent of that:
choosing **30 fps** gives the renderer a 33 ms budget regardless of the panel.
Do not assume you must match the panel's refresh rate.
