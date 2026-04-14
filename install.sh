#!/usr/bin/env bash

exec > >(tee install_log.txt) 2>&1

echo "=========================================="
echo " FasterTranscriberApp V2 Installer"
echo "=========================================="

# 1. Capture absolute path of the directory before sourcing profiles
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# 2. Load profiles (which might change the working directory)
for profile in ~/.zprofile ~/.zshrc ~/.bash_profile ~/.bashrc; do
    [ -f "$profile" ] && source "$profile"
done

# Return to script directory securely
cd "$APP_DIR" || exit 1

# 3. Check Homebrew
if ! command -v brew &>/dev/null; then
  echo "Homebrew not found. Installing..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# 4. Check dependencies (ffmpeg, ollama)
echo "Ensuring ffmpeg and ollama are installed..."
brew install ffmpeg --quiet
if ! command -v ollama &>/dev/null; then
  brew install ollama --quiet
fi
echo "Pulling llama3.2 model for summarization..."
ollama pull llama3.2

# 5. Check for uv (lightning-fast python package manager)
if ! command -v uv &>/dev/null; then
  echo "Installing uv for ultra-fast dependency management..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  source ~/.cargo/env 2>/dev/null || export PATH="$HOME/.local/bin:$PATH"
fi

# 6. Setup Python Virtual Environment using uv
echo "Setting up Python Environment..."

# uv venv creates `.venv` by default. We specify python 3.11 for stability with GUI frameworks
uv venv --python 3.11 .venv

# 6. Install requirements
echo "Installing application dependencies..."
uv pip install -r requirements.txt

# 7. Create Desktop Launcher (.app)
LAUNCHER_APP=~/Desktop/TranscriberV2.app
echo "Creating native desktop app at $LAUNCHER_APP..."

# We create an internal bash runner first
cat <<EOF > "run_app.sh"
#!/bin/bash
cd "$APP_DIR"
source .venv/bin/activate
python src/main.py
EOF
chmod +x "run_app.sh"

# Then compile an AppleScript that executes it silently
osacompile -e 'do shell script "'"$APP_DIR"'/run_app.sh > /dev/null 2>&1 &"' -o "$LAUNCHER_APP"

echo "=========================================="
echo " Installation Complete!"
echo " Double-click TranscriberV2.app on your desktop to run the app silently."
echo "=========================================="
