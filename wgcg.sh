#!/bin/bash
# Author: Milos Buncic
# Date: 2019/09/25
# Description: Wireguard config generator

### Global variables
# Default options
# Server name (wireguard interface name e.g. wg0 || wg1 || wg2)
SERVER_NAME=${WGCG_SERVER_NAME:-"wg0"}
# VPN (WG) IP private address
SERVER_WG_IP=${WGCG_SERVER_WG_IP:-"10.0.0.1"}
# Static server port
SERVER_PORT=${WGCG_SERVER_PORT:-"52001"}
# Server's public IP or FQDN
# To discover server's public IP use: curl -sSL https://ifconfig.co
SERVER_PUBLIC_IP=${WGCG_SERVER_PUBLIC_IP:-"wg.example.com"}
# Working directory where all generated files will be stored
WORKING_DIR=${WGCG_WORKING_DIR:-"${HOME}/wireguard"}


# Text colors
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
NONE="\033[0m"

# Dependencies required by the script
DEPS=(
  "wg"
  "qrencode"
  "rsync"
)

# Check if all dependencies are installed
for DEP in ${DEPS[@]}; do
  if ! which ${DEP} &> /dev/null; then
    echo -e "${RED}ERROR${NONE}: ${BLUE}${DEP}${NONE} tool isn't installed!"
    STAT=1
  fi
done
[[ ${STAT} -eq 1 ]] && exit 1


help() {
  echo -e "${BLUE}Usage${NONE}:"
  echo -e "  ${GREEN}$(basename ${0})${NONE} options"
  echo
  echo -e "${BLUE}Options${NONE}:"
  echo -e "  ${GREEN}-s${NONE}|${GREEN}--add-server-config${NONE} [server_name] [server_wg_ip] [server_port]"
  echo -e "  ${GREEN}-c${NONE}|${GREEN}--add-client-config${NONE} client_name client_wg_ip [server_name] [server_port] [server_public_ip]"
  echo -e "  ${GREEN}-B${NONE}|${GREEN}--add-clients-batch${NONE} filename.csv"
  echo -e "  ${GREEN}-r${NONE}|${GREEN}--rm-client-config${NONE} client_name [server_name]"
  echo -e "  ${GREEN}-q${NONE}|${GREEN}--gen-qr-code${NONE} client_name"
  echo -e "  ${GREEN}-l${NONE}|${GREEN}--list-used-ips${NONE}"
  echo -e "  ${GREEN}-S${NONE}|${GREEN}--sync${NONE} [server_name] [server_public_ip]"
  echo -e "  ${GREEN}-h${NONE}|${GREEN}--help${NONE}"
  echo
  echo -e "${BLUE}Current default options${NONE}:"
  echo -e "  WGCG_SERVER_NAME=${GREEN}\"${SERVER_NAME}\"${NONE}"
  echo -e "  WGCG_SERVER_WG_IP=${GREEN}\"${SERVER_WG_IP}\"${NONE}"
  echo -e "  WGCG_SERVER_PORT=${GREEN}\"${SERVER_PORT}\"${NONE}"
  echo -e "  WGCG_SERVER_PUBLIC_IP=${GREEN}\"${SERVER_PUBLIC_IP}\"${NONE}"
  echo -e "  WGCG_WORKING_DIR=${GREEN}\"${WORKING_DIR}\"${NONE}"
}


# Validator for IP addresses and service ports
validator() {
  local mode="${1}"
  local value="${2}"
  local ret regex ip_octets fqdn

  ret=0
  case ${mode} in
    'ipaddress')
      regex='^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'
      ip_address=${value}
      ip_octets=(${value//./ })

      if [[ ${ip_address} =~ ${regex} ]]; then
        for ip_octet in ${ip_octets[@]}; do
          if [[ ${ip_octet} -gt 255 ]]; then
            ret=1
            break
          fi

          if [[ ${#ip_octet} -gt 1 ]] && [[ ${ip_octet:0:1} -eq 0 ]]; then
            ret=1
            break
          fi
        done
      else
        ret=1
      fi
    ;;
    'svcport')
      regex='^[0-9]{1,5}$'
      svc_port=${value}

      if [[ ! ${svc_port} =~ ${regex} ]] || [[ ${svc_port} -gt 65535 ]]; then
        ret=1
      fi
    ;;
    'fqdn')
      regex='(?=^.{4,253}$)(^((?!-)[a-zA-Z0-9-]{0,62}[a-zA-Z0-9]\.)+[a-zA-Z]{2,63}$)'
      fqdn=${value}

      if ! echo ${fqdn} | grep -Pq ${regex}; then
        ret=1
      fi
  esac

  return ${ret}
}


# Remove client configuration file
remove_client_config() {
  local client_name="${1}"
  local server_name="${2}"

  local client_config="${WORKING_DIR}/client-${client_name}.conf"
  local server_config="${WORKING_DIR}/server-${server_name}.conf"

  if [[ -z ${client_name} ]] || [[ -z ${server_name} ]]; then
    help
    exit 1
  fi

  if [[ ! -f ${client_config} ]]; then
    echo -e "${RED}ERROR${NONE}: Client config ${BLUE}${client_config}${NONE} could not be found!"
    exit 1
  fi

  if [[ ! -f ${server_config} ]]; then
    echo -e "${RED}ERROR${NONE}: Server config ${BLUE}${server_config}${NONE} could not be found!"
    exit 1
  fi

  # Delete Peer block if client_name exist
  sed -i.backup "/### ${client_name} - START/,/### ${client_name} - END/d" ${server_config}
  # Delete all empty lines at end of file
  sed -i.backup -e :a -e '/^\n*$/{$d;N;ba' -e '}' ${server_config}
  # Suppress repeated empty output lines
  cat -s ${server_config} > ${server_config}.backup
  mv ${server_config}.backup ${server_config}

  # Delete config and key files
  rm -f ${WORKING_DIR}/client-${client_name}{.conf,.conf.png,-private.key,-public.key}

  echo -e "${GREEN}INFO${NONE}: Client config ${RED}${client_config}${NONE} has been successfully removed!"
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

  [[ ! -d ${WORKING_DIR} ]] && mkdir -p ${WORKING_DIR}

  local server_private_key="${WORKING_DIR}/server-${server_name}-private.key"
  local server_config="${WORKING_DIR}/server-${server_name}.conf"
  local server_generated="${WORKING_DIR}/.server-${server_name}.generated"

  validator ipaddress ${server_wg_ip}
  if [[ ${?} -ne 0 ]]; then
    echo -e "${RED}ERROR${NONE}: ${RED}${server_wg_ip}${NONE} is not valid IP address!"
    exit 1
  fi

  validator svcport ${server_port}
  if [[ ${?} -ne 0 ]]; then
    echo -e "${RED}ERROR${NONE}: ${RED}${server_port}${NONE} is not valid port number!"
    exit 1
  fi

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
SKIP_ANSWER=false
gen_client_config() {
  local client_name="${1}"
  local client_wg_ip="${2}"
  local server_name="${3}"
  local server_port="${4}"
  local server_public_ip="${5}"
  local server_wg_ip client_config_match server_config_match

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
    echo -e "${GREEN}INFO${NONE}: Server config and keys could not be found, please run script with ${GREEN}--server-config${NONE} option first"
    exit 1
  fi

  validator ipaddress ${client_wg_ip}
  if [[ ${?} -ne 0 ]]; then
    echo -e "${RED}ERROR${NONE}: ${RED}${client_wg_ip}${NONE} is not valid IP address!"
    return 1
  fi

  validator svcport ${server_port}
  if [[ ${?} -ne 0 ]]; then
    echo -e "${RED}ERROR${NONE}: ${RED}${server_port}${NONE} is not valid port number!"
    return 1
  fi

  if ! validator ipaddress ${server_public_ip} && ! validator fqdn ${server_public_ip}; then
    echo -e "${RED}ERROR${NONE}: ${RED}${server_public_ip}${NONE} is not valid IP address nor FQDN!"
    return 1
  fi

  server_config_match=$(grep -l "^Address = ${client_wg_ip}" ${server_config})
  if [[ -n ${server_config_match} ]]; then
    echo -e "${RED}ERROR${NONE}: WG private IP address ${RED}${client_wg_ip}${NONE} is used by server => ${BLUE}${server_config_match}${NONE}"
    return 1
  fi

  server_wg_ip=$(awk -F'[ /]' '/^Address =/ {print $(NF-1)}' ${server_config})
  if [[ ${server_wg_ip%.*} != ${client_wg_ip%.*} ]]; then
    echo -e "${RED}ERROR${NONE}: Client private IP address ${RED}${client_wg_ip}${NONE} does not belong to the range: ${GREEN}${server_wg_ip%.*}.1${NONE} - ${GREEN}${server_wg_ip%.*}.254${NONE}"
    return 1
  fi

  if [[ -f ${client_private_key} ]]; then
    if [[ ${SKIP_ANSWER} == false ]]; then
      echo -e "${YELLOW}WARNING${NONE}: This is destructive operation!"
      echo -ne "Config and key files for client ${GREEN}${client_name}${NONE} are already generated, do you want to overwrite it? (${GREEN}yes${NONE}/${RED}no${NONE}): "
      read answer

      [[ ${answer} != "yes" ]] && return 1
    fi

    remove_client_config ${client_name} ${server_name}
  else
    if find ${WORKING_DIR} -maxdepth 1 | egrep -q "client-.*\.conf$"; then
      client_config_match=$(grep -l "^Address = ${client_wg_ip}" ${WORKING_DIR}/client-*.conf)
      if [[ -n ${client_config_match} ]]; then
        echo -e "${RED}ERROR${NONE}: WG private IP address ${RED}${client_wg_ip}${NONE} already in use => ${BLUE}${client_config_match}${NONE}"
        return 1
      fi
    fi
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
    echo -e "${RED}ERROR${NONE}: Error while generating QR code, config file ${BLUE}${config_path}${NONE} does not exist!"
    exit 1
  fi

  cat ${config_path} | qrencode -o ${config_path}.png && chmod 600 ${config_path}.png
  echo -e "${GREEN}INFO${NONE}: QR file ${BLUE}${config_path}.png${NONE} has been generated successfully!"
}


# Generate client configs in batch
gen_client_config_batch() {
  local client_batch_csv_file="${1}"
  local client_name client_wg_ip

  if [[ ! -f ${client_batch_csv_file} ]]; then
    echo -e "${RED}ERROR${NONE}: Client batch file ${BLUE}${client_batch_csv_file}${NONE} does not exist, please create one first!"
    exit 1
  fi

  SKIP_ANSWER=true
  while IFS=',' read client_name client_wg_ip; do
    gen_client_config ${client_name} ${client_wg_ip} ${SERVER_NAME} ${SERVER_PORT} ${SERVER_PUBLIC_IP}
    [[ ${?} -ne 0 ]] && continue
    gen_qr ${client_name}
  done < <(egrep -v '^(#|$)' ${client_batch_csv_file})
}


# List used private IPs
wg_list_used_ips() {
  local ip_client_list

  [[ ! -d ${WORKING_DIR} ]] && exit 0

  for client_config in $(find ${WORKING_DIR} -maxdepth 1 -name "client-*.conf"); do
    ip_client_list="${GREEN}$(awk -F'[ /]' '/^Address =/ {print $(NF-1)}' ${client_config})${NONE} => ${BLUE}${client_config}${NONE}\n${ip_client_list}"
  done

  echo -ne ${ip_client_list} | sort -k1n
}


# Sync configuration with server
wg_sync() {
  local server_name="${1}"
  local server_public_ip="${2}"

  local server_config="${WORKING_DIR}/server-${server_name}.conf"

  if [[ ! -f ${server_config} ]]; then
    echo -e "${RED}ERROR${NONE}: Server config ${BLUE}${server_config}${NONE} does not exist, aborting sync command..."
    exit 1
  fi

  if ! validator ipaddress ${server_public_ip} && ! validator fqdn ${server_public_ip}; then
    echo -e "${RED}ERROR${NONE}: ${RED}${server_public_ip}${NONE} is not valid IP address nor FQDN!"
    exit 1
  fi

  ssh root@${server_public_ip} "which wg-quick &> /dev/null"
  if [[ ${?} -ne 0 ]]; then
    echo -e "${YELLOW}WARNING${NONE}: It looks like ${GREEN}wireguard-tools${NONE} package isn't installed on the server, aborting..."
    exit 1
  fi

  rsync -q --chmod 600 ${server_config} root@${server_public_ip}:/etc/wireguard/${server_name}.conf
  if [[ ${?} -eq 0 ]]; then
    echo -e "${GREEN}INFO${NONE}: Server configuration ${BLUE}${server_config}${NONE} successfully copied over to the server ${BLUE}${server_public_ip}${NONE}"
    echo -ne "Do you want to restart ${GREEN}wg-quick${NONE} service? (${GREEN}yes${NONE}/${RED}no${NONE}): "
    read answer

    if [[ ${answer} == "yes" ]]; then
      ssh root@${server_public_ip} "
        if ! systemctl is-enabled wg-quick@${server_name}.service &> /dev/null; then
          systemctl enable --now wg-quick@${server_name}.service &> /dev/null
          exit 0
        fi
        systemctl is-active wg-quick@${server_name}.service &> /dev/null && systemctl restart wg-quick@${server_name}.service
      "
    fi
  else
    echo -e "${RED}ERROR${NONE}: Copying configuration ${BLUE}${server_config}${NONE} to server ${BLUE}${server_public_ip}${NONE} has failed!"
    exit 1
  fi
}


case ${1} in
  '-s'|'--add-server-config')
    shift
    # server_name, server_wg_ip, server_port
    gen_server_config ${1:-${SERVER_NAME}} ${2:-${SERVER_WG_IP}} ${3:-${SERVER_PORT}}
  ;;
  '-c'|'--add-client-config')
    shift
    # client_name, client_wg_ip, server_name, server_port, server_public_ip
    gen_client_config ${1:-''} ${2:-''} ${3:-${SERVER_NAME}} ${4:-${SERVER_PORT}} ${5:-${SERVER_PUBLIC_IP}}
    [[ ${?} -ne 0 ]] && exit 1
    # client_name
    gen_qr ${1}
  ;;
  '-r'|'--rm-client-config')
    shift
    # client_name, server_name
    remove_client_config ${1:-''} ${2:-${SERVER_NAME}}
  ;;
  '-B'|'--add-clients-batch')
    shift
    # client_batch_csv_file
    gen_client_config_batch ${1}
  ;;
  '-q'|'--gen-qr-code')
    shift
    # client_name
    gen_qr ${1}
  ;;
  '-l'|'--list-used-ips')
    wg_list_used_ips
  ;;
  '-S'|'--sync')
    shift
    # server_name, server_public_ip
    wg_sync ${1:-${SERVER_NAME}} ${2:-${SERVER_PUBLIC_IP}}
  ;;
  *)
    help
esac
