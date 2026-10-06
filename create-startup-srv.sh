#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Minecraft Fabric 26.1.2 + systemd installer
# Debian / Ubuntu
# ============================================================

# ---------- Variables ----------
PACKAGES=("openjdk-21-jdk" "wget" "curl" "jq")
MC_VERSION="26.1.2"
MC_DIR="${HOME}/minecraft"
MC_JAR="server.jar"
FABRIC_INSTALLER="${MC_DIR}/fabric-installer.jar"
SERVICE_NAME="minecraft"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# Change these if you want different RAM limits.
MC_MIN_RAM="2G"
MC_MAX_RAM="4G"

# ---------- Colors ----------
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ---------- Root / real user ----------
if [[ "${EUID}" -eq 0 ]]; then
    if [[ -z "${SUDO_USER:-}" || "${SUDO_USER}" == "root" ]]; then
        error "Run this script as your normal user with sudo access, not directly as root."
        exit 1
    fi
    RUN_USER="${SUDO_USER}"
else
    RUN_USER="${USER}"
fi

RUN_HOME="$(getent passwd "${RUN_USER}" | cut -d: -f6)"

if [[ -z "${RUN_HOME}" ]]; then
    error "Could not determine home directory for ${RUN_USER}."
    exit 1
fi

# Keep the requested $HOME/minercaft/server.jar-style layout,
# but use the actual user's home directory even when sudo is used.
MC_DIR="${RUN_HOME}/minecraft"
MC_JAR="server.jar"
FABRIC_INSTALLER="${MC_DIR}/fabric-installer.jar"

# ---------- Loading bar ----------
loading_bar() {
    local message="$1"
    local i
    printf "%s [" "$message"
    for i in $(seq 1 30); do
        printf "#"
        sleep 0.03
    done
    printf "] 100%%\n"
}

# ---------- Check OS ----------
if [[ ! -f /etc/os-release ]]; then
    error "Cannot detect Linux distribution."
    exit 1
fi

. /etc/os-release
if [[ "${ID:-}" != "debian" && "${ID_LIKE:-}" != *debian* ]]; then
    warn "This script is intended for Debian/Ubuntu-based systems."
fi

# ---------- Install packages ----------
info "Updating APT..."
sudo apt update

info "Installing required packages: ${PACKAGES[*]}"
sudo apt install -y "${PACKAGES[@]}"

# ---------- Verify Java ----------
info "Checking Java..."
JAVA_MAJOR="$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d. -f1 | head -n1)"

if [[ -z "${JAVA_MAJOR}" || "${JAVA_MAJOR}" -lt 25 ]]; then
    error "Java 25 or newer is required. Detected: ${JAVA_MAJOR:-unknown}"
    exit 1
fi

info "Java OK: $(java -version 2>&1 | head -n1)"

# ---------- Create server directory ----------
info "Creating Minecraft directory: ${MC_DIR}"
sudo -u "${RUN_USER}" mkdir -p "${MC_DIR}"

# ---------- Download Fabric installer ----------
info "Finding the latest Fabric installer..."
FABRIC_INSTALLER_VERSION="$(
    curl -fsSL "https://meta.fabricmc.net/v2/versions/installer" |
    jq -r 'map(select(.stable == true))[0].version'
)"

if [[ -z "${FABRIC_INSTALLER_VERSION}" || "${FABRIC_INSTALLER_VERSION}" == "null" ]]; then
    error "Could not determine a Fabric installer version."
    exit 1
fi

FABRIC_INSTALLER_URL="https://maven.fabricmc.net/net/fabricmc/fabric-installer/${FABRIC_INSTALLER_VERSION}/fabric-installer-${FABRIC_INSTALLER_VERSION}.jar"

info "Downloading Fabric installer ${FABRIC_INSTALLER_VERSION}..."
sudo -u "${RUN_USER}" wget -q --show-progress \
    -O "${FABRIC_INSTALLER}" \
    "${FABRIC_INSTALLER_URL}"

# ---------- Install Fabric server ----------
info "Installing Fabric server for Minecraft ${MC_VERSION}..."
sudo -u "${RUN_USER}" java -jar "${FABRIC_INSTALLER}" server \
    -mcversion "${MC_VERSION}" \
    -downloadMinecraft \
    -dir "${MC_DIR}"

# The Fabric installer creates fabric-server-launch.jar and downloads server.jar.
if [[ ! -f "${MC_DIR}/fabric-server-launch.jar" ]]; then
    error "Fabric server launcher was not created."
    exit 1
fi

if [[ ! -f "${MC_DIR}/${MC_JAR}" ]]; then
    error "Minecraft ${MC_VERSION} server.jar was not downloaded."
    exit 1
fi

# ---------- EULA ----------
# Set this to true only if you agree to Minecraft's EULA.
echo "eula=true" | sudo -u "${RUN_USER}" tee "${MC_DIR}/eula.txt" >/dev/null

# ---------- Permissions ----------
sudo chown -R "${RUN_USER}:${RUN_USER}" "${MC_DIR}"

# ---------- Remove installer after installation ----------
rm -f "${FABRIC_INSTALLER}"

# ---------- Create systemd service ----------
info "Creating systemd service: ${SERVICE_FILE}"

sudo tee "${SERVICE_FILE}" >/dev/null <<EOF
[Unit]
Description=Minecraft Fabric Server ${MC_VERSION}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
Group=${RUN_USER}
WorkingDirectory=${MC_DIR}

# Fabric's server launcher starts the downloaded server.jar.
ExecStart=/usr/bin/java -Xms${MC_MIN_RAM} -Xmx${MC_MAX_RAM} -jar ${MC_DIR}/fabric-server-launch.jar nogui

Restart=on-failure
RestartSec=10
TimeoutStopSec=30

# Give the server a normal environment.
Environment="HOME=${RUN_HOME}"
Environment="JAVA_HOME=/usr/lib/jvm/java-25-openjdk-amd64"

# Make logs visible through journalctl.
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# ---------- systemd ----------
info "Reloading systemd..."
sudo systemctl daemon-reload

info "Enabling Minecraft service..."
sudo systemctl enable "${SERVICE_NAME}.service"

info "Starting Minecraft..."
sudo systemctl restart "${SERVICE_NAME}.service"

# ---------- Wait for startup ----------
echo
loading_bar "Waiting for Minecraft to start"

if sudo systemctl is-active --quiet "${SERVICE_NAME}.service"; then
    echo
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN} Minecraft Fabric ${MC_VERSION} is RUNNING! ${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo
    echo "Server directory : ${MC_DIR}"
    echo "Minecraft JAR    : ${MC_DIR}/${MC_JAR}"
    echo "Fabric launcher  : ${MC_DIR}/fabric-server-launch.jar"
    echo "Service          : ${SERVICE_NAME}.service"
    echo
    echo "Useful commands:"
    echo "  sudo systemctl status ${SERVICE_NAME}"
    echo "  sudo systemctl restart ${SERVICE_NAME}"
    echo "  sudo systemctl stop ${SERVICE_NAME}"
    echo "  sudo journalctl -u ${SERVICE_NAME} -f"
    echo
else
    echo
    error "Minecraft service failed to start."
    echo
    sudo systemctl status "${SERVICE_NAME}" --no-pager || true
    echo
    echo "Recent logs:"
    sudo journalctl -u "${SERVICE_NAME}" -n 50 --no-pager || true
    exit 1
fi
