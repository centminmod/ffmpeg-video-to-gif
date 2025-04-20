## macOS Integration: Automator Quick Actions for MP4 Conversion

This guide explains how to integrate the `vid2gif_pro` script with macOS Finder, allowing you to convert videos to MP4 (H.264 or H.265) directly from the right-click menu using Automator Quick Actions. Skipped instructions for AV1 conversion as the conversion takes too long and uses more resources.

This method uses helper "wrapper" scripts for reliability, ensuring `ffmpeg` and other necessary tools are found correctly.

### Prerequisites

1.  **`vid2gif_func.sh` Installed:** Ensure you have followed the main installation steps for the `vid2gif_pro` function, specifically that the `vid2gif_func.sh` file exists (e.g., at `~/.my_scripts/vid2gif_func.sh`).
2.  **`ffmpeg` Installed:** `ffmpeg` (and `x264`/`x265` libraries) must be installed, typically via Homebrew (`brew install ffmpeg`).
3.  **Text Editor:** You'll need a command-line text editor like `nano`.
4.  **Permissions:** You will need administrator privileges (`sudo`) to create files in `/usr/local/bin`.

### Step 1: Create Wrapper Scripts

We'll create two separate scripts in `/usr/local/bin`, one for H.264 conversion and one for H.265. These scripts will call your main `vid2gif_pro` function with specific settings.

**A. Create H.264 Wrapper Script:**

1.  Open the file in `nano` (this will create it if it doesn't exist):
    ```bash
    sudo nano /usr/local/vid2convert_wrapper_x264.sh
    ```
    *(Note: Changed name slightly for clarity)*

2.  Paste the following content into `nano`:
    ```bash
    #!/bin/zsh
    # Wrapper script for H.264 conversion via vid2gif_pro

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
      # Define output filename (customize CRF in name if desired)
      target_filename="${base}-h264_crf29.mp4"
      target_path="${dir}/${target_filename}"

      # --- Execute conversion ---
      # Customize flags (e.g., --crf value) as needed
      vid2gif_pro --src "$f" --to-mp4-h264 --crf 29 --target "$target_path"
    done
    ```

3.  Save and exit `nano`: Press `Ctrl+X`, then `Y`, then `Enter`.

4.  Make the script executable:
    ```bash
    sudo chmod +x /usr/local/vid2convert_wrapper_x264.sh
    ```

**B. Create H.265 Wrapper Script:**

1.  Open the file in `nano`:
    ```bash
    sudo nano /usr/local/vid2convert_wrapper_x265.sh
    ```

2.  Paste the following content into `nano`:
    ```bash
    #!/bin/zsh
    # Wrapper script for H.265 conversion via vid2gif_pro

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
      # Define output filename (customize CRF in name if desired)
      target_filename="${base}-h265_crf31.mp4" # Matched CRF 31 from your example
      target_path="${dir}/${target_filename}"

      # --- Execute conversion ---
      # Customize flags (e.g., --crf value) as needed
      vid2gif_pro --src "$f" --to-mp4-h265 --crf 31 --target "$target_path" # Matched CRF 31
    done
    ```

3.  Save and exit `nano`: Press `Ctrl+X`, then `Y`, then `Enter`.

4.  Make the script executable:
    ```bash
    sudo chmod +x /usr/local/vid2convert_wrapper_x265.sh
    ```

*(**Note:** I adjusted the CRF value in the H.265 script to 31 to match the filename you specified in your draft. Feel free to change the `--crf` value and the corresponding part of `target_filename` in both scripts to your preferred defaults.)*

### Step 2: Create Automator Quick Actions

Now, create a Quick Action for each wrapper script.

**A. Create H.264 Quick Action:**

1.  **Launch Automator** (from Applications folder or Spotlight).
2.  Select **File > New** (`⌘N`).
3.  Choose **Quick Action** and click **Choose**.
4.  At the top of the workflow pane, configure:
    * "Workflow receives current" → `movie files` (or `files or folders` for broader compatibility).
    * "in" → `Finder`.
    * *(Optional)* Choose an icon from the "Image" dropdown.
5.  In the Actions library search bar (left side), type `Run Shell Script` and drag the action to the workflow pane on the right.
6.  Configure the "Run Shell Script" action:
    * **Shell:** Select `/bin/zsh` (must match the `#!` line in your wrapper script).
    * **Pass input:** Select `as arguments`.
    * **Script Code:** Replace the default script content with this single line, pointing to your H.264 wrapper:
        ```bash
        /usr/local/vid2convert_wrapper_x264.sh "$@"
        ```
7.  **Save** the Quick Action: **File > Save** (`⌘S`).
8.  Enter a descriptive name that will appear in the right-click menu, e.g., `Convert to MP4 (H.264)`.

**B. Create H.265 Quick Action:**

1.  **Repeat** steps 1-5 above (Launch Automator, New Quick Action, Configure Workflow).
2.  **Configure** the "Run Shell Script" action:
    * **Shell:** `/bin/zsh`.
    * **Pass input:** `as arguments`.
    * **Script Code:** Use this single line, pointing to your H.265 wrapper:
        ```bash
        /usr/local/vid2convert_wrapper_x265.sh "$@"
        ```
3.  **Save** the Quick Action: **File > Save** (`⌘S`).
4.  Enter a descriptive name, e.g., `Convert to MP4 (H.265)`.

### Usage

1.  Navigate to a video file (or select multiple video files) in Finder.
2.  Right-click (or Control-click) on the selected file(s).
3.  Hover over **Quick Actions**.
4.  Select either `Convert to MP4 (H.264)` or `Convert to MP4 (H.265)`.

The conversion will start, using the settings defined in the corresponding wrapper script, and the output MP4 file will be saved in the same directory as the source file with the specified name (e.g., `inputfile-h264_crf29.mp4`).