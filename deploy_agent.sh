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

preflight_checks() {
    local missing=0
    for tool in python3 zip; do
        if ! command -v "$tool" > /dev/null 2>&1; then
            err "'$tool' is not installed. Please install it and try again."
            missing=1
        fi
    done
    (( missing )) && return 1
    echo "Found: $(python3 --version 2>&1)"
    echo "Found: zip ($(command -v zip))"
    return 0
}

ask_project_name() {
    local input
    while true; do
        read -r -p "Enter a name for the project (letters, numbers, - and _ only): " input
        if [[ -z "$input" ]]; then
            err "Name cannot be empty."
        elif ! is_valid_name "$input"; then
            err "Invalid name. No spaces, slashes, or special characters."
        else
            break
        fi
    done
    PROJECT_NAME="$input"
    PROJECT_DIR="$START_DIR/attendance_tracker_${PROJECT_NAME}"

    if [[ -e "$PROJECT_DIR" ]]; then
        read -r -p "'attendance_tracker_${PROJECT_NAME}' already exists. Overwrite? (y/n): " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            rm -rf "$PROJECT_DIR" || { err "Could not remove existing directory."; return 1; }
            echo "Old directory removed."
        else
            err "Deployment aborted. Existing directory left untouched."
            return 1
        fi
    fi
    return 0
}

create_structure() {
    mkdir -p "$PROJECT_DIR/Helpers" "$PROJECT_DIR/reports" 2>/dev/null || {
        err "Could not create directories (permission denied?)."
        return 1
    }
    for f in attendance_checker.py config.json assets.csv; do
        if [[ ! -f "$TEMPLATES_DIR/$f" ]]; then
            err "Missing template: templates/$f"
            return 1
        fi
    done
    cp "$TEMPLATES_DIR/attendance_checker.py" "$PROJECT_DIR/attendance_checker.py" &&
    cp "$TEMPLATES_DIR/config.json" "$PROJECT_DIR/Helpers/config.json" || {
        err "Failed to copy template files."
        return 1
    }
    echo "Directory structure created and fixed files copied."
}


