#!/bin/bash
# File: (e.g., ~/.my_scripts/vid2gif_func.sh)
# Contains the updated vid2gif_pro function using a two-pass
# palettegen/paletteuse approach for better quality and size.
# Includes --half-size, --third-size, --resolution, --fps options.
# Adds --lossy, --dither, --crop options and paletteuse optimizations.
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
    local lossy_level=""     # Gifsicle lossiness level [N] (optional)
    local dither_algo="sierra2_4a" # Dithering algorithm for paletteuse (optional)
    local crop_coords=""     # Crop dimensions W:H:X:Y (optional)

    # --- Parameter Parsing ---
    # More robust parsing using case statement
    while [[ $# -gt 0 ]]; do
        local key="$1"
        case $key in
            --src) src="$2"; shift 2 ;;
            --target) target="$2"; shift 2 ;;
            --resolution) resolution="$2"; shift 2 ;;
            --fps) fps="$2"; shift 2 ;;
            --half-size) half_size=true; shift 1 ;;
            --third-size) third_size=true; shift 1 ;;
            --no-optimize) optimize=false; shift 1 ;;
            --lossy)
                # Check if next argument is a number (level) or another option/end
                if [[ -z "$2" || "$2" == --* ]]; then
                    lossy_level="true" # Use default lossy value
                else
                    lossy_level="$2" # Use provided level
                    shift 1 # Consume the level value
                fi
                shift 1 # Consume --lossy
                ;;
            --dither) dither_algo="$2"; shift 2 ;;
            --crop) crop_coords="$2"; shift 2 ;; # Expect W:H:X:Y
            *)    # unknown option
            echo "Unknown option: $1" >&2
            echo "Usage: vid2gif_pro --src <input> [--target <output>] [--resolution <WxH>] [--fps <rate>]" >&2
            echo "                     [--half-size] [--third-size] [--no-optimize] [--lossy [level]]" >&2
            echo "                     [--dither <algo>] [--crop <W:H:X:Y>]" >&2
            return 1
            ;;
        esac
    done

    # --- Input Validation ---
    if [[ -z "$src" ]]; then
        echo -e "\nError: Source file required. Use '--src <input video file>'.\n" >&2
         echo "Usage: vid2gif_pro --src <input> [--target <output>] [--resolution <WxH>] [--fps <rate>]" >&2
         echo "                     [--half-size] [--third-size] [--no-optimize] [--lossy [level]]" >&2
         echo "                     [--dither <algo>] [--crop <W:H:X:Y>]" >&2
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
    # Build filter string: Crop -> Scale -> FPS
    local filters=""
    local filter_list=() # Use array to manage filter order easily

    # 1. Crop (if specified)
    if [[ -n "$crop_coords" ]]; then
        echo "Applying crop: $crop_coords"
        filter_list+=("crop=${crop_coords}")
    fi

    # 2. Scaling (Priority: --third-size > --half-size > --resolution > no scaling)
    local scale_applied_msg=""
    if [[ "$third_size" == true ]]; then
        filter_list+=("scale=iw/3:ih/3")
        scale_applied_msg="Applying ~33% scaling (--third-size)."
    elif [[ "$half_size" == true ]]; then
        filter_list+=("scale=iw/2:ih/2")
        scale_applied_msg="Applying 50% scaling (--half-size)."
    elif [[ -n "$resolution" ]]; then
        resolution="${resolution//x/:}" # Ensure ':' separator
        filter_list+=("scale=${resolution}")
        scale_applied_msg="Applying custom resolution: $resolution (--resolution)."
    fi

    # 3. FPS
    filter_list+=("fps=${fps}")
    if [[ -z "$scale_applied_msg" ]]; then
         scale_applied_msg="Using original resolution (adjusting FPS to $fps)."
    fi
    echo "$scale_applied_msg"

    # Join filters with comma
    local IFS=, # Set Internal Field Separator to comma
    filters="${filter_list[*]}" # Join array elements with comma
    unset IFS # Reset IFS


    # --- Temporary Palette File (Create -> Rename Workaround) ---
    local palette_file=""    # Final path with .png
    local base_temp_file=""  # Path created by mktemp initially
    # echo "Attempting to create base temporary file..." # DEBUG (commented out)

    base_temp_file=$(mktemp "${TMPDIR:-/tmp}/vid2gif_palette_XXXXXX")
    local mktemp_exit_code=$?
    if [[ $mktemp_exit_code -ne 0 || -z "$base_temp_file" || ! -f "$base_temp_file" ]]; then
        echo "Error: Failed to create BASE temporary file using mktemp (code: $mktemp_exit_code)." >&2
        return 1
    fi
    # echo "Base temporary file created: $base_temp_file" # DEBUG (commented out)

    palette_file="${base_temp_file}.png"
    # echo "Attempting to rename base file to: $palette_file" # DEBUG (commented out)
    if ! mv "$base_temp_file" "$palette_file"; then
        echo "Error: Failed to rename temporary file to '$palette_file'." >&2
        rm -f "$base_temp_file" # Clean up original
        return 1
    fi
    # echo "Temporary palette file created successfully: $palette_file" # DEBUG (commented out)
    trap 'rm -f "$palette_file"' EXIT INT TERM HUP


    # --- Pass 1: Generate Palette ---
    echo "Pass 1: Generating palette (using filters: $filters)..."
    local palettegen_cmd_array=(
        "ffmpeg" "-y" "-v" "warning"
        "-i" "$src"
        "-vf" "${filters},palettegen=stats_mode=diff" # Apply filters first
        "-update" "1"
        "$palette_file"
    )
    if ! "${palettegen_cmd_array[@]}"; then
        echo "Error during palette generation." >&2
        return 1
    fi
    if [[ ! -s "$palette_file" ]]; then
       echo "Error: Palette file generation failed or created an empty file." >&2
       return 1
    fi
    # echo "Palette generation successful." # DEBUG (commented out)

    # --- Pass 2: Generate GIF using Palette ---
    # Add diff_mode=rectangle to paletteuse for potential size saving
    local paletteuse_options="dither=${dither_algo}:diff_mode=rectangle"
    echo "Pass 2: Generating GIF (using filters: $filters, palette options: $paletteuse_options)..."
    local gifgen_cmd_array=(
        "ffmpeg" "-y" "-v" "quiet"
        "-i" "$src"
        "-i" "$palette_file"
        "-filter_complex" "[0:v]${filters}[s]; [s][1:v]paletteuse=${paletteuse_options}" # Apply filters & use palette
        "$target"
    )
    if ! "${gifgen_cmd_array[@]}"; then
        echo "Error during final GIF generation." >&2
        return 1
    fi
    # echo "GIF generation successful." # DEBUG (commented out)

    # Palette file is automatically removed by trap

    # --- Execute Gifsicle Optimization (if enabled) ---
    if [[ "$optimize" == true ]]; then
        if [[ ! -f "$target" ]]; then
             echo "Warning: Target file '$target' not found after ffmpeg step. Skipping optimization." >&2
        else
            local gifsicle_opts=()
            local lossy_msg=""
            if [[ -n "$lossy_level" ]]; then
                 if [[ "$lossy_level" == "true" ]]; then
                     gifsicle_opts+=("--lossy")
                     lossy_msg=" (lossy default)"
                 else
                     gifsicle_opts+=("--lossy=${lossy_level}")
                      lossy_msg=" (lossy=${lossy_level})"
                 fi
            fi
            gifsicle_opts+=("-O3")

            echo "Optimizing '$target' with gifsicle${lossy_msg}..."
            # Correct order: gifsicle [INPUT] [OPTIONS] -o [OUTPUT]
            # Or: gifsicle [OPTIONS] -o [OUTPUT] [INPUT]
            # Using: gifsicle -O3 --lossy=N -o output.gif input.gif
            if ! gifsicle "${gifsicle_opts[@]}" -o "$target" "$target"; then
                echo "Warning: gifsicle optimization failed, but GIF was created." >&2
            fi
         fi
    else
        echo "Skipping gifsicle optimization (--no-optimize)."
    fi

    # --- Notification (macOS specific) ---
    # ... (Notification code remains the same) ...
     if [[ -f "$target" ]] && command -v osascript &> /dev/null; then
        osascript -e "display notification \"'$target' successfully converted and saved\" with title \"Video to GIF Complete\""
    fi


    # --- Final Success Message ---
    # ... (Success message code remains the same) ...
     if [[ -f "$target" ]]; then
        echo "Successfully created '$target'"
        rm -f "$palette_file" # Ensure removal on success
        trap - EXIT INT TERM HUP # Disable trap
        return 0
    else
        echo "Error: Conversion finished, but target file '$target' was not found." >&2
        return 1 # trap will cleanup
    fi
}

# --- How to Use ---
# (Same as before: save, source, ensure dependencies ffmpeg/gifsicle are installed)
# Example: vid2gif_pro --src video.mov --fps 8
# Example: vid2gif_pro --src video.mov --half-size --lossy=80
# Example: vid2gif_pro --src video.mov --dither bayer --third-size
# Example: vid2gif_pro --src video.mov --crop 640:480:100:50 # Crop to 640x480 starting at x=100, y=50