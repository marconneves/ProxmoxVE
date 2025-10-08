#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT
# Adapted for WAHA by Gemini
# Source: https://waha.devlike.pro/

APP="WAHA"
var_tags="${var_tags:-automation,messaging}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /opt/waha/docker-compose.yaml ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  UPD=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "WAHA Maintenance" --radiolist --cancel-button Exit-Script "Spacebar = Select" 12 60 4 \
    "1" "Update WAHA to latest version" ON \
    "2" "Restart WAHA services" OFF \
    "3" "View WAHA real-time logs" OFF \
    "4" "Remove unused Docker images" OFF \
    3>&1 1>&2 2>&3)

  if [ "$UPD" == "1" ]; then
    msg_info "Updating ${APP} to the latest version..."
    ( cd /opt/waha && docker compose pull && docker compose up -d )
    msg_ok "Updated Successfully"
    exit
  fi
  if [ "$UPD" == "2" ]; then
    msg_info "Restarting ${APP} services..."
    ( cd /opt/waha && docker compose restart )
    msg_ok "Restarted Successfully"
    exit
  fi
  if [ "$UPD" == "3" ]; then
    msg_info "Displaying real-time logs... (Press Ctrl+C to exit)"
    echo -e "\n"
    docker compose -f /opt/waha/docker-compose.yaml logs -f
    exit
  fi
  if [ "$UPD" == "4" ]; then
    msg_info "Removing all unused Docker images..."
    docker image prune -af
    msg_ok "Removed all unused images"
    exit
  fi
}

start
build_container
description

msg_info "Setting up Container..."
cat <<'EOF' >$VMLOG
LXC_INSTALL='
# Install dependencies
apt-get update
apt-get install -y curl wget uuid-runtime gnupg

# Install Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Setup WAHA
mkdir -p /opt/waha
cd /opt/waha
wget -qO .env https://raw.githubusercontent.com/devlikeapro/waha/refs/heads/core/.env.example
wget -qO docker-compose.yaml https://raw.githubusercontent.com/devlikeapro/waha/refs/heads/core/docker-compose.yaml

# Generate secure credentials
API_KEY_PLAIN=$(uuidgen | tr -d "-")
API_KEY_HASHED=$(echo -n "$API_KEY_PLAIN" | sha512sum | head -c 128)
DASHBOARD_PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)

# Update .env file
sed -i "s|WAHA_API_KEY=sha512:{SHA512_HEX_OF_YOUR_API_KEY_HERE}|WAHA_API_KEY=sha512:${API_KEY_HASHED}|" .env
sed -i "s/WAHA_DASHBOARD_USERNAME=admin/WAHA_DASHBOARD_USERNAME=admin/" .env
sed -i "s/WAHA_DASHBOARD_PASSWORD=admin/WAHA_DASHBOARD_PASSWORD=${DASHBOARD_PASS}/" .env
sed -i "s/WHATSAPP_SWAGGER_USERNAME=admin/WHATSAPP_SWAGGER_USERNAME=admin/" .env
sed -i "s/WHATSAPP_SWAGGER_PASSWORD=admin/WHATSAPP_SWAGGER_PASSWORD=${DASHBOARD_PASS}/" .env

# Save credentials for final summary
echo "API_KEY=${API_KEY_PLAIN}" > /opt/waha/credentials.log
echo "PASSWORD=${DASHBOARD_PASS}" >> /opt/waha/credentials.log

# Pull image and start services
docker compose pull
docker compose up -d

# Cleanup
apt-get autoremove -y
apt-get clean
'
EOF
pct_exec_script

CREDENTIALS=$(pct exec $CTID -- cat /opt/waha/credentials.log)
API_KEY=$(echo "$CREDENTIALS" | grep "API_KEY" | cut -d'=' -f2)
PASSWORD=$(echo "$CREDENTIALS" | grep "PASSWORD" | cut -d'=' -f2)

msg_ok "Completed Successfully!\n"
echo -e "${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "\n${YW}--- Your WAHA Credentials (SAVE THESE!) ---${CL}"
echo -e "Dashboard / Swagger User: ${BL}admin${CL}"
echo -e "Dashboard / Swagger Pass: ${BL}${PASSWORD}${CL}"
echo -e "X-Api-Key Header:         ${BL}${API_KEY}${CL}"
echo -e "\n${YW}Access WAHA using the following URL:${CL}"
echo -e "${BGN}http://${IP}:3000${CL}"

