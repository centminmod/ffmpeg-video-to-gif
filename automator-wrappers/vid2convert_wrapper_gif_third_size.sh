#!/bin/zsh
# Wrapper script for GIF (1/3 size) conversion via vid2gif_pro

# Ensure Homebrew executables are found
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Source the main function script (adjust path if needed)
source "$HOME/.my_scripts/vid2gif_func.sh"

# Process each file passed from Finder
for f in "$@"
do
  # --- Prepare output path ---
  dir=$(dirname "$f")
  filename_with_ext=$(basename "$f")
  base="${filename_with_ext%.*}"
  # Define output filename
  target_filename="${base}-third_size.gif"
  target_path="${dir}/${target_filename}"

  # --- Execute conversion ---
  # vid2gif_pro defaults to GIF if no --to-mp4-* flag is given
  # Add other GIF flags like --fps or --lossy here if desired
  vid2gif_pro --src "$f" --third-size --lossy --dither bayer --target "$target_path"
done