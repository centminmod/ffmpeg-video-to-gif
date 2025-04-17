Video to GIF conversion for MacOS users inspired by https://gist.github.com/SheldonWangRJT/8d3f44a35c8d1386a396b9b49b43c385 discussion.

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

~~~bash
file cloudflare-security-rate-limit-analysis-170425-third-0.gif
cloudflare-security-rate-limit-analysis-170425-third-0.gif: GIF image data, version 89a, 798 x 372
~~~
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


~~~bash
ls -lah cloudflare-security*        
-rw-r--r--  1 username  staff   2.5M 17 Apr 15:25 cloudflare-security-rate-limit-analysis-170425-0.gif
-rw-r--r--@ 1 username  staff   5.0M 17 Apr 15:24 cloudflare-security-rate-limit-analysis-170425-0.mov
-rw-r--r--@ 1 username  staff   3.6M 17 Apr 15:15 cloudflare-security-rate-limit-analysis-170425-1.gif
-rw-r--r--@ 1 username  staff   7.6M 17 Apr 14:28 cloudflare-security-rate-limit-analysis-170425-1.mov
-rw-r--r--@ 1 username  staff   1.9M 17 Apr 15:36 cloudflare-security-rate-limit-analysis-170425-half-0.gif
-rw-r--r--  1 username  staff   1.3M 17 Apr 20:55 cloudflare-security-rate-limit-analysis-170425-lossy-bayer-1.gif
-rw-r--r--@ 1 username  staff   879K 17 Apr 15:56 cloudflare-security-rate-limit-analysis-170425-third-0.gif
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
-rw-r--r--  1 username  staff   3.1M 17 Apr 20:42 gemini-2.5-pro-atari-missile-command-v15-3-lossy-dither-bayer.gif
-rw-r--r--  1 username  staff   6.5M 17 Apr 20:35 gemini-2.5-pro-atari-missile-command-v15-3-lossy.gif
-rw-r--r--  1 username  staff   6.8M 17 Apr 20:18 gemini-2.5-pro-atari-missile-command-v15-3.gif
-rw-r--r--@ 1 username  staff    67M  8 Apr 07:50 gemini-2.5-pro-atari-missile-command-v15-3.mov
~~~

A combined version `vid2gif_func.sh`

`~/.bashrc` or `~/.zshrc`

~~~bash
if [[ -f ~/".my_scripts/vid2gif_func.sh" ]]; then
  source ~/".my_scripts/vid2gif_func.sh"
fi
~~~

**Key changes and features of the combined `vid2gif_pro` function:**

1.  **Robust Parameter Parsing:** Uses a `case` statement, which is generally better for handling flags (like `--half-size`, `--no-optimize`) and parameters with values.
2.  **Clear Defaults:** Defaults are set at the beginning (`fps=10`, `optimize=true`).
3.  **Required Source:** Explicitly checks if `--src` was provided and if the file exists.
4.  **Flexible Output Naming:** Uses `--target` if provided, otherwise derives from `--src` filename.
5.  **Combined Scaling Options:**
    * You can use `--half-size` for the 50% scaling behaviour from `v2gif`.
    * You can use `--resolution WxH` (or `W:H`) for specific dimensions like `v2g`.
    * If neither is specified, it uses the original resolution.
    * `--half-size` takes precedence over `--resolution` if both are accidentally provided.
6.  **FPS Control:** Uses `--fps` like `v2g`, defaulting to 10.
7.  **Includes `v2gif` Flags:** Adds `-y` (overwrite output) and `-v quiet` (less FFMPEG chatter) to the `ffmpeg` command by default.
8.  **Optional Optimization:** Includes `gifsicle -O3` optimization by default but allows disabling it with `--no-optimize`.
9.  **macOS Notifications:** Keeps the `osascript` notification from `v2g`.
10. **Error Handling:** Basic checks for source file existence and reports FFMPEG errors. Added a warning if `gifsicle` fails.
11. **Local Variables:** Uses `local` for variables inside the function to avoid polluting the global shell environment.
12. **Clearer Output:** Prints messages about the parameters being used and the steps being taken.

This combined function offers the flexibility of `v2g` with the useful defaults and flags found in `v2gif`.

```bash
declare -f vid2gif_pro                                             
vid2gif_pro () {
    local src="" 
    local target="" 
    local resolution="" 
    local fps=10 
    local half_size=false 
    local third_size=false 
    local optimize=true 
    local dither_algo="sierra2_4a" 
    while [[ $# -gt 0 ]]
    do
        local key="$1" 
        case $key in
            (--src) src="$2" 
                shift 2 ;;
            (--target) target="$2" 
                shift 2 ;;
            (--resolution) resolution="$2" 
                shift 2 ;;
            (--fps) fps="$2" 
                shift 2 ;;
            (--half-size) half_size=true 
                shift 1 ;;
            (--third-size) third_size=true 
                shift 1 ;;
            (--no-optimize) optimize=false 
                shift 1 ;;
            (*) echo "Unknown option: $1"
                echo "Usage: vid2gif_pro --src <input> [--target <output>] [--resolution <WxH>] [--fps <rate>] [--half-size] [--third-size] [--no-optimize]"
                return 1 ;;
        esac
    done
    if [[ -z "$src" ]]
    then
        echo -e "\nError: Source file required. Use '--src <input video file>'.\n"
        echo "Usage: vid2gif_pro --src <input> [--target <output>] [--resolution <WxH>] [--fps <rate>] [--half-size] [--third-size] [--no-optimize]"
        return 1
    fi
    if [[ ! -f "$src" ]]
    then
        echo -e "\nError: Source file not found: $src\n"
        return 1
    fi
    if [[ -z "$target" ]]
    then
        local basename="${src%.*}" 
        [[ "$basename" == "$src" ]] && basename="${src}_converted" 
        target="$basename.gif" 
    fi
    local filters="" 
    local scale_applied_msg="" 
    if [[ "$third_size" == true ]]
    then
        filters="scale=iw/3:ih/3" 
        scale_applied_msg="Applying ~33% scaling (--third-size)." 
    elif [[ "$half_size" == true ]]
    then
        filters="scale=iw/2:ih/2" 
        scale_applied_msg="Applying 50% scaling (--half-size)." 
    elif [[ -n "$resolution" ]]
    then
        resolution="${resolution//x/:}" 
        filters="scale=$resolution" 
        scale_applied_msg="Applying custom resolution: $resolution (--resolution)." 
    fi
    if [[ -n "$filters" ]]
    then
        filters+=",fps=${fps}" 
    else
        filters="fps=${fps}" 
        scale_applied_msg="Using original resolution (adjusting FPS to $fps)." 
    fi
    if [[ -n "$scale_applied_msg" ]]
    then
        echo "$scale_applied_msg"
    fi
    local palette_file
    palette_file=$(mktemp "${TMPDIR:-/tmp}/vid2gif_palette_XXXXXXXXXX.png") 
    trap 'rm -f "$palette_file"' EXIT INT TERM HUP
    echo "Pass 1: Generating palette (using filters: $filters)..."
    local palettegen_cmd_array=("ffmpeg" "-y" "-v" "warning" "-i" "$src" "-vf" "${filters},palettegen=stats_mode=diff" "-update" "1" "$palette_file") 
    if ! "${palettegen_cmd_array[@]}"
    then
        echo "Error during palette generation. Check FFMPEG warnings above."
        return 1
    fi
    if [[ ! -s "$palette_file" ]]
    then
        echo "Error: Palette file generation failed or created an empty file."
        return 1
    fi
    echo "Pass 2: Generating GIF using palette (dither: $dither_algo)..."
    local gifgen_cmd_array=("ffmpeg" "-y" "-v" "quiet" "-i" "$src" "-i" "$palette_file" "-filter_complex" "[0:v]${filters}[s]; [s][1:v]paletteuse=dither=${dither_algo}" "$target") 
    if ! "${gifgen_cmd_array[@]}"
    then
        echo "Error during final GIF generation."
        return 1
    fi
    if [[ "$optimize" == true ]]
    then
        if [[ ! -f "$target" ]]
        then
            echo "Warning: Target file '$target' not found after ffmpeg step. Skipping optimization."
        else
            echo "Optimizing '$target' with gifsicle..."
            if ! gifsicle -O3 "$target" -o "$target"
            then
                echo "Warning: gifsicle optimization failed, but GIF was created."
            fi
        fi
    else
        echo "Skipping gifsicle optimization (--no-optimize)."
    fi
    if [[ -f "$target" ]] && command -v osascript &> /dev/null
    then
        osascript -e "display notification \"'$target' successfully converted and saved\" with title \"Video to GIF Complete\""
    fi
    if [[ -f "$target" ]]
    then
        echo "Successfully created '$target'"
        return 0
    else
        echo "Error: Conversion finished, but target file '$target' was not found."
        return 1
    fi
}
```