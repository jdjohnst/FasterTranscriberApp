import os
import sys
import threading
import subprocess
import customtkinter as ctk
from tkinter import messagebox
from src.logger import logger
from src.system_checks import check_hardware_safety
from src.transcription import TranscriptionEngine

# Setup Modern Dark/Light theme
ctk.set_appearance_mode("System")
ctk.set_default_color_theme("blue")

class TranscriptionApp(ctk.CTk):
    def __init__(self):
        super().__init__()

        self.title("FasterTranscriberApp V2")
        self.geometry("550x650")
        self.resizable(False, False)

        # Background operation tracking
        self.active_thread = None
        self.stop_event = threading.Event()

        # UI Data Variables
        self.selected_file = ctk.StringVar(value="")
        self.model_var = ctk.StringVar(value="base")
        self.operation_var = ctk.StringVar(value="format_only")
        self.summary_type_var = ctk.StringVar(value="General")
        
        self.build_ui()

    def build_ui(self):
        # Header
        header = ctk.CTkLabel(self, text="Transcribe & Summarize", font=ctk.CTkFont(size=24, weight="bold"))
        header.pack(pady=(20, 10))

        # Audio File Selection
        file_frame = ctk.CTkFrame(self)
        file_frame.pack(fill="x", padx=30, pady=10)
        ctk.CTkLabel(file_frame, text="1. Select Audio File:", font=ctk.CTkFont(weight="bold")).pack(anchor="w", padx=10, pady=(10, 5))
        
        self.browse_btn = ctk.CTkButton(file_frame, text="Browse...", command=self.browse_file, width=120)
        self.browse_btn.pack(side="left", padx=10, pady=(0, 10))
        
        self.file_label = ctk.CTkLabel(file_frame, textvariable=self.selected_file, text_color="gray", width=300, anchor="w")
        self.file_label.pack(side="left", fill="x", expand=True, padx=10, pady=(0, 10))

        # Model Selection
        model_frame = ctk.CTkFrame(self)
        model_frame.pack(fill="x", padx=30, pady=10)
        ctk.CTkLabel(model_frame, text="2. Choose Whisper Model:", font=ctk.CTkFont(weight="bold")).pack(anchor="w", padx=10, pady=(10, 5))
        self.model_combo = ctk.CTkComboBox(model_frame, values=["tiny", "base", "small", "medium", "large-v1", "large-v2"], variable=self.model_var, width=200)
        self.model_combo.pack(anchor="w", padx=10, pady=(0, 10))

        # Operations
        ops_frame = ctk.CTkFrame(self)
        ops_frame.pack(fill="x", padx=30, pady=10)
        ctk.CTkLabel(ops_frame, text="3. Select Operations:", font=ctk.CTkFont(weight="bold")).pack(anchor="w", padx=10, pady=(10, 5))
        
        self.radio_format = ctk.CTkRadioButton(ops_frame, text="Format Transcript (Punctuation & Syntax)", variable=self.operation_var, value="format_only", command=self.on_op_change)
        self.radio_format.pack(anchor="w", padx=10, pady=5)
        self.radio_summary = ctk.CTkRadioButton(ops_frame, text="Summarize Only (Fast)", variable=self.operation_var, value="summary_only", command=self.on_op_change)
        self.radio_summary.pack(anchor="w", padx=10, pady=5)
        self.radio_both = ctk.CTkRadioButton(ops_frame, text="Format & Summarize (Resource Intensive)", variable=self.operation_var, value="both", command=self.on_op_change)
        self.radio_both.pack(anchor="w", padx=10, pady=5)

        # Context Summary
        self.context_label = ctk.CTkLabel(ops_frame, text="Summary Context:")
        self.context_label.pack(anchor="w", padx=10, pady=(10, 0))
        self.context_combo = ctk.CTkComboBox(ops_frame, values=["General", "Lecture / Presentation", "Meeting / Group Discussion", "Interview / Conversation"], variable=self.summary_type_var, width=250)
        self.context_combo.pack(anchor="w", padx=10, pady=(0, 10))
        self.on_op_change()

        # Action Buttons
        btn_frame = ctk.CTkFrame(self, fg_color="transparent")
        btn_frame.pack(pady=20)
        
        self.start_btn = ctk.CTkButton(btn_frame, text="Start Transcription", font=ctk.CTkFont(weight="bold"), command=self.start_processing)
        self.start_btn.pack(side="left", padx=10)

        self.cancel_btn = ctk.CTkButton(btn_frame, text="Cancel", font=ctk.CTkFont(weight="bold"), fg_color="#D32F2F", hover_color="#B71C1C", command=self.cancel_processing, state="disabled")
        self.cancel_btn.pack(side="left", padx=10)

        # Progress Section
        self.progress_bar = ctk.CTkProgressBar(self, width=450)
        self.progress_bar.pack(pady=(10, 5))
        self.progress_bar.set(0)

        self.status_label = ctk.CTkLabel(self, text="Ready", text_color="gray")
        self.status_label.pack()

    def browse_file(self):
        file_types = [("Audio Files", "*.mp3 *.wav *.m4a *.aac *.flac *.ogg *.mp4 *.mov")]
        path = ctk.filedialog.askopenfilename(title="Select Audio File", filetypes=file_types)
        if path:
            self.selected_file.set(path)

    def on_op_change(self):
        op = self.operation_var.get()
        if op == "format_only":
            self.context_combo.configure(state="disabled")
        else:
            self.context_combo.configure(state="normal")

    def toggle_ui(self, running):
        state = "disabled" if running else "normal"
        self.browse_btn.configure(state=state)
        self.model_combo.configure(state=state)
        self.start_btn.configure(state=state)
        self.cancel_btn.configure(state="normal" if running else "disabled")
        self.radio_format.configure(state=state)
        self.radio_summary.configure(state=state)
        self.radio_both.configure(state=state)
        
        if running:
            self.context_combo.configure(state="disabled")
        else:
            self.on_op_change()

    def update_progress(self, msg, pct):
        def _update():
            self.status_label.configure(text=msg)
            self.progress_bar.set(pct / 100.0)
            self.update_idletasks()
        self.after(0, _update)

    def start_processing(self):
        audio_file = self.selected_file.get()
        model_name = self.model_var.get()
        operation = self.operation_var.get()
        summary_type = self.summary_type_var.get()

        if not audio_file or not os.path.exists(audio_file):
            messagebox.showerror("Error", "Please select a valid audio file.")
            return

        # Hardware safety check
        safe, msg = check_hardware_safety(model_name, operation)
        if not safe:
            if not messagebox.askyesno("Hardware Warning", msg):
                return

        self.stop_event.clear()
        self.toggle_ui(True)
        self.update_progress("Starting engine...", 0)

        # Start thread
        self.active_thread = threading.Thread(
            target=self.processing_worker,
            args=(audio_file, model_name, operation, summary_type),
            daemon=True
        )
        self.active_thread.start()

    def cancel_processing(self):
        if messagebox.askyesno("Cancel Processing", "Are you sure you want to stop? All progress will be lost."):
            logger.info("User initiated cancellation.")
            self.stop_event.set()
            self.update_progress("Cancelling...", 0)
            self.cancel_btn.configure(state="disabled")

    def processing_worker(self, audio_file, model_name, operation, summary_type):
        try:
            engine = TranscriptionEngine(callback=self.update_progress, stop_event=self.stop_event)
            
            # Phase 1: Transcribe
            full_text = engine.run_transcription(audio_file, model_name)
            if self.stop_event.is_set(): return self.on_process_end("Cancelled by user.")
            
            raw_path = engine.save_output(full_text, audio_file, "_raw_transcript.txt")
            
            final_text = full_text

            # Phase 2: Format
            if operation in ["format_only", "both"]:
                formatted = engine.run_formatting(full_text, start_pct=50, end_pct=75 if operation=="both" else 100)
                if self.stop_event.is_set(): return self.on_process_end("Cancelled by user.")
                final_text = formatted
                engine.save_output(formatted, audio_file, "_labeled_transcript.txt")

            # Phase 3: Summarize
            if operation in ["summary_only", "both"]:
                start_p = 50 if operation == "summary_only" else 75
                summary = engine.run_summarization(final_text, summary_type, start_pct=start_p, end_pct=100)
                if self.stop_event.is_set(): return self.on_process_end("Cancelled by user.")
                engine.save_output(summary, audio_file, "_summary.txt")

            self.on_process_end("Success", raw_path)

        except Exception as e:
            logger.error(f"Processing error: {e}", exc_info=True)
            self.after(0, lambda: messagebox.showerror("Error", f"An error occurred:\n{e}\n\nCheck debug.log for details."))
            self.on_process_end("Error")

    def on_process_end(self, result_msg, open_path=None):
        def _update():
            self.toggle_ui(False)
            if result_msg == "Success":
                self.update_progress("Completed successfully!", 100)
                if open_path and os.path.exists(open_path):
                    subprocess.run(["open", os.path.dirname(open_path)])
            elif result_msg == "Error":
                self.update_progress("Failed due to error.", 0)
            else:
                self.update_progress("Cancelled.", 0)
        self.after(0, _update)

if __name__ == "__main__":
    app = TranscriptionApp()
    app.mainloop()
