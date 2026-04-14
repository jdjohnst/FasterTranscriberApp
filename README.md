# FasterTranscriber

A comprehensive, local-only transcriber utilizing Faster Whisper and Ollama with a multithreading GUI via CustomTkinter.

FasterTranscriber is a simple, self-contained audio transcription assistant designed for macOS (M1 or newer recommended). It transcribes audio interviews using the OpenAI Whisper model (via Faster-Whisper), then formats and/or summarizes the transcript using LLaMA 3.2 via Ollama. All processing happens entirely on your computer, meaning that no internet or cloud services are used after installation. Your data never leaves your device, making the process as secure as your Mac itself.

## Installation

To install FasterTranscriber on a new Mac, simply open **Terminal** (`Cmd + Space` -> "Terminal") and paste the following block of code:

```bash
git clone https://github.com/jdjohnst/FasterTranscriber.git
cd FasterTranscriber
chmod +x install.sh
./install.sh
```

This will automatically download the codebase, configure Python, install all background dependencies, and place a launch icon on your Desktop. 
Launching the app for the first time will likely be delayed by a few seconds. Wait for at least 15 seconds before clicking again. You may have to search among open windows.

## System Requirements

- macOS 12.0 or later (Apple Silicon required — M1, M2, or M3)  
- At least 16GB RAM (larger RAM -> faster processing)
- At least 25GB of free disk space for models and transcribed audio  
- Your Mac may run hot and use a significant portion of CPU during transcription — this is expected. Begin transcription when plugged in and at 100% to reduce heat and improve performance.

## App Usage

1. Double-click the `FasterTranscriber.app` shortcut on your Desktop to launch the utility.
2. In the app window, choose an audio file from your Downloads folder and select a Whisper model:  
   - Larger Whisper models (like `large`) provide the most accurate transcriptions but require more memory and run slower.  
   - Smaller models (`base`, `small`) are faster and use less memory but may be less accurate. 
3. Choose your Operation Mode:  
   - **Format Transcript**: Outputs a readable script with appropriate syntax and punctuation. Speaker changes are hard to detect but it does a decent job.  
   - **Summarize Raw Transcript (Fast Mode)**: Bypasses formatting entirely and instantly summarizes the raw transcription. No accuracy is lost by skipping formatting.  
   - **Format & Summarize**: Performs both actions (very resource and time intensive).  
   *(If asking for a summary, you can select the Summary Context to dictate exactly how the AI takes notes)*
4. Click **Start Transcription**. The GUI progress bar will dynamically track segments.
5. When finished, up to three files will be saved to your Downloads folder:  
   - `[file_name]_raw_transcript.txt`
   - `[file_name]_labeled_transcript.txt`  
   - `[file_name]_summary.txt`

## Troubleshooting

- **App freezes or closes after pressing "Start Transcription":**  
  This usually means Faster-Whisper failed to load or run. Check `debug.log` to see if your system ran out of RAM, or try using the `base` model.
- **Ollama says it’s not running:**  
  The backend logic will automatically boot the Ollama daemon. If it fails, open Terminal and type `ollama serve` to start the server manually.

## Uninstallation

To completely remove the application and its background components from your system, open your terminal, navigate to the directory where you originally installed the app, and run the uninstallation script:

```bash
cd FasterTranscriber
./uninstall.sh
```

This will automatically stop any running transcriber background processes, remove the isolated Python environment, delete the Desktop launcher, and give you the option to completely uninstall the Ollama service. Once the script finishes, you can safely delete the cloned repository directory.
