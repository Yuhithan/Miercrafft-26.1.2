#!/bin/bash
set -u

# ---------------- CONFIG ----------------

SERVER_DIR="$HOME/minecraft/Server_fabric_26.1_2"

# RAM
MIN_RAM="4G"
MAX_RAM="6G"

# Minecraft port
MC_PORT="25565"

# Playit service
PLAYIT_SERVICE="playit"

# ---------------- FUNCTIONS ----------------

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

cleanup() {
    log "Stopping Minecraft..."

    if [ -n "${MC_PID:-}" ] && kill -0 "$MC_PID" 2>/dev/null; then
        kill -SIGINT "$MC_PID"

        # Give Minecraft time to save
        for i in {1..30}; do
            if ! kill -0 "$MC_PID" 2>/dev/null; then
                break
            fi
            sleep 1
        done
    fi

    log "Minecraft stopped."
}

trap cleanup SIGINT SIGTERM EXIT

# ---------------- CHECKS ----------------

log "=========================================="
log " Minecraft Fabric Server"
log "=========================================="

log "Server directory:"
log "$SERVER_DIR"

if [ ! -d "$SERVER_DIR" ]; then
    log "ERROR: Server directory does not exist!"
    exit 1
fi

cd "$SERVER_DIR" || exit 1

# Check Java
if ! command -v java >/dev/null 2>&1; then
    log "ERROR: Java is not installed."
    exit 1
fi

JAVA_VERSION=$(java -version 2>&1 | head -n 1)

log "Java: $JAVA_VERSION"

# Minecraft 26.1 requires Java 25
if ! java -version 2>&1 | grep -q '"25'; then
    log "ERROR: Minecraft 26.1 requires Java 25."
    log "Installed Java:"
    java -version
    exit 1
fi

# ---------------- FIND FABRIC JAR ----------------

if [ -f "fabric-server-launch.jar" ]; then
    SERVER_JAR="fabric-server-launch.jar"
elif [ -f "server.jar" ]; then
    SERVER_JAR="server.jar"
else
    log "ERROR: No Fabric server JAR found!"
    log "Expected:"
    log "  fabric-server-launch.jar"
    log "or"
    log "  server.jar"
    exit 1
fi

log "Server JAR: $SERVER_JAR"

# ---------------- EULA ----------------

if [ ! -f "eula.txt" ]; then
    log "ERROR: eula.txt does not exist."
    log "Start the server manually once and accept the EULA."
    exit 1
fi

if grep -q "eula=false" eula.txt; then
    log "ERROR: Minecraft EULA has not been accepted."
    log "Edit:"
    log "$SERVER_DIR/eula.txt"
    log "and change eula=false to eula=true."
    exit 1
fi

# ---------------- PLAYIT ----------------

if command -v systemctl >/dev/null 2>&1; then

    if systemctl list-unit-files | grep -q "^playit.service"; then

        log "Starting Playit.gg..."

        systemctl start "$PLAYIT_SERVICE"

        sleep 2

        if systemctl is-active --quiet "$PLAYIT_SERVICE"; then
            log "Playit.gg: ONLINE"
        else
            log "WARNING: Playit service is not running."
            log "Check with:"
            log "journalctl -u playit -n 50 --no-pager"
        fi

    else
        log "WARNING: playit.service not installed."
        log "Install Playit first."
    fi

fi

# ---------------- SERVER INFO ----------------

log "=========================================="
log " Starting Minecraft"
log "=========================================="

log "Directory : $SERVER_DIR"
log "Port      : $MC_PORT"
log "RAM       : $MIN_RAM - $MAX_RAM"
log "Java      : 25"
log "Fabric    : detected"
log "Playit    : requested"

# ---------------- START MINECRAFT ----------------

exec java \
    -Xms"$MIN_RAM" \
    -Xmx"$MAX_RAM" \
    -XX:+UseZGC \
    -XX:+UnlockExperimentalVMOptions \
    -XX:+AlwaysPreTouch \
    -jar "$SERVER_JAR" \
    nogui