#!/usr/bin/env bash
set -Eeuo pipefail

MARIADB_BACKUP_BIN="${MARIADB_BACKUP_BIN:-mariadb-backup}"
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/mariadb}"
DATADIR="${DATADIR:-/var/lib/mysql}"
SOCKET="${SOCKET:-/run/mysqld/mysqld.sock}"
HOST="${HOST:-localhost}"
PORT="${PORT:-3306}"
USER_NAME="${USER_NAME:-backup}"
PASSWORD="${PASSWORD:-}"
PASSWORD_FILE="${PASSWORD_FILE:-}"
PARALLEL="${PARALLEL:-2}"
USE_MEMORY="${USE_MEMORY:-512M}"
TMPDIR="${TMPDIR:-/tmp}"
OPEN_FILES_LIMIT="${OPEN_FILES_LIMIT:-65535}"
FTWRL_WAIT_TIMEOUT="${FTWRL_WAIT_TIMEOUT:-30}"
FTWRL_WAIT_THRESHOLD="${FTWRL_WAIT_THRESHOLD:-10}"
FTWRL_WAIT_QUERY_TYPE="${FTWRL_WAIT_QUERY_TYPE:-ALL}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
FULL_PREFIX="${FULL_PREFIX:-full}"
INCR_PREFIX="${INCR_PREFIX:-inc}"
LOG_DIR="${LOG_DIR:-$BACKUP_ROOT/logs}"
META_DIR_NAME="${META_DIR_NAME:-meta}"
TIMESTAMP="${TIMESTAMP:-$(date '+%F_%H-%M-%S')}"
SERVICE_NAME="${SERVICE_NAME:-mariadb}"
MYSQL_OWNER="${MYSQL_OWNER:-mysql:mysql}"

TARGET_DIR="${TARGET_DIR:-}"
INCREMENTAL_DIR="${INCREMENTAL_DIR:-}"
BASE_DIR="${BASE_DIR:-}"
FORCE_NON_EMPTY_DIRECTORIES="${FORCE_NON_EMPTY_DIRECTORIES:-false}"
STOP_SERVICE_ON_RESTORE="${STOP_SERVICE_ON_RESTORE:-true}"
CHOWN_AFTER_RESTORE="${CHOWN_AFTER_RESTORE:-true}"

MODE=""
LOG_FILE=""
MARIADB_ARGS=()

die() {
  echo "ERROR: $*" >&2
  exit 1
}

log() {
  echo "[$(date '+%F %T')] $*"
}

usage() {
  cat <<'EOF'
Usage:
  backup_full_and_incrimental.sh <mode> [options]

Modes:
  full
  incr
  prepare-full
  prepare-incr
  chain-prepare
  restore
  info
EOF
}

bool_is_true() {
  case "${1,,}" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

require_bin() {
  command -v "$1" >/dev/null 2>&1 || die "Required binary not found: $1"
}

ensure_dir() {
  mkdir -p "$1"
}

read_password_from_file() {
  [[ -n "$PASSWORD_FILE" ]] || return 0
  [[ -f "$PASSWORD_FILE" ]] || die "Password file not found: $PASSWORD_FILE"
  PASSWORD="$(<"$PASSWORD_FILE")"
}

build_common_args() {
  MARIADB_ARGS=()
  MARIADB_ARGS+=("--user=$USER_NAME")

  if [[ -n "$PASSWORD" ]]; then
    MARIADB_ARGS+=("--password=$PASSWORD")
  fi

  if [[ -n "$SOCKET" ]]; then
    MARIADB_ARGS+=("--socket=$SOCKET")
  else
    MARIADB_ARGS+=("--host=$HOST" "--port=$PORT")
  fi

  MARIADB_ARGS+=("--parallel=$PARALLEL")
  MARIADB_ARGS+=("--open-files-limit=$OPEN_FILES_LIMIT")
  MARIADB_ARGS+=("--tmpdir=$TMPDIR")
  MARIADB_ARGS+=("--ftwrl-wait-timeout=$FTWRL_WAIT_TIMEOUT")
  MARIADB_ARGS+=("--ftwrl-wait-threshold=$FTWRL_WAIT_THRESHOLD")
  MARIADB_ARGS+=("--ftwrl-wait-query-type=$FTWRL_WAIT_QUERY_TYPE")
}

write_meta() {
  local dir="$1"
  local meta_dir="$dir/$META_DIR_NAME"
  ensure_dir "$meta_dir"

  cat > "$meta_dir/script.env" <<EOF
MODE=$MODE
TIMESTAMP=$TIMESTAMP
BACKUP_ROOT=$BACKUP_ROOT
DATADIR=$DATADIR
SOCKET=$SOCKET
HOST=$HOST
PORT=$PORT
USER_NAME=$USER_NAME
PARALLEL=$PARALLEL
USE_MEMORY=$USE_MEMORY
TMPDIR=$TMPDIR
OPEN_FILES_LIMIT=$OPEN_FILES_LIMIT
RETENTION_DAYS=$RETENTION_DAYS
SERVICE_NAME=$SERVICE_NAME
MYSQL_OWNER=$MYSQL_OWNER
EOF
}

get_latest_full_backup() {
  find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name "${FULL_PREFIX}_*" | sort | tail -n 1
}

get_incrementals_for_base() {
  local base="$1"
  local base_name
  base_name="$(basename "$base")"
  find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name "${INCR_PREFIX}_*" | sort | while read -r inc; do
    if [[ -f "$inc/$META_DIR_NAME/base_name" ]] && [[ "$(cat "$inc/$META_DIR_NAME/base_name")" == "$base_name" ]]; then
      echo "$inc"
    fi
  done
}

get_latest_incremental_or_base() {
  local base="$1"
  local last="$base"
  while read -r inc; do
    [[ -n "$inc" ]] && last="$inc"
  done < <(get_incrementals_for_base "$base")
  echo "$last"
}

assert_target_exists() {
  [[ -n "$TARGET_DIR" ]] || die "--target-dir is required"
  [[ -d "$TARGET_DIR" ]] || die "Target directory not found: $TARGET_DIR"
}

assert_incremental_exists() {
  [[ -n "$INCREMENTAL_DIR" ]] || die "--incremental-dir is required"
  [[ -d "$INCREMENTAL_DIR" ]] || die "Incremental directory not found: $INCREMENTAL_DIR"
}

cleanup_old_full_backups() {
  local now epoch_cutoff
  now="$(date +%s)"
  epoch_cutoff=$(( now - RETENTION_DAYS * 86400 ))

  find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name "${FULL_PREFIX}_*" | while read -r full; do
    local mtime
    mtime="$(stat -c %Y "$full")"
    if (( mtime < epoch_cutoff )); then
      log "Deleting old full backup: $full"
      rm -rf -- "$full"
    fi
  done
}

print_info() {
  assert_target_exists
  log "Backup info for: $TARGET_DIR"
  [[ -f "$TARGET_DIR/xtrabackup_info" ]] && { echo "----- xtrabackup_info -----"; cat "$TARGET_DIR/xtrabackup_info"; }
  [[ -f "$TARGET_DIR/xtrabackup_checkpoints" ]] && { echo "----- xtrabackup_checkpoints -----"; cat "$TARGET_DIR/xtrabackup_checkpoints"; }
}

parse_args() {
  [[ $# -gt 0 ]] || { usage; exit 1; }
  MODE="$1"
  shift

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --backup-root) BACKUP_ROOT="$2"; shift 2 ;;
      --target-dir) TARGET_DIR="$2"; shift 2 ;;
      --incremental-dir) INCREMENTAL_DIR="$2"; shift 2 ;;
      --base-dir) BASE_DIR="$2"; shift 2 ;;
      --datadir) DATADIR="$2"; shift 2 ;;
      --socket) SOCKET="$2"; shift 2 ;;
      --host) HOST="$2"; shift 2 ;;
      --port) PORT="$2"; shift 2 ;;
      --user) USER_NAME="$2"; shift 2 ;;
      --password) PASSWORD="$2"; shift 2 ;;
      --password-file) PASSWORD_FILE="$2"; shift 2 ;;
      --parallel) PARALLEL="$2"; shift 2 ;;
      --use-memory) USE_MEMORY="$2"; shift 2 ;;
      --tmpdir) TMPDIR="$2"; shift 2 ;;
      --open-files-limit) OPEN_FILES_LIMIT="$2"; shift 2 ;;
      --retention-days) RETENTION_DAYS="$2"; shift 2 ;;
      --service-name) SERVICE_NAME="$2"; shift 2 ;;
      --mysql-owner) MYSQL_OWNER="$2"; shift 2 ;;
      --force-non-empty-directories) FORCE_NON_EMPTY_DIRECTORIES="$2"; shift 2 ;;
      --stop-service-on-restore) STOP_SERVICE_ON_RESTORE="$2"; shift 2 ;;
      --chown-after-restore) CHOWN_AFTER_RESTORE="$2"; shift 2 ;;
      --timestamp) TIMESTAMP="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown argument: $1" ;;
    esac
  done
}

run_full_backup() {
  ensure_dir "$BACKUP_ROOT"
  ensure_dir "$LOG_DIR"
  read_password_from_file
  build_common_args

  TARGET_DIR="${TARGET_DIR:-$BACKUP_ROOT/${FULL_PREFIX}_${TIMESTAMP}}"
  LOG_FILE="$LOG_DIR/full_${TIMESTAMP}.log"

  ensure_dir "$TARGET_DIR"
  ensure_dir "$TARGET_DIR/$META_DIR_NAME"

  log "Starting full backup: $TARGET_DIR"
  "$MARIADB_BACKUP_BIN" \
    "${MARIADB_ARGS[@]}" \
    --backup \
    --target-dir="$TARGET_DIR" \
    2>&1 | tee "$LOG_FILE"

  write_meta "$TARGET_DIR"
  echo "$(basename "$TARGET_DIR")" > "$TARGET_DIR/$META_DIR_NAME/base_name"
  echo "full" > "$TARGET_DIR/$META_DIR_NAME/backup_type"

  cleanup_old_full_backups
  log "Full backup completed: $TARGET_DIR"
}

run_incremental_backup() {
  ensure_dir "$BACKUP_ROOT"
  ensure_dir "$LOG_DIR"
  read_password_from_file
  build_common_args

  local base last_ref
  base="${BASE_DIR:-$(get_latest_full_backup)}"
  [[ -n "$base" ]] || die "No full backup found. Create a full backup first."

  last_ref="$(get_latest_incremental_or_base "$base")"
  TARGET_DIR="${TARGET_DIR:-$BACKUP_ROOT/${INCR_PREFIX}_${TIMESTAMP}}"
  LOG_FILE="$LOG_DIR/incr_${TIMESTAMP}.log"

  ensure_dir "$TARGET_DIR"
  ensure_dir "$TARGET_DIR/$META_DIR_NAME"

  log "Starting incremental backup: $TARGET_DIR"
  log "Base full backup: $base"
  log "Incremental basedir: $last_ref"

  "$MARIADB_BACKUP_BIN" \
    "${MARIADB_ARGS[@]}" \
    --backup \
    --target-dir="$TARGET_DIR" \
    --incremental-basedir="$last_ref" \
    2>&1 | tee "$LOG_FILE"

  write_meta "$TARGET_DIR"
  echo "$(basename "$base")" > "$TARGET_DIR/$META_DIR_NAME/base_name"
  echo "$last_ref" > "$TARGET_DIR/$META_DIR_NAME/parent_ref"
  echo "incremental" > "$TARGET_DIR/$META_DIR_NAME/backup_type"

  log "Incremental backup completed: $TARGET_DIR"
}

run_prepare_full() {
  assert_target_exists
  ensure_dir "$LOG_DIR"
  LOG_FILE="$LOG_DIR/prepare_full_${TIMESTAMP}.log"

  log "Preparing full backup: $TARGET_DIR"
  "$MARIADB_BACKUP_BIN" \
    --prepare \
    --use-memory="$USE_MEMORY" \
    --target-dir="$TARGET_DIR" \
    2>&1 | tee "$LOG_FILE"

  log "Prepare full completed: $TARGET_DIR"
}

run_prepare_incremental() {
  assert_target_exists
  assert_incremental_exists
  ensure_dir "$LOG_DIR"
  LOG_FILE="$LOG_DIR/prepare_incr_${TIMESTAMP}.log"

  log "Applying incremental backup"
  log "Base target-dir: $TARGET_DIR"
  log "Incremental dir : $INCREMENTAL_DIR"

  "$MARIADB_BACKUP_BIN" \
    --prepare \
    --use-memory="$USE_MEMORY" \
    --target-dir="$TARGET_DIR" \
    --incremental-dir="$INCREMENTAL_DIR" \
    2>&1 | tee "$LOG_FILE"

  log "Incremental apply completed"
}

run_chain_prepare() {
  assert_target_exists
  run_prepare_full

  local inc
  while read -r inc; do
    [[ -n "$inc" ]] || continue
    INCREMENTAL_DIR="$inc"
    run_prepare_incremental
  done < <(get_incrementals_for_base "$TARGET_DIR")

  log "Full chain prepared successfully for base: $TARGET_DIR"
}

run_restore() {
  assert_target_exists
  ensure_dir "$LOG_DIR"
  LOG_FILE="$LOG_DIR/restore_${TIMESTAMP}.log"

  if bool_is_true "$STOP_SERVICE_ON_RESTORE"; then
    log "Stopping service: $SERVICE_NAME"
    systemctl stop "$SERVICE_NAME"
  fi

  if [[ -d "$DATADIR" ]] && [[ -n "$(find "$DATADIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    if ! bool_is_true "$FORCE_NON_EMPTY_DIRECTORIES"; then
      die "Datadir is not empty: $DATADIR"
    fi
  fi

  log "Restoring backup from $TARGET_DIR to $DATADIR"
  if bool_is_true "$FORCE_NON_EMPTY_DIRECTORIES"; then
    "$MARIADB_BACKUP_BIN" --copy-back --force-non-empty-directories --target-dir="$TARGET_DIR" --datadir="$DATADIR" 2>&1 | tee "$LOG_FILE"
  else
    "$MARIADB_BACKUP_BIN" --copy-back --target-dir="$TARGET_DIR" --datadir="$DATADIR" 2>&1 | tee "$LOG_FILE"
  fi

  if bool_is_true "$CHOWN_AFTER_RESTORE"; then
    chown -R "$MYSQL_OWNER" "$DATADIR"
  fi

  if bool_is_true "$STOP_SERVICE_ON_RESTORE"; then
    systemctl start "$SERVICE_NAME"
  fi

  log "Restore completed"
}

main() {
  parse_args "$@"
  require_bin "$MARIADB_BACKUP_BIN"
  require_bin find
  require_bin sort
  require_bin tee

  case "$MODE" in
    full) run_full_backup ;;
    incr) run_incremental_backup ;;
    prepare-full) run_prepare_full ;;
    prepare-incr) run_prepare_incremental ;;
    chain-prepare) run_chain_prepare ;;
    restore) run_restore ;;
    info) print_info ;;
    *) usage; die "Unsupported mode: $MODE" ;;
  esac
}

main "$@"