import logging
import os

def setup_logger(log_file="debug.log"):
    """
    Configure a centralized logger to track application events and errors implicitly.
    Output will be sent sequentially to the debug.log file.
    """
    logger = logging.getLogger("FasterTranscriber")
    logger.setLevel(logging.DEBUG)

    # Disable propagating to standard output / root logger to keep stdout cleaner
    logger.propagate = False

    # Prevent adding multiple handlers if called multiple times
    if not logger.handlers:
        file_handler = logging.FileHandler(log_file, mode="a")
        file_handler.setLevel(logging.DEBUG)
        
        formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(module)s - %(message)s'
        )
        file_handler.setFormatter(formatter)
        logger.addHandler(file_handler)

    return logger

# Global logger instance configured by default
logger = setup_logger()
