#!/bin/bash
# Author: Milos Buncic
# Date: 2019/09/25
# Description: Wireguard config generator

### Global variables
# Default options
# Specify any server name you like
SERVER_NAME=${SERVER_NAME:-"wg0"}
# VPN (WG) IP private address
SERVER_WG_IP=${SERVER_WG_IP:-"10.0.0.1"}
# Static server port
SERVER_PORT=${SERVER_PORT:-"52001"}
# Server's public IP or FQDN
# To discover server's public IP use: curl -sSL https://ifconfig.co
SERVER_PUBLIC_IP=${SERVER_PUBLIC_IP:-"wg0.example.com"}

# Dependencies required by the script
DEPS=(
  "wg"
  "qrencode"
)
# Working directory where all generated files will be stored
WORKING_DIR="${HOME}/wireguard"

# Check if all dependencies are installed
for DEP in ${DEPS[@]}; do
  if ! which ${DEP} &> /dev/null; then
    echo "ERROR: ${DEP} tool isn't installed"
    RET=1
  fi
done
[[ ${RET} -eq 1 ]] && exit 1

# Create working directory if doesn't exist
if [[ ! -d ${WORKING_DIR} ]]; then
  mkdir -p ${WORKING_DIR}
fi


help() {
  echo "Usage: $(basename ${0}) options"
  echo
  echo "Options:"
  echo "  -s|--server-config [server_name] [server_wg_ip] [server_port]"
  echo "  -c|--client-config client_name client_wg_ip [server_name] [server_port] [server_public_ip]"
  echo "  -q|--gen-qr-code client_name"
}


# Generate preshared, server and client keys
gen_keys() {
  local name_prefix="${1}"

  wg genkey | tee ${WORKING_DIR}/${name_prefix}-private.key | wg pubkey > ${WORKING_DIR}/${name_prefix}-public.key
  [[ ! -f ${WORKING_DIR}/preshared.key ]] && wg genpsk > ${WORKING_DIR}/preshared.key 2> /dev/null
  chmod 600 ${WORKING_DIR}/{${name_prefix}-private.key,preshared.key}
}


# Generate server configuration file
gen_server_config() {
  local server_name="${1}"
  local server_wg_ip="${2}"
  local server_port="${3}"

  if [[ -f ${WORKING_DIR}/server-${server_name}-private.key ]]; then
    echo -n "Server config and keys are already generated, do you want to override it (yes/no): "
    read override

    [[ ${override} != "yes" ]] && exit 1
  fi

  gen_keys server-${server_name}

  cat > ${WORKING_DIR}/server-${server_name}.conf <<EOF && chmod 600 ${WORKING_DIR}/server-${server_name}.conf
[Interface]
Address = ${server_wg_ip}/24
ListenPort = ${server_port}
PrivateKey = $(head -1 ${WORKING_DIR}/server-${server_name}-private.key)
PostUp = /usr/local/bin/wgfw.sh add
PostDown = /usr/local/bin/wgfw.sh del
EOF

  touch ${WORKING_DIR}/.server-${server_name}.generated
  echo "Server config ${WORKING_DIR}/server-${server_name}.conf has been generated successfully!"
}


# Generate client and update server configuration file
gen_client_config() {
  local client_name="${1}"
  local client_wg_ip="${2}"
  local server_name="${3}"
  local server_port="${4}"
  local server_public_ip="${5}"

  if [[ -z ${client_name} ]] || [[ -z ${client_wg_ip} ]]; then
    help
    exit 1
  fi

  if [[ ! -f ${WORKING_DIR}/.server-${server_name}.generated ]]; then
    echo "Server config and keys could not be found, please use --server-config first"
    exit 1
  fi

  if [[ -f ${WORKING_DIR}/client-${client_name}-private.key ]]; then
    echo -n "Client config and keys are already generated, do you want to override it (yes/no): "
    read override

    [[ ${override} != "yes" ]] && exit 1

    # Delete Peer block if client_name already exist
    sed -i.backup "/### ${client_name} - START/,/### ${client_name} - END/d" ${WORKING_DIR}/server-${server_name}.conf
    # Delete all blank lines at end of file
    sed -i.backup -e :a -e '/^\n*$/{$d;N;ba' -e '}' ${WORKING_DIR}/server-${server_name}.conf
    # Suppress repeated empty output lines
    cat -s ${WORKING_DIR}/server-${server_name}.conf > ${WORKING_DIR}/server-${server_name}.conf.backup
    mv ${WORKING_DIR}/server-${server_name}.conf{.backup,}
  fi

  gen_keys client-${client_name}

  cat > ${WORKING_DIR}/client-${client_name}.conf <<EOF && chmod 600 ${WORKING_DIR}/client-${client_name}.conf
[Interface]
Address = ${client_wg_ip}/24
PrivateKey = $(head -1 ${WORKING_DIR}/client-${client_name}-private.key)
DNS = 1.1.1.1, 1.0.0.1

[Peer]
PublicKey = $(head -1 ${WORKING_DIR}/server-${server_name}-public.key)
PresharedKey = $(head -1 ${WORKING_DIR}/preshared.key)
AllowedIPs = 0.0.0.0/0
Endpoint = ${server_public_ip}:${server_port}
PersistentKeepalive = 25
EOF

  cat >> ${WORKING_DIR}/server-${server_name}.conf <<EOF

### ${client_name} - START
[Peer]
PublicKey = $(head -1 ${WORKING_DIR}/client-${client_name}-public.key)
PresharedKey = $(head -1 ${WORKING_DIR}/preshared.key)
AllowedIPs = ${client_wg_ip}/32
PersistentKeepalive = 25
### ${client_name} - END
EOF

  echo "Client config ${WORKING_DIR}/client-${client_name}.conf has been generated successfully!"
}


# Generate QR code
gen_qr() {
  local config_name="${1}"
  local config_path="${WORKING_DIR}/client-${config_name}.conf"

  if [[ ! -f ${config_path} ]]; then
    echo "ERROR: Error while generating QR code, config file ${config_path} does not exist"
    exit 1
  fi

  cat ${config_path} | qrencode -o ${config_path}.png && chmod 600 ${config_path}.png
  echo "QR file ${config_path}.png has been generated successfully!"
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
  *)
    help
esac
