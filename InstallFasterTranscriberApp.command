#!/usr/bin/env bash

# Log all output to a file for debugging
exec > >(tee ~/FasterTranscriberApp/install_log.txt) 2>&1

# Load shell profiles to ensure environment variables are set
[ -f "$HOME/.zprofile" ] && source "$HOME/.zprofile"
[ -f "$HOME/.zshrc" ] && source "$HOME/.zshrc"
[ -f "$HOME/.bash_profile" ] && source "$HOME/.bash_profile"


# Check and install official Python 3.11 with tkinter support if missing
echo "Searching for Python 3.11 with tkinter support..."
PYTHON_PKG_PATH="/Library/Frameworks/Python.framework/Versions/3.11/bin/python3"
if [ ! -x "$PYTHON_PKG_PATH" ]; then
  echo "Python 3.11 not found at $PYTHON_PKG_PATH."
  echo "Downloading and installing official Python 3.11 from python.org..."
  curl -o /tmp/python3.11.pkg https://www.python.org/ftp/python/3.11.9/python-3.11.9-macos11.pkg
  sudo installer -pkg /tmp/python3.11.pkg -target /
  rm /tmp/python3.11.pkg
fi
PYTHON_PATH="$PYTHON_PKG_PATH"

if ! "$PYTHON_PATH" -V | grep -q "Python 3.11"; then
  echo "Error: Python 3.11 was not correctly installed."
  exit 1
fi

if ! "$PYTHON_PATH" -c "import tkinter" &>/dev/null; then
  echo "tkinter not found. Attempting to install system libraries and link Tcl/Tk..."
  brew install python-tk@3.11
  brew link python-tk@3.11
  # Try again
  if ! "$PYTHON_PATH" -c "import tkinter" &>/dev/null; then
    echo "tkinter installation failed. Please check your Python configuration or install tkinter manually."
    exit 1
  fi
fi
echo "Using Python at: $PYTHON_PATH"


# --- Install global Python packages (for CLI fallback use) ---
echo "Installing global Python packages (for CLI fallback use)..."
"$PYTHON_PATH" -m pip install --upgrade pip
"$PYTHON_PATH" -m pip install faster-whisper requests

echo "Setting up FasterTranscriberApp..."

# --- Check if Homebrew is installed; install if not ---
if ! command -v brew &>/dev/null; then
  echo "Homebrew not found. Installing..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi


# --- Install Tcl-Tk support (for tkinter GUI) ---
echo "Installing Tcl-Tk support (for tkinter GUI)..."
brew install tcl-tk

# --- Install ffmpeg (required for Whisper to decode audio) ---
echo "Installing ffmpeg (required for Whisper to decode audio)..."
brew install ffmpeg


 # Set environment variables to help Python locate Tcl-Tk in all relevant shell profiles
if ! grep -q '# >>> FasterTranscriberApp Tcl-Tk Setup >>>' ~/.zshrc; then
  {
    echo '# >>> FasterTranscriberApp Tcl-Tk Setup >>>'
    echo 'export LDFLAGS="-L/opt/homebrew/opt/tcl-tk/lib"'
    echo 'export CPPFLAGS="-I/opt/homebrew/opt/tcl-tk/include"'
    echo 'export PKG_CONFIG_PATH="/opt/homebrew/opt/tcl-tk/lib/pkgconfig"'
    echo '# <<< FasterTranscriberApp Tcl-Tk Setup <<<'
  } >> ~/.zshrc
fi

for PROFILE in ~/.zprofile ~/.bash_profile; do
  if [ -f "$PROFILE" ] && ! grep -q '# >>> FasterTranscriberApp Tcl-Tk Setup >>>' "$PROFILE"; then
    {
      echo '# >>> FasterTranscriberApp Tcl-Tk Setup >>>'
      echo 'export LDFLAGS="-L/opt/homebrew/opt/tcl-tk/lib"'
      echo 'export CPPFLAGS="-I/opt/homebrew/opt/tcl-tk/include"'
      echo 'export PKG_CONFIG_PATH="/opt/homebrew/opt/tcl-tk/lib/pkgconfig"'
      echo '# <<< FasterTranscriberApp Tcl-Tk Setup <<<'
    } >> "$PROFILE"
  fi
done

source ~/.zshrc
source ~/.zprofile
source ~/.bash_profile



# --- Install Ollama if needed ---
if ! command -v ollama &>/dev/null; then
  echo "Installing Ollama..."
  brew install ollama
fi

echo "Pulling llama3.2 model (if not already present)..."
ollama pull llama3.2

 # --- Set up application directory and Python virtual environment ---
mkdir -p ~/FasterTranscriberApp
cd ~/FasterTranscriberApp || exit

echo "Creating Python virtual environment..."
if [ ! -d "venv" ]; then
  "$PYTHON_PATH" -m venv venv
fi
source venv/bin/activate

echo "Installing Python packages..."
# Note: faster-whisper includes CTranslate2 for optimized inference; no need to install torch or ctranslate2 separately.
pip install --upgrade pip
pip install faster-whisper requests

echo "Saving GUI script..."
cat <<'EOF' > transcriber_gui.py
#!/usr/bin/env python3
import os
import glob
import threading
import tkinter as tk
from tkinter import ttk, messagebox
import time
import subprocess
import traceback
from faster_whisper import WhisperModel  # Uses CTranslate2 backend (no PyTorch)
import requests
import sys

CHUNK_SIZE = 250

OLLAMA_HOST = "http://localhost:11434"
OLLAMA_MODEL = "llama3.2"

SUMMARY_PROMPTS = {
    "General": {
        "chunk": "Provide a concise, bulleted summary of the most critical specific points, decisions, and takeaways from this section.",
        "combine": "1. Executive Summary (2-3 sentences max)\n2. Key Takeaways (use bullet points to list the most important specific details)\n3. Action Items or Decisions (if applicable)"
    },
    "Lecture / Presentation": {
        "chunk": "Act as an expert student taking highly detailed notes. Extract all key concepts, formulas, dates, definitions, and critical facts mentioned in this section.",
        "combine": "1. Lecture Topic Overview (1-2 sentences)\n2. Detailed Course Notes (use nested bullet points heavily; capture specific facts, dates, principles, or formulas)\n3. Key Vocabulary & Definitions\n4. Main Conclusions or 'Exam' Takeaways"
    },
    "Meeting / Group Discussion": {
        "chunk": "Act as a meticulous meeting secretary. Extract all distinct discussion topics, final decisions, unresolved parked items, and specific tasks/action items mentioned in this section.",
        "combine": "1. Meeting Overview (2-3 sentences max)\n2. Detailed Discussion Recap (bullet out what was specifically discussed, grouped by topic)\n3. Conclusions & Key Decisions\n4. Unresolved Topics / Things to Come Back To\n5. Action Items (Tasks to be done, including owners if mentioned)"
    },
    "Interview / Conversation": {
        "chunk": "Provide a concise, bulleted breakdown of the core subject, perspectives or stances mentioned, and any specific quotes or insights.",
        "combine": "1. Core Subject & Outcome (2-3 sentences max)\n2. Perspectives / Stances (bullet points identifying key speakers' views)\n3. Important Quotes or Unique Insights\n4. Conversation Outcome"
    }
}

def list_downloads_files():
    """
    List audio files in the user's Downloads directory, sorted by modification time (newest first).
    """
    downloads_folder = os.path.expanduser("~/Downloads")
    files = sorted(
        glob.glob(os.path.join(downloads_folder, "*")),
        key=os.path.getmtime,
        reverse=True
    )
    audio_files = [f for f in files if f.lower().endswith((".mp3", ".wav", ".m4a", ".aac", ".flac", ".ogg", ".mp4"))]
    return audio_files

def convert_to_wav(audio_file):
    """
    Safely convert any media file to a 16kHz WAV using FFmpeg.
    This bypasses native PyAV container parsing errors for complex mp4 files.
    """
    print(f"Pre-processing media file with FFmpeg: {os.path.basename(audio_file)}")
    temp_dir = os.path.expanduser("~/Downloads")
    base_name = os.path.splitext(os.path.basename(audio_file))[0]
    temp_wav = os.path.join(temp_dir, f".{base_name}_temp_conv.wav")
    
    import shutil
    ffmpeg_cmd = shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"
    try:
        subprocess.run(
            [ffmpeg_cmd, "-y", "-i", audio_file, "-vn", "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", temp_wav],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True
        )
        return temp_wav
    except Exception as e:
        print(f"[WARN] FFmpeg conversion failed. Falling back to native PyAV reader: {e}")
        return audio_file

def transcribe_audio(audio_file, model_size):
    print(f"Loading Faster-Whisper model: {model_size}")
    model = WhisperModel(model_size, compute_type="default")  # optimized automatically
    
    safe_audio = convert_to_wav(audio_file)
    
    segments_generator, _ = model.transcribe(safe_audio)
    segments = []
    for i, segment in enumerate(segments_generator, 1):
       print(f"[Segment {i}] {segment.text}")
       segments.append(segment)
    full_text = "\n".join([segment.text for segment in segments])
    print("[INFO] Faster-Whisper transcription completed successfully.")
    
    if safe_audio != audio_file and os.path.exists(safe_audio):
        try:
            os.remove(safe_audio)
        except Exception:
            pass
            
    return {"text": full_text}

def save_transcript(result, audio_file):
    """
    Save the raw transcription text to a file in the Downloads directory.
    """
    base_name = os.path.splitext(os.path.basename(audio_file))[0]
    out_dir = os.path.expanduser("~/Downloads")
    out_file = os.path.join(out_dir, base_name + "_raw_transcript.txt")
    with open(out_file, "w", encoding="utf-8") as f:
        f.write(result["text"])
    print(f"Raw transcript saved to: {out_file}")
    return out_file

def chunk_text(text, chunk_size=CHUNK_SIZE):
    """
    Split the transcript text into chunks of approximately chunk_size words.
    """
    words = text.split()
    chunks = []
    for i in range(0, len(words), chunk_size):
        chunks.append(" ".join(words[i:i+chunk_size]))
    return chunks

def check_ollama_running():
    """
    Check if the Ollama server is running and accessible.
    If not, attempt to start it automatically.
    """
    try:
        response = requests.get(f"{OLLAMA_HOST}/api/tags", timeout=2)
        if response.status_code == 200:
            return True
    except requests.exceptions.RequestException:
        pass

    print("[INFO] Ollama is not currently running. Attempting to start 'ollama serve' automatically...")
    try:
        subprocess.Popen(["ollama", "serve"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        # Wait up to 10 seconds for the server to initialize
        for i in range(10):
            time.sleep(1)
            try:
                response = requests.get(f"{OLLAMA_HOST}/api/tags", timeout=2)
                if response.status_code == 200:
                    print("[INFO] Ollama started successfully.")
                    return True
            except requests.exceptions.RequestException:
                pass
    except Exception as e:
        print(f"[ERROR] Could not start Ollama automatically: {e}")

    print("[WARN] Ollama server not reachable at localhost:11434")
    return False

def label_chunk(chunk, idx, total, ollama_model=OLLAMA_MODEL):
    """
    Send a chunk of transcript to Ollama for speaker labeling and punctuation correction.
    """
    instruction_part = """You are given a raw transcript of a real spoken conversation.

Instructions:
- Add appropriate punctuation (commas, periods, question marks, etc.) to improve grammar and clarity.
- Ensure punctuation is contextually appropriate and correct for spoken dialogue.
- Remove inappropriate repetitions of words (3+ times in a row; example: yeah yeah yeah yeah yeah -> yeah yeah).
- Remove incorrect punctuation.
- Remove incorrect and excessive line breaks.
- Each sentence must appear on a new line.
- Do not insert any blank lines between sentences.
- Do not prepend or append anything to the transcript (e.g., no titles like 'Here is the formatted transcript').
- Do not summarize, paraphrase, or add any content.
- Your output must be the same length and structure as the input, only with improved formatting and speaker labels.
- Preserve the original spoken content exactly as heard, with only punctuation and sentence structure corrected.


EXAMPLE INPUT:
hi there how.
are you.
i'm good how are, you doing

EXAMPLE OUTPUT:
Hi there, how are you?
I'm good. How are you doing?"""
    prompt = (
        instruction_part
        + f"\n\nTRANSCRIPT CHUNK:\n{chunk}"
    )
    response = requests.post(
        f"{OLLAMA_HOST}/api/generate",
        json={"model": ollama_model, "prompt": prompt, "stream": False},
        timeout=120
    )
    response.raise_for_status()
    answer = response.json()["response"]
    return answer

def label_transcript(text, progress_callback=None):
    """
    Label the entire transcript text by chunking and processing each chunk with Ollama.
    """
    if not check_ollama_running():
        print("[ERROR] Ollama server is not running at localhost:11434.")
        print("Please make sure Ollama is installed and running (`ollama serve`).")
        return
    print("\nLabeling transcript with Ollama...")
    chunks = chunk_text(text)
    labeled_chunks = []
    for idx, chunk in enumerate(chunks):
        print(f"[Ollama] Processing chunk {idx + 1} of {len(chunks)} ({int((idx + 1) / len(chunks) * 100)}%)")
        if progress_callback:
            progress_callback(idx, len(chunks))
        labeled = label_chunk(chunk, idx, len(chunks))
        labeled_chunks.append(labeled)
    return "\n".join(labeled_chunks)

def save_labeled_transcript(labeled_text, audio_file):
    """
    Save the labeled transcript text to a file in the Downloads directory.
    """
    base_name = os.path.splitext(os.path.basename(audio_file))[0]
    out_dir = os.path.expanduser("~/Downloads")
    out_file = os.path.join(out_dir, base_name + "_labeled_transcript.txt")
    with open(out_file, "w", encoding="utf-8") as f:
        f.write(labeled_text)
    print(f"Labeled transcript saved to: {out_file}")
    return out_file

def summarize_transcript(text, summary_type="General", ollama_model=OLLAMA_MODEL):
    """
    Generate a detailed summary of the formatted transcript using Ollama.
    Handles long transcripts by chunking if necessary.
    """
    print("\nGenerating structured summary with Ollama...")
    # Llama 3.2 supports large contexts natively. 
    # Use ~10k words per chunk (roughly ~13k tokens) so most files process in a single fast pass.
    chunks = chunk_text(text, chunk_size=10000)
    prompt_config = SUMMARY_PROMPTS.get(summary_type, SUMMARY_PROMPTS["General"])
    
    if len(chunks) == 1:
        prompt = (
            "You are an expert executive assistant. Please read the following transcript and provide a highly useful, structured summary. "
            "Be direct and ignore fluff. Use the following structure:\n"
            f"{prompt_config['combine']}\n\n"
            f"TRANSCRIPT:\n{chunks[0]}"
        )
        try:
            response = requests.post(
                f"{OLLAMA_HOST}/api/generate",
                json={
                    "model": ollama_model, 
                    "prompt": prompt, 
                    "stream": False,
                    "options": {"num_ctx": 16384, "temperature": 0.4}
                },
                timeout=600
            )
            response.raise_for_status()
            return response.json()["response"]
        except Exception as e:
            print(f"[ERROR] Summarization failed: {e}")
            return "Summarization failed."
    else:
        chunk_summaries = []
        for i, chunk in enumerate(chunks):
            print(f"[Ollama] Extacting details from part {i+1} of {len(chunks)}...")
            prompt = (
                "You are an expert executive assistant analyzing a section of a lengthy transcript. "
                f"{prompt_config['chunk']}\n\n"
                f"TRANSCRIPT PART:\n{chunk}"
            )
            try:
                response = requests.post(
                    f"{OLLAMA_HOST}/api/generate",
                    json={
                        "model": ollama_model, 
                        "prompt": prompt, 
                        "stream": False,
                        "options": {"num_ctx": 16384, "temperature": 0.3}
                    },
                    timeout=600
                )
                response.raise_for_status()
                chunk_summaries.append(response.json()["response"])
            except Exception as e:
                print(f"[ERROR] Summarization failed on part {i+1}: {e}")
                chunk_summaries.append(f"[Failed to summarize part {i+1}]")
                
        print("[Ollama] Unifying details into final structured summary...")
        combined_text = "\n\n".join(chunk_summaries)
        final_prompt = (
            "You are an expert executive assistant. Below are sequential notes from different sections of a very long transcript. "
            "Please combine them into one final, highly informative, and concise summary. Avoid long flowing paragraphs.\n"
            "Format exactly with:\n"
            f"{prompt_config['combine']}\n\n"
            f"PARTIAL NOTES:\n{combined_text}"
        )
        try:
            response = requests.post(
                f"{OLLAMA_HOST}/api/generate",
                json={
                    "model": ollama_model, 
                    "prompt": final_prompt, 
                    "stream": False,
                    "options": {"num_ctx": 16384, "temperature": 0.4}
                },
                timeout=600
            )
            response.raise_for_status()
            return response.json()["response"]
        except Exception as e:
            print(f"[ERROR] Final summarization failed: {e}")
            return "Combined Partial Summaries:\n" + combined_text

def save_summary_transcript(summary_text, audio_file):
    """
    Save the summary text to a file in the Downloads directory.
    """
    base_name = os.path.splitext(os.path.basename(audio_file))[0]
    out_dir = os.path.expanduser("~/Downloads")
    out_file = os.path.join(out_dir, base_name + "_summary.txt")
    with open(out_file, "w", encoding="utf-8") as f:
        f.write(summary_text)
    print(f"Summary saved to: {out_file}")
    return out_file

class TranscriptionGUI:
    """
    GUI application class for FasterTranscriberApp: select audio files, transcribe, and label transcripts.
    """
    def __init__(self, root):
        self.root = root
        self.root.title("FasterTranscriberApp: Whisper + Ollama Transcription")
        self.root.geometry("480x420")
        self.audio_files = list_downloads_files()
        self.selected_file = tk.StringVar()
        self.model_var = tk.StringVar(value="base")
        self.status_var = tk.StringVar(value="Ready")

        # Dropdown to select audio file from Downloads
        tk.Label(root, text="Choose audio file from Downloads:").pack(pady=(10,0))
        self.file_combo = ttk.Combobox(root, values=self.audio_files, textvariable=self.selected_file, width=60)
        if self.audio_files:
            self.selected_file.set(self.audio_files[0])
        self.file_combo.pack()

        # Dropdown to select Whisper model size
        tk.Label(root, text="Whisper model:").pack(pady=(10,0))
        self.model_combo = ttk.Combobox(
            root,
            values=["tiny", "base", "small", "medium", "large-v1", "large-v2"],
            textvariable=self.model_var,
            width=10
        )
        self.model_combo.pack()

        # Operation Mode Radio Buttons
        tk.Label(root, text="Select Operation:").pack(pady=(10,0))
        self.operation_var = tk.StringVar(value="format_only")
        
        self.operations_frame = tk.Frame(root)
        self.operations_frame.pack()
        ttk.Radiobutton(self.operations_frame, text="Format Transcript", variable=self.operation_var, value="format_only").pack(anchor=tk.W)
        ttk.Radiobutton(self.operations_frame, text="Summarize Raw Transcript (Fast Mode)", variable=self.operation_var, value="summary_only").pack(anchor=tk.W)
        ttk.Radiobutton(self.operations_frame, text="Format & Summarize (Resource Intensive)", variable=self.operation_var, value="both").pack(anchor=tk.W)

        # Context Combobox
        tk.Label(root, text="Summary Context:").pack(pady=(5,0))
        self.summary_type_var = tk.StringVar(value="General")
        self.summary_type_combo = ttk.Combobox(
            root,
            values=["General", "Lecture / Presentation", "Meeting / Group Discussion", "Interview / Conversation"],
            textvariable=self.summary_type_var,
            width=35,
            state="readonly"
        )
        self.summary_type_combo.pack()
        
        def on_operation_changed(*args):
            op = self.operation_var.get()
            if op == "format_only":
                self.summary_type_combo.config(state="disabled")
            else:
                self.summary_type_combo.config(state="readonly")
                
        self.operation_var.trace_add('write', on_operation_changed)
        on_operation_changed()

        # Button to start transcription
        self.start_btn = ttk.Button(root, text="Start Transcription", command=self.start_transcription)
        self.start_btn.pack(pady=15)

        # Status label to display current state
        self.status_label = tk.Label(root, textvariable=self.status_var)
        self.status_label.pack(pady=(10,0))

    def start_transcription(self):
        """
        Validate selections and start the transcription process after hiding the GUI.
        """
        audio_file = self.selected_file.get()
        model_name = self.model_var.get()
        if not audio_file or not os.path.exists(audio_file):
            messagebox.showerror("Error", "Please select a valid audio file.")
            return
        self.start_btn.config(state="disabled")
        self.file_combo.config(state="disabled")
        self.model_combo.config(state="disabled")
        for child in self.operations_frame.winfo_children():
            child.configure(state="disabled")
        self.summary_type_combo.config(state="disabled")
        self.status_var.set("Transcribing...")
        self.root.update()
        def delayed_start():
            time.sleep(0.25)
            self.root.destroy()
            # Construct shell command to run transcriber_gui.py directly in terminal
            script_path = os.path.abspath(__file__)
            venv_python = os.path.join(os.path.dirname(script_path), "venv", "bin", "python")
            operation = self.operation_var.get()
            summary_type = self.summary_type_var.get()
            cmd = f'osascript -e \'tell application "Terminal" to do script "source {os.path.dirname(script_path)}/venv/bin/activate && {venv_python} {script_path} --run \\"{audio_file}\\" \\"{model_name}\\" \\"{operation}\\" \\"{summary_type}\\""\''
            os.system(cmd)
        self.root.after(100, delayed_start)

if __name__ == "__main__":
    if "--run" in sys.argv:
        idx = sys.argv.index("--run")
        if idx + 2 < len(sys.argv):
            audio_file = sys.argv[idx + 1]
            model_name = sys.argv[idx + 2]
            result = transcribe_audio(audio_file, model_name)
            raw_file = save_transcript(result, audio_file)
            operation = "format_only"
            summary_type = "General"
            if idx + 3 < len(sys.argv):
                operation = sys.argv[idx + 3]
            if idx + 4 < len(sys.argv):
                summary_type = sys.argv[idx + 4]

            if not check_ollama_running():
                print("[ERROR] Ollama server is not running at localhost:11434.")
                print("Please make sure Ollama is installed and running (`ollama serve`).")
                sys.exit(1)

            text = result["text"]
            final_text_for_summary = text

            if operation in ["format_only", "both"]:
                print("Starting Ollama speaker labeling...")
                chunks = chunk_text(text)
                total_chunks = len(chunks)
                labeled_chunks = []
                for idx, chunk in enumerate(chunks):
                    print(f"Processing chunk {idx+1} of {total_chunks}...")
                    labeled = label_chunk(chunk, idx, total_chunks)
                    labeled_chunks.append(labeled)
                labeled_text = "\n".join(labeled_chunks)
                save_labeled_transcript(labeled_text, audio_file)
                final_text_for_summary = labeled_text
            
            if operation in ["summary_only", "both"]:
                summary_text = summarize_transcript(final_text_for_summary, summary_type=summary_type)
                save_summary_transcript(summary_text, audio_file)
                
            print("Done. Opening output folder in Finder...")
            folder_path = os.path.dirname(raw_file)
            subprocess.run(["open", folder_path])
        else:
            print("Usage: transcriber_gui.py --run <audio_file_path> <model_name>")
    else:
        root = tk.Tk()
        app = TranscriptionGUI(root)
        root.mainloop()
EOF

LAUNCHER_PATH=~/Desktop/FasterTranscriberApp.command
echo "Creating launcher on Desktop at: $LAUNCHER_PATH"
cat <<EOF > "$LAUNCHER_PATH"
#!/bin/bash
cd ~/FasterTranscriberApp
source venv/bin/activate
"$PYTHON_PATH" transcriber_gui.py
echo "FasterTranscriberApp launched successfully."
EOF

chmod +x "$LAUNCHER_PATH"


echo "Creating README_FASTER_FIRST.txt..."
cat <<'EOF' > ~/FasterTranscriberApp/README_FASTER_FIRST.txt
Welcome to FasterTranscriberApp! Please read everything below before trying to install.

Explanation:
FasterTranscriberApp is a simple, self-contained audio transcription assistant designed for macOS (M1 or newer recommended). It transcribes audio interviews using the OpenAI Whisper model (via Faster-Whisper), then formats the transcript using LLaMA 3.2 via Ollama. All processing happens entirely on your computer, meaning that no internet or cloud services are used after installation. Your data never leaves your device, making the process as secure as your Mac itself.

This is not a native macOS application — it runs via Terminal and uses Python scripts with a basic graphical user interface (GUI) to help you start transcription jobs.


System Requirements:  
- macOS 12.0 or later (Apple Silicon required — M1+)  
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
   - Transcription speed depends on the Whisper model selected and the length of the recording. Expect between 15 and 60 seconds per 60 seconds of audio, then 10-20 seconds per minute of transcript formatting. This varies depending on system capabilities.
4. When finished, two files will be saved to your Downloads folder, named after the input file:  
   - A raw transcript (`[file_name]_raw_transcript.txt`)
   - A labeled, speaker-formatted transcript (`[file_name]_labeled_transcript.txt`)

Removal:  
1. You can uninstall everything by double-clicking `UNinstallFasterTranscriberApp.command` if you no longer want or need the tool.  
   - You will be prompted to keep or uninstall Ollama, the local AI program (like ChatGPT or Copilot), for your own later use  
   - If you choose not to uninstall Ollama, you can open your Terminal and type 'ollama run llama3.2' to ask questions like you would with any other internet-based AI program

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

- Ollama starts automatically in the background, but if it doesn't: you can open Terminal and type `ollama serve` to start the Ollama server manually. Make sure you’ve installed Ollama and pulled the `llama3.2` model (`ollama pull llama3.2`).

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
EOF

echo "Creating UNinstallFasterTranscriberApp.command..."
cat <<'EOF' > ~/FasterTranscriberApp/UNinstallFasterTranscriberApp.command
#!/bin/bash

echo "This will uninstall the FasterTranscriberApp and remove related configurations. Continue? (y/n)"
read -r confirm
if [[ "$confirm" != "y" ]]; then
  echo "Uninstallation cancelled."
  exit 0
fi

echo "Stopping any running transcription processes..."
pkill -f transcriber_gui.py

echo "Removing FasterTranscriberApp directory..."
rm -rf ~/FasterTranscriberApp

echo "Removing FasterTranscriberApp launcher from Desktop..."
rm -f ~/Desktop/FasterTranscriberApp.command

echo "Removing environment variables from .zshrc..."
echo "Would you also like to uninstall Ollama? (y/n)"
echo "Ollama is a tool that lets your computer run AI models directly, without needing the internet. You can use it for things like writing help, answering questions, or research support."
echo "If you choose not to uninstall Ollama, you can open your Terminal and type 'ollama run llama3.2' to ask questions like you would with ChatGPT."
read -r remove_ollama
if [[ "$remove_ollama" == "y" ]]; then
  echo "Uninstalling Ollama..."
  brew uninstall ollama
else
  echo "Skipping Ollama uninstallation."
fi
sed -i '' '/# >>> FasterTranscriberApp Tcl-Tk Setup >>>/,/# <<< FasterTranscriberApp Tcl-Tk Setup <<</d' ~/.zshrc
sed -i '' '/# >>> FasterTranscriberApp Tcl-Tk Setup >>>/,/# <<< FasterTranscriberApp Tcl-Tk Setup <<</d' ~/.zprofile
sed -i '' '/# >>> FasterTranscriberApp Tcl-Tk Setup >>>/,/# <<< FasterTranscriberApp Tcl-Tk Setup <<</d' ~/.bash_profile

echo "FasterTranscriberApp has been fully uninstalled, including environment variables from all shell profiles."

EOF

chmod +x ~/FasterTranscriberApp/UNinstallFasterTranscriberApp.command

echo "Copying documentation to Downloads/FasterTranscriberApp_Information..."
mkdir -p ~/Downloads/FasterTranscriberApp_Information
cp ~/FasterTranscriberApp/README_FASTER_FIRST.txt ~/Downloads/FasterTranscriberApp_Information/README_FASTER_FIRST.txt
cp ~/FasterTranscriberApp/UNinstallFasterTranscriberApp.command ~/Downloads/FasterTranscriberApp_Information/UNinstallFasterTranscriberApp.command

echo "Setup complete. You can now double-click 'FasterTranscriberApp' on your Desktop to run the app."