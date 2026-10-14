# Automated Project Bootstrapping & Process Management

`deploy_agent.sh` is a Bash script that deploys, runs and archives the logs of a
**Student Attendance Tracker** (a Python app), and cleans up safely if the user
interrupts a deployment with **Ctrl+C** or **Ctrl+Z**.

The Python application (`attendance_checker.py`) is **never modified**. Everything
here is shell scripting around it: deployment, configuration, execution, log
archival and interrupt handling.

Video Walkthrough: https://youtu.be/gTgz0KgcwW0

---

## Table of Contents

1. [Why a bootstrap script?](#why-a-bootstrap-script)
2. [Repository layout](#repository-layout)
3. [Requirements](#requirements)
4. [How to run the script and select a feature](#how-to-run-the-script-and-select-a-feature)
5. [Feature 1: Deploy](#feature-1-deploy)
6. [How the threshold update works](#how-the-threshold-update-works)
7. [Relationship between `total_sessions` and the roster](#relationship-between-total_sessions-and-the-roster)
8. [Feature 2: Run](#feature-2-run)
9. [Feature 3: Archive logs (directories and timestamped filenames)](#feature-3-archive-logs)
10. [Signal handling: Ctrl+C and Ctrl+Z](#signal-handling-ctrlc-and-ctrlz)
11. [How the deployed structure was tested](#how-the-deployed-structure-was-tested)
12. [Edge cases handled](#edge-cases-handled)
13. [Design decisions](#design-decisions)
14. [Known limitations](#known-limitations)
15. [Git workflow](#git-workflow)

---

## Why a bootstrap script?

Setting up an environment by hand is slow and error-prone. Scripting it gives:

- **Reproducibility:** every deployment has exactly the same structure and configuration.
- **Efficiency:** a manual setup of several minutes becomes seconds.
- **Reliability:** no typos in folder names, no missing files, no wrong permissions.

---

## Repository layout

```
deploy_agent_rayymaxx/
├── deploy_agent.sh          # the master script (deploy, run, archive, signal handling)
├── README.md                # this file
├── .gitignore               # keeps test deployments and zip archives out of git
└── templates/               # unmodified source files
    ├── attendance_checker.py
    ├── assets.csv           # sample roster: 10 students, 4 prior sessions each
    └── config.json          # thresholds, run_mode, total_sessions
```

The script finds `templates/` relative to **its own location**, so it works no
matter which directory you launch it from. Deployed projects are created next to
the script.

### What a deployed project looks like

```
attendance_tracker_{name}/
├── attendance_checker.py        # executable (chmod +x)
├── Helpers/
│   ├── assets.csv               # the roster
│   └── config.json              # owner read/write only (chmod 600)
├── reports/                     # starts empty; the app creates attendance.log / absent.log here
└── archives/                    # created by Feature 3
    ├── attendance/
    │   └── attendance_YYYYMMDD_HHMMSS.log
    └── absent/
        └── absent_YYYYMMDD_HHMMSS.log
```

---

## Requirements

- Linux, macOS or WSL (Ctrl+Z behaviour and `chmod 600` need a real Unix terminal)
- `bash`
- `python3`
- `zip`

The script checks for `python3` and `zip` before doing anything and prints a clear
error if either is missing.

---

## How to run the script and select a feature

I chose an **interactive menu** (rather than command-line flags) because it is
simpler to use and to demonstrate.

```bash
chmod +x deploy_agent.sh
./deploy_agent.sh
```

```
===== Attendance Tracker Deploy Agent =====
1) Deploy application
2) Run application
3) Archive logs
4) Exit
Choose an option [1-4]:
```

 Option - Action

`1` Deploy a new project (includes a verification run at the end) 
`2` Run an already deployed project 
`3` Archive the logs of a deployed project 
`4` Exit 

The menu repeats after each action until you choose `4`.

---

## Feature 1: Deploy

Choosing `1` runs these steps in order:

1. **Pre-flight checks:** verifies `python3` and `zip` exist and prints
   `python3 --version`. If anything is missing, it stops before creating anything.
2. **Signal trap enabled** (see [Signal handling](#signal-handling-ctrlc-and-ctrlz)).
3. **Project name:** asks for a name via `read` and creates `attendance_tracker_{name}/`.
   - Allowed characters: letters, numbers, `-` and `_`. Empty names, spaces,
     slashes and special characters are rejected and re-prompted.
   - If the directory already exists it is **never silently overwritten**. You are
     asked whether to overwrite (`y`) or abort (`n`).
4. **Directory structure:** creates the project root, `Helpers/` and `reports/`,
   checking that each step succeeded (for example, a permission-denied error gives
   a clear message instead of a crash).
5. **Fixed files:** copies `attendance_checker.py` and `config.json` from
   `templates/`, unmodified. If a template is missing, it fails with a clear message.
6. **Roster (`Helpers/assets.csv`):** you choose how it is built:
   - **Option A: copy from the template.** Asks how many students (1 to 10, the
     number available) and copies the header plus that many rows.
   - **Option B: generate a fresh roster.** Asks how many students (1 to 20) and
     builds the rows from the `SAMPLE_NAMES` and `SAMPLE_EMAILS` arrays defined in
     the script, with `Attendance Count` and `Absence Count` both starting at `0`.
7. **Permissions:** `chmod +x` on `attendance_checker.py` and `chmod 600` on
   `Helpers/config.json`, followed by an `ls -l` confirmation so the result is visible.
8. **Threshold update (optional):** see the next section.
9. **Verification:** the trap is switched off and the application is started
   (Feature 2). A successful startup proves the structure, roster and config work together.

If any step fails, the partially created project directory is removed so no
half-made deployment is left behind.

---

## How the threshold update works

After permissions are set, the script asks:

```
Update the attendance alert thresholds? (y/n):
```

- **`n`** keeps the template values (`warning` 75, `failure` 50).
- **`y`** prompts for a new `warning` and a new `failure` value using `read`.

**Validation (done before `sed` ever runs):**

- Pressing **Enter** with no input applies the default (75 for warning, 50 for failure).
- Each value must be a **whole number from 0 to 100**. Letters, decimals, negatives,
  empty-after-trim and out-of-range values are rejected and re-prompted.
- `failure` must be **lower than** `warning`. If not, both are asked for again.

**The edit itself:** `sed` rewrites only the `"warning": <number>` and
`"failure": <number>` lines of the **deployed** `Helpers/config.json` (never the
template). The file is not reformatted or reordered; every other line stays
byte-for-byte the same. The pattern keeps the key and spacing and replaces only the digits:

```
"warning": 75   ->   "warning": 80
"failure": 50   ->   "failure": 60
```

`sed -i.bak ... && rm -f ....bak` is used because `-i` behaves differently on
GNU/Linux and macOS; this form works on both and leaves no stray backup file.
After the edit, the updated lines are printed as confirmation, and the file keeps
its `600` permissions.

---

## Relationship between `total_sessions` and the roster

`config.json` contains `total_sessions`: the total number of sessions **including
today's**. It must always be **one more than the prior sessions recorded in the
roster**, because the app calculates each student's percentage as
`attended / total_sessions` and warns if a student's prior sessions do not equal
`total_sessions - 1`.

| Roster option | Prior sessions per student | `total_sessions` |
|---|---|---|
| **A: copied from template** | 4 (`Attendance + Absence = 4`) | **5** (shipped as-is in the template) |
| **B: generated fresh** | 0 (all counts start at 0) | **1** (the script edits the deployed config) |

No extra prompt is needed: the script ships the consistent value automatically.
For Option B, `sed` changes only the `"total_sessions"` line in the deployed
`config.json`; the template is never touched.

---

## Feature 2: Run

Choosing `2` (or reaching the end of a deploy) runs:

```bash
cd attendance_tracker_{name}
python3 attendance_checker.py
```

- From the menu it lists existing deployed projects and asks for the name.
- If the project does not exist, it prints a clear error and returns to the menu.
- The app is interactive: it asks `[P]resent or [A]bsent?` for each student, updates
  `Helpers/assets.csv`, and appends session results to `reports/attendance.log`
  and `reports/absent.log`.
- The run happens in a subshell, so the script's own working directory is unchanged afterwards.
- `absent.log` is only created if at least one student was marked absent.

---

## Feature 3: Archive logs

Choosing `3` asks for the project name, then archives the logs generated by the app.

```
attendance_tracker_{name}/
└── archives/
    ├── attendance/
    │   └── attendance_20261014_031501.log
    └── absent/
        └── absent_20261014_031501.log
```

**How it works:**

1. Checks the project directory exists.
2. Generates **one timestamp** (`YYYYMMDD_HHMMSS`) and uses it for both logs, so the
   pair from the same run are easy to match.
3. For each of `reports/attendance.log` and `reports/absent.log`:
   - if it exists, it is **copied** into its own archive directory with the
     timestamp in the filename (`attendance_<timestamp>.log` or `absent_<timestamp>.log`);
   - if it does not exist, the script prints `Skipped: reports/absent.log does not
     exist (nothing to archive).` and **continues without crashing**.
4. Prints a confirmation showing each archived log and its final path (or
   `No logs were archived.` if neither existed).

**What triggers an archive:** archiving only happens when you choose option `3`.
Nothing is archived automatically. Run it after a marking session.

**Notes:**

- Archive directories are created on demand with `mkdir -p`.
- Files are **copied, not moved**, so the originals in `reports/` stay intact. If an
  archive step fails, no log is lost.
- The app **appends** to its logs each session, so an archived copy contains all
  sessions recorded up to that point.

---

## Signal handling: Ctrl+C and Ctrl+Z

While a deployment is in progress, pressing **Ctrl+C** (`SIGINT`) or **Ctrl+Z**
(`SIGTSTP`) does not leave a mess. The script traps both signals.

### What happens on interrupt

1. Prints `!! Deployment interrupted (INT/TSTP). Cleaning up...`
2. Changes to the script's directory so `zip` and `rm` work on the right paths.
3. **Zips** whatever exists of `attendance_tracker_{name}/` into
   `attendance_tracker_{name}_archive.zip` (a real `.zip` file made with the `zip` command).
4. **Deletes** the incomplete project directory (only if the zip succeeded, so work is never lost).
5. Prints `Session closed cleanly.` and exits (code `130` for Ctrl+C, `148` for Ctrl+Z).

**Order matters: zip first, delete second.**

### When the trap is active

- **On:** from the end of the pre-flight checks until the end of the threshold step.
- **Off:** before the verification run. The trap is for the *deployment script*, not
  for the Python marking session. Pressing Ctrl+C during marking is handled by
  `attendance_checker.py` itself, which saves the students marked so far and exits.

### Safeguards

- **Nothing to clean yet:** if the interrupt comes before the project directory is
  created (for example at the name prompt), the script reports "Nothing had been
  created yet" and exits without zipping or deleting anything.
- **Existing projects are protected:** a `DIR_CREATED` flag is set only once *this
  run* creates the directory. If you interrupt at the "already exists, overwrite?"
  prompt, the existing project is left untouched.
- **Repeat interrupts:** further signals are ignored while the cleanup runs, and an
  old zip of the same name is replaced, not appended to.
- **Closed input:** if input ends mid-deployment (for example piped input runs out),
  every prompt treats it as an abort and runs the same cleanup instead of looping forever.
- **Failed steps:** if a deploy step fails (not interrupted), the partial directory is
  also removed.

### What the `.zip` contains

Whatever had been created at the moment of the interrupt. For example:

| Interrupted at | Zip contents |
|---|---|
| Roster prompt | root folder, `attendance_checker.py`, `Helpers/config.json`, `reports/` |
| Threshold prompt | the above plus `Helpers/assets.csv` |
| Name prompt | no zip (nothing created yet) |

### How to test the Ctrl+C / Ctrl+Z path

1. Run `./deploy_agent.sh` and choose `1`.
2. Enter a name (for example `demo`) and wait for the roster prompt `Choose A or B:`.
3. Press **Ctrl+C**. Repeat in another run with **Ctrl+Z**.
4. Verify the result:
   ```bash
   ls                                           # the zip exists, the project folder is gone
   unzip -l attendance_tracker_demo_archive.zip # list what was archived
   # no unzip? use: python3 -m zipfile -l attendance_tracker_demo_archive.zip
   ```
5. Try other moments too: at the name prompt (nothing to zip), at the threshold prompt
   (almost everything zipped), and at the overwrite prompt with an existing project
   (the existing project must survive).

Ctrl+Z needs a real interactive terminal to behave as it will in use.

---

## How the deployed structure was tested

Testing was done in layers, first by hand and then with scripted input and real signals.

**1. Manual baseline.** Before writing any script, the project was assembled by hand
and run once to see what correct looks like: the prompts, the files that appear in
`reports/`, and how the `Attendance Count` / `Absence Count` columns change.

**2. Structure and content checks after each deploy:**

```bash
find attendance_tracker_demo | sort                   # exact required layout
cat attendance_tracker_demo/Helpers/assets.csv        # header + requested number of rows
cat attendance_tracker_demo/Helpers/config.json       # thresholds and total_sessions
ls -l attendance_tracker_demo/Helpers                 # config.json is -rw-------
ls -l attendance_tracker_demo/attendance_checker.py   # -rwxr-xr-x
diff templates/config.json attendance_tracker_demo/Helpers/config.json   # only intended lines differ
cmp templates/attendance_checker.py attendance_tracker_demo/attendance_checker.py   # identical
```

**3. Test matrix:**

| Area | Cases tested | Result |
|---|---|---|
| Pre-flight | `zip` missing (restricted `PATH`) | clear error, nothing created |
| Project name | empty, spaces, slashes, existing directory (overwrite and abort) | rejected / prompted correctly |
| Roster A | 1, 8, 10 students; 0, 11, letters | valid copied, invalid rejected, `total_sessions` stays 5 |
| Roster B | 1, 3, 5 students; 0, 21, letters | valid generated at 0/0, invalid rejected, `total_sessions` becomes 1 |
| Thresholds | Enter for defaults, `80`/`60`, letters, negative, `150`, failure higher than warning | defaults applied, invalid re-prompted, only the two lines change |
| Permissions | after deploy | `config.json` `-rw-------`, checker `-rwxr-xr-x`, still 600 after threshold edit |
| Run | valid project, nonexistent project | runs / clear error |
| Archive | both logs, only one log, run after a session | correct directories, shared timestamp, graceful "skipped" message |
| Templates | after every test | byte-identical to the originals |
| Signals | Ctrl+C and Ctrl+Z at name, roster, threshold and overwrite prompts | zip created with correct contents, directory removed, existing project untouched |
| Trap scope | Ctrl+C during the marking session | no trap, project kept, no zip |
| Repeat interrupt | same project name twice | one zip, replaced |
| Failure path | template missing mid-deploy | partial directory removed |
| Closed input | input ends at several prompts | clean abort, no infinite loop |

**4. Full end-to-end run (Option A, 8 students).** Pre-flight, 8 students copied,
permissions confirmed, thresholds kept, marking session completed with correct
percentages and alerts, then archive produced matching timestamped files:

```
Archived: .../reports/attendance.log -> .../archives/attendance/attendance_20261014_031501.log
Archived: .../reports/absent.log     -> .../archives/absent/absent_20261014_031501.log
```

---

## Edge cases handled

- Missing `python3` or `zip`: fails early with a clear message
- Empty or invalid project names
- Project directory already exists (overwrite or abort, never silent)
- Permission denied while creating directories
- Missing template files
- Student count out of range or non-numeric
- Threshold input empty, non-numeric, out of range, or failure not below warning
- No `absent.log` because nobody was absent
- Interrupt before anything is created, mid-deploy, or at the overwrite prompt
- Failed deploy step: partial directory cleaned up
- Input closed unexpectedly: no infinite loops
- Invalid menu choice: error message, menu shown again

---

## Design decisions

- **Interactive menu** instead of flags: easier to demonstrate and harder to misuse.
- **Script-relative paths:** `templates/` and projects are located from the script's own
  directory, so it works from anywhere.
- **Small reusable validators** (`is_positive_int`, `is_percent`, `is_valid_name`) so
  validation is written once.
- **Strict project names:** prevents unexpected paths, which matters because
  overwrite uses `rm -rf`.
- **`sed` edits the deployed config only:** templates are treated as read-only.
- **Zip before delete, delete only if zip succeeded:** an interrupt can never lose work.
- **`DIR_CREATED` guard:** the trap only touches a directory this run created.
- **Trap off during verification:** the trap belongs to deployment, not to the Python session.
- **`cp` instead of `mv` for archiving:** non-destructive; originals remain in `reports/`.
- **One shared timestamp per archive run:** each pair of logs is easy to trace together.

---

## Known limitations

- Option B generates at most **20** students (the size of the sample name arrays);
  Option A is limited to the **10** rows in the template.
- Archiving is cumulative because the app appends to its logs. Each archive holds
  every session recorded so far.
- Re-running a session on the same project makes the roster no longer match
  `total_sessions`. Deploy a fresh project for clean demos.
- Pressing Ctrl+C at the main menu (outside a deploy) ends the script with the default
  shell behaviour; the deploy-time trap is intentionally limited to deployment.
- The roster CSV is rewritten by the Python app with Windows-style `\r\n` line endings.
  This comes from the app, not the script.

---

## Git workflow

- Repository named `deploy_agent_rayymaxx`.
- `main` holds the clean baseline: `README.md`, `.gitignore`, `templates/`, then the
  finished script.
- Features were developed on separate branches and merged into `main` when working:
  - deploy flow (structure, roster, permissions, thresholds)
  - archive and run features
  - signal handling (trap, zip-then-delete)
- `.gitignore` excludes generated test deployments (`attendance_tracker_*/`) and
  interrupt archives (`*.zip`), so `main` contains only source files.
- Commit messages use prefixes such as `feat:`, `fix:`, `docs:` and `chore:`.

---

_Video walkthrough: https://youtu.be/gTgz0KgcwW0_


