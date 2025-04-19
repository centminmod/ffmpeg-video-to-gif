#!/bin/bash
# File: (e.g., ~/.my_scripts/vid2gif_func.sh)
# Enhanced function to convert video to GIF or MP4 (H.264/H.265/AV1).
# Includes options for resolution, FPS, cropping, optimization, etc.
# Retains original name vid2gif_pro, adds alias vid2vid_pro.
# **Updated scaling logic to ensure even dimensions for codecs.**

# --- Enhanced video conversion function ---
vid2gif_pro() {
    # --- Defaults ---
    local src=""             # Input video file (required)
    local target=""          # Output file (optional, defaults based on conversion type)
    local resolution=""      # Specific output resolution e.g., 640:480 (optional)
    local fps=""             # Frames per second (optional, uses source default for MP4)
    local default_gif_fps=10 # Default FPS *only* for GIF output
    local half_size=false    # Scale to 50% width/height (optional)
    local third_size=false   # Scale to 33% width/height (optional, overrides half-size)
    local optimize_gif=true  # Run gifsicle -O3 for GIFs (optional, default true)
    local lossy_level=""     # Gifsicle lossiness level [N] (optional)
    local dither_algo="sierra2_4a" # Dithering algorithm for paletteuse (optional)
    local crop_coords=""     # Crop dimensions W:H:X:Y (optional)
    local output_format="gif" # Default output format
    local video_codec=""     # Codec for MP4 output (libx264, libx265, or libaom-av1)
    local crf=23             # Constant Rate Factor (default good for x264, adjust for others)
    local preset="medium"    # Encoding speed vs compression (less impact on libaom-av1)

    # --- Parameter Parsing ---
    while [[ $# -gt 0 ]]; do
        local key="$1"
        case $key in
            --src) src="$2"; shift 2 ;;
            --target) target="$2"; shift 2 ;;
            --resolution) resolution="$2"; shift 2 ;;
            --fps) fps="$2"; shift 2 ;; # Applies to GIF, optional override for MP4
            --half-size) half_size=true; shift 1 ;;
            --third-size) third_size=true; shift 1 ;;
            --crop) crop_coords="$2"; shift 2 ;; # Expect W:H:X:Y

            # GIF specific options
            --no-optimize) optimize_gif=false; shift 1 ;;
            --lossy)
                if [[ -z "$2" || "$2" == --* ]]; then
                    lossy_level="true"
                else
                    lossy_level="$2"; shift 1
                fi
                shift 1 ;;
            --dither) dither_algo="$2"; shift 2 ;;

            # MP4 specific options
            --to-mp4-h264) output_format="mp4"; video_codec="libx264"; shift 1 ;;
            --to-mp4-h265) output_format="mp4"; video_codec="libx265"; shift 1 ;;
            --to-mp4-av1) output_format="mp4"; video_codec="libaom-av1"; shift 1 ;; # Added AV1
            --crf) crf="$2"; shift 2 ;;
            --preset) preset="$2"; shift 2 ;;

            *)    # unknown option
            echo "Unknown option: $1" >&2
            echo "Usage: vid2gif_pro --src <input> [--target <output>] [options]" >&2
            echo "  Conversion Type:" >&2
            echo "    --to-mp4-h264      Output MP4 with H.264" >&2
            echo "    --to-mp4-h265      Output MP4 with H.265/HEVC" >&2
            echo "    --to-mp4-av1       Output MP4 with AV1 (slow!)" >&2
            echo "    (Default: GIF)" >&2
            echo "  General Options:" >&2
            echo "    --resolution <WxH> Scale output" >&2
            echo "    --half-size        Scale to 50%" >&2
            echo "    --third-size       Scale to ~33%" >&2
            echo "    --crop <W:H:X:Y>   Crop video" >&2
            echo "  GIF Specific:" >&2
            echo "    --fps <rate>       Set GIF frame rate (default: $default_gif_fps)" >&2
            echo "    --no-optimize      Disable gifsicle optimization" >&2
            echo "    --lossy [level]    Enable gifsicle lossy compression" >&2
            echo "    --dither <algo>    Set paletteuse dither algorithm (default: $dither_algo)" >&2
            echo "  MP4 Specific:" >&2
            echo "    --fps <rate>       Override source frame rate (use carefully)" >&2
            echo "    --crf <value>      Set Constant Rate Factor (default: $crf, adjust for codec)" >&2
            echo "    --preset <name>    Set encoding preset (default: $preset, less effect on AV1)" >&2
            return 1
            ;;
        esac
    done

    # --- Input Validation ---
    if [[ -z "$src" ]]; then
        echo -e "\nError: Source file required. Use '--src <input video file>'.\n" >&2
        return 1
    fi
    if [[ ! -f "$src" ]]; then
        echo -e "\nError: Source file not found: $src\n" >&2
        return 1
    fi
    if [[ "$output_format" == "mp4" && -z "$video_codec" ]]; then
        echo "Warning: MP4 output requested but no codec specified. Defaulting to H.264." >&2
        video_codec="libx264"
    fi


    # --- Determine Output Filename ---
    if [[ -z "$target" ]]; then
        local basename="${src%.*}"
        [[ "$basename" == "$src" ]] && basename="${src}_converted"
        local codec_suffix=""
        if [[ "$output_format" == "mp4" ]]; then
            codec_suffix="-${video_codec}" # e.g., -libx264, -libaom-av1
        fi
        target="$basename${codec_suffix}.${output_format}" # e.g., video-libx264.mp4 or video.gif
    fi

    # --- Prepare Filters ---
    local filters=""
    local filter_list=()
    local scale_filter="" # Store scale filter separately
    local scale_applied_msg=""

    # 1. Scaling (Ensure dimensions are divisible by 2 for video codecs)
    if [[ "$third_size" == true ]]; then
        # Scale width to 1/3, calculate height preserving aspect ratio, ensure height is even
        scale_filter="scale=iw/3:-2"
        scale_applied_msg="Applying ~33% scaling (--third-size, ensuring even dimensions)."
    elif [[ "$half_size" == true ]]; then
        # Scale width to 1/2, calculate height preserving aspect ratio, ensure height is even
        scale_filter="scale=iw/2:-2"
        scale_applied_msg="Applying 50% scaling (--half-size, ensuring even dimensions)."
    elif [[ -n "$resolution" ]]; then
        # Use specified resolution, ensure dimensions are even friendly
        local width_res=$(echo "$resolution" | cut -d':' -f1 | cut -d'x' -f1)
        local height_res=$(echo "$resolution" | cut -d':' -f2 | cut -d'x' -f2)
        if [[ "$width_res" =~ ^[0-9]+$ ]] && [[ "$height_res" =~ ^[0-9]+$ ]]; then
            # If both W and H provided, force width, calculate height to be even
             scale_filter="scale=${width_res}:-2"
             scale_applied_msg="Applying custom resolution (W=${width_res}, H=auto-even) (--resolution)."
             # If H matters more: scale_filter="scale=-2:${height_res}"
        elif [[ "$width_res" =~ ^[0-9]+$ ]]; then # Only W provided (e.g., 640x?)
             scale_filter="scale=${width_res}:-2"
             scale_applied_msg="Applying custom resolution (W=${width_res}, H=auto-even) (--resolution)."
        elif [[ "$height_res" =~ ^[0-9]+$ ]]; then # Only H provided (e.g., ?x480)
             scale_filter="scale=-2:${height_res}"
             scale_applied_msg="Applying custom resolution (W=auto-even, H=${height_res}) (--resolution)."
        else
            echo "Warning: Invalid resolution format '$resolution'. Ignoring." >&2
        fi
    fi
    if [[ -n "$scale_filter" ]]; then
         filter_list+=("$scale_filter")
    fi


    # 2. Crop (if specified) - Applied *before* scaling typically makes sense
    if [[ -n "$crop_coords" ]]; then
        echo "Applying crop: $crop_coords"
        # Insert crop filter at the beginning of the list
        filter_list=("crop=${crop_coords}" "${filter_list[@]}")
    fi

    # 3. FPS (Handled differently for GIF vs MP4)
    local effective_fps=$fps # User specified FPS
    if [[ "$output_format" == "gif" ]]; then
        if [[ -z "$effective_fps" ]]; then
            effective_fps=$default_gif_fps
        fi
        # Add fps filter *after* scaling/cropping for GIF
        filter_list+=("fps=${effective_fps}")
        if [[ -z "$scale_applied_msg" && -z "$crop_coords" ]]; then
             scale_applied_msg="Using original resolution (adjusting FPS to $effective_fps)."
        elif [[ -z "$scale_applied_msg" ]]; then
             scale_applied_msg="(adjusting FPS to $effective_fps)." # Append FPS info if other filters applied
        fi
    elif [[ -n "$effective_fps" ]]; then
         # FPS for MP4 will be handled by the -r flag, not filtergraph unless needed for complex chains
         if [[ -z "$scale_applied_msg" && -z "$crop_coords" ]]; then
             scale_applied_msg="Using original resolution (adjusting FPS to $effective_fps)."
         elif [[ -z "$scale_applied_msg" ]]; then
              scale_applied_msg="(adjusting FPS to $effective_fps)."
         fi
    elif [[ -z "$scale_applied_msg" && -z "$crop_coords" ]]; then
         # No scaling, no cropping, no FPS change mentioned
         scale_applied_msg="Using original resolution and frame rate."
    fi


    if [[ -n "$scale_applied_msg" ]]; then
        # Display the final scaling/FPS message
        echo "$scale_applied_msg"
    fi

    # Join filters with comma
    local IFS=,
    filters="${filter_list[*]}"
    unset IFS

    # --- Execute Conversion ---
    local exit_code=0
    if [[ "$output_format" == "gif" ]]; then
        # --- GIF Conversion (Two-Pass) ---
        local palette_file=""
        local base_temp_file=""
        base_temp_file=$(mktemp "${TMPDIR:-/tmp}/vid2gif_palette_XXXXXX")
        local mktemp_exit_code=$?
        if [[ $mktemp_exit_code -ne 0 || -z "$base_temp_file" || ! -f "$base_temp_file" ]]; then
             echo "Error: Failed to create BASE temporary file using mktemp (code: $mktemp_exit_code)." >&2
             return 1
        fi
        palette_file="${base_temp_file}.png"
        if ! mv "$base_temp_file" "$palette_file"; then
            echo "Error: Failed to rename temporary file to '$palette_file'." >&2
            rm -f "$base_temp_file"
            return 1
        fi
        trap 'rm -f "$palette_file"' EXIT INT TERM HUP

        echo "Pass 1: Generating palette (using filters: $filters)..."
        # Build command array for palette generation
        local palettegen_cmd_array=("ffmpeg" "-y" "-v" "warning" "-i" "$src")
        # Append filters only if $filters is not empty
        if [[ -n "$filters" ]]; then
            palettegen_cmd_array+=("-vf" "${filters},palettegen=stats_mode=diff")
        else
            palettegen_cmd_array+=("-vf" "palettegen=stats_mode=diff")
        fi
        palettegen_cmd_array+=("-update" "1" "$palette_file")

        # Execute palette generation
        if ! "${palettegen_cmd_array[@]}"; then
            echo "Error during palette generation." >&2
            exit_code=1
        elif [[ ! -s "$palette_file" ]]; then
           echo "Error: Palette file generation failed or created an empty file." >&2
           exit_code=1
        else
            # --- Pass 2: Generate GIF ---
            local paletteuse_options="dither=${dither_algo}:diff_mode=rectangle"
            echo "Pass 2: Generating GIF (using filters: $filters, palette options: $paletteuse_options)..."
            # Build command array for GIF generation
            local gifgen_cmd_array=("ffmpeg" "-y" "-v" "quiet" "-i" "$src" "-i" "$palette_file")
            # Construct filter_complex argument carefully
            local filter_complex_str=""
            if [[ -n "$filters" ]]; then
                # Apply filters first, then use palette
                filter_complex_str="[0:v]${filters}[s]; [s][1:v]paletteuse=${paletteuse_options}"
            else
                # No pre-filters, just use palette
                filter_complex_str="[0:v]paletteuse=${paletteuse_options}[out]" # Need output label if no filter chain
                 # If just using paletteuse directly, no explicit [out] might be needed, ffmpeg often infers.
                 # Let's simplify assuming ffmpeg handles it if no pre-filter:
                 filter_complex_str="[0:v][1:v]paletteuse=${paletteuse_options}"
            fi
            gifgen_cmd_array+=("-filter_complex" "$filter_complex_str")
            gifgen_cmd_array+=("$target")

            # Execute GIF generation
            if ! "${gifgen_cmd_array[@]}"; then
                echo "Error during final GIF generation." >&2
                exit_code=1
            else
                 # --- Gifsicle Optimization ---
                 if [[ "$optimize_gif" == true ]]; then
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
                         if ! gifsicle "${gifsicle_opts[@]}" -o "$target" "$target"; then
                             echo "Warning: gifsicle optimization failed, but GIF was created." >&2
                         fi
                      fi
                 else
                     echo "Skipping gifsicle optimization (--no-optimize)."
                 fi
            fi
        fi
        rm -f "$palette_file" # Clean up palette file
        trap - EXIT INT TERM HUP # Disable trap

    elif [[ "$output_format" == "mp4" ]]; then
        # --- MP4 Conversion (Single Pass) ---
        local conv_msg="Converting to MP4 ($video_codec)..."
        if [[ "$video_codec" == "libaom-av1" ]]; then conv_msg+=" This might take a while."; fi
        echo "$conv_msg"

        local mp4_cmd_array=( "ffmpeg" "-y" "-v" "warning" "-i" "$src" )

        # Add video filters if any were defined
        if [[ -n "$filters" ]]; then
            mp4_cmd_array+=( "-vf" "$filters" )
        fi

        # Add video codec options
        mp4_cmd_array+=( "-c:v" "$video_codec" )
        if [[ "$video_codec" == "libaom-av1" ]]; then
             mp4_cmd_array+=( "-crf" "$crf" )
             mp4_cmd_array+=( "-b:v" "0" ) # Needed for CRF mode in libaom-av1
             mp4_cmd_array+=( "-strict" "experimental" ) # May be needed depending on ffmpeg version
        else # libx264, libx265
             mp4_cmd_array+=( "-preset" "$preset" )
             mp4_cmd_array+=( "-crf" "$crf" )
        fi

        # Add audio options (or disable audio if source lacks it)
        # Probing audio stream using ffprobe for better reliability
        local has_audio=false
        if command -v ffprobe &> /dev/null; then
            # Check if ffprobe finds any audio stream
            if ffprobe -v error -select_streams a:0 -show_entries stream=codec_type -of csv=p=0 "$src" &> /dev/null; then
                has_audio=true
            fi
        else
             # Fallback: Use ffmpeg check if ffprobe not found (less reliable)
             if ffmpeg -i "$src" -vn -c:a copy -f null - -v error &> /dev/null; then
                  has_audio=true
             fi
             echo "Warning: ffprobe not found. Using less reliable audio detection." >&2
        fi

        if [[ "$has_audio" == true ]]; then
             mp4_cmd_array+=( "-c:a" "aac" ) # Set audio codec (AAC is common for MP4)
             mp4_cmd_array+=( "-b:a" "128k" ) # Set audio bitrate (adjust as needed)
        else
             mp4_cmd_array+=( "-an" ) # Explicitly disable audio
             echo "Info: No audio stream detected in source. Disabling audio output (-an)."
        fi

        mp4_cmd_array+=( "-movflags" "+faststart" ) # Optimize for web streaming

        # Override FPS if specified by user for MP4
        if [[ -n "$effective_fps" ]]; then
             mp4_cmd_array+=( "-r" "$effective_fps" )
             echo "Overriding output frame rate to $effective_fps fps."
        fi

        mp4_cmd_array+=( "$target" ) # Output file

        # For debugging uncomment the next line:
        # echo "Executing: ${mp4_cmd_array[@]}"

        # Execute command
        if ! "${mp4_cmd_array[@]}"; then
             echo "Error during MP4 conversion." >&2
             exit_code=1
        fi
    else
        echo "Error: Unsupported output format '$output_format'" >&2
        return 1
    fi

    # --- Notification and Final Message ---
    if [[ $exit_code -eq 0 && -f "$target" ]]; then
        echo "Successfully created '$target'"
        if command -v osascript &> /dev/null; then
             local notification_title="Conversion Complete"
             if [[ "$output_format" == "gif" ]]; then notification_title="GIF Creation Complete"; fi
            osascript -e "display notification \"'$target' successfully converted and saved\" with title \"$notification_title\""
        fi
        return 0
    else
        echo "Error: Conversion failed or target file '$target' was not found." >&2
        return 1
    fi
}

# --- Alias ---
# Create an alias vid2vid_pro pointing to vid2gif_pro
alias vid2vid_pro='vid2gif_pro'

# --- How to Use ---
# 1. Save this code to a file, e.g., ~/.my_scripts/vid2gif_func.sh
# 2. Make it executable: chmod +x ~/.my_scripts/vid2gif_func.sh
# 3. Source it in your ~/.bashrc or ~/.zshrc:
#    if [[ -f ~/.my_scripts/vid2gif_func.sh ]]; then
#        source ~/.my_scripts/vid2gif_func.sh
#    fi
# 4. Reload your shell: source ~/.zshrc OR source ~/.bashrc
# 5. Ensure ffmpeg (with libaom enabled for AV1), ffprobe, and gifsicle are installed.
#    Check AV1 support: ffmpeg -codecs | grep libaom
#    Install/update: brew install ffmpeg gifsicle
#
# --- Examples ---
# Convert MOV to GIF (default) using original name
# vid2gif_pro --src input.mov
#
# Convert MOV to MP4 H.265 using alias
# vid2vid_pro --src input.mov --to-mp4-h265 --crf 26
#
# Convert MOV to MP4 AV1, third size (expect long processing time)
# vid2gif_pro --src input.mov --to-mp4-av1 --third-size --crf 35