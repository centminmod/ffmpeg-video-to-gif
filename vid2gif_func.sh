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