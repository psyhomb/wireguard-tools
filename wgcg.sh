#!/bin/bash
# Author: Milos Buncic
# Date: 2019/09/25
# Description: Wireguard config generator

### Global variables
# Default options
# Server name (should be same as Wireguard interface name)
SERVER_NAME=${WGCG_SERVER_NAME:-"wg0"}
# VPN (WG) IP private address
SERVER_WG_IP=${WGCG_SERVER_WG_IP:-"10.0.0.1"}
# Static server port
SERVER_PORT=${WGCG_SERVER_PORT:-"52001"}
# Server's public IP or FQDN
# To discover server's public IP use: curl -sSL https://ifconfig.co
SERVER_PUBLIC_IP=${WGCG_SERVER_PUBLIC_IP:-"wg0.example.com"}

# Dependencies required by the script
DEPS=(
  "wg"
  "qrencode"
)
# Working directory where all generated files will be stored
WORKING_DIR="${HOME}/wireguard"

# Text colors
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
NONE="\033[0m"

# Check if all dependencies are installed
for DEP in ${DEPS[@]}; do
  if ! which ${DEP} &> /dev/null; then
    echo -e "${RED}ERROR${NONE}: ${BLUE}${DEP}${NONE} tool isn't installed"
    RET=1
  fi
done
[[ ${RET} -eq 1 ]] && exit 1

# Create working directory if doesn't exist
if [[ ! -d ${WORKING_DIR} ]]; then
  mkdir -p ${WORKING_DIR}
fi


help() {
  echo -e "${BLUE}Usage${NONE}:"
  echo -e "  ${GREEN}$(basename ${0})${NONE} options"
  echo
  echo -e "${BLUE}Options${NONE}:"
  echo -e "  ${GREEN}-s${NONE}|${GREEN}--server-config${NONE} [server_name] [server_wg_ip] [server_port]"
  echo -e "  ${GREEN}-c${NONE}|${GREEN}--client-config${NONE} client_name client_wg_ip [server_name] [server_port] [server_public_ip]"
  echo -e "  ${GREEN}-q${NONE}|${GREEN}--gen-qr-code${NONE} client_name"
  echo -e "  ${GREEN}-S${NONE}|${GREEN}--sync${NONE} [server_name] [server_public_ip]"
  echo -e "  ${GREEN}-h${NONE}|${GREEN}--help${NONE}"
  echo
  echo -e "${BLUE}Current default options${NONE}:"
  echo -e "  export WGCG_SERVER_NAME=${GREEN}\"${SERVER_NAME}\"${NONE}"
  echo -e "  export WGCG_SERVER_WG_IP=${GREEN}\"${SERVER_WG_IP}\"${NONE}"
  echo -e "  export WGCG_SERVER_PORT=${GREEN}\"${SERVER_PORT}\"${NONE}"
  echo -e "  export WGCG_SERVER_PUBLIC_IP=${GREEN}\"${SERVER_PUBLIC_IP}\"${NONE}"
}


# Generate preshared, server and client keys
gen_keys() {
  local name_prefix="${1}"

  local private_key="${WORKING_DIR}/${name_prefix}-private.key"
  local public_key="${WORKING_DIR}/${name_prefix}-public.key"
  local preshared_key="${WORKING_DIR}/preshared.key"

  wg genkey | tee ${private_key} | wg pubkey > ${public_key}
  [[ ! -f ${preshared_key} ]] && wg genpsk > ${preshared_key} 2> /dev/null
  chmod 600 ${private_key} ${preshared_key}
}


# Generate server configuration file
gen_server_config() {
  local server_name="${1}"
  local server_wg_ip="${2}"
  local server_port="${3}"

  local server_private_key="${WORKING_DIR}/server-${server_name}-private.key"
  local server_config="${WORKING_DIR}/server-${server_name}.conf"
  local server_generated="${WORKING_DIR}/.server-${server_name}.generated"

  if [[ -f ${server_private_key} ]]; then
    echo -e "${YELLOW}WARNING${NONE}: This is destructive operation, also it will require regeneration of all client configs!"
    echo -ne "Server config and keys are already generated, do you want to overwrite it? (${GREEN}yes${NONE}/${RED}no${NONE}): "
    read answer

    [[ ${answer} != "yes" ]] && exit 1
  fi

  gen_keys server-${server_name}

  cat > ${server_config} <<EOF && chmod 600 ${server_config}
[Interface]
Address = ${server_wg_ip}/24
ListenPort = ${server_port}
PrivateKey = $(head -1 ${server_private_key})
PostUp = /usr/local/bin/wgfw.sh add
PostDown = /usr/local/bin/wgfw.sh del
EOF

  touch ${server_generated}
  echo -e "${GREEN}INFO${NONE}: Server config ${BLUE}${server_config}${NONE} has been generated successfully!"
}


# Generate client and update server configuration file
gen_client_config() {
  local client_name="${1}"
  local client_wg_ip="${2}"
  local server_name="${3}"
  local server_port="${4}"
  local server_public_ip="${5}"

  local preshared_key="${WORKING_DIR}/preshared.key"
  local client_private_key="${WORKING_DIR}/client-${client_name}-private.key"
  local client_public_key="${WORKING_DIR}/client-${client_name}-public.key"
  local client_config="${WORKING_DIR}/client-${client_name}.conf"
  local server_public_key="${WORKING_DIR}/server-${server_name}-public.key"
  local server_config="${WORKING_DIR}/server-${server_name}.conf"
  local server_generated="${WORKING_DIR}/.server-${server_name}.generated"

  if [[ -z ${client_name} ]] || [[ -z ${client_wg_ip} ]]; then
    help
    exit 1
  fi

  if [[ ! -f ${server_generated} ]]; then
    echo -e "${GREEN}INFO${NONE}: Server config and keys could not be found, please use ${GREEN}--server-config${NONE} first"
    exit 1
  fi

  if [[ -f ${client_private_key} ]]; then
    echo -e "${YELLOW}WARNING${NONE}: This is destructive operation!"
    echo -ne "Client config and keys are already generated, do you want to overwrite it? (${GREEN}yes${NONE}/${RED}no${NONE}): "
    read answer

    [[ ${answer} != "yes" ]] && exit 1

    # Delete Peer block if client_name already exist
    sed -i.backup "/### ${client_name} - START/,/### ${client_name} - END/d" ${server_config}
    # Delete all blank lines at end of file
    sed -i.backup -e :a -e '/^\n*$/{$d;N;ba' -e '}' ${server_config}
    # Suppress repeated empty output lines
    cat -s ${server_config} > ${server_config}.backup
    mv ${server_config}.backup ${server_config}
  fi

  gen_keys client-${client_name}

  cat > ${client_config} <<EOF && chmod 600 ${client_config}
[Interface]
Address = ${client_wg_ip}/24
PrivateKey = $(head -1 ${client_private_key})
DNS = 1.1.1.1, 1.0.0.1

[Peer]
PublicKey = $(head -1 ${server_public_key})
PresharedKey = $(head -1 ${preshared_key})
AllowedIPs = 0.0.0.0/0
Endpoint = ${server_public_ip}:${server_port}
PersistentKeepalive = 25
EOF

  cat >> ${server_config} <<EOF

### ${client_name} - START
[Peer]
PublicKey = $(head -1 ${client_public_key})
PresharedKey = $(head -1 ${preshared_key})
AllowedIPs = ${client_wg_ip}/32
PersistentKeepalive = 25
### ${client_name} - END
EOF

  echo -e "${GREEN}INFO${NONE}: Client config ${BLUE}${client_config}${NONE} has been generated successfully!"
}


# Generate QR code
gen_qr() {
  local config_name="${1}"
  local config_path="${WORKING_DIR}/client-${config_name}.conf"

  if [[ ! -f ${config_path} ]]; then
    echo -e "${RED}ERROR${NONE}: Error while generating QR code, config file ${BLUE}${config_path}${NONE} does not exist"
    exit 1
  fi

  cat ${config_path} | qrencode -o ${config_path}.png && chmod 600 ${config_path}.png
  echo -e "${GREEN}INFO${NONE}: QR file ${BLUE}${config_path}.png${NONE} has been generated successfully!"
}


# Sync configuration with server
wg_sync() {
  local server_name="${1}"
  local server_public_ip="${2}"

  local server_config="${WORKING_DIR}/server-${server_name}.conf"

  ssh root@${server_public_ip} "which wg-quick &> /dev/null"
  if [[ ${?} -ne 0 ]]; then
    echo -e "${YELLOW}WARNING${NONE}: It looks like ${GREEN}wireguard-tools${NONE} package isn't installed on the server, aborting..."
    exit 1
  fi

  rsync -q --chmod 600 ${server_config} root@${server_public_ip}:/etc/wireguard/wg0.conf
  if [[ ${?} -eq 0 ]]; then
    echo -e "${GREEN}INFO${NONE}: Server configuration ${server_config} successfully copied over to the server ${server_public_ip}"
    echo -ne "Do you want to restart wg-quick service? (${GREEN}yes${NONE}/${RED}no${NONE}): "
    read answer

    if [[ ${answer} == "yes" ]]; then
      ssh root@${server_public_ip} "
        systemctl is-active wg-quick@wg0.service &> /dev/null && systemctl restart wg-quick@wg0.service
      "
    fi
  else
    echo -e "${RED}ERROR${NONE}: Copying configuration ${server_config} to server ${server_public_ip} has failed!"
    exit 1
  fi
}


case ${1} in
  '-s'|'--server-config')
    shift
    # server_name, server_wg_ip, server_port
    gen_server_config ${1:-${SERVER_NAME}} ${2:-${SERVER_WG_IP}} ${3:-${SERVER_PORT}}
  ;;
  '-c'|'--client-config')
    shift
    # client_name, client_wg_ip, server_name, server_port, server_public_ip
    gen_client_config ${1:-''} ${2:-''} ${3:-${SERVER_NAME}} ${4:-${SERVER_PORT}} ${5:-${SERVER_PUBLIC_IP}}
    # client_name
    gen_qr ${1}
  ;;
  '-q'|'--gen-qr-code')
    shift
    # client_name
    gen_qr ${1}
  ;;
  '-S'|'--sync')
    shift
    # server_name, server_public_ip
    wg_sync ${1:-${SERVER_NAME}} ${2:-${SERVER_PUBLIC_IP}}
  ;;
  *)
    help
esac
