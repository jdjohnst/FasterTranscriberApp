#!/usr/bin/env bash

echo "Uninstalling FasterTranscriberApp V2..."

echo "Stopping background processes..."
pkill -f "src/main.py" 2>/dev/null

echo "Removing virtual environment..."
rm -rf .venv

echo "Removing desktop launcher..."
rm -f ~/Desktop/TranscriberV2.command

echo "Removing debug logs..."
rm -f src/debug.log
rm -f debug.log

echo "Would you like to uninstall Ollama? (y/n)"
read -r remove_ollama
if [[ "$remove_ollama" == "y" ]]; then
  echo "Uninstalling Ollama..."
  brew uninstall ollama
fi

echo "Uninstallation complete. You can safely delete this directory."
