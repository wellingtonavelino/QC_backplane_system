#!/bin/bash

# Go to directory where tehe script is 
cd "$(dirname "$0")"

# Open browser pointing to Flask
xdg-open http://127.0.0.1:5000 >/dev/null 2>&1 &

# Run app.py
python3 app.py

# Pause in the end. Linux-equivalent command
read -p "Press ENTER to exit..."
