Welcome to FasterTranscriberApp! Please read everything below before trying to install.

Explanation:
FasterTranscriberApp is a simple, self-contained audio transcription assistant designed for macOS (M1 or newer recommended). It transcribes audio interviews using the OpenAI Whisper model (via Faster-Whisper), then formats the transcript using LLaMA 3 via Ollama. All processing happens entirely on your computer, meaning that no internet or cloud services are used after installation. Your data never leaves your device, making the process as secure as your Mac itself.

This is not a native macOS application — it runs via Terminal and uses Python scripts with a basic graphical user interface (GUI) to help you start transcription jobs.


System Requirements:  
- macOS 12.0 or later (Apple Silicon required — M1, M2, or M3)  
- At least 16GB RAM (larger RAM -> faster processing)
- 8-core CPU or more (all M1 and newer Macs qualify)  
- Integrated Apple GPU (standard)  
- At least 25GB of free disk space for models and transcribed audio  
- Your Mac may run hot and use a significant portion of CPU during transcription — this is expected. Begin transcription when plugged in and at 100% to reduce heat and improve performance. If it feels too hot, run a fan or place a towel-covered ice pack underneath the device.


Installation Instructions:  
1. Double-click `InstallFasterTranscriberApp.command` to begin installation.  
2. Follow the prompts in Terminal. The script will install Python 3.11 (required), Homebrew, Tcl-Tk (for the graphical interface), and Ollama if they are not already present.  
3. During installation, your Mac may ask for your computer password to authorize changes. This is normal. When Terminal says "Password:", type your password and press Enter. (You won’t see the characters as you type — that’s expected. If you make a mistake, it will ask again.)  
4. Installation can take up to an hour depending on your internet speed and computer performance. Once installation begins, allow it to finish — you can continue using your Mac in the meantime. Troubleshooting tips are found below.

App Usage:
1. Once installation is complete for the first and only time, double-click `FasterTranscriberApp` on your Desktop to launch the transcription tool. You do not need to install anything again when you return to the tool later.
2. In the app window, choose an audio file from your Downloads folder and select a Whisper model:  
   - The first time you run the app with a given model (especially `large`), Faster-Whisper will need to load the model into memory, which may take several minutes. Subsequent uses will be faster.
   - Larger Whisper models (like `large`) provide the most accurate transcriptions but require more memory and run slower.  
   - Smaller models (`base`, `small`) are faster and use less memory but may be less accurate. Use these if you have limited RAM, want quicker results, or are working with shorter or clearer audio.  
3. Click "Start Transcription" — the GUI will close and the transcription will begin in Terminal.  
   - Transcription speed depends on the Whisper model selected and the length of the recording. For Large model, expect between 5 and 30 seconds of transcribing per 60 seconds of audio, then 5-10 seconds per minute of transcript formatting. This varies depending on system capabilities.
4. When finished, two files will be saved to your Downloads folder, named after the input file:  
   - A raw transcript (`[file_name]_raw_transcript.txt`)
   - A labeled, speaker-formatted transcript (`[file_name]_labeled_transcript.txt`)

Removal:  
1. You can uninstall everything by double-clicking `UNinstallFasterTranscriberApp.command` if you no longer want or need the tool.  
   - You will be prompted to keep or uninstall Ollama, the local AI program (like ChatGPT or Copilot), for your own later use  
   - If you choose not to uninstall Ollama, you can open your Terminal and type 'ollama run llama3' to ask questions like you would with any other internet-based AI program

---

Notes & Disclaimers:

- This tool is provided open-source, as-is, and is not an official application of Apple, OpenAI, or Meta.
- While it uses models developed by OpenAI (Whisper, via Faster-Whisper) and Meta (LLaMA 3), it runs entirely offline once installed. No part of the transcription process uses the internet or sends data to external servers.
- Transcription uses Faster-Whisper for better performance on local devices.
- Results will not be perfect, or even great. This tool is designed by an amateur and aims to quicken the manual transcription process for free.
- For best performance, use clearly recorded audio files. Excessively long, noisy, or low-quality audio may result in less accurate transcriptions. Whisper does not do well with people talking over each other.
- Labeled transcripts rely on AI inference for speaker changes and punctuation. Review and edit the output before using it in professional contexts.
- Due to the combination of open-source tools not originally intended to be used in conjunction, the transcript may contain unusual errors (excessively repeated words, words in a different language). It is recommended that the transcript is reviewed while listening to the original audio file.
- Use this tool responsibly. It is intended for transcribing conversations or interviews with proper consent.

System Behavior:  
- Transcription is CPU and GPU intensive. Your Mac’s integrated Apple GPU and CPU will be heavily utilized, which may cause increased fan noise, heat, and system load. This is normal and expected during transcription.  
- Running the app while plugged in and on a hard surface with good ventilation helps maintain performance and reduce thermal throttling.  
- If your laptop gets too hot or slows down significantly, find ways to cool it down gently (put it on a stand, remove cases, put ice packs underneath it (not directly on it)). This will improve performance.

Developed by Jacob Johnston 7/25

---

Troubleshooting:

If you run into issues during installation or transcription, try the following:

- **Terminal says 'Permission denied' when running `.command` files:**  
  Right-click the file, choose **Get Info**, and ensure the permissions at the bottom say "Read & Write" for your user. You can also run `chmod +x filename.command` in Terminal to make the file executable.

- **Python or Tkinter errors during install:**  
  Ensure you are running macOS 12.0 or later and that you allow the official Python installer to complete. Reboot your Mac and run the installer again if needed.

- **App freezes or closes after pressing "Start Transcription":**  
  This usually means Faster-Whisper failed to load or run. Try using a smaller Whisper model like `base` or `small`, and make sure the input file is supported and not corrupted.

- **Ollama says it’s not running:**  
  Open Terminal and type `ollama serve` to start the Ollama server manually. Make sure you’ve installed Ollama and pulled the `llama3` model (`ollama pull llama3`).

- **Audio file not showing up in the dropdown:**  
  Move your file into the Downloads folder and ensure it is in a supported format (`.mp3`, `.wav`, `.m4a`, `.mp4`, `.mov`, etc.).

- **Still stuck?**
  You can open the Terminal manually and navigate to `~/FasterTranscriberApp` and try running the app with:
  ```
  cd ~/FasterTranscriberApp
  source venv/bin/activate
  python transcriber_gui.py
  ```
  This may give more detailed error output for debugging.