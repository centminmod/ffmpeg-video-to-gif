#!/bin/zsh
# Wrapper script for H.264 conversion via vid2gif_pro

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
source "$HOME/.my_scripts/vid2gif_func.sh"

for f in "$@"
do
  # --- Prepare output path ---
  dir=$(dirname "$f")
  filename_with_ext=$(basename "$f")
  base="${filename_with_ext%.*}"
  # Define output filename
  target_filename="${base}-h264_crf29.mp4"
  target_path="${dir}/${target_filename}"

  # --- Execute conversion ---
  vid2gif_pro --src "$f" --to-mp4-h264 --crf 29 --target "$target_path"
done