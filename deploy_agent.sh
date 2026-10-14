#!/bin/bash 

START_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # where the script lives
TEMPLATES_DIR="$START_DIR/templates"
PROJECT_NAME=""      # the {input} part, set during deploy
PROJECT_DIR=""       # attendance_tracker_{input}


