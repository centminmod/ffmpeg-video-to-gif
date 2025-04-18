# Universal Video Converter Pro (`vid2gif_pro` / `vid2vid_pro`)

A command-line Bash function for macOS users to convert videos to high-quality animated GIFs or efficiently encoded MP4 video formats (H.264, H.265/HEVC, AV1).

Built upon `ffmpeg` and optionally `gifsicle` for optimization, this script provides fine-grained control over resolution, frame rate, cropping, quality, and output format and inspired by https://gist.github.com/SheldonWangRJT/8d3f44a35c8d1386a396b9b49b43c385 discussion.

## Features

* **Video to GIF:** Creates optimized animated GIFs using a two-pass `ffmpeg` process (`palettegen`/`paletteuse`) for better quality and smaller file sizes.
* **Video to MP4:** Converts videos to MP4 format using modern codecs:
    * H.264 (`libx264`) - Best compatibility.
    * H.265/HEVC (`libx265`) - Better compression than H.264.
    * AV1 (`libaom-av1`) - Excellent compression, but significantly slower encoding.
* **Flexible Options:** Control resolution (scaling, specific dimensions), frame rate, cropping, quality (CRF for MP4, lossiness for GIF), dithering (GIF), and encoding presets (MP4).
* **Optimization:** Uses `gifsicle` for further GIF optimization (optional). MP4 output includes `+faststart` flag for web streaming optimization.
* **Convenience:** Automatically determines output filename if not specified. Provides macOS notifications on completion.
* **Aliases:** Can be called as `vid2gif_pro` or `vid2vid_pro`.

## Requirements

* **macOS:** Tested on macOS. Uses `mktemp` and `osascript` for notifications.
* **`ffmpeg`:** The core conversion tool. Must be installed and available in your `$PATH`.
    * For AV1 support, `ffmpeg` must be compiled with `libaom-av1` enabled. Check with: `ffmpeg -codecs | grep libaom`
* **`gifsicle`:** Required *only* for GIF optimization (`--optimize` flag, enabled by default for GIFs).

You can typically install these dependencies using [Homebrew](https://brew.sh/):
```bash
brew install ffmpeg gifsicle
```
*(If AV1 support is missing in the default `ffmpeg` brew formula, you might need to investigate custom builds or alternative formulas)*

## Installation

1.  **Save the Script:** Save the code provided in the `vid2gif_func.sh` file (or similar) to a location like `~/.my_scripts/vid2gif_func.sh`.
2.  **Make Executable (Optional but good practice):**
    ```bash
    chmod +x ~/.my_scripts/vid2gif_func.sh
    ```
3.  **Source the Script:** Add the following line to your shell configuration file (`~/.zshrc` for Zsh or `~/.bashrc` or `~/.bash_profile` for Bash) to make the function available in your terminal sessions:
    ```bash
    if [[ -f ~/.my_scripts/vid2gif_func.sh ]]; then
      source ~/.my_scripts/vid2gif_func.sh
    fi
    ```
4.  **Reload Shell:** Open a new terminal window or run `source ~/.zshrc` (or your respective config file).

## Usage

The function can be called using either `vid2gif_pro` or `vid2vid_pro`.

```bash
vid2gif_pro --src <input_video> [options]
# or
vid2vid_pro --src <input_video> [options]
```

**Required Argument:**

* `--src <input_file>`: Path to the source video file.

**Output Options:**

* `--target <output_file>`: Specify the output filename. If omitted, defaults are generated based on the source name and conversion type (e.g., `source.gif`, `source-libx264.mp4`).
* `--to-mp4-h264`: Convert to MP4 using H.264 (libx264) codec.
* `--to-mp4-h265`: Convert to MP4 using H.265 (libx265) codec.
* `--to-mp4-av1`: Convert to MP4 using AV1 (libaom-av1) codec (slow!).
* *(Default Output)*: If no `--to-mp4-*` flag is given, the output defaults to GIF.

**General Options:**

* `--resolution <WxH>`: Set a specific output resolution (e.g., `640x480` or `640:480`).
* `--half-size`: Scale output to 50% of original dimensions.
* `--third-size`: Scale output to ~33% of original dimensions (overrides `--half-size` and `--resolution`).
* `--crop <W:H:X:Y>`: Crop the video. W=width, H=height, X=offset-x, Y=offset-y.
* `--fps <rate>`: Set frame rate.
    * For GIF: Sets the output GIF FPS (default: 10).
    * For MP4: Overrides the source video frame rate (use with caution).

**GIF Specific Options:**

* `--dither <algo>`: Dithering algorithm for `paletteuse` (default: `sierra2_4a`). Other options include `bayer`, `heckbert`, etc.
* `--no-optimize`: Disable `gifsicle` optimization step.
* `--lossy [level]`: Enable lossy GIF compression using `gifsicle`. Optionally provide a level (e.g., `--lossy 80`).

**MP4 Specific Options:**

* `--crf <value>`: Constant Rate Factor (quality setting). Lower values = better quality, larger file. (Default: 23). Recommended ranges vary by codec (e.g., 18-28 for x264, 20-30 for x265, 30-45 for AV1).
* `--preset <name>`: Encoding speed preset (e.g., `ultrafast`, `fast`, `medium`, `slow`, `veryslow`). Affects speed vs. compression efficiency. (Default: `medium`). Less impact on `libaom-av1`.

## Examples

**1. Convert MOV to Optimized GIF (Default)**

```bash
# Basic conversion, 1/3 size, default 10 fps
vid2gif_pro --src my_video.mov --third-size

# Half size, 15 fps, custom target name
vid2gif_pro --src screen_recording.mov --half-size --fps 15 --target preview.gif

# Lossy GIF, bayer dither, 8 fps
vid2gif_pro --src animation.mov --lossy 80 --dither bayer --fps 8 --target small_anim.gif
```

**2. Convert MOV to MP4 (H.264 - libx264)**

```bash
# Convert with default settings (CRF 23), auto filename like my_video-libx264.mp4
vid2vid_pro --src my_video.mov --to-mp4-h264

# Higher quality (CRF 20), faster preset, specific resolution
vid2vid_pro --src lecture.mov --to-mp4-h264 --crf 20 --preset fast --resolution 1280x720
```

**3. Convert MOV to MP4 (H.265 - libx265)**

```bash
# Convert using CRF 26 for good compression, keep original frame rate
vid2vid_pro --src vacation.mov --to-mp4-h265 --crf 26

# Convert, force 30 fps, 1/3 size
vid2vid_pro --src drone_footage.mov --to-mp4-h265 --third-size --fps 30 --crf 28
```

**4. Convert MOV to MP4 (AV1 - libaom-av1)** - *Expect long processing times*

```bash
# Convert using CRF 35, keep original frame rate
vid2vid_pro --src conference_talk.mov --to-mp4-av1 --crf 35

# Convert, 1/3 size, force 15 fps (will be very slow)
vid2vid_pro --src long_clip.mov --to-mp4-av1 --third-size --fps 15 --crf 40
```

## Notes

* **AV1 Performance:** Encoding with `libaom-av1` is CPU-intensive and significantly slower than H.264 or H.265.
* **macOS Notifications:** If `osascript` is available, a system notification will appear upon successful conversion.
* **Error Handling:** The script includes basic checks for input files and reports errors from `ffmpeg` or `gifsicle`.
* **Temporary Files:** A temporary PNG file is created for the GIF palette generation in `/tmp` (or `$TMPDIR`) and is automatically cleaned up.

## MOV To GIF

~~~bash
vid2gif_pro --src cloudflare-security-rate-limit-analysis-170425-0.mov --third-size --target cloudflare-security-rate-limit-analysis-170425-third-0.gif

Applying ~33% scaling (--third-size).
Pass 1: Generating palette (using filters: scale=iw/3:ih/3,fps=10)...
[Parsed_palettegen_2 @ 0x6000032a5970] The input frame is not in sRGB, colors may be off
    Last message repeated 308 times
Pass 2: Generating GIF using palette (dither: sierra2_4a)...
Optimizing 'cloudflare-security-rate-limit-analysis-170425-third-0.gif' with gifsicle...
Successfully created 'cloudflare-security-rate-limit-analysis-170425-third-0.gif'
~~~

`--third-size` output GIF

`cloudflare-security-rate-limit-analysis-170425-third-0.gif` file info:

~~~bash
file cloudflare-security-rate-limit-analysis-170425-third-0.gif
cloudflare-security-rate-limit-analysis-170425-third-0.gif: GIF image data, version 89a, 798 x 372
~~~

`cloudflare-security-rate-limit-analysis-170425-third-0.gif` exiftool info:

~~~bash
exiftool cloudflare-security-rate-limit-analysis-170425-third-0.gif
ExifTool Version Number         : 13.25
File Name                       : cloudflare-security-rate-limit-analysis-170425-third-0.gif
Directory                       : .
File Size                       : 900 kB
File Modification Date/Time     : 2025:04:17 15:56:18+10:00
File Access Date/Time           : 2025:04:17 16:04:54+10:00
File Inode Change Date/Time     : 2025:04:17 15:59:47+10:00
File Permissions                : -rw-r--r--
File Type                       : GIF
File Type Extension             : gif
MIME Type                       : image/gif
GIF Version                     : 89a
Image Width                     : 798
Image Height                    : 372
Has Color Map                   : Yes
Color Resolution Depth          : 8
Bits Per Pixel                  : 8
Background Color                : 6
Animation Iterations            : Infinite
XMP Toolkit                     : Image::ExifTool 12.60
X Resolution                    : 72
Y Resolution                    : 72
Transparent Color               : 0
Frame Count                     : 309
Duration                        : 30.90 s
Image Size                      : 798x372
Megapixels                      : 0.297
~~~

`cloudflare-security-rate-limit-analysis-170425-third-0.gif`

![mov to GIFF third-size](examples/cloudflare-security-rate-limit-analysis-170425-third-0.gif)

~~~bash
vid2gif_pro --src cloudflare-security-rate-limit-analysis-170425-0.mov --half-size --target cloudflare-security-rate-limit-analysis-170425-half-0.gif

Applying 50% scaling (--half-size).
Pass 1: Generating palette (using filters: scale=iw/2:ih/2,fps=10)...
[Parsed_palettegen_2 @ 0x60000367d6b0] The input frame is not in sRGB, colors may be off
    Last message repeated 308 times
Pass 2: Generating GIF using palette (dither: sierra2_4a)...
Optimizing 'cloudflare-security-rate-limit-analysis-170425-half-0.gif' with gifsicle...
Successfully created 'cloudflare-security-rate-limit-analysis-170425-half-0.gif'
~~~

~~~bash
vid2gif_pro --src cloudflare-security-rate-limit-analysis-170425-0.mov --target cloudflare-security-rate-limit-analysis-170425-0.gif

Converting 'cloudflare-security-rate-limit-analysis-170425-0.mov' to 'cloudflare-security-rate-limit-analysis-170425-0.gif'...
Parameters: FPS=10, Optimize=true
Using original resolution.
Executing FFMPEG command...
Optimizing 'cloudflare-security-rate-limit-analysis-170425-0.gif' with gifsicle...
gifsicle: warning: huge GIF, conserving memory (processing may take a while)
Successfully created 'cloudflare-security-rate-limit-analysis-170425-0.gif'
~~~

~~~bash
vid2gif_pro --src cloudflare-security-rate-limit-analysis-170425-1.mov --target cloudflare-security-rate-limit-analysis-170425-1.gif

Converting 'cloudflare-security-rate-limit-analysis-170425-1.mov' to 'cloudflare-security-rate-limit-analysis-170425-1.gif'...
Parameters: FPS=10, Optimize=true
Using original resolution.
Executing FFMPEG command...
Optimizing 'cloudflare-security-rate-limit-analysis-170425-1.gif' with gifsicle...
gifsicle: warning: huge GIF, conserving memory (processing may take a while)
Successfully created 'cloudflare-security-rate-limit-analysis-170425-1.gif'
~~~

With `--lossy --dither bayer` gifsicle compression instead of default `sierra2_4a`.

~~~bash
vid2gif_pro --src cloudflare-security-rate-limit-analysis-170425-1.mov --third-size --lossy --dither bayer --target cloudflare-security-rate-limit-analysis-170425-lossy-bayer-1.gif

Applying ~33% scaling (--third-size).
Pass 1: Generating palette (using filters: scale=iw/3:ih/3,fps=10)...
[Parsed_palettegen_2 @ 0x600001e793f0] The input frame is not in sRGB, colors may be off
    Last message repeated 467 times
Pass 2: Generating GIF (using filters: scale=iw/3:ih/3,fps=10, palette options: dither=bayer:diff_mode=rectangle)...
Optimizing 'cloudflare-security-rate-limit-analysis-170425-lossy-bayer-1.gif' with gifsicle (lossy default)...
Successfully created 'cloudflare-security-rate-limit-analysis-170425-lossy-bayer-1.gif'
~~~

With `--lossy --dither bayer --fps 6` gifsicle compression instead of default `sierra2_4a`.  Reduced original MOV 5MB video to 663KB GIF.

~~~bash
vid2gif_pro --src cloudflare-security-rate-limit-analysis-170425-0.mov --third-size --lossy --dither bayer --fps 6 --target cloudflare-security-rate-limit-analysis-170425-lossy-bayer-fps6-0.gif

Applying ~33% scaling (--third-size).
Pass 1: Generating palette (using filters: scale=iw/3:ih/3,fps=6)...
[Parsed_palettegen_2 @ 0x600000468790] The input frame is not in sRGB, colors may be off
    Last message repeated 184 times
Pass 2: Generating GIF (using filters: scale=iw/3:ih/3,fps=6, palette options: dither=bayer:diff_mode=rectangle)...
Optimizing 'cloudflare-security-rate-limit-analysis-170425-lossy-bayer-fps6-0.gif' with gifsicle (lossy default)...
Successfully created 'cloudflare-security-rate-limit-analysis-170425-lossy-bayer-fps6-0.gif'
~~~


FYI, online converters like https://convertio.co/mov-gif/ took my 5MB `cloudflare-security-rate-limit-analysis-170425-0.mov` MOV video file and converted to 11.3MB GIF file!


~~~bash
ls -lah cloudflare-security*        
2.5M 17 Apr 15:25 cloudflare-security-rate-limit-analysis-170425-0.gif
5.0M 17 Apr 15:24 cloudflare-security-rate-limit-analysis-170425-0.mov
3.6M 17 Apr 15:15 cloudflare-security-rate-limit-analysis-170425-1.gif
7.6M 17 Apr 14:28 cloudflare-security-rate-limit-analysis-170425-1.mov
1.9M 17 Apr 15:36 cloudflare-security-rate-limit-analysis-170425-half-0.gif
1.3M 17 Apr 20:55 cloudflare-security-rate-limit-analysis-170425-lossy-bayer-1.gif
663K 18 Apr 15:33 cloudflare-security-rate-limit-analysis-170425-lossy-bayer-fps6-0.gif
879K 17 Apr 15:56 cloudflare-security-rate-limit-analysis-170425-third-0.gif
~~~

Another example

~~~bash
vid2gif_pro --src 'gemini-2.5-pro-atari-missile-command-v15-3.mov' --third-size --target 'gemini-2.5-pro-atari-missile-command-v15-3.gif'

Applying ~33% scaling (--third-size).
Attempting to create base temporary file...
Base temporary file created: /var/folders/cv/b75n7x712sz61_y6pj62489r0000gn/T//vid2gif_palette_pTUR2G
Attempting to rename base file to: /var/folders/cv/b75n7x712sz61_y6pj62489r0000gn/T//vid2gif_palette_pTUR2G.png
Temporary palette file created successfully: /var/folders/cv/b75n7x712sz61_y6pj62489r0000gn/T//vid2gif_palette_pTUR2G.png
Pass 1: Generating palette (using filters: scale=iw/3:ih/3,fps=10)...
[Parsed_palettegen_2 @ 0x6000010c8840] The input frame is not in sRGB, colors may be off
    Last message repeated 332 times
Palette generation successful.
Pass 2: Generating GIF using palette (dither: sierra2_4a)...
GIF generation successful.
Optimizing 'gemini-2.5-pro-atari-missile-command-v15-3.gif' with gifsicle...
Successfully created 'gemini-2.5-pro-atari-missile-command-v15-3.gif'
~~~

With `--lossy` gifsicle compression

~~~bash
vid2gif_pro --src 'gemini-2.5-pro-atari-missile-command-v15-3.mov' --third-size --lossy --target 'gemini-2.5-pro-atari-missile-command-v15-3-lossy.gif'

Applying ~33% scaling (--third-size).
Pass 1: Generating palette (using filters: scale=iw/3:ih/3,fps=10)...
[Parsed_palettegen_2 @ 0x600003844840] The input frame is not in sRGB, colors may be off
    Last message repeated 332 times
Pass 2: Generating GIF (using filters: scale=iw/3:ih/3,fps=10, palette options: dither=sierra2_4a:diff_mode=rectangle)...
Optimizing 'gemini-2.5-pro-atari-missile-command-v15-3-lossy.gif' with gifsicle (lossy default)...
Successfully created 'gemini-2.5-pro-atari-missile-command-v15-3-lossy.gif'
~~~

With `--lossy --dither bayer` gifsicle compression instead of default `sierra2_4a`. Reduced original MOV 67MB video to 3.1MB GIF.

~~~bash
vid2gif_pro --src 'gemini-2.5-pro-atari-missile-command-v15-3.mov' --third-size --lossy --dither bayer --target 'gemini-2.5-pro-atari-missile-command-v15-3-lossy-dither-bayer.gif'

Applying ~33% scaling (--third-size).
Pass 1: Generating palette (using filters: scale=iw/3:ih/3,fps=10)...
[Parsed_palettegen_2 @ 0x6000001e4210] The input frame is not in sRGB, colors may be off
    Last message repeated 332 times
Pass 2: Generating GIF (using filters: scale=iw/3:ih/3,fps=10, palette options: dither=bayer:diff_mode=rectangle)...
Optimizing 'gemini-2.5-pro-atari-missile-command-v15-3-lossy-dither-bayer.gif' with gifsicle (lossy default)...
Successfully created 'gemini-2.5-pro-atari-missile-command-v15-3-lossy-dither-bayer.gif'
~~~

~~~bash
ls -lah 'gemini-2.5-pro-atari-missile-command-v15-3.mov' 'gemini-2.5-pro-atari-missile-command-v15-3.gif' 'gemini-2.5-pro-atari-missile-command-v15-3-lossy.gif' 'gemini-2.5-pro-atari-missile-command-v15-3-lossy-dither-bayer.gif'
3.1M 17 Apr 20:42 gemini-2.5-pro-atari-missile-command-v15-3-lossy-dither-bayer.gif
6.5M 17 Apr 20:35 gemini-2.5-pro-atari-missile-command-v15-3-lossy.gif
6.8M 17 Apr 20:18 gemini-2.5-pro-atari-missile-command-v15-3.gif
 67M  8 Apr 07:50 gemini-2.5-pro-atari-missile-command-v15-3.mov
~~~

A combined version `vid2gif_func.sh`

`~/.bashrc` or `~/.zshrc`

~~~bash
if [[ -f ~/".my_scripts/vid2gif_func.sh" ]]; then
  source ~/".my_scripts/vid2gif_func.sh"
fi
~~~

## MOV To MP4/AV1


For MOV to MP4/AVI use alias command `vid2gif_pro`.

MOV to AV1

~~~bash
vid2gif_pro \
  --src cloudflare-security-rate-limit-analysis-170425-0.mov \
  --to-mp4-av1 \
  --third-size \
  --crf 35 \
  --target cloudflare-security-rate-limit-analysis-170425-av1-crf35.mp4

Applying ~33% scaling (--third-size).
Converting to MP4 (libaom-av1)... This might take a while for AV1.
[out#0/mp4 @ 0x600002e1c000] Codec AVOption b:a (set bitrate (in bits/s)) has not been used for any stream. The most likely reason is either wrong type (e.g. a video option with no video streams) or that it is a private option of some decoder which was not actually used for any stream.
Successfully created 'cloudflare-security-rate-limit-analysis-170425-av1-crf35.mp4'
~~~

MOV to x264

~~~bash
vid2gif_pro \
  --src cloudflare-security-rate-limit-analysis-170425-0.mov \
  --to-mp4-h264 \
  --third-size \
  --crf 23 \
  --target cloudflare-security-rate-limit-analysis-170425-x264-crf23.mp4

Applying ~33% scaling (--third-size).
Converting to MP4 (libx264)... This might take a while for AV1.
[out#0/mp4 @ 0x600001c50000] Codec AVOption b:a (set bitrate (in bits/s)) has not been used for any stream. The most likely reason is either wrong type (e.g. a video option with no video streams) or that it is a private option of some decoder which was not actually used for any stream.
Successfully created 'cloudflare-security-rate-limit-analysis-170425-x264-crf23.mp4'
~~~

MOV to x265

~~~bash
vid2gif_pro \
  --src cloudflare-security-rate-limit-analysis-170425-0.mov \
  --to-mp4-h265 \
  --third-size \
  --crf 23 \
  --target cloudflare-security-rate-limit-analysis-170425-x265-crf23.mp4

Applying ~33% scaling (--third-size).
Converting to MP4 (libx265)... This might take a while for AV1.
[out#0/mp4 @ 0x600001148000] Codec AVOption b:a (set bitrate (in bits/s)) has not been used for any stream. The most likely reason is either wrong type (e.g. a video option with no video streams) or that it is a private option of some decoder which was not actually used for any stream.
x265 [info]: HEVC encoder version 4.1+1-1d117be
x265 [info]: build info [Mac OS X][clang 16.0.0][64 bit] 8bit+10bit+12bit
x265 [info]: using cpu capabilities: NEON Neon_DotProd Neon_I8MM
x265 [info]: Main profile, Level-3.1 (Main tier)
x265 [info]: Thread pool created using 14 threads
x265 [info]: Slices                              : 1
x265 [info]: frame threads / pool features       : 3 / wpp(6 rows)
x265 [warning]: Source height < 720p; disabling lookahead-slices
x265 [info]: Coding QT: max CU size, min CU size : 64 / 8
x265 [info]: Residual QT: max TU size, max depth : 32 / 1 inter / 1 intra
x265 [info]: ME / range / subpel / merge         : hex / 57 / 2 / 3
x265 [info]: Keyframe min / max / scenecut / bias  : 25 / 250 / 40 / 5.00 
x265 [info]: Lookahead / bframes / badapt        : 20 / 4 / 2
x265 [info]: b-pyramid / weightp / weightb       : 1 / 1 / 0
x265 [info]: References / ref-limit  cu / depth  : 3 / off / on
x265 [info]: AQ: mode / str / qg-size / cu-tree  : 2 / 1.0 / 32 / 1
x265 [info]: Rate Control / qCompress            : CRF-23.0 / 0.60
x265 [info]: tools: rd=3 psy-rd=2.00 early-skip rskip mode=1 signhide tmvp
x265 [info]: tools: b-intra strong-intra-smoothing deblock sao
x265 [info]: frame I:      8, Avg QP:21.82  kb/s: 6079.44 
x265 [info]: frame P:    520, Avg QP:29.98  kb/s: 107.83  
x265 [info]: frame B:   1322, Avg QP:33.51  kb/s: 27.10   
x265 [info]: Weighted P-Frames: Y:0.0% UV:0.0%

encoded 1850 frames in 2.00s (926.65 fps), 75.96 kb/s, Avg QP:32.46
Successfully created 'cloudflare-security-rate-limit-analysis-170425-x265-crf23.mp4'
~~~

* Original MOV = 5.0MB
* AV1 converted and resized to 1/3 resolution = 127KB
* x264 converted and resized to 1/3 resolution = 279KB
* x265 converted and resized to 1/3 resolution = 318KB

~~~bash
ls -lah cloudflare-security* | egrep 'mov|mp4'
5.0M 17 Apr 15:24 cloudflare-security-rate-limit-analysis-170425-0.mov
127K 19 Apr 00:58 cloudflare-security-rate-limit-analysis-170425-av1-crf35.mp4
279K 19 Apr 00:59 cloudflare-security-rate-limit-analysis-170425-x264-crf23.mp4
318K 19 Apr 00:59 cloudflare-security-rate-limit-analysis-170425-x265-crf23.mp4
~~~