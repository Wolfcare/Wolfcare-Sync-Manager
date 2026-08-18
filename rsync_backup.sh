 #!/bin/bash
#
# run it without gui: rsync_backup.sh run
#
# GitHub: https://github.com/username/Wolfcare-Sync-Manager
# Enhanced with Claude AI: https://claude.ai
#
set -uo pipefail

CONFIG_DIR="$HOME/.config/rsync_backup"
DIRS_FILE="$CONFIG_DIR/dirs.list"
CONF_FILE="$CONFIG_DIR/settings.conf"
LOG_FILE="$CONFIG_DIR/backup.log"
CRON_MARKER="# rsync_backup_auto_job"

DEST_ROOT=""

# ---------- setup ----------

init_config() {
    mkdir -p "$CONFIG_DIR"
    touch "$DIRS_FILE" "$LOG_FILE"
    [[ -f "$CONF_FILE" ]] || : > "$CONF_FILE"
}

load_settings() {
    DEST_ROOT=""
    if [[ -f "$CONF_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$CONF_FILE"
    fi
}

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S')  $1" >> "$LOG_FILE"
}

pause() {
    read -r -n1 -p "Press any key to continue..." _ || true
    echo
}

script_full_path() {
    cd "$(dirname "$0")" >/dev/null 2>&1 && pwd -P
    printf '%s' "/$(basename "$0")"
}

resolved_self() {
    local dir base
    dir="$(cd "$(dirname "$0")" && pwd -P)"
    base="$(basename "$0")"
    echo "$dir/$base"
}

#directory list management

add_directory() {
    read -r -e -p "Full path of directory to back up: " dir
    dir="${dir%/}"
    if [[ -z "$dir" ]]; then
        echo "No path entered."
        return
    fi
    if [[ ! -d "$dir" ]]; then
        echo "Not a directory: $dir"
        return
    fi
    dir="$(cd "$dir" && pwd -P)"
    if grep -qxF "$dir" "$DIRS_FILE" 2>/dev/null; then
        echo "Already in the list: $dir"
        return
    fi
    echo "$dir" >> "$DIRS_FILE"
    echo "Added: $dir"
}

list_directories() {
    if [[ ! -s "$DIRS_FILE" ]]; then
        echo "(no directories configured yet)"
        return
    fi
    nl -ba -w2 -s') ' "$DIRS_FILE"
}

remove_directory() {
    if [[ ! -s "$DIRS_FILE" ]]; then
        echo "(no directories configured yet)"
        return
    fi
    list_directories
    read -r -p "Number to remove (blank to cancel): " num
    [[ -z "$num" ]] && return
    if ! [[ "$num" =~ ^[0-9]+$ ]]; then
        echo "Invalid input."
        return
    fi
    local total
    total=$(wc -l < "$DIRS_FILE" | tr -d ' ')
    if (( num < 1 || num > total )); then
        echo "Out of range."
        return
    fi
    sed -i '' "${num}d" "$DIRS_FILE"
    echo "Removed entry $num."
}

set_destination() {
    read -r -e -p "Destination root path (e.g. /Volumes/BackupDrive): " dest
    dest="${dest%/}"
    if [[ -z "$dest" ]]; then
        echo "No path entered."
        return
    fi
    if [[ ! -d "$dest" ]]; then
        read -r -p "Path does not exist. Create it? [y/N]: " yn
        if [[ "$yn" =~ ^[Yy]$ ]]; then
            mkdir -p "$dest" || { echo "Could not create $dest"; return; }
        else
            return
        fi
    fi
    dest="$(cd "$dest" && pwd -P)"
    grep -v '^DEST_ROOT=' "$CONF_FILE" 2>/dev/null > "$CONF_FILE.tmp" || true
    mv "$CONF_FILE.tmp" "$CONF_FILE"
    echo "DEST_ROOT=\"$dest\"" >> "$CONF_FILE"
    echo "Destination set to: $dest"
}

show_settings() {
    load_settings
    echo "Destination root : ${DEST_ROOT:-(not set)}"
    echo "Source dirs file : $DIRS_FILE"
    echo "Log file         : $LOG_FILE"
    echo
    echo "Directories configured:"
    list_directories
}

#backup main

run_backup() {
    load_settings
    init_config

    if [[ -z "$DEST_ROOT" ]]; then
        echo "Destination not set. Use the menu to set one first."
        log "ABORT: destination not configured"
        return 1
    fi
    if [[ ! -d "$DEST_ROOT" ]]; then
        echo "Destination $DEST_ROOT is not reachable (drive unmounted?)."
        log "ABORT: destination $DEST_ROOT not reachable"
        return 1
    fi
    if [[ ! -s "$DIRS_FILE" ]]; then
        echo "No source directories configured."
        log "ABORT: no source directories configured"
        return 1
    fi

    local ts version_root
    ts="$(date '+%Y-%m-%d_%H%M%S')"
    version_root="$DEST_ROOT/.versions/$ts"

    log "===== Backup run started ($ts) ====="

    while IFS= read -r src; do
        [[ -z "$src" ]] && continue
        if [[ ! -d "$src" ]]; then
            log "SKIP (missing) $src"
            continue
        fi

        # Copy the CONTENTS of the source dir straight into the
        # destination root, e.g.
        # /Users/wolfcare/Downloads -> $DEST_ROOT/...
        local dest="$DEST_ROOT"
        mkdir -p "$dest"

        log "Syncing $src/ -> $dest/"
        # -a          archive mode (perms, times, symlinks, recursive...)
        # -c          compare by CHECKSUM instead of size/mtime
        # --backup / --backup-dir
        #             any destination file about to be overwritten because
        #             its checksum differs is moved here first, preserving
        #             its relative path -> acts as simple version control
        rsync -a -c --itemize-changes \
              --backup --backup-dir="$version_root" \
              "$src/" "$dest/" >> "$LOG_FILE" 2>&1
        local rc=$?
        if [[ $rc -eq 0 ]]; then
            log "OK   $src (rsync exit 0)"
        else
            log "FAIL $src (rsync exit $rc)"
        fi
    done < "$DIRS_FILE"

    #nothing changed)
    if [[ -d "$version_root" ]]; then
        find "$version_root" -type d -empty -delete 2>/dev/null
    fi

    log "===== Backup run finished ====="
    echo "Backup complete. See log: $LOG_FILE"
}

view_log() {
    echo "----- last 50 log lines ($LOG_FILE) -----"
    tail -n 50 "$LOG_FILE" 2>/dev/null || echo "(no log yet)"
}

#cron it

install_cron() {
    echo "How often should this run?"
    echo "  1) Every hour"
    echo "  2) Every day at a specific time"
    echo "  3) Every N minutes"
    echo "  4) Custom cron expression"
    echo "  5) Cancel"
    read -r -p "Choice: " c
    local cron_expr=""
    case "$c" in
        1) cron_expr="0 * * * *" ;;
        2)
            read -r -p "Hour (0-23): " hh
            read -r -p "Minute (0-59): " mm
            cron_expr="$mm $hh * * *"
            ;;
        3)
            read -r -p "Run every how many minutes: " n
            cron_expr="*/$n * * * *"
            ;;
        4)
            read -r -p "Enter full 5-field cron expression: " cron_expr
            ;;
        *) echo "Cancelled."; return ;;
    esac

    if [[ -z "$cron_expr" ]]; then
        echo "No schedule entered, cancelled."
        return
    fi

    local self line
    self="$(resolved_self)"
    line="$cron_expr /bin/bash \"$self\" run >> \"$LOG_FILE\" 2>&1 $CRON_MARKER"

    ( crontab -l 2>/dev/null | grep -vF "$CRON_MARKER" ; echo "$line" ) | crontab -

    echo "Cron job installed with schedule: $cron_expr"
    echo "Note (macOS): if the job doesn't seem to run, grant 'cron' / Terminal"
    echo "Full Disk Access under System Settings > Privacy & Security."
}

remove_cron() {
    ( crontab -l 2>/dev/null | grep -vF "$CRON_MARKER" ) | crontab -
    echo "Cron job removed (if one existed)."
}

show_cron() {
    local found
    found="$(crontab -l 2>/dev/null | grep -F "$CRON_MARKER")"
    if [[ -z "$found" ]]; then
        echo "No cron job currently installed."
    else
        echo "Current cron job:"
        echo "$found"
    fi
}

#main men

main_menu() {
    while true; do
        clear
        echo "+=====================================================================================+"
        echo ""
        echo "   rsync backup manager by santo.berlin"
        echo ""
        echo "+=====================================================================================+"
        echo ""
        load_settings
        echo "   Destination: ${DEST_ROOT:-(not set)}"
        echo "   Directories configured: $(wc -l < "$DIRS_FILE" 2>/dev/null | tr -d ' ')"
        echo ""
        echo "+-------------------------------------------------------------------------------------+"
        echo
        echo "   1) Add a directory to back up"
        echo "   2) Remove a directory"
        echo "   3) List directories"
        echo "   4) Set destination root"
        echo "   5) Run backup now"
        echo "   6) Install / update cron schedule"
        echo "   7) Show current cron schedule"
        echo "   8) Remove cron schedule"
        echo "   9) View recent log"
        echo "   0) Exit"
        echo
        echo "+-------------------------------------------------------------------------------------+"
        echo
        read -r -p "   Choose an option: " choice
        echo
        case "$choice" in
            1) add_directory ;;
            2) remove_directory ;;
            3) list_directories ;;
            4) set_destination ;;
            5) run_backup ;;
            6) install_cron ;;
            7) show_cron ;;
            8) remove_cron ;;
            9) view_log ;;
            0) exit 0 ;;
            *) echo "Invalid choice." ;;
        esac
        echo
        pause
    done
}

#EP!

init_config

if [[ "${1:-}" == "run" ]]; then
    run_backup
    exit $?
fi

main_menu