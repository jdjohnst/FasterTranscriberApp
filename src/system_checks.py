import psutil
from src.logger import logger

def get_total_ram_gb():
    """
    Returns the total available system RAM in Gigabytes.
    For Apple Silicon, this roughly equates to Unified Memory.
    """
    total_bytes = psutil.virtual_memory().total
    total_gb = total_bytes / (1024 ** 3)
    logger.debug(f"Detected System RAM: {total_gb:.2f} GB")
    return total_gb

def check_hardware_safety(model_name: str, operation: str) -> bool:
    """
    Checks if the user's hardware is likely capable of running the chosen operation safely.
    Returns (True, "") if safe, or (False, "warning message") if there is a risk.
    """
    ram_gb = get_total_ram_gb()
    
    # 8GB Macs might struggle with large models, especially if formatting simultaneously.
    is_large_model = "large" in model_name.lower()
    is_heavy_operation = operation == "both"
    
    if ram_gb <= 8.5:  # Buffer for 8GB configs (can report as ~8.0 or slightly more)
        if is_large_model and is_heavy_operation:
            msg = (
                "⚠️ HARDWARE WARNING\n\n"
                f"Your system has ~{ram_gb:.1f}GB of RAM. The '{model_name}' model paired with "
                "local AI Summarization ('Format & Summarize') is extremely resource intensive.\n\n"
                "Attempting this may result in system lag, excessive heat, or crashes. "
                "It is highly recommended to use a 'base' or 'small' model instead on this machine.\n\n"
                "Do you still want to proceed?"
            )
            logger.warning(f"Hardware warning triggered for 8GB RAM + {model_name} model + {operation}")
            return False, msg
        elif is_large_model:
            msg = (
                "⚠️ MEMORY WARNING\n\n"
                f"Your system has ~{ram_gb:.1f}GB of RAM. Processing the '{model_name}' model "
                "may consume most of your available memory, causing system slowdowns.\n\n"
                "Do you want to proceed?"
            )
            logger.warning(f"Hardware warning triggered for 8GB RAM + {model_name} model")
            return False, msg
            
    return True, ""
