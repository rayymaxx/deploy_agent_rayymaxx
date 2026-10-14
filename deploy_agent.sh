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

SAMPLE_NAMES=("Alice Johnson" "Bob Smith" "Carol Davis" "David Lee" "Eva Martinez"
              "Frank Wilson" "Grace Kim" "Henry Brown" "Irene Clark" "Jack Turner"
              "Karen White" "Liam Scott" "Maria Lopez" "Noah Adams" "Olivia Reed"
              "Peter Young" "Quinn Baker" "Rachel Green" "Sam Carter" "Tina Evans")
SAMPLE_EMAILS=("alice@example.com" "bob@example.com" "carol@example.com" "david@example.com"
               "eva@example.com" "frank@example.com" "grace@example.com" "henry@example.com"
               "irene@example.com" "jack@example.com" "karen@example.com" "liam@example.com"
               "maria@example.com" "noah@example.com" "olivia@example.com" "peter@example.com"
               "quinn@example.com" "rachel@example.com" "sam@example.com" "tina@example.com")

ask_count() {   
    local max="$1" n
    while true; do
        read -r -p "How many students (1-$max)? " n
        if is_positive_int "$n" && (( n <= max )); then COUNT="$n"; return; fi
        err "Enter a whole number between 1 and $max."
    done
}

build_roster() {
    local csv="$PROJECT_DIR/Helpers/assets.csv"
    local cfg="$PROJECT_DIR/Helpers/config.json"
    echo "How should the roster be built?"
    echo "  A) Copy from the template (sample students with 4 prior sessions)"
    echo "  B) Generate a fresh roster (all counts start at 0)"
    local choice
    while true; do
        read -r -p "Choose A or B: " choice
        [[ "$choice" =~ ^[AaBb]$ ]] && break
        err "Please enter A or B."
    done

    if [[ "$choice" =~ ^[Aa]$ ]]; then
        local available
        available=$(tail -n +2 "$TEMPLATES_DIR/assets.csv" | grep -c .)
        ask_count "$available"
        head -n $(( COUNT + 1 )) "$TEMPLATES_DIR/assets.csv" > "$csv" || return 1
        echo "Copied header + $COUNT students. total_sessions stays at 5."
    else
        local max=${#SAMPLE_NAMES[@]}
        ask_count "$max"
        echo "Email,Names,Attendance Count,Absence Count" > "$csv"
        for (( i=0; i<COUNT; i++ )); do
            echo "${SAMPLE_EMAILS[$i]},${SAMPLE_NAMES[$i]},0,0" >> "$csv"
        done
        # fresh roster = first session, so edit the DEPLOYED config (not the template)
        sed -i.bak 's/\("total_sessions":[[:space:]]*\)[0-9][0-9]*/\11/' "$cfg" && rm -f "$cfg.bak"
        echo "Generated $COUNT students. total_sessions set to 1."
    fi
}

set_permissions() {
    chmod +x "$PROJECT_DIR/attendance_checker.py" &&
    chmod 600 "$PROJECT_DIR/Helpers/config.json" || {
        err "Could not set permissions."
        return 1
    }
    echo "Permissions set:"
    ls -l "$PROJECT_DIR/attendance_checker.py" "$PROJECT_DIR/Helpers/config.json"
}

read_threshold() {   
    local label="$1" def="$2" val
    while true; do
        read -r -p "New $label threshold [default $def]: " val
        val="${val:-$def}"
        if is_percent "$val"; then THRESHOLD_VALUE=$((10#$val)); return; fi
        err "Must be a whole number between 0 and 100."
    done
}

update_thresholds() {
    local cfg="$PROJECT_DIR/Helpers/config.json"
    read -r -p "Update the attendance alert thresholds? (y/n): " ans
    [[ "$ans" =~ ^[Yy]$ ]] || { echo "Keeping default thresholds."; return 0; }

    local warn fail
    while true; do
        read_threshold "warning" 75; warn=$THRESHOLD_VALUE
        read_threshold "failure" 50; fail=$THRESHOLD_VALUE
        (( fail < warn )) && break
        err "Failure ($fail) must be lower than warning ($warn). Try again."
    done

    sed -i.bak -e "s/\(\"warning\":[[:space:]]*\)[0-9][0-9]*/\1$warn/" \
               -e "s/\(\"failure\":[[:space:]]*\)[0-9][0-9]*/\1$fail/" "$cfg" &&
        rm -f "$cfg.bak" || { err "Failed to update config.json."; return 1; }
    echo "Thresholds updated: warning=$warn, failure=$fail"
    grep -E '"warning"|"failure"' "$cfg"
}

run_app() {   
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        echo "Deployed projects:"; ls -d "$START_DIR"/attendance_tracker_*/ 2>/dev/null | xargs -n1 basename 2>/dev/null
        read -r -p "Project name to run (the part after attendance_tracker_): " name
    fi
    local dir="$START_DIR/attendance_tracker_${name}"
    if [[ ! -d "$dir" ]]; then err "Project '$dir' does not exist. Deploy it first."; return 1; fi
    if [[ ! -f "$dir/attendance_checker.py" ]]; then err "attendance_checker.py missing in $dir."; return 1; fi
    ( cd "$dir" && python3 attendance_checker.py )
}


