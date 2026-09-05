#!/data/data/com.termux/files/usr/bin/sh
# Obsidian vault sync for Android/Termux using rclone.

set -u

LOCAL_PATH=${OBSIDIAN_LOCAL_PATH:-"$HOME/storage/shared/Obsidian"}
REMOTE_PATH=${OBSIDIAN_REMOTE_PATH:-"gdrive:00 - Central Workspace/obsidian"}
REMOTE_NAME=${OBSIDIAN_REMOTE_NAME:-gdrive}
LOG_DIR=${OBSIDIAN_LOG_DIR:-"$HOME/.local/state/obsidian-rclone/log"}
REMOTE_LOG_PATH=${OBSIDIAN_REMOTE_LOG_PATH:-"gdrive:00 - Central Workspace/log"}
SNAPSHOT_DIR=${OBSIDIAN_SNAPSHOT_DIR:-"$HOME/.local/share/obsidian-rclone/snapshots"}
MAX_SNAPSHOTS=${OBSIDIAN_MAX_SNAPSHOTS:-10}

ACTION=sync
RESYNC=false
DRY_RUN=false
NO_SNAPSHOT=false
SNAPSHOT_ID=
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
LOG_FILE="$LOG_DIR/obsidian-sync_$TIMESTAMP.log"
EXIT_CODE=0
SNAPSHOT_PATH=

usage() {
    cat <<EOF
Usage: $(basename "$0") [action] [options]

Actions:
  sync                 Bidirectional sync (default; cloud wins conflicts)
  pull                 Copy cloud vault to this device
  push                 Copy this device's vault to cloud
  status               Show connection, vault, log, and snapshot status
  history              List local snapshots
  restore <timestamp>  Restore snapshot (for example: 20260831_143000)

Options:
  --resync             Rebuild bisync state; use on first run
  --dry-run             Preview changes without modifying files
  --no-snapshot         Do not create a snapshot before sync or pull
  -h, --help            Show this help

Configuration can be overridden with OBSIDIAN_LOCAL_PATH, OBSIDIAN_REMOTE_PATH,
OBSIDIAN_REMOTE_NAME, OBSIDIAN_LOG_DIR, OBSIDIAN_REMOTE_LOG_PATH,
OBSIDIAN_SNAPSHOT_DIR, and OBSIDIAN_MAX_SNAPSHOTS.
EOF
}

log() {
    level=$1
    shift
    entry="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
    printf '%s\n' "$entry" | tee -a "$LOG_FILE"
}

die() {
    log ERROR "$*"
    exit 1
}

parse_arguments() {
    while [ "$#" -gt 0 ]; do
        case $1 in
            sync|pull|push|status|history)
                ACTION=$1
                ;;
            restore)
                ACTION=restore
                shift
                [ "$#" -gt 0 ] || die "restore requires a snapshot timestamp"
                SNAPSHOT_ID=$1
                ;;
            --resync)
                RESYNC=true
                ;;
            --dry-run)
                DRY_RUN=true
                ;;
            --no-snapshot)
                NO_SNAPSHOT=true
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                printf 'Unknown argument: %s\n\n' "$1" >&2
                usage >&2
                exit 2
                ;;
        esac
        shift
    done
}

check_rclone() {
    command -v rclone >/dev/null 2>&1 || die "rclone is not installed. Run: pkg install rclone"
    log OK "rclone found: $(rclone version 2>/dev/null | sed -n '1p')"
}

check_remote() {
    if ! rclone listremotes 2>/dev/null | grep -Fxq "$REMOTE_NAME:"; then
        die "Remote '$REMOTE_NAME' is not configured. Run: rclone config"
    fi
    if ! rclone lsd "$REMOTE_NAME:" --max-depth 1 >/dev/null 2>&1; then
        die "Cannot connect to '$REMOTE_NAME'. Check network and rclone authentication."
    fi
    log OK "Remote connection verified: $REMOTE_NAME"
}

check_local_path() {
    if [ ! -d "$LOCAL_PATH" ]; then
        if [ "$ACTION" = pull ]; then
            mkdir -p "$LOCAL_PATH" || die "Cannot create local vault: $LOCAL_PATH"
            log OK "Created local vault directory: $LOCAL_PATH"
            return
        fi
        die "Local vault not found: $LOCAL_PATH. Use 'pull' for the first download."
    fi
    log OK "Local vault found: $LOCAL_PATH ($(find "$LOCAL_PATH" -type f | wc -l | tr -d ' ') files)"
}

rotate_snapshots() {
    snapshot_count=0
    for snapshot in "$SNAPSHOT_DIR"/obsidian_*.tar.gz; do
        [ -f "$snapshot" ] || continue
        snapshot_count=$((snapshot_count + 1))
        if [ "$snapshot_count" -gt "$MAX_SNAPSHOTS" ]; then
            rm -f -- "$snapshot"
            log INFO "Rotated old snapshot: $(basename "$snapshot")"
        fi
    done
}

create_snapshot() {
    [ "$NO_SNAPSHOT" = true ] && { log INFO "Snapshot creation skipped"; return; }
    mkdir -p "$SNAPSHOT_DIR" || { log WARN "Cannot create snapshot directory"; return; }
    SNAPSHOT_PATH="$SNAPSHOT_DIR/obsidian_$TIMESTAMP.tar.gz"
    if tar -C "$LOCAL_PATH" -czf "$SNAPSHOT_PATH" .; then
        log OK "Snapshot created: $(basename "$SNAPSHOT_PATH")"
        rotate_snapshots
    else
        rm -f -- "$SNAPSHOT_PATH"
        SNAPSHOT_PATH=
        log WARN "Snapshot failed; continuing without one"
    fi
}

show_history() {
    [ -d "$SNAPSHOT_DIR" ] || { printf 'No snapshots found.\n'; return; }
    found=false
    for snapshot in "$SNAPSHOT_DIR"/obsidian_*.tar.gz; do
        [ -f "$snapshot" ] || continue
        found=true
        name=$(basename "$snapshot" .tar.gz)
        printf '%s  %s\n' "${name#obsidian_}" "$(du -h "$snapshot" | awk '{print $1}')"
    done
    [ "$found" = true ] || printf 'No snapshots found.\n'
}

restore_snapshot() {
    snapshot="$SNAPSHOT_DIR/obsidian_$SNAPSHOT_ID.tar.gz"
    [ -f "$snapshot" ] || die "Snapshot not found: $snapshot"
    [ -d "$LOCAL_PATH" ] || die "Local vault not found: $LOCAL_PATH"
    if [ "$DRY_RUN" = true ]; then
        log INFO "[DRY RUN] Would restore $snapshot to $LOCAL_PATH"
        return
    fi

    mkdir -p "$SNAPSHOT_DIR" || die "Cannot create snapshot directory"
    safety_snapshot="$SNAPSHOT_DIR/obsidian_${TIMESTAMP}_pre-restore.tar.gz"
    tar -C "$LOCAL_PATH" -czf "$safety_snapshot" . || die "Safety snapshot failed; restore aborted"
    find "$LOCAL_PATH" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + || die "Could not clear local vault"
    tar -C "$LOCAL_PATH" -xzf "$snapshot" || die "Restore failed; safety snapshot is $safety_snapshot"
    log OK "Vault restored from snapshot: $SNAPSHOT_ID"
}

run_rclone() {
    log INFO "Executing: rclone $*"
    rclone "$@"
    result=$?
    [ "$result" -eq 0 ] && log OK "Sync completed successfully" || log ERROR "rclone exited with code $result"
    return "$result"
}

run_sync() {
    set -- bisync "$LOCAL_PATH" "$REMOTE_PATH" --conflict-resolve path2 --conflict-loser num --conflict-suffix conflict --resilient --recover --verbose --log-file "$LOG_FILE"
    [ "$RESYNC" = true ] && set -- "$@" --resync --resync-mode path2
    [ "$DRY_RUN" = true ] && set -- "$@" --dry-run
    run_rclone "$@"
}

run_pull() {
    set -- sync "$REMOTE_PATH" "$LOCAL_PATH" --verbose --log-file "$LOG_FILE"
    [ "$DRY_RUN" = true ] && set -- "$@" --dry-run
    run_rclone "$@"
}

run_push() {
    set -- sync "$LOCAL_PATH" "$REMOTE_PATH" --verbose --log-file "$LOG_FILE"
    [ "$DRY_RUN" = true ] && set -- "$@" --dry-run
    run_rclone "$@"
}

send_log() {
    rclone copyto "$LOG_FILE" "$REMOTE_LOG_PATH/$(basename "$LOG_FILE")" --verbose >/dev/null 2>&1 || log WARN "Could not upload log; it remains at $LOG_FILE"
}

show_status() {
    check_rclone
    check_remote
    if [ -d "$LOCAL_PATH" ]; then
        log INFO "Local vault: $LOCAL_PATH ($(find "$LOCAL_PATH" -type f | wc -l | tr -d ' ') files, $(du -sh "$LOCAL_PATH" | awk '{print $1}'))"
    else
        log WARN "Local vault not found: $LOCAL_PATH"
    fi
    [ -d "$SNAPSHOT_DIR" ] && log INFO "Snapshots: $(find "$SNAPSHOT_DIR" -maxdepth 1 -name 'obsidian_*.tar.gz' -type f | wc -l | tr -d ' ') / $MAX_SNAPSHOTS"
}

main() {
    parse_arguments "$@"
    mkdir -p "$LOG_DIR" || { printf 'Cannot create log directory: %s\n' "$LOG_DIR" >&2; exit 1; }

    case $ACTION in
        history)
            show_history
            exit 0
            ;;
        status)
            show_status
            exit 0
            ;;
    esac

    check_rclone
    check_remote
    check_local_path

    if [ "$ACTION" = restore ]; then
        restore_snapshot
        send_log
        exit 0
    fi

    if [ "$ACTION" = sync ] || [ "$ACTION" = pull ]; then
        [ "$(find "$LOCAL_PATH" -type f | wc -l | tr -d ' ')" -gt 0 ] && create_snapshot
    fi

    case $ACTION in
        sync) run_sync || EXIT_CODE=$? ;;
        pull) run_pull || EXIT_CODE=$? ;;
        push) run_push || EXIT_CODE=$? ;;
    esac
    send_log
    exit "$EXIT_CODE"
}

main "$@"