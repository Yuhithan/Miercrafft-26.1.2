```bash
#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# Minecraft Fabric 26.1.2 Server Installer
# Ubuntu 24.04
#
# Installs:
#   - OpenJDK 25
#   - wget
#   - curl
#   - jq
#   - Fabric Server Launcher
#
# Creates:
#   $HOME/minecraft/
#   /etc/systemd/system/minecraft.service
# ============================================================


# ============================================================
# VARIABLES
# ============================================================

MC_VERSION="26.1.2"

MC_DIR="${HOME}/minecraft"

MC_JAR="server.jar"

FABRIC_JAR="${MC_DIR}/fabric-server.jar"

SERVICE_NAME="minecraft"

SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# Change these if your machine has more/less RAM.
MC_MIN_RAM="2G"
MC_MAX_RAM="4G"

PACKAGES=(
    openjdk-25-jdk
    wget
    curl
    jq
)


# ============================================================
# COLORS
# ============================================================

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
RESET="\033[0m"


# ============================================================
# FUNCTIONS
# ============================================================

info() {
    echo -e "${GREEN}[INFO]${RESET} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${RESET} $1"
}

error() {
    echo -e "${RED}[ERROR]${RESET} $1"
}

loading_bar() {

    local message="$1"

    echo -ne "${CYAN}${message}${RESET} ["

    for i in $(seq 1 30); do
        echo -ne "#"
        sleep 0.04
    done

    echo "] 100%"
}


# ============================================================
# CHECK UBUNTU
# ============================================================

if [[ ! -f /etc/os-release ]]; then

    error "Cannot detect operating system."

    exit 1

fi

source /etc/os-release


if [[ "${ID}" != "ubuntu" ]]; then

    warn "This script was designed specifically for Ubuntu 24.04."

fi


if [[ "${VERSION_ID:-}" != "24.04" ]]; then

    warn "Detected Ubuntu version: ${VERSION_ID:-unknown}"

fi


# ============================================================
# CHECK USER
# ============================================================

if [[ "${EUID}" -eq 0 ]]; then

    error "Do not run this script directly as root."

    echo
    echo "Run it as your normal user:"
    echo
    echo "  ./create-startup-srv.sh"
    echo

    exit 1

fi


if ! sudo -v; then

    error "This script requires sudo privileges."

    exit 1

fi


# ============================================================
# APT UPDATE
# ============================================================

echo
info "Updating APT package lists..."

sudo apt update


# ============================================================
# REMOVE OLD JAVA 21
# ============================================================

if dpkg -s openjdk-21-jdk >/dev/null 2>&1; then

    info "Removing old OpenJDK 21..."

    sudo apt remove -y openjdk-21-jdk

fi


# ============================================================
# INSTALL PACKAGES
# ============================================================

echo
info "Installing required packages:"
echo

for PACKAGE in "${PACKAGES[@]}"; do
    echo "  - ${PACKAGE}"
done

echo

sudo apt install -y "${PACKAGES[@]}"


# ============================================================
# SELECT JAVA 25
# ============================================================

info "Configuring Java 25..."

JAVA25="/usr/lib/jvm/java-25-openjdk-amd64/bin/java"


if [[ ! -x "${JAVA25}" ]]; then

    error "Java 25 was not found at:"
    echo "${JAVA25}"

    echo
    echo "Installed Java versions:"
    update-alternatives --list java 2>/dev/null || true

    exit 1

fi


# Make Java 25 the default Java command.
sudo update-alternatives --set java "${JAVA25}"


# ============================================================
# VERIFY JAVA
# ============================================================

echo
info "Checking Java version..."

JAVA_VERSION="$("${JAVA25}" -version 2>&1 | head -n 1)"

echo "${JAVA_VERSION}"


JAVA_MAJOR="$(
    "${JAVA25}" -version 2>&1 |
    awk -F '"' '/version/ {print $2}' |
    cut -d. -f1
)"


if [[ "${JAVA_MAJOR}" -lt 25 ]]; then

    error "Java 25 or newer is required."

    exit 1

fi


info "Java 25 detected successfully."


# ============================================================
# CREATE MINECRAFT DIRECTORY
# ============================================================

echo
info "Creating Minecraft directory..."

mkdir -p "${MC_DIR}"


# ============================================================
# GET LATEST FABRIC LOADER
# ============================================================

info "Getting Fabric Loader version..."

FABRIC_LOADER="$(
    curl -fsSL \
    "https://meta.fabricmc.net/v2/versions/loader/${MC_VERSION}" |
    jq -r 'map(select(.loader.stable == true))[0].loader.version'
)"


if [[ -z "${FABRIC_LOADER}" || "${FABRIC_LOADER}" == "null" ]]; then

    error "Could not find a stable Fabric Loader for Minecraft ${MC_VERSION}."

    exit 1

fi


info "Fabric Loader: ${FABRIC_LOADER}"


# ============================================================
# GET LATEST FABRIC INSTALLER
# ============================================================

info "Getting Fabric installer version..."

FABRIC_INSTALLER="$(
    curl -fsSL \
    "https://meta.fabricmc.net/v2/versions/installer" |
    jq -r 'map(select(.stable == true))[0].version'
)"


if [[ -z "${FABRIC_INSTALLER}" || "${FABRIC_INSTALLER}" == "null" ]]; then

    error "Could not find a stable Fabric installer."

    exit 1

fi


info "Fabric Installer: ${FABRIC_INSTALLER}"


# ============================================================
# DOWNLOAD FABRIC SERVER LAUNCHER
# ============================================================

FABRIC_URL="https://meta.fabricmc.net/v2/versions/loader/${MC_VERSION}/${FABRIC_LOADER}/${FABRIC_INSTALLER}/server/jar"


echo
info "Downloading Fabric server launcher..."

wget \
    --show-progress \
    -O "${FABRIC_JAR}" \
    "${FABRIC_URL}"


if [[ ! -f "${FABRIC_JAR}" ]]; then

    error "Fabric server launcher download failed."

    exit 1

fi


# ============================================================
# CREATE SERVER JAR
# ============================================================

# The Fabric executable server launcher will download
# the required Minecraft server files when first started.

info "Fabric server launcher downloaded."


# ============================================================
# EULA
# ============================================================

echo
warn "Minecraft EULA"

echo
echo "This installer will create eula.txt with:"
echo
echo "  eula=true"
echo
echo "Only continue if you agree to the Minecraft EULA."
echo

read -r -p "Do you agree to the Minecraft EULA? [y/N]: " EULA_REPLY

if [[ ! "${EULA_REPLY}" =~ ^[Yy]$ ]]; then

    error "EULA not accepted."

    echo
    echo "The installation has been stopped."

    exit 1

fi


echo "eula=true" > "${MC_DIR}/eula.txt"


# ============================================================
# CREATE SYSTEMD SERVICE
# ============================================================

echo
info "Creating systemd service..."

sudo tee "${SERVICE_FILE}" > /dev/null <<EOF
[Unit]
Description=Minecraft Fabric ${MC_VERSION} Server
Documentation=https://fabricmc.net/
After=network-online.target
Wants=network-online.target

[Service]

Type=simple

User=${USER}
Group=${USER}

WorkingDirectory=${MC_DIR}

ExecStart=${JAVA25} -Xms${MC_MIN_RAM} -Xmx${MC_MAX_RAM} -jar ${FABRIC_JAR} nogui

Restart=on-failure
RestartSec=10

TimeoutStopSec=60

Environment="HOME=${HOME}"

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF


# ============================================================
# SYSTEMD RELOAD
# ============================================================

echo
info "Reloading systemd..."

sudo systemctl daemon-reload


# ============================================================
# ENABLE SERVICE
# ============================================================

info "Enabling Minecraft service..."

sudo systemctl enable "${SERVICE_NAME}.service"


# ============================================================
# START SERVER
# ============================================================

echo
info "Starting Minecraft server..."

sudo systemctl restart "${SERVICE_NAME}.service"


# ============================================================
# LOADING BAR
# ============================================================

echo
loading_bar "Starting Minecraft server"


# ============================================================
# CHECK STATUS
# ============================================================

echo
info "Checking Minecraft service..."

sleep 3

if sudo systemctl is-active --quiet "${SERVICE_NAME}.service"; then

    echo
    echo -e "${GREEN}==============================================${RESET}"
    echo -e "${GREEN}       MINECRAFT SERVER IS RUNNING!          ${RESET}"
    echo -e "${GREEN}==============================================${RESET}"
    echo

    echo "Minecraft version : ${MC_VERSION}"
    echo "Fabric Loader     : ${FABRIC_LOADER}"
    echo "Java              : 25"
    echo "Server directory  : ${MC_DIR}"
    echo "Fabric launcher   : ${FABRIC_JAR}"
    echo "RAM               : ${MC_MIN_RAM} - ${MC_MAX_RAM}"
    echo

    echo "Systemd service:"
    echo "  ${SERVICE_NAME}.service"
    echo

    echo "Useful commands:"
    echo
    echo "  sudo systemctl status minecraft"
    echo "  sudo systemctl restart minecraft"
    echo "  sudo systemctl stop minecraft"
    echo "  sudo systemctl start minecraft"
    echo "  sudo journalctl -u minecraft -f"
    echo

else

    echo
    error "Minecraft failed to start."
    echo

    echo "Systemd status:"
    sudo systemctl status "${SERVICE_NAME}.service" --no-pager || true

    echo
    echo "Recent Minecraft logs:"
    sudo journalctl -u "${SERVICE_NAME}.service" -n 50 --no-pager || true

    exit 1

fi


# ============================================================
# FINISHED
# ============================================================

echo
echo -e "${GREEN}==============================================${RESET}"
echo -e "${GREEN}          INSTALLATION COMPLETE              ${RESET}"
echo -e "${GREEN}==============================================${RESET}"
echo

echo "Minecraft ${MC_VERSION} + Fabric is installed."
echo "Java 25 is configured."
echo "Systemd is configured."
echo "The server is enabled at boot."
echo "The server is currently running."

echo
echo "Server files:"
echo "  ${MC_DIR}"

echo
echo "To watch the server:"
echo
echo "  sudo journalctl -u minecraft -f"

echo
echo "Done!"
```
