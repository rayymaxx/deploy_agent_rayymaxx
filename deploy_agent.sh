#!/bin/bash 

START_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # where the script lives
TEMPLATES_DIR="$START_DIR/templates"
PROJECT_NAME=""      # the {input} part, set during deploy
PROJECT_DIR=""       # attendance_tracker_{input}

msg()  { echo -e "\n>> $*"; }
err()  { echo "ERROR: $*" >&2; }

is_positive_int() { [[ "$1" =~ ^[1-9][0-9]*$ ]]; }
is_percent()      { [[ "$1" =~ ^[0-9]+$ ]] && (( 10#$1 >= 0 && 10#$1 <= 100 )); }
is_valid_name()   { [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]]; }

# Placeholders for trap logic
enable_trap()  { :; }
disable_trap() { :; }


