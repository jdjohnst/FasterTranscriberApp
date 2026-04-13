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
echo "If you choose not to uninstall Ollama, you can open your Terminal and type 'ollama run llama3' to ask questions like you would with ChatGPT."
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
