#!/bin/bash
set -e

# ============================================================
# entrypoint.sh - Manages Spaces backup/restore lifecycle
#
# On start:  Restore /data from Spaces (if backup exists)
# Running:   Periodic backup every 15 minutes
# On stop:   Final backup to Spaces before exit
# ============================================================

DATA_DIR="/data"
BACKUP_PREFIX="backup"
BACKUP_INTERVAL=${BACKUP_INTERVAL:-900}  # 15 minutes default

# S3cmd configuration file
S3CFG="/root/.s3cfg"

# ---- Helper functions ----

configure_s3cmd() {
    # Only configure if Spaces credentials are provided
    if [ -z "$SPACES_ACCESS_KEY" ] || [ -z "$SPACES_SECRET_KEY" ]; then
        echo "[entrypoint] No Spaces credentials found, skipping backup configuration"
        return 1
    fi

    SPACES_ENDPOINT="${SPACES_ENDPOINT:-https://nyc3.digitaloceanspaces.com}"
    SPACES_BUCKET="${SPACES_BUCKET:-heroku-userbot-backup}"

    # Extract host from endpoint URL
    SPACES_HOST=$(echo "$SPACES_ENDPOINT" | sed 's|https://||' | sed 's|http://||')

    cat > "$S3CFG" <<EOF
[default]
access_key = ${SPACES_ACCESS_KEY}
secret_key = ${SPACES_SECRET_KEY}
host_base = ${SPACES_HOST}
host_bucket = %(bucket)s.${SPACES_HOST}
use_https = True
EOF

    echo "[entrypoint] s3cmd configured for ${SPACES_ENDPOINT}"
    return 0
}

spaces_restore() {
    if [ ! -f "$S3CFG" ]; then
        return 0
    fi

    echo "[entrypoint] Checking for existing backup in s3://${SPACES_BUCKET}/${BACKUP_PREFIX}/ ..."
    
    # Check if backup exists
    if s3cmd ls "s3://${SPACES_BUCKET}/${BACKUP_PREFIX}/" 2>/dev/null | grep -q .; then
        echo "[entrypoint] Backup found, restoring..."
        s3cmd sync "s3://${SPACES_BUCKET}/${BACKUP_PREFIX}/" "${DATA_DIR}/" \
            --skip-existing \
            --no-delete-removed \
            2>&1 | tail -5
        echo "[entrypoint] Restore complete"
    else
        echo "[entrypoint] No backup found, starting fresh"
    fi
}

spaces_backup() {
    if [ ! -f "$S3CFG" ]; then
        return 0
    fi

    echo "[entrypoint] Backing up ${DATA_DIR} to s3://${SPACES_BUCKET}/${BACKUP_PREFIX}/ ..."
    
    # Sync data dir to Spaces, excluding build artifacts and caches
    s3cmd sync "${DATA_DIR}/" "s3://${SPACES_BUCKET}/${BACKUP_PREFIX}/" \
        --exclude '__pycache__/*' \
        --exclude '*.pyc' \
        --exclude '.git/*' \
        --exclude 'node_modules/*' \
        --exclude 'Heroku/.git/*' \
        2>&1 | tail -5
    
    echo "[entrypoint] Backup complete at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

periodic_backup() {
    while true; do
        sleep "$BACKUP_INTERVAL"
        spaces_backup
    done
}

# ---- Signal handling ----

shutdown() {
    echo "[entrypoint] Received shutdown signal, performing final backup..."
    spaces_backup
    echo "[entrypoint] Final backup done, exiting"
    
    # Forward signal to child process
    if [ -n "$APP_PID" ]; then
        kill -TERM "$APP_PID" 2>/dev/null
        wait "$APP_PID" 2>/dev/null
    fi
    
    exit 0
}

trap shutdown SIGTERM SIGINT

# ---- Main ----

echo "[entrypoint] Starting Heroku Userbot entrypoint..."

# Configure Spaces (if credentials available)
SPACES_ENABLED=false
if configure_s3cmd; then
    SPACES_ENABLED=true
fi

# Restore from Spaces
if [ "$SPACES_ENABLED" = true ]; then
    spaces_restore
fi

# Start periodic backup in background
if [ "$SPACES_ENABLED" = true ]; then
    periodic_backup &
    BACKUP_PID=$!
    echo "[entrypoint] Periodic backup started (every ${BACKUP_INTERVAL}s, PID: ${BACKUP_PID})"
fi

# Start the application (pass CMD arguments)
echo "[entrypoint] Starting application: $@"
"$@" &
APP_PID=$!

# Wait for the application to exit
wait "$APP_PID"
EXIT_CODE=$?

# Final backup on normal exit
if [ "$SPACES_ENABLED" = true ]; then
    spaces_backup
fi

exit $EXIT_CODE
