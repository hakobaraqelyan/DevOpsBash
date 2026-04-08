#!/bin/bash

###############################################################################
# MariaDB Backup Script v2.1 (Fixed DB List Command)
# Ubuntu 24.04 + MariaDB 10.11+
###############################################################################

# --- Default արժեքներ ---
DEFAULT_BACKUP_DIR="/var/backups/mariadb"
DEFAULT_RETENTION_DAYS=3
DEFAULT_COMPRESSOR="gzip"
DEFAULT_COMPRESS_LEVEL=6
DEFAULT_DUMP_CMD="mariadb-dump"
DEFAULT_MYSQL_CMD="mariadb"
DEFAULT_LOG_DIR="/var/log/mariadb-backup"

# --- Փոփոխականներ ---
BACKUP_DIR="$DEFAULT_BACKUP_DIR"
RETENTION_DAYS="$DEFAULT_RETENTION_DAYS"
COMPRESSOR="$DEFAULT_COMPRESSOR"
COMPRESS_LEVEL="$DEFAULT_COMPRESS_LEVEL"
DUMP_CMD="$DEFAULT_DUMP_CMD"
MYSQL_CMD="$DEFAULT_MYSQL_CMD"
LOG_DIR="$DEFAULT_LOG_DIR"

# --- Սխալների հավաքագրում ---
declare -a FAILED_DBS
ERROR_REPORT_FILE=""

# --- Օգնություն ---
show_help() {
    echo "Օգտագործման ձևը: $0 [պարամետրեր]"
    echo "  -d, --dir           Պահպանման ճանապարհ (Default: $DEFAULT_BACKUP_DIR)"
    echo "  -r, --retention     Պահպանման օրեր (Default: $DEFAULT_RETENTION_DAYS)"
    echo "  -c, --compressor    Արխիվատոր (Default: $DEFAULT_COMPRESSOR)"
    echo "  -l, --level         Սեղմման աստիճան 1-9 (Default: $DEFAULT_COMPRESS_LEVEL)"
    echo "  -h, --help          Օգնություն"
}

# --- Արգումենտներ ---
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dir) BACKUP_DIR="$2"; shift 2 ;;
        -r|--retention) RETENTION_DAYS="$2"; shift 2 ;;
        -c|--compressor) COMPRESSOR="$2"; shift 2 ;;
        -l|--level) COMPRESS_LEVEL="$2"; shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "Սխալ պարամետր: $1"; show_help; exit 1 ;;
    esac
done

# --- Նախապատրաստում ---
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
DATE_STAMP=$(date +"%Y-%m-%d")
mkdir -p "$BACKUP_DIR"
mkdir -p "$LOG_DIR"

MAIN_LOG="${LOG_DIR}/backup_${DATE_STAMP}.log"
ERROR_REPORT_FILE="${LOG_DIR}/errors_${DATE_STAMP}.report"

# Լոգեր ֆունկցիա
log_message() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$MAIN_LOG"
}

log_message "=== Սկսվում է Backup պրոցեսը ==="
log_message "Պանակ: $BACKUP_DIR | Պահպանում: $RETENTION_DAYS օր"

# Ստուգել հրամանները
if ! command -v $DUMP_CMD &> /dev/null; then
    log_message "ՍԽԱԼ: $DUMP_CMD հրամանը չի գտնվել։"
    exit 1
fi

if ! command -v $MYSQL_CMD &> /dev/null; then
    log_message "ՍԽԱԼ: $MYSQL_CMD հրամանը չի գտնվել։"
    exit 1
fi

# --- ՇՏԿՎԱԾ ՄԱՍ ---
# Ստանալ բազաների ցանկը mariadb կլիենտով (ոչ թե dump-ով)
DBS=$($MYSQL_CMD --silent --skip-column-names -e "SHOW DATABASES;" | grep -Ev "(mysql|information_schema|performance_schema|sys)")

if [ -z "$DBS" ]; then
    log_message "Նախազգուշացում: Օգտագործողի բազաներ չեն գտնվել։"
    exit 0
fi

TOTAL_DBS=$(echo "$DBS" | wc -l)
CURRENT_DB=0
SUCCESS_COUNT=0

# --- Հիմնական Ցիկլ ---
for DB in $DBS; do
    CURRENT_DB=$((CURRENT_DB + 1))
    log_message "[$CURRENT_DB/$TOTAL_DBS] Մշակվում է՝ $DB"
    
    FILE_NAME="${DB}_${TIMESTAMP}.sql"
    BACKUP_FILE="${BACKUP_DIR}/${FILE_NAME}"
    DB_BACKUP_SUCCESS=false

    # 1. Կատարել Dump
    if $DUMP_CMD --single-transaction --quick --lock-tables=false "$DB" > "$BACKUP_FILE" 2>> "$MAIN_LOG"; then
        
        # 2. Սեղմել (եթե պահանջվում է)
        if [ "$COMPRESSOR" == "gzip" ]; then
            if gzip -${COMPRESS_LEVEL} "$BACKUP_FILE"; then
                log_message "   + Dump և սեղմում հաջողված է։"
                DB_BACKUP_SUCCESS=true
            else
                log_message "   - ՍԽԱԼ: Սեղմումը ձախողվեց։"
            fi
        else
            log_message "   + Dump հաջողված է (առանց սեղմման)։"
            DB_BACKUP_SUCCESS=true
        fi
    else
        log_message "   - ՍԽԱԼ: Dump ձախողվեց։"
    fi

    # 3. Ռոտացիա և Ջնջում (Միայն եթե հաջողվել է)
    if [ "$DB_BACKUP_SUCCESS" == true ]; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        
        # Ջնջել միայն ԱՅՍ բազայի հին ֆայլերը
        DELETED_COUNT=$(find "$BACKUP_DIR" -maxdepth 1 -type f -name "${DB}_*.sql*" -mtime +$RETENTION_DAYS -delete -print | wc -l)
        
        if [ "$DELETED_COUNT" -gt 0 ]; then
            log_message "   * Ջնջվել են $DELETED_COUNT հին արխիվ ($DB)։"
        fi
    else
        # Եթե ձախողվել է, ավելացնել սխալների ցուցակ
        FAILED_DBS+=("$DB")
        log_message "   ! ՈՒՇԱԴՐՈՒԹՅՈՒՆ: $DB բազայի հին արխիվները ՉԵՆ ջնջվել (պահպանվում են)։"
    fi
done

# --- Վերջնական Հաղորդում (Report) ---
log_message "=== Պրոցեսն ավարտված է ==="
log_message "Հաջողված: $SUCCESS_COUNT / $TOTAL_DBS"

if [ ${#FAILED_DBS[@]} -gt 0 ]; then
    log_message "ՍԽԱԼՆԵՐ ԵՆ ՀԱՅՏՆԱԲԵՐՎԵԼ!"
    
    # Ստեղծել սխալների զեկույց ֆայլ
    {
        echo "Backup Error Report"
        echo "Date: $(date)"
        echo "Host: $(hostname)"
        echo "-----------------------------------"
        echo "Failed Databases:"
        for failed_db in "${FAILED_DBS[@]}"; do
            echo "- $failed_db"
        done
        echo "-----------------------------------"
        echo "Action Required: Check $MAIN_LOG for details."
    } > "$ERROR_REPORT_FILE"

    # Տպել էկրանին
    echo ""
    echo "=========================================="
    echo "⚠️  ՈՒՇԱԴՐՈՒԹՅՈՒՆ: Backup-ի սխալներ"
    echo "=========================================="
    echo "Հետևյալ բազաները չեն backup-վել:"
    for failed_db in "${FAILED_DBS[@]}"; do
        echo "  ❌ $failed_db"
    done
    echo ""
    echo "Մանրամասն զեկույցը պահպանված է՝ $ERROR_REPORT_FILE"
    echo "Հին արխիվները չեն ջնջվել սխալված բազաների համար։"
    echo "=========================================="
    
    exit 1
else
    log_message "Բոլոր բազաները backup-վել են հաջողությամբ։"
    exit 0
fi