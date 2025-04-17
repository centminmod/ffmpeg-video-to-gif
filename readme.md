Video to GIF conversion for MacOS users inspired by https://gist.github.com/SheldonWangRJT/8d3f44a35c8d1386a396b9b49b43c385 discussion.

A combined version. It prioritizes explicit parameters (`--resolution`, `--fps`) but adds a `--half-size` flag inspired by `v2gif` and includes the `-y` and `-v quiet` flags.

```bash
#!/bin/bash

# Combined video to GIF conversion function
# Inspired by:
# - https://gist.github.com/SheldonWangRJT/8d3f44a35c8d1386a396b9b49b43c385
# - v2gif (fixed scaling, quiet, overwrite)
# - v2g (parameter parsing, notifications, gifsicle)

vid2gif_pro() {
    # --- Defaults ---
    local src=""             # Input video file (required)
    local target=""          # Output GIF file (optional, defaults to source name .gif)
    local resolution=""      # Specific output resolution e.g., 640:480 (optional)
    local fps=10             # Frames per second (optional, default 10)
    local half_size=false    # Scale to 50% width/height (optional, overrides --resolution)
    local optimize=true      # Run gifsicle -O3 (optional, default true)

    # --- Parameter Parsing ---
    # More robust parsing using case statement
    while [[ $# -gt 0 ]]; do
        local key="$1"
        case $key in
            --src)
            src="$2"
            shift # past argument
            shift # past value
            ;;
            --target)
            target="$2"
            shift # past argument
            shift # past value
            ;;
            --resolution)
            resolution="$2" # e.g., 640:480 or 640x480
            shift # past argument
            shift # past value
            ;;
            --fps)
            fps="$2"
            shift # past argument
            shift # past value
            ;;
            --half-size)
            half_size=true
            shift # past argument (it's a flag, no value)
            ;;
            --no-optimize)
            optimize=false
            shift # past argument
            ;;
            *)    # unknown option
            echo "Unknown option: $1"
            return 1
            ;;
        esac
    done

    # --- Input Validation ---
    if [[ -z "$src" ]]; then
        echo -e "\nError: Source file required. Use '--src <input video file>'.\n"
        echo "Usage: vid2gif_pro --src <input> [--target <output>] [--resolution <WxH>] [--fps <rate>] [--half-size] [--no-optimize]"
        return 1
    fi
    if [[ ! -f "$src" ]]; then
        echo -e "\nError: Source file not found: $src\n"
        return 1
    fi

    # --- Determine Output Filename ---
    if [[ -z "$target" ]]; then
        local basename="${src%.*}"
        # Handle cases where input might not have an extension
        [[ "$basename" == "$src" ]] && basename="${src}_converted"
        target="$basename.gif"
    fi

    # --- Prepare FFMPEG Flags ---
    local ffmpeg_flags="-y -v quiet" # Overwrite and quiet by default
    local fps_flag="-r $fps"
    local scale_filter=""

    if [[ "$half_size" == true ]]; then
        scale_filter="-vf scale=iw/2:ih/2" # Relative 50% scaling
        echo "Applying 50% scaling (--half-size)."
    elif [[ -n "$resolution" ]]; then
        # Replace 'x' with ':' if used, as FFMPEG scale filter prefers ':'
        resolution="${resolution//x/:}"
        scale_filter="-vf scale=$resolution" # Absolute scaling
        echo "Applying custom resolution: $resolution (--resolution)."
    else
        echo "Using original resolution."
        # No scale filter needed
    fi

    # --- Construct and Run Commands ---
    echo "Converting '$src' to '$target'..."
    echo "Parameters: FPS=$fps, Optimize=$optimize"

    # Build the ffmpeg command string (optional, for debugging)
    # local cmd="ffmpeg $ffmpeg_flags -i \"$src\" $scale_filter -pix_fmt rgb8 $fps_flag \"$target\""
    # echo "Running FFMPEG: $cmd"

    # Execute FFMPEG
    if ! ffmpeg $ffmpeg_flags -i "$src" $scale_filter -pix_fmt rgb8 $fps_flag "$target"; then
        echo "Error during FFMPEG conversion."
        return 1
    fi

    # Execute Gifsicle Optimization (if enabled)
    if [[ "$optimize" == true ]]; then
        echo "Optimizing '$target' with gifsicle..."
        # local gifsicle_cmd="gifsicle -O3 \"$target\" -o \"$target\""
        # echo "Running Gifsicle: $gifsicle_cmd"
        if ! gifsicle -O3 "$target" -o "$target"; then
            echo "Warning: gifsicle optimization failed, but GIF was created."
            # Decide if this should be a fatal error (return 1) or just a warning
        fi
    else
        echo "Skipping gifsicle optimization (--no-optimize)."
    fi

    # --- Notification (macOS specific) ---
    if command -v osascript &> /dev/null; then
        osascript -e "display notification \"'$target' successfully converted and saved\" with title \"Video to GIF Complete\""
    fi

    echo "Successfully created '$target'"
    return 0
}

# --- How to Use ---
# Place this function in your ~/.bashrc, ~/.zshrc, or save it as a script.
# Then source the file (e.g., source ~/.zshrc) or make the script executable.

# Examples:
# vid2gif_pro --src my_video.mov
# vid2gif_pro --src input.mp4 --target output_name.gif
# vid2gif_pro --src video.avi --fps 15
# vid2gif_pro --src large_video.mov --half-size
# vid2gif_pro --src details.mp4 --resolution 640:480 --fps 20
# vid2gif_pro --src raw.mov --no-optimize --target unoptimized.gif
```

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