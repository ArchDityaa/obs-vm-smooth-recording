# Smooth OBS screen recording in a Linux VM

**Wayland · software rendering (no GPU) · RDP-friendly**

This is a practical, measured guide to fixing **choppy / stuttering OBS screen
recordings inside a Linux virtual machine** that has no GPU acceleration
(software rendering via llvmpipe/swrast).

Real case study: OBS Studio was dropping **84.2 %** of all frames on a Zorin OS
VM (≈ 9 fps of a 60 fps target). After the fix it runs at a **stable 30 fps with
0.0 % dropped frames**, *while the RDP session stayed connected*.

> Verified with OBS Studio 30.0.2 on Zorin OS 17 (Ubuntu/GNOME 46, Wayland) in a
> QEMU/KVM guest using a virtual display (`Virtual-1`, 1280×800) and
> `gnome-remote-desktop` for RDP.

---

## Table of contents

- [Symptoms](#symptoms)
- [TL;DR — the fix](#tldr--the-fix)
- [Why it happens](#why-it-happens)
- [Step by step](#step-by-step)
- [Before / After](#before--after)
- [Demo](#demo)
- [Measure it yourself](#measure-it-yourself)
- [Troubleshooting](#troubleshooting)
- [When this won't help](#when-this-wont-help)
- [Repository contents](#repository-contents)
- [License](#license)

---

## Symptoms

- The recording looks choppy, or the cursor/animations seem to "jump".
- Desktop animations (window open/close, workspace switch) appear **missing**.
- OBS is barely using the CPU, yet frames are dropped.
- The OBS log contains something like:

  ```
  Output 'adv_file_output': Number of lagged frames due to rendering lag/stalls: 4169 (84.2%)
  ```

## TL;DR — the fix

In **Settings → Video** and **Settings → Output**:

| Setting | Value |
|---|---|
| Base (Canvas) Resolution | **same as your display** (e.g. `1280x800`) |
| Output (Scaled) Resolution | **same as Base** (no scaling!) |
| Common FPS Values | **30** |
| Scale Filtering | Bilinear (irrelevant when Base = Output) |

In **Settings → Output → Recording** (Advanced mode, `x264`):

| Setting | Value |
|---|---|
| Encoder | `x264` (software — there is no working GPU encoder in the VM) |
| Rate Control | `CRF` |
| CRF | `20` |
| Preset | **`superfast`** |
| Profile | `high` |
| Keyframe Interval | `2` s |
| Format | `mkv` (remux to mp4 later) |

Then:

- **Disable the OBS preview** — View → uncheck *Preview* (or set
  `PreviewEnabled=false` in `global.ini`). It can cost ~10 ms/frame.
- **Disable screen blanking** so the recording doesn't capture a black screen.
- **Close heavy apps** (software centres, browsers with many tabs, etc.).

That's it. No GPU required.

## Why it happens

Inside a VM without GPU passthrough, every pixel OBS touches is processed by the
**CPU**. OBS has to do, for every frame:

1. receive the captured frame from PipeWire (Wayland screen capture),
2. **convert** the colour format (e.g. BGRA → NV12),
3. **scale** it to the output resolution,
4. **encode** it with x264.

Steps 2–4 are the expensive part. At 1080p, `render_convert_texture` alone was
measured at **~69 ms per frame**. A 60 fps budget is only **16.7 ms**, so ~84 %
of frames were thrown away.

The fix attacks the cost directly:

- **Base = Output resolution** removes the scaling step entirely.
- **30 fps** doubles the per-frame budget (33.3 ms).
- **`superfast`** makes the encoder cheaper.
- **Preview off** removes a second render pass (~11 ms).
- Keeping the resolution at the **native display size** halves the pixel count
  compared to 1080p.

Result: average render time dropped from **~80 ms to ~4–12 ms**.

## Step by step

### Option A — manual (recommended first time)

1. Create a dedicated profile: **Profile → New** (e.g. `Smooth30`).
2. Apply the values from [TL;DR](#tldr--the-fix) above.
3. Add a screen capture source: **Sources → + → Screen Capture (PipeWire)** and
   pick your monitor in the dialog.
4. Add audio: **Desktop Audio** and **Mic/Aux** (or your real mic).
5. Turn the preview off.
6. Record a short test and check the log (see
   [Measure it yourself](#measure-it-yourself)).

### Option B — script

```bash
# Installs the "Smooth30" profile into ~/.config/obs-studio (backs up first)
./scripts/apply-obs-profile.sh
```

Then open OBS and select the **Smooth30** profile (Profile menu).

> The script only installs a *new profile*; it never touches your scenes or
> recordings.

## Before / After

Measured live through the OBS WebSocket API (`scripts/obs-stat.py`), **with RDP
still connected**:

| Metric | Before | After |
|---|---|---|
| Lagged / skipped frames | **4169 (84.2 %)** | **0 (0.0 %)** |
| Average render time | ~80 ms | **~4–12 ms** |
| Active FPS | ~9 | **30.0 (stable)** |
| OBS CPU usage | high | ~11–23 % |

Raw log evidence (before):

```
Output 'adv_file_output': Total frames output: 4916
Output 'adv_file_output': Total drawn frames: 4951
Output 'adv_file_output': Number of lagged frames due to rendering lag/stalls: 4169 (84.2%)
```

## Demo

Real capture with these settings (1280×800 @ 30 fps, x264 `superfast`),
recorded inside the VM — fullscreen animation, converted to GIF:

![Smooth fullscreen animation recorded at 1280x800 30fps](assets/demo-smooth.gif)

Still frame from the same recording:

![Still frame of the recorded animation](assets/recording-screenshot.png)

## Measure it yourself

You don't need to guess — OBS exposes exact counters:

1. Enable the WebSocket server: **Tools → WebSocket Server Settings → Enable**,
   set a password.
2. Run the measuring script:

   ```bash
   pip install websockets            # or: sudo apt install python3-websockets
   OBS_WS_PASSWORD='your-password' ./scripts/obs-stat.py --duration 20
   ```

   It prints `activeFps`, `averageFrameRenderTime` and the **render-skip
   percentage** in real time. Target: **< 1 % skipped**.

3. Or just read the OBS log after a recording:

   ```bash
   ./scripts/diagnose.sh
   ```

## Troubleshooting

| Still laggy? | Try |
|---|---|
| Slightly over budget | Lower FPS to **25**, or preset to **`ultrafast`** |
| Want 16:9 | Output **1280×720** instead of 1280×800 |
| Encoder is the bottleneck (see `video_thread_time` in the log) | Preset `ultrafast`, or raise CRF |
| Whole system is slow | Close other apps, don't run the OBS preview, record to a fast disk |
| Black screen in the recording | Re-select the monitor in the Screen Capture source; make sure screen blanking is off |

## When this won't help

If you want a **smooth 1080p60** recording, no OBS setting will save you in a VM
without a GPU. Solid 1080p60 requires **hardware acceleration at the host level**
(virgl, GPU passthrough, or running OBS on real hardware). On pure software
rendering the realistic ceiling is roughly **720p–800p at 25–40 fps**.

## Repository contents

```
README.md                   This file
README.id.md                Indonesian version
assets/demo-smooth.gif      Demo GIF (real capture with these settings)
assets/recording-screenshot.png  Still frame from the demo recording
docs/diagnosis.md           How to read OBS logs and find the bottleneck
docs/vm-wayland-rdp.md      VM + Wayland + PipeWire + RDP specifics
docs/reference-settings.md  Why each setting is what it is
config/basic.ini            OBS profile template (video/output/audio)
config/recordEncoder.json   x264 encoder settings
config/scene-template.json  A minimal screen-capture scene collection
scripts/diagnose.sh         Collect system info + compute render-lag %
scripts/obs-stat.py         Live stats via OBS WebSocket
scripts/apply-obs-profile.sh Install the profile into OBS
```

## License

[MIT](LICENSE).
