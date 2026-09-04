# Imitor Sync Manager

A native macOS app for running scheduled, versioned backups with `rsync`. It manages any number of independent sync tasks — each with its own source folders, destination, and schedule — and runs quietly in the background via the menu bar, without needing Terminal or cron.

Requires macOS 13 (Ventura) or later.

## Get a modern rsync via Homebrew (recommended)

macOS's built-in `rsync` is either an ancient 2.6.9-era build or, on recent
macOS, Apple's `openrsync` reimplementation — both lack `--info=progress2`,
which is what this app uses to show a live progress bar and ETA per task,
and both are missing years of upstream `rsync` bug fixes and performance
work. The app still runs fine without it — sources are backed up and
versioned correctly either way — but you get a plainer experience (no
progress bar/ETA) until a newer `rsync` is available.

1. **Install Homebrew** if you don't already have it — one command from the
   Terminal, see [brew.sh](https://brew.sh).
2. **Install rsync**:
   ```
   brew install rsync
   ```

The app checks once a day and will try to run this for you automatically if
Homebrew is already installed, but that background check depends on the app
being able to find and run `brew` the same way a Terminal shell does, which
isn't always reliable from a GUI app on every machine. If you want to be
certain you're on a current `rsync`, run the command above yourself — the
app always prefers a Homebrew-installed `rsync` (`/opt/homebrew/bin/rsync`
or `/usr/local/bin/rsync`) over macOS's own, with no configuration needed.

## Features

### Sync tasks
Every backup job is a self-contained **task**: its own sources, its own destination, its own schedule. Add as many as you need — a "Documents → external drive, nightly" task and a "Photos → NAS, weekly" task run completely independently. Tasks live in the sidebar; double-click one to rename it inline.

### Sources, per-folder copy mode
Add any number of source directories to a task. Each source independently chooses how it lands in the destination:
- **Contents Only** — the folder's contents are copied straight into the destination root.
- **Folder + Contents** — the folder itself is copied as a subfolder of the destination, so two sources with overlapping filenames don't collide.

### Destination
Pick any folder or mounted volume as a task's destination. The app shows a live reachability indicator (green/red) so you know at a glance if a destination drive is unmounted before a run fails.

### Versioned backups
Nothing is silently overwritten. Whenever a file in the destination is about to be replaced because it changed, the old copy is moved into a timestamped `.versions/<date>_<time>/` folder first — simple, automatic point-in-time recovery.

### Scheduling
Each task can run automatically: hourly, daily at a set time, weekly on a chosen day, or every N minutes. Schedules are implemented as per-task `launchd` LaunchAgents — the native macOS mechanism, and more reliable than cron under modern macOS's permission model. Turning a schedule off cleanly removes its LaunchAgent.

### Menu bar + window
A full window for managing tasks, sources, destinations, and schedules, plus an Activity Log. A menu bar item shows live per-task status (idle / syncing / last result with timestamp) with one-click "Run Now" per task or "Run All Now," so you never have to open the window just to check on things.

### Run status
Clicking "Run Now" shows exactly when a task finishes — "Completed at HH:MM" in green, or "Failed at HH:MM" in red — right where you clicked, plus in the menu bar and sidebar.

### No separate installs required
The app shells out to the `rsync` already built into macOS (`/usr/bin/rsync`), so there's nothing extra to download to get started. See [Get a modern rsync via Homebrew](#get-a-modern-rsync-via-homebrew-recommended) above for why you'd want a newer one anyway.

## Configuration & data

Task configuration lives in `~/.config/rsync_backup/tasks.json`. Activity logs are written to `~/.config/rsync_backup/backup.log`. Both are created automatically on first run.

## Where it came from

The project started as `rsync_backup.sh`, a terminal-based backup manager written by **Santo Berlin** — a menu-driven bash script that tracked source directories and a destination in `~/.config/rsync_backup/`, ran `rsync` with checksum-based versioning, and could schedule itself via `crontab`. That original script is still included in this repository (`rsync_backup.sh`) and remains fully compatible — the app reads and migrates its config format automatically.

Imitor Sync Manager is a full native macOS rewrite of that tool, built by **Wolfcare**, with the SwiftUI implementation written by **Claude** (Anthropic's AI model) working directly with Wolfcare inside Claude Code, Anthropic's agentic coding CLI. The original script's core backup logic and file-format conventions were carried forward deliberately; the interface, multi-task architecture, `launchd` scheduling, menu bar, and app icon were designed and built fresh for macOS.

Script written by Santo Berlin © 2026. GUI written by Wolfcare © 2026.

## How it was built

The app was written through an iterative, conversational process rather than a single spec-and-build pass — starting from a single-task GUI wrapper around the bash script's logic, then expanding to independent multi-task support, per-source copy modes, inline renaming, and run-status feedback, with each change built and functionally tested before moving to the next.

- **SwiftUI**, targeting macOS 13+, with the project structure generated via **XcodeGen** from `project.yml` rather than a hand-edited `.xcodeproj`.
- Backup logic was verified **headlessly** first — invoking the compiled binary directly with `--run <task-id>` against scratch test folders — to confirm `rsync` behaviour, versioning, and multi-task isolation before the GUI was ever involved.
- Config storage intentionally mirrors the original bash script's format where possible, with automatic migration for anyone still holding old-format data.
- The app icon is generated from a vector source (`Design/imitor_icon.svg`) into the full macOS icon set and a dedicated menu bar glyph.

## Project layout

```
Sources/
  App/          App entry point, Info.plist, asset catalog (icons)
  Models/       SyncTask, SourceEntry, ScheduleKind, BackupStore, config I/O
  Services/     rsync execution, launchd scheduling, headless --run path
  Views/        SwiftUI views (task list, sources, destination, schedule, log, menu bar)
Design/         Vector logo source
project.yml     XcodeGen project spec
rsync_backup.sh Original bash script (still functional, config-compatible)
```
