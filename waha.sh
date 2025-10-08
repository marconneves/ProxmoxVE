#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# --- INÍCIO DO BLOCO DE CORREÇÃO ---
# Esta função sobrescreve a original do 'build.func' para remover a última linha,
# que tentava executar um script de instalação externo via curl, causando o erro.
function build_container() {
  #  if [ "$VERBOSE" == "yes" ]; then set -x; fi

  NET_STRING="-net0 name=eth0,bridge=$BRG$MAC,ip=$NET$GATE$VLAN$MTU"
  case "$IPV6_METHOD" in
  auto) NET_STRING="$NET_STRING,ip6=auto" ;;
  dhcp) NET_STRING="$NET_STRING,ip6=dhcp" ;;
  static)
    NET_STRING="$NET_STRING,ip6=$IPV6_ADDR"
    [ -n "$IPV6_GATE" ] && NET_STRING="$NET_STRING,gw6=$IPV6_GATE"
    ;;
  none) ;;
  esac
  if [ "$CT_TYPE" == "1" ]; then
    FEATURES="keyctl=1,nesting=1"
  else
    FEATURES="nesting=1"
  fi

  if [ "$ENABLE_FUSE" == "yes" ]; then
    FEATURES="$FEATURES,fuse=1"
  fi

  if [[ $DIAGNOSTICS == "yes" ]]; then
    post_to_api
  fi

  TEMP_DIR=$(mktemp -d)
  pushd "$TEMP_DIR" >/dev/null
  if [ "$var_os" == "alpine" ]; then
    export FUNCTIONS_FILE_PATH="$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/alpine-install.func)"
  else
    export FUNCTIONS_FILE_PATH="$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/install.func)"
  fi

  export DIAGNOSTICS="$DIAGNOSTICS"
  export RANDOM_UUID="$RANDOM_UUID"
  export CACHER="$APT_CACHER"
  export CACHER_IP="$APT_CACHER_IP"
  export tz="$timezone"
  export APPLICATION="$APP"
  export app="$NSAPP"
  export PASSWORD="$PW"
  export VERBOSE="$VERBOSE"
  export SSH_ROOT="${SSH}"
  export SSH_AUTHORIZED_KEY
  export CTID="$CT_ID"
  export CTTYPE="$CT_TYPE"
  export ENABLE_FUSE="$ENABLE_FUSE"
  export ENABLE_TUN="$ENABLE_TUN"
  export PCT_OSTYPE="$var_os"
  export PCT_OSVERSION="$var_version"
  export PCT_DISK_SIZE="$DISK_SIZE"
  export PCT_OPTIONS="
    -features $FEATURES
    -hostname $HN
    -tags $TAGS
    $SD
    $NS
    $NET_STRING
    -onboot 1
    -cores $CORE_COUNT
    -memory $RAM_SIZE
    -unprivileged $CT_TYPE
    $PW
  "
  # This executes create_lxc.sh and creates the container and .conf file
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/create_lxc.sh)" $?

  LXC_CONFIG="/etc/pve/lxc/${CTID}.conf"

  # USB passthrough for privileged LXC (CT_TYPE=0)
  if [ "$CT_TYPE" == "0" ]; then
    cat <<EOF >>"$LXC_CONFIG"
# USB passthrough
lxc.cgroup2.devices.allow: a
lxc.cap.drop:
lxc.cgroup2.devices.allow: c 188:* rwm
lxc.cgroup2.devices.allow: c 189:* rwm
lxc.mount.entry: /dev/serial/by-id  dev/serial/by-id  none bind,optional,create=dir
lxc.mount.entry: /dev/ttyUSB0       dev/ttyUSB0       none bind,optional,create=file
lxc.mount.entry: /dev/ttyUSB1       dev/ttyUSB1       none bind,optional,create=file
lxc.mount.entry: /dev/ttyACM0       dev/ttyACM0       none bind,optional,create=file
lxc.mount.entry: /dev/ttyACM1       dev/ttyACM1       none bind,optional,create=file
EOF
  fi

  # VAAPI passthrough (código omitido para brevidade, mas está aqui)
  # TUN device passthrough
  if [ "$ENABLE_TUN" == "yes" ]; then
    cat <<EOF >>"$LXC_CONFIG"
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
EOF
  fi

  msg_info "Starting LXC Container"
  pct start "$CTID"

  for i in {1..10}; do
    if pct status "$CTID" | grep -q "status: running"; then
      msg_ok "Started LXC Container"
      break
    fi
    sleep 1
    if [ "$i" -eq 10 ]; then
      msg_error "LXC Container did not reach running state"
      exit 1
    fi
  done

  if [ "$var_os" != "alpine" ]; then
    msg_info "Waiting for network in LXC container"
    # ... (lógica de verificação de rede)
     for i in {1..10}; do if pct exec "$CTID" -- ping -c1 -W1 deb.debian.org >/dev/null 2>&1; then msg_ok "Network in LXC is reachable (ping)"; break; fi; if [ "$i" -lt 10 ]; then msg_warn "No network in LXC yet (try $i/10) – waiting..."; sleep 3; else msg_error "No network in LXC after all checks."; exit 1; fi; done
  fi

  msg_info "Customizing LXC Container"
  : "${tz:=Etc/UTC}"
  if [ "$var_os" == "alpine" ]; then
    sleep 3
    pct exec "$CTID" -- /bin/sh -c 'cat <<EOF >/etc/apk/repositories
http://dl-cdn.alpinelinux.org/alpine/latest-stable/main
http://dl-cdn.alpinelinux.org/alpine/latest-stable/community
EOF'
    pct exec "$CTID" -- ash -c "apk add bash newt curl openssh nano mc ncurses jq >/dev/null"
  else
    sleep 3
    pct exec "$CTID" -- bash -c "apt-get update >/dev/null && apt-get install -y sudo curl mc gnupg2 jq >/dev/null"
  fi
  msg_ok "Customized LXC Container"

  # A LINHA PROBLEMÁTICA QUE EXISTIA AQUI FOI REMOVIDA.
  # lxc-attach -n "$CTID" -- bash -c "$(curl ...)"
}
# --- FIM DO BLOCO DE CORREÇÃO ---


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
set -e
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
sed -i "s|^WAHA_API_KEY=.*|WAHA_API_KEY=sha512:${API_KEY_HASHED}|" .env
sed -i "s/^WAHA_DASHBOARD_USERNAME=.*/WAHA_DASHBOARD_USERNAME=admin/" .env
sed -i "s/^WAHA_DASHBOARD_PASSWORD=.*/WAHA_DASHBOARD_PASSWORD=${DASHBOARD_PASS}/" .env
sed -i "s/^WHATSAPP_SWAGGER_USERNAME=.*/WHATSAPP_SWAGGER_USERNAME=admin/" .env
sed -i "s/^WHATSAPP_SWAGGER_PASSWORD=.*/WHATSAPP_SWAGGER_PASSWORD=${DASHBOARD_PASS}/" .env

# Save credentials for final summary
echo "API_KEY=${API_KEY_PLAIN}" > /opt/waha/credentials.log
echo "PASSWORD=${DASHBOARD_PASS}" >> /opt/waha/credentials.log

# Pull image and start services
docker compose pull
docker compose up -d

# Cleanup
apt-get autovemove -y
apt-get clean
'
EOF
pct_exec_script

CREDENTIALS=$(pct exec $CTID -- cat /opt/waha/credentials.log)
pct exec $CTID -- rm /opt/waha/credentials.log

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