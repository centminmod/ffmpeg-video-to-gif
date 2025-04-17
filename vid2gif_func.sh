#!/bin/bash
# File: (e.g., ~/.my_scripts/vid2gif_func.sh)
# Contains the updated vid2gif_pro function using a two-pass
# palettegen/paletteuse approach for better quality and size.
# Includes --half-size, --third-size, and --resolution options.
# Uses create-then-rename workaround for mktemp on macOS.

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
            shift 2 # past argument and value
            ;;
            --target)
            target="$2"
            shift 2
            ;;
            --resolution)
            resolution="$2" # e.g., 640:480 or 640x480
            shift 2
            ;;
            --fps)
            fps="$2"
            shift 2
            ;;
            --half-size)
            half_size=true
            shift 1 # past argument (it's a flag, no value)
            ;;
            --third-size)
            third_size=true
            shift 1 # past argument (it's a flag, no value)
            ;;
            --no-optimize)
            optimize=false
            shift 1
            ;;
            *)    # unknown option
            echo "Unknown option: $1" >&2
            echo "Usage: vid2gif_pro --src <input> [--target <output>] [--resolution <WxH>] [--fps <rate>] [--half-size] [--third-size] [--no-optimize]" >&2
            return 1
            ;;
        esac
    done

    # --- Input Validation ---
    if [[ -z "$src" ]]; then
        echo -e "\nError: Source file required. Use '--src <input video file>'.\n" >&2
        echo "Usage: vid2gif_pro --src <input> [--target <output>] [--resolution <WxH>] [--fps <rate>] [--half-size] [--third-size] [--no-optimize]" >&2
        return 1
    fi
    if [[ ! -f "$src" ]]; then
        echo -e "\nError: Source file not found: $src\n" >&2
        return 1
    fi

    # --- Determine Output Filename ---
    if [[ -z "$target" ]]; then
        local basename="${src%.*}"
        [[ "$basename" == "$src" ]] && basename="${src}_converted"
        target="$basename.gif"
    fi

    # --- Prepare Filters ---
    local filters=""
    local scale_applied_msg=""
    if [[ "$third_size" == true ]]; then
        filters="scale=iw/3:ih/3"
        scale_applied_msg="Applying ~33% scaling (--third-size)."
    elif [[ "$half_size" == true ]]; then
        filters="scale=iw/2:ih/2"
        scale_applied_msg="Applying 50% scaling (--half-size)."
    elif [[ -n "$resolution" ]]; then
        resolution="${resolution//x/:}"
        filters="scale=$resolution"
        scale_applied_msg="Applying custom resolution: $resolution (--resolution)."
    fi
    if [[ -n "$filters" ]]; then
        filters+=",fps=${fps}"
    else
        filters="fps=${fps}"
        scale_applied_msg="Using original resolution (adjusting FPS to $fps)."
    fi
    if [[ -n "$scale_applied_msg" ]]; then
       echo "$scale_applied_msg"
    fi

    # --- Temporary Palette File (Create -> Rename Workaround) ---
    local palette_file=""    # Final path with .png
    local base_temp_file=""  # Path created by mktemp initially
    echo "Attempting to create base temporary file..." # DEBUG

    # 1. Create a unique temporary file using a simple template
    base_temp_file=$(mktemp "${TMPDIR:-/tmp}/vid2gif_palette_XXXXXX")
    local mktemp_exit_code=$?

    # Check if base file creation succeeded
    if [[ $mktemp_exit_code -ne 0 || -z "$base_temp_file" || ! -f "$base_temp_file" ]]; then
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2
        echo "Error: Failed to create BASE temporary file using mktemp." >&2
        echo "mktemp exit code: $mktemp_exit_code" >&2
        echo "Attempted pattern: ${TMPDIR:-/tmp}/vid2gif_palette_XXXXXX" >&2
        echo "Resulting base_temp_file variable: '$base_temp_file'" >&2
        echo "TMPDIR is: '${TMPDIR:-/tmp}' - check permissions." >&2
        return 1
    fi
    echo "Base temporary file created: $base_temp_file" # DEBUG Success

    # 2. Construct the desired final filename with .png suffix
    palette_file="${base_temp_file}.png"
    echo "Attempting to rename base file to: $palette_file" # DEBUG

    # 3. Rename the base file to the final palette filename
    if ! mv "$base_temp_file" "$palette_file"; then
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2
        echo "Error: Failed to rename temporary file from '$base_temp_file' to '$palette_file'." >&2
        # Try to clean up the original file if rename failed
        rm -f "$base_temp_file"
        return 1
    fi
    echo "Temporary palette file created successfully: $palette_file" # DEBUG Success

    # 4. Ensure the RENAMED file ($palette_file) is cleaned up reliably
    # Define cleanup function AFTER palette_file name is known and file exists
    trap 'echo ">>> Cleaning up temporary palette: $palette_file"; rm -f "$palette_file"' EXIT INT TERM HUP
    # --- End of Temporary Palette File Section ---


    # --- Pass 1: Generate Palette ---
    echo "Pass 1: Generating palette (using filters: $filters)..."
    local palettegen_cmd_array=(
        "ffmpeg" "-y" "-v" "warning"
        "-i" "$src"
        "-vf" "${filters},palettegen=stats_mode=diff"
        "-update" "1"
        "$palette_file" # Use the renamed file path
    )
    if ! "${palettegen_cmd_array[@]}"; then
        echo "Error during palette generation. Check FFMPEG warnings above." >&2
        return 1 # trap will cleanup
    fi
    if [[ ! -s "$palette_file" ]]; then
       echo "Error: Palette file generation failed or created an empty file." >&2
       return 1 # trap will cleanup
    fi
    echo "Palette generation successful." # DEBUG

    # --- Pass 2: Generate GIF using Palette ---
    echo "Pass 2: Generating GIF using palette (dither: $dither_algo)..."
    local gifgen_cmd_array=(
        "ffmpeg" "-y" "-v" "quiet"
        "-i" "$src"
        "-i" "$palette_file" # Use the renamed file path
        "-filter_complex" "[0:v]${filters}[s]; [s][1:v]paletteuse=dither=${dither_algo}"
        "$target"
    )
    if ! "${gifgen_cmd_array[@]}"; then
        echo "Error during final GIF generation." >&2
        return 1 # trap will cleanup
    fi
    echo "GIF generation successful." # DEBUG

    # Palette file is automatically removed by trap

    # --- Execute Gifsicle Optimization (if enabled) ---
    if [[ "$optimize" == true ]]; then
        if [[ ! -f "$target" ]]; then
             echo "Warning: Target file '$target' not found after ffmpeg step. Skipping optimization." >&2
        else
            echo "Optimizing '$target' with gifsicle..."
            if ! gifsicle -O3 "$target" -o "$target"; then
                echo "Warning: gifsicle optimization failed, but GIF was created." >&2
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
        # Clean up trap explicitly ONLY on successful completion
        rm -f "$palette_file" # Ensure removal on success (trap will also run, but better safe)
        trap - EXIT INT TERM HUP # Disable trap
        return 0
    else
        echo "Error: Conversion finished, but target file '$target' was not found." >&2
        return 1 # trap will cleanup
    fi
}

# --- How to Use ---
# (Same as before: save, source, ensure dependencies ffmpeg/gifsicle are installed)