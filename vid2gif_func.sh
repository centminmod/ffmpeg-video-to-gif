#!/bin/bash
# File: (e.g., ~/.my_scripts/vid2gif_func.sh)
# Contains the updated vid2gif_pro function using a two-pass
# palettegen/paletteuse approach for better quality and size.
# Includes --half-size, --third-size, and --resolution options.

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
    local half_size=false    # Scale to 50% width/height (optional)
    local third_size=false   # Scale to 33% width/height (optional, overrides half-size)
    local optimize=true      # Run gifsicle -O3 (optional, default true)
    local dither_algo="sierra2_4a" # Dithering algorithm for paletteuse (optional)

    # --- Parameter Parsing ---
    # More robust parsing using case statement
    while [[ $# -gt 0 ]]; do
        local key="$1"
        case $key in
            --src)
            src="$2"
            shift 2
            ;;
            --target)
            target="$2"
            shift 2
            ;;
            --resolution)
            resolution="$2"
            shift 2
            ;;
            --fps)
            fps="$2"
            shift 2
            ;;
            --half-size)
            half_size=true
            shift 1
            ;;
            --third-size)
            third_size=true
            shift 1
            ;;
            --no-optimize)
            optimize=false
            shift 1
            ;;
            *) 
            echo "Unknown option: $1"
            echo "Usage: vid2gif_pro --src <input> [--target <output>] [--resolution <WxH>] [--fps <rate>] [--half-size] [--third-size] [--no-optimize]"
            return 1
            ;;
        esac
    done

    # --- Input Validation ---
    if [[ -z "$src" ]]; then
        echo -e "\nError: Source file required. Use '--src <input video file>'.\n"
        # <<< UPDATED USAGE MESSAGE
        echo "Usage: vid2gif_pro --src <input> [--target <output>] [--resolution <WxH>] [--fps <rate>] [--half-size] [--third-size] [--no-optimize]"
        return 1
    fi
    if [[ ! -f "$src" ]]; then
        echo -e "\nError: Source file not found: $src\n"
        return 1
    fi

    # --- Determine Output Filename ---
    if [[ -z "$target" ]]; then
        local basename="${src%.*}"
        [[ "$basename" == "$src" ]] && basename="${src}_converted"
        target="$basename.gif"
    fi

    # --- Prepare Filters ---
    # Build filter string for ffmpeg's -vf or -filter_complex
    # Priority: --third-size > --half-size > --resolution > no scaling
    local filters=""
    local scale_applied_msg=""
    if [[ "$third_size" == true ]]; then # <<< CHECK THIRD FIRST
        filters="scale=iw/3:ih/3"
        scale_applied_msg="Applying ~33% scaling (--third-size)."
    elif [[ "$half_size" == true ]]; then # <<< CHECK HALF SECOND
        filters="scale=iw/2:ih/2"
        scale_applied_msg="Applying 50% scaling (--half-size)."
    elif [[ -n "$resolution" ]]; then # <<< CHECK RESOLUTION THIRD
        resolution="${resolution//x/:}" # Ensure ':' separator
        filters="scale=$resolution"
        scale_applied_msg="Applying custom resolution: $resolution (--resolution)."
    fi
    # Add fps filter - needs comma separator if scale filter already exists
    if [[ -n "$filters" ]]; then
        filters+=",fps=${fps}"
    else
        filters="fps=${fps}"
        # Set message here if only fps is applied (no scaling)
        scale_applied_msg="Using original resolution (adjusting FPS to $fps)."
    fi
    # Print status only once
    if [[ -n "$scale_applied_msg" ]]; then
       echo "$scale_applied_msg"
    fi


    # --- Temporary Palette File ---
    local palette_file
    # Use mktemp with a full path template ending in .png
    palette_file=$(mktemp "${TMPDIR:-/tmp}/vid2gif_palette_XXXXXXXXXX.png")
    trap 'rm -f "$palette_file"' EXIT INT TERM HUP

    # --- Pass 1: Generate Palette ---
    echo "Pass 1: Generating palette (using filters: $filters)..."
    local palettegen_cmd_array=(
        "ffmpeg" "-y" "-v" "warning"
        "-i" "$src"
        "-vf" "${filters},palettegen=stats_mode=diff"
        "-update" "1"
        "$palette_file"
    )
    if ! "${palettegen_cmd_array[@]}"; then
        echo "Error during palette generation. Check FFMPEG warnings above."
        return 1
    fi
    if [[ ! -s "$palette_file" ]]; then
       echo "Error: Palette file generation failed or created an empty file."
       return 1
    fi

    # --- Pass 2: Generate GIF using Palette ---
    echo "Pass 2: Generating GIF using palette (dither: $dither_algo)..."
    local gifgen_cmd_array=(
        "ffmpeg" "-y" "-v" "quiet"
        "-i" "$src"
        "-i" "$palette_file"
        "-filter_complex" "[0:v]${filters}[s]; [s][1:v]paletteuse=dither=${dither_algo}"
        "$target"
    )
    if ! "${gifgen_cmd_array[@]}"; then
        echo "Error during final GIF generation."
        return 1
    fi

    # Palette file is automatically removed by trap

    # --- Execute Gifsicle Optimization (if enabled) ---
    if [[ "$optimize" == true ]]; then
        if [[ ! -f "$target" ]]; then
             echo "Warning: Target file '$target' not found after ffmpeg step. Skipping optimization."
        else
            echo "Optimizing '$target' with gifsicle..."
            if ! gifsicle -O3 "$target" -o "$target"; then
                echo "Warning: gifsicle optimization failed, but GIF was created."
            fi
         fi
    else
        echo "Skipping gifsicle optimization (--no-optimize)."
    fi

    # --- Notification (macOS specific) ---
    if [[ -f "$target" ]] && command -v osascript &> /dev/null; then
        osascript -e "display notification \"'$target' successfully converted and saved\" with title \"Video to GIF Complete\""
    fi

    # --- Final Success Message ---
    if [[ -f "$target" ]]; then
        echo "Successfully created '$target'"
        return 0
    else
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
#    Example: vid2gif_pro --src screen_rec.mp4 --resolution 800:-1 # Keep aspect ratio
#    Example: vid2gif_pro --src another_video.mkv --third-size # <<< NEW EXAMPLE