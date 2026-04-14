import os
import glob
import time
import shutil
import subprocess
import requests
import threading
from faster_whisper import WhisperModel
from src.logger import logger

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



def chunk_text(text, chunk_size=CHUNK_SIZE):
    """Split transcript text into chunks of roughly chunk_size words."""
    words = text.split()
    return [" ".join(words[i:i+chunk_size]) for i in range(0, len(words), chunk_size)]

def check_ollama_running(stop_event=None):
    """Check if the Ollama server is running and start it if not."""
    try:
        response = requests.get(f"{OLLAMA_HOST}/api/tags", timeout=2)
        if response.status_code == 200:
            return True
    except requests.exceptions.RequestException:
        pass

    logger.info("Ollama is not running. Attempting to start automatically...")
    try:
        subprocess.Popen(["ollama", "serve"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(15):
            if stop_event and stop_event.is_set():
                return False
            time.sleep(1)
            try:
                response = requests.get(f"{OLLAMA_HOST}/api/tags", timeout=2)
                if response.status_code == 200:
                    logger.info("Ollama started successfully.")
                    return True
            except requests.exceptions.RequestException:
                pass
    except Exception as e:
        logger.error(f"Could not start Ollama automatically: {e}")

    return False

class TranscriptionEngine:
    def __init__(self, callback=None, stop_event=None):
        self.callback = callback or (lambda msg, pct=None: None)
        self.stop_event = stop_event or threading.Event()

    def _convert_to_wav(self, audio_file):
        """Safely convert any media file to a 16kHz WAV using FFmpeg."""
        self.callback("Pre-processing media file with FFmpeg...", 0)
        logger.info(f"FFmpeg preprocessing: {audio_file}")
        
        temp_dir = os.path.dirname(os.path.abspath(audio_file))
        base_name = os.path.splitext(os.path.basename(audio_file))[0]
        temp_wav = os.path.join(temp_dir, f".{base_name}_temp_conv.wav")
        
        ffmpeg_cmd = shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"
        try:
            subprocess.run(
                [ffmpeg_cmd, "-y", "-i", audio_file, "-vn", "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", temp_wav],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True
            )
            return temp_wav
        except Exception as e:
            logger.warning(f"FFmpeg conversion failed. Falling back to native: {e}")
            return audio_file

    def run_transcription(self, audio_file, model_size):
        """Run Faster Whisper."""
        self.callback(f"Loading '{model_size}' model into memory...", 5)
        
        if self.stop_event.is_set(): return None

        # Apple Silicon optimization: int8 quantization significantly reduces RAM footprint
        # and typically increases CPU inference speed without noticeable accuracy loss.
        model = WhisperModel(model_size, compute_type="int8")
        safe_audio = self._convert_to_wav(audio_file)
        
        if self.stop_event.is_set(): return None

        self.callback("Transcribing audio... (This may take a while)", 15)
        segments_generator, info = model.transcribe(safe_audio)
        
        segments = []
        for i, segment in enumerate(segments_generator, 1):
            if self.stop_event.is_set():
                logger.info("Transcription cancelled by user.")
                return None
            segments.append(segment.text)
            # Update progress dynamically based on segment time vs total time
            pct = 15 + int((segment.end / info.duration) * 35)
            self.callback(f"Transcribing audio... {int(segment.end)}s / {int(info.duration)}s", min(pct, 50))
            
        full_text = "\n".join(segments)
        logger.info("Faster-Whisper transcription completed.")
        
        if safe_audio != audio_file and os.path.exists(safe_audio):
            try: os.remove(safe_audio)
            except: pass
            
        return full_text

    def run_formatting(self, text, start_pct=50, end_pct=75):
        """Run Ollama formatting / speaker labeling."""
        self.callback("Checking Ollama server connection...", start_pct)
        if not check_ollama_running(self.stop_event):
            raise RuntimeError("Ollama server is not running.")
            
        chunks = chunk_text(text)
        labeled_chunks = []
        
        instruction_part = (
            "You are given a raw transcript of a real spoken conversation.\n\n"
            "Instructions:\n- Add appropriate punctuation to improve grammar.\n"
            "- Remove inappropriate repetitions of words.\n"
            "- Remove incorrect punctuation and line breaks.\n"
            "- Each sentence must appear on a new line.\n"
            "- Do not summarize, paraphrase, or add any content.\n"
            "- Preserve the original spoken content exactly as heard.\n\n"
            "EXAMPLE INPUT:\nhi there how.\nare you.\ni'm good how are, you doing\n\n"
            "EXAMPLE OUTPUT:\nHi there, how are you?\nI'm good. How are you doing?"
        )

        for idx, chunk in enumerate(chunks):
            if self.stop_event.is_set(): return None
            
            cur_pct = start_pct + int((idx / len(chunks)) * (end_pct - start_pct))
            msg = f"Formatting transcript chunk {idx+1}/{len(chunks)}..."
            logger.info(msg)
            self.callback(msg, cur_pct)
            
            prompt = instruction_part + f"\n\nTRANSCRIPT CHUNK:\n{chunk}"
            try:
                response = requests.post(
                    f"{OLLAMA_HOST}/api/generate",
                    json={"model": OLLAMA_MODEL, "prompt": prompt, "stream": False},
                    timeout=120
                )
                response.raise_for_status()
                labeled_chunks.append(response.json()["response"])
            except Exception as e:
                logger.error(f"Ollama formatting failed on chunk {idx+1}: {e}")
                raise RuntimeError(f"Ollama formatting failed: {e}")
                
        return "\n".join(labeled_chunks)

    def run_summarization(self, text, summary_type="General", start_pct=75, end_pct=95):
        """Run Ollama Summarization."""
        self.callback("Checking Ollama server connection...", start_pct)
        if not check_ollama_running(self.stop_event):
            raise RuntimeError("Ollama server is not running.")
            
        self.callback("Generating summary...", start_pct + 5)
        chunks = chunk_text(text, chunk_size=10000)
        prompt_config = SUMMARY_PROMPTS.get(summary_type, SUMMARY_PROMPTS["General"])
        
        if len(chunks) == 1:
            if self.stop_event.is_set(): return None
            prompt = (
                "You are an expert executive assistant. Please read the following transcript and provide a highly useful, structured summary.\n"
                f"{prompt_config['combine']}\n\nTRANSCRIPT:\n{chunks[0]}"
            )
            response = requests.post(
                f"{OLLAMA_HOST}/api/generate",
                json={"model": OLLAMA_MODEL, "prompt": prompt, "stream": False, "options": {"num_ctx": 16384, "temperature": 0.4}},
                timeout=600
            )
            response.raise_for_status()
            return response.json()["response"]
            
        else:
            chunk_summaries = []
            for i, chunk in enumerate(chunks):
                if self.stop_event.is_set(): return None
                
                cur_pct = start_pct + 5 + int((i / len(chunks)) * ((end_pct - start_pct) / 2))
                msg = f"Extracting details from part {i+1}/{len(chunks)}..."
                logger.info(msg)
                self.callback(msg, cur_pct)
                
                prompt = (
                    f"You are an expert executive assistant analyzing a section of a lengthy transcript.\n"
                    f"{prompt_config['chunk']}\n\nTRANSCRIPT PART:\n{chunk}"
                )
                resp = requests.post(
                    f"{OLLAMA_HOST}/api/generate",
                    json={"model": OLLAMA_MODEL, "prompt": prompt, "stream": False, "options": {"num_ctx": 16384, "temperature": 0.3}},
                    timeout=600
                )
                resp.raise_for_status()
                chunk_summaries.append(resp.json()["response"])
                
            self.callback("Unifying summary sections...", end_pct - 2)
            combined_text = "\n\n".join(chunk_summaries)
            final_prompt = (
                "You are an expert executive assistant. Below are sequential notes from different sections of a very long transcript. "
                "Please combine them into one final, highly informative, and concise summary.\n"
                f"{prompt_config['combine']}\n\nPARTIAL NOTES:\n{combined_text}"
            )
            
            if self.stop_event.is_set(): return None
            
            resp = requests.post(
                f"{OLLAMA_HOST}/api/generate",
                json={"model": OLLAMA_MODEL, "prompt": final_prompt, "stream": False, "options": {"num_ctx": 16384, "temperature": 0.4}},
                timeout=600
            )
            resp.raise_for_status()
            return resp.json()["response"]

    def save_output(self, content, audio_file, suffix):
        """Save text output to downloads."""
        out_dir = os.path.dirname(os.path.abspath(audio_file))
        base_name = os.path.splitext(os.path.basename(audio_file))[0]
        out_file = os.path.join(out_dir, base_name + suffix)
        with open(out_file, "w", encoding="utf-8") as f:
            f.write(content)
        return out_file
