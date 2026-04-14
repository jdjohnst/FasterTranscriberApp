import sys
import os

# Add root folder to sys.path to allow src.* imports to work seamlessly when running as script
current_dir = os.path.dirname(os.path.abspath(__file__))
parent_dir = os.path.dirname(current_dir)
sys.path.insert(0, parent_dir)

from src.logger import logger

def main():
    logger.info("Transcriber App Launched")
    try:
        from src.gui import TranscriptionApp
        app = TranscriptionApp()
        app.mainloop()
    except Exception as e:
        logger.error(f"Failed to start Application: {e}", exc_info=True)
        print(f"Critical execution error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
