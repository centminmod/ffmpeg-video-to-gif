Video to GIF conversion for MacOS users inspired by https://gist.github.com/SheldonWangRJT/8d3f44a35c8d1386a396b9b49b43c385 discussion.

~~~bash
vid2gif_pro --src cloudflare-security-rate-limit-analysis-170425-0.mov --half-size --target cloudflare-security-rate-limit-analysis-170425-half-0.gif
Converting 'cloudflare-security-rate-limit-analysis-170425-0.mov' to 'cloudflare-security-rate-limit-analysis-170425-half-0.gif'...
Parameters: FPS=10, Optimize=true
Applying 50% scaling (--half-size).
Executing FFMPEG command...
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

A combined version. It prioritizes explicit parameters (`--resolution`, `--fps`) but adds a `--half-size` flag inspired by `v2gif` and includes the `-y` and `-v quiet` flags.

```bash
#!/bin/bash
# File: (e.g., ~/.my_scripts/vid2gif_func.sh)
# Contains the updated vid2gif_pro function using an array for ffmpeg args.

# --- Combined video to GIF conversion function ---
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
            echo "Usage: vid2gif_pro --src <input> [--target <output>] [--resolution <WxH>] [--fps <rate>] [--half-size] [--no-optimize]"
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

    # --- Construct and Run Commands ---
    echo "Converting '$src' to '$target'..."
    echo "Parameters: FPS=$fps, Optimize=$optimize"

    # Build the ffmpeg command in an array for robustness
    local cmd_array=("ffmpeg")
    cmd_array+=("-y")           # Overwrite output
    cmd_array+=("-v" "quiet")   # Verbosity level quiet
    cmd_array+=("-i" "$src")    # Input file

    # Add scaling filter if specified
    local scale_applied=false
    if [[ "$half_size" == true ]]; then
        echo "Applying 50% scaling (--half-size)."
        cmd_array+=("-vf" "scale=iw/2:ih/2")
        scale_applied=true
    elif [[ -n "$resolution" ]]; then
        resolution="${resolution//x/:}" # Ensure ':' separator
        echo "Applying custom resolution: $resolution (--resolution)."
        cmd_array+=("-vf" "scale=$resolution")
        scale_applied=true
    fi
    # Only print "Using original resolution" if no scaling was applied
    if [[ "$scale_applied" == false ]]; then
        echo "Using original resolution."
        # No scaling arguments needed
    fi

    # Add remaining options and output file
    cmd_array+=("-pix_fmt" "rgb8")
    cmd_array+=("-r" "$fps")
    cmd_array+=("$target")

    # --- Execute FFMPEG ---
    echo "Executing FFMPEG command..."
    # Optional: uncomment the next line to see the exact arguments array being passed
    # printf "  Arg: '%s'\n" "${cmd_array[@]}"

    if ! "${cmd_array[@]}"; then
        echo "Error during FFMPEG conversion."
        # Optional: You could attempt to remove a potentially partially created target file
        # rm -f "$target"
        return 1
    fi

    # --- Execute Gifsicle Optimization (if enabled) ---
    if [[ "$optimize" == true ]]; then
        # Check if the target file was actually created before optimizing
        if [[ ! -f "$target" ]]; then
             echo "Warning: Target file '$target' not found after ffmpeg step. Skipping optimization."
        else
            echo "Optimizing '$target' with gifsicle..."
            if ! gifsicle -O3 "$target" -o "$target"; then
                echo "Warning: gifsicle optimization failed, but GIF was created."
                # Decide if this should be a fatal error (return 1) or just a warning
            fi
         fi
    else
        echo "Skipping gifsicle optimization (--no-optimize)."
    fi

    # --- Notification (macOS specific) ---
    # Check if target file exists before notifying success
    if [[ -f "$target" ]] && command -v osascript &> /dev/null; then
        osascript -e "display notification \"'$target' successfully converted and saved\" with title \"Video to GIF Complete\""
    fi

    # Final success message only if file exists
    if [[ -f "$target" ]]; then
        echo "Successfully created '$target'"
        return 0
    else
        # This case might occur if ffmpeg succeeded according to exit code, but produced no file
        echo "Error: Conversion finished, but target file '$target' was not found."
        return 1
    fi
}

# --- How to Use ---
# 1. Save this code:
#    - As a separate file (e.g., ~/".my_scripts/vid2gif_func.sh").
#    - OR paste directly into your ~/.zshrc (or ~/.bash_profile for Bash).
# 2. If saved as a separate file, add this line to your ~/.zshrc (or ~/.bash_profile):
#    if [[ -f ~/".my_scripts/vid2gif_func.sh" ]]; then
#      source ~/".my_scripts/vid2gif_func.sh"
#    fi
# 3. Apply changes:
#    - Open a new terminal window.
#    - OR run `source ~/.zshrc` (or `source ~/.bash_profile`).
# 4. Ensure dependencies are installed (Homebrew recommended on macOS):
#    brew install ffmpeg gifsicle
# 5. Run the function:
#    vid2gif_pro --src <input_video> [options...]
#    Example: vid2gif_pro --src my_video.mov --half-size --fps 15
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

```bash
declare -f vid2gif_pro

vid2gif_pro () {
    local src="" 
    local target="" 
    local resolution="" 
    local fps=10 
    local half_size=false 
    local optimize=true 
    while [[ $# -gt 0 ]]
    do
        local key="$1" 
        case $key in
            (--src) src="$2" 
                shift
                shift ;;
            (--target) target="$2" 
                shift
                shift ;;
            (--resolution) resolution="$2" 
                shift
                shift ;;
            (--fps) fps="$2" 
                shift
                shift ;;
            (--half-size) half_size=true 
                shift ;;
            (--no-optimize) optimize=false 
                shift ;;
            (*) echo "Unknown option: $1"
                return 1 ;;
        esac
    done
    if [[ -z "$src" ]]
    then
        echo -e "\nError: Source file required. Use '--src <input video file>'.\n"
        echo "Usage: vid2gif_pro --src <input> [--target <output>] [--resolution <WxH>] [--fps <rate>] [--half-size] [--no-optimize]"
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
    local ffmpeg_flags="-y -v quiet" 
    local fps_flag="-r $fps" 
    local scale_filter="" 
    if [[ "$half_size" == true ]]
    then
        scale_filter="-vf scale=iw/2:ih/2" 
        echo "Applying 50% scaling (--half-size)."
    elif [[ -n "$resolution" ]]
    then
        resolution="${resolution//x/:}" 
        scale_filter="-vf scale=$resolution" 
        echo "Applying custom resolution: $resolution (--resolution)."
    else
        echo "Using original resolution."
    fi
    echo "Converting '$src' to '$target'..."
    echo "Parameters: FPS=$fps, Optimize=$optimize"
    if ! ffmpeg $ffmpeg_flags -i "$src" $scale_filter -pix_fmt rgb8 $fps_flag "$target"
    then
        echo "Error during FFMPEG conversion."
        return 1
    fi
    if [[ "$optimize" == true ]]
    then
        echo "Optimizing '$target' with gifsicle..."
        if ! gifsicle -O3 "$target" -o "$target"
        then
            echo "Warning: gifsicle optimization failed, but GIF was created."
        fi
    else
        echo "Skipping gifsicle optimization (--no-optimize)."
    fi
    if command -v osascript &> /dev/null
    then
        osascript -e "display notification \"'$target' successfully converted and saved\" with title \"Video to GIF Complete\""
    fi
    echo "Successfully created '$target'"
    return 0
}
```