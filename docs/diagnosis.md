# Diagnosing OBS performance from the logs

OBS records everything you need to know in its log files. This document shows how
to read them and pinpoint **which stage** is dropping frames.

## Where the logs are

```
~/.config/obs-studio/logs/
```

Each session creates a timestamped `.txt` file. The most recent one is the useful
one. You can also open the current log from **Help → Log Files → View Current
Log**.

## Step 1 — find the summary block

Search for `Recording Stop`. Right after it OBS prints the output statistics:

```
info: ==== Recording Stop ====
info: Output 'adv_file_output': stopping
info: Output 'adv_file_output': Total frames output: 4916
info: Output 'adv_file_output': Total drawn frames: 4951
info: Output 'adv_file_output': Number of lagged frames due to rendering lag/stalls: 4169 (84.2%)
info: Output 'adv_file_output': Number of dropped frames due to insufficient bandwidth: 0 (0.0%)
```

| Line | Meaning |
|---|---|
| `Total frames output` | frames actually written to the file |
| `Total drawn frames` | frames OBS managed to render |
| **`lagged frames due to rendering lag/stalls`** | **the important one** — frames the *renderer* could not produce in time. High value = CPU/render bottleneck. |
| `dropped frames due to insufficient bandwidth` | network issue (streaming only) |

`84.2%` lagged means the machine could only render ~1 frame out of every 6.

Quick command:

```bash
grep -E "lagged frames|Total frames output|Total drawn" \
  ~/.config/obs-studio/logs/*.txt
```

## Step 2 — check the profiler block

On a clean shutdown OBS prints a profiler table:

```
info: == Profiler Results ===============================
info: run_program_init: 1234.5 ms
info:  ─OBSBasic::InitBasicConfig: ...
info:  ─OBSBasic::ResetOutputs: ...
info:  ─video_thread_time: 12.3 ms
info:  ─render_convert_texture: 69.0 ms
info:  ─render_displays: 11.6 ms
info:  ─output_frame: 5.0 ms
```

Interpreting the interesting entries:

| Entry | What it tells you |
|---|---|
| `render_convert_texture` | time to **convert the colour format** of each captured frame. Huge on software rendering. |
| `render_displays` | time to render the **preview + projectors**. High → turn the preview off. |
| `output_frame` | time to hand the frame to the encoder. |
| `video_thread_time` | time spent **encoding**. High → use a faster preset (`superfast`/`ultrafast`). |

In the original case `render_convert_texture` was **69 ms** and `render_displays`
**11.6 ms** — together far above the 16.7 ms budget of 60 fps.

## Step 3 — identify the bottleneck

```
if lagged frames > ~5%:
    if render_convert_texture or render_displays is large:
        -> render-side bottleneck  (resolution / scaling / preview)
    elif video_thread_time is large:
        -> encoder bottleneck      (preset / CRF / resolution)
```

## Step 4 — verify the fix

After changing settings, record again and confirm:

```
Number of lagged frames due to rendering lag/stalls: 0 (0.0%)
```

For a live measurement without stopping the recording, use
[`scripts/obs-stat.py`](../scripts/obs-stat.py) (OBS WebSocket).
