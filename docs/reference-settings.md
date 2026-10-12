# Reference: what each setting does and why

## Video

| Setting (UI) | `basic.ini` key | Value here | Why |
|---|---|---|---|
| Base (Canvas) Resolution | `BaseCX` / `BaseCY` | display size, e.g. `1280` / `800` | The canvas should match the source so nothing is scaled. |
| Output (Scaled) Resolution | `OutputCX` / `OutputCY` | **same as Base** | Scaling is one of the most expensive per-frame operations on the CPU. Removing it is the single biggest win. |
| FPS Type | `FPSType` | `0` (Common) | Common FPS values are simplest. |
| Common FPS Values | `FPSCommon` | `30` | Halves the work vs 60 fps and doubles the per-frame budget (16.7 ms → 33.3 ms). |
| Downscale Filter | `ScaleType` | `bilinear` | Irrelevant when Base = Output, but bilinear is the cheapest if you ever scale. |
| Color Format | `ColorFormat` | `NV12` | The cheapest format x264 accepts; avoids an extra conversion. |
| Color Space / Range | `ColorSpace` / `ColorRange` | `709` / `Partial` | OBS defaults; fine for screen content. |

## Output (Advanced recording)

| Setting (UI) | key | Value | Why |
|---|---|---|---|
| Output Mode | `[Output] Mode` | `Advanced` | Needed to pick encoder options directly. |
| Recording Encoder | `[AdvOut] RecEncoder` | `obs_x264` | Software encoder — the only reliable option in a GPU-less VM. |
| Recording Format | `[AdvOut] RecFormat2` | `mkv` | MKV survives a crash/corruption better than MP4; remux later. |
| Recording Path | `[AdvOut] RecFilePath` | your `~/Videos` | Where files are written. |
| Rate Control | `recordEncoder.json` `rate_control` | `CRF` | Constant quality; simplest and good for screen content. (x264 accepts CBR/ABR/VBR/CRF — not CQP.) |
| CRF | `crf` | `20` | Lower = better quality/bigger file. 18–22 is a good range. |
| Preset | `preset` | `superfast` | Big speed win over `veryfast`/`faster`; `ultrafast` is the last resort. |
| Profile | `profile` | `high` | Fine; doesn't affect speed much. |
| Keyframe Interval | `keyint_sec` | `2` | 2 s is a sane default. |

## Global / UI

| Setting | key | Value | Why |
|---|---|---|---|
| Preview enabled | `global.ini [BasicWindow] PreviewEnabled` | `false` | The preview is a second render pass (~10 ms/frame). Turning it off is nearly free performance. |
| Process priority | `global.ini [General] ProcessPriority` | `High` | Helps OBS get scheduled promptly in a busy VM. |

## Important: paths are not expanded

OBS's `basic.ini` does **not** expand `$HOME`. The template in this repo uses the
placeholder `__HOME__`; `scripts/apply-obs-profile.sh` replaces it with your real
home directory.

## Reverting

The script never deletes anything. To undo, just select a different profile in
OBS, or delete `~/.config/obs-studio/basic/profiles/Smooth30/`. Backups made by
the script end in `.bak`.
