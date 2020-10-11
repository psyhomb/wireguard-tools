#!/bin/bash
# Author: Milos Buncic
# Date: 2019/09/25
# Description: Wireguard config generator

### Import global variables from configuration file
CONFIG_FILE="${HOME}/wireguard/wgcg/wgcg.conf"
for CF in "${WGCG_CONFIG_FILE}" "${CONFIG_FILE}"; do
  if [[ -f "${CF}" ]]; then
    CONFIG_FILE="${CF}"
    source "${CONFIG_FILE}"
    break
  fi
done

### Global variables
# Default options
# Server name (wireguard interface name e.g. wg0 || wg1 || wg2)
SERVER_NAME=${WGCG_SERVER_NAME}
# VPN (WG) IP private address
SERVER_WG_IP=${WGCG_SERVER_WG_IP}
# Static server port
SERVER_PORT=${WGCG_SERVER_PORT}
# Server's public IP or FQDN
# To discover server's public IP use: curl -sSL https://ifconfig.co
SERVER_PUBLIC_IP=${WGCG_SERVER_PUBLIC_IP}
# SSH server IP address (default: ${WGCG_SERVER_PUBLIC_IP})
# Note: This option can be used in case SSH server is listening on different IP address,
#       if not specified, ${WGCG_SERVER_PUBLIC_IP} will be used instead
SERVER_SSH_IP=${WGCG_SERVER_SSH_IP}
# SSH server port (default: 22)
SERVER_SSH_PORT=${WGCG_SERVER_SSH_PORT}
# Space separated list of DNS IPs (default: 1.1.1.1 1.0.0.1)
CLIENT_DNS_IPS=${WGCG_CLIENT_DNS_IPS}
# Space separated list of subnets (with CIDR) required for split-tunneling (default: 0.0.0.0/0)
CLIENT_ALLOWED_IPS=${WGCG_CLIENT_ALLOWED_IPS}
# Working directory where all generated files will be stored
WORKING_DIR=${WGCG_WORKING_DIR}

### Text colors
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
NONE="\033[0m"

### Dependencies required by the script
DEPS=(
  "wg"
  "gpg"
  "qrencode"
  "grepcidr"
)

# Check if all dependencies are installed
for DEP in ${DEPS[@]}; do
  if ! which ${DEP} &> /dev/null; then
    echo -e "${RED}ERROR${NONE}: ${BLUE}${DEP}${NONE} tool isn't installed!"
    STAT=1
  fi
done
[[ ${STAT} -eq 1 ]] && exit 1


### Functions
# Show help
help() {
  echo -e "${BLUE}Usage${NONE}:"
  echo -e "  ${GREEN}$(basename ${0})${NONE} options"
  echo
  echo -e "${BLUE}Options${NONE}:"
  echo -e "  ${GREEN}-P${NONE}|${GREEN}--sysprep${NONE} filename.sh                                  Install WireGuard kernel module, required tools and scripts (will establish SSH connection with server)"
  echo -e "  ${GREEN}-s${NONE}|${GREEN}--add-server-config${NONE}                                    Generate server configuration"
  echo -e "  ${GREEN}-c${NONE}|${GREEN}--add-client-config${NONE} client_name client_wg_ip           Generate client configuration"
  echo -e "  ${GREEN}-B${NONE}|${GREEN}--add-clients-batch${NONE} filename.csv[:rewrite|:norewrite]  Generate configuration for multiple clients in batch mode"
  echo -e "                                                            Supported action modes are 'rewrite' or 'norewrite' (default)"
  echo -e "                                                            'rewrite' action mean regenerate ALL, 'norewrite' mean generate only configs and keys for new clients"
  echo -e "  ${GREEN}-e${NONE}|${GREEN}--encrypt-config${NONE} client_name [passphrase]              Encrypt configuration file by using symmetric encryption (if passphrase not specified it will be generated - RECOMMENDED)"
  echo -e "  ${GREEN}-d${NONE}|${GREEN}--decrypt-config${NONE} client_name                           Decrypt configuration file and print it out on stdout"
  echo -e "  ${GREEN}-r${NONE}|${GREEN}--rm-client-config${NONE} client_name                         Remove client configuration"
  echo -e "  ${GREEN}-q${NONE}|${GREEN}--gen-qr-code${NONE} client_name [-]                          Generate QR code (PNG format) from client configuration file, if - is used, QR code will be printed out on stdout instead"
  echo -e "  ${GREEN}-l${NONE}|${GREEN}--list-used-ips${NONE}                                        List all clients IPs that are currently in use"
  echo -e "  ${GREEN}-S${NONE}|${GREEN}--sync${NONE}                                                 Synchronize server configuration (will establish SSH connection with server)"
  echo -e "  ${GREEN}-h${NONE}|${GREEN}--help${NONE}                                                 Show this help"
  echo
  echo -e "${BLUE}Current default options${NONE}:"
  echo -e "  WGCG_SERVER_NAME=${GREEN}\"${SERVER_NAME}\"${NONE}"
  echo -e "  WGCG_SERVER_WG_IP=${GREEN}\"${SERVER_WG_IP}\"${NONE}"
  echo -e "  WGCG_SERVER_PORT=${GREEN}\"${SERVER_PORT}\"${NONE}"
  echo -e "  WGCG_SERVER_PUBLIC_IP=${GREEN}\"${SERVER_PUBLIC_IP}\"${NONE}"
  [[ -n ${SERVER_SSH_IP} ]] && echo -e "  WGCG_SERVER_SSH_IP=${GREEN}\"${SERVER_SSH_IP}\"${NONE}"
  [[ -n ${SERVER_SSH_PORT} ]] && echo -e "  WGCG_SERVER_SSH_PORT=${GREEN}\"${SERVER_SSH_PORT}\"${NONE}"
  [[ -n ${CLIENT_DNS_IPS} ]] && echo -e "  WGCG_CLIENT_DNS_IPS=${GREEN}\"${CLIENT_DNS_IPS}\"${NONE}"
  [[ -n ${CLIENT_ALLOWED_IPS} ]] && echo -e "  WGCG_CLIENT_ALLOWED_IPS=${GREEN}\"${CLIENT_ALLOWED_IPS}\"${NONE}"
  echo -e "  WGCG_WORKING_DIR=${GREEN}\"${WORKING_DIR}\"${NONE}"
}


# Check mandatory global variables
check_variables() {
  if [[ -z ${SERVER_NAME} ]] || [[ -z ${SERVER_WG_IP} ]] || [[ -z ${SERVER_PORT} ]] || [[ -z ${SERVER_PUBLIC_IP} ]] || [[ -z ${WORKING_DIR} ]]; then
    echo -e "${RED}ERROR${NONE}: Missing mandatory variables, please check and modify ${GREEN}${CONFIG_FILE}${NONE} configuration file accordingly!"
    help
    return 1
  fi
}

check_variables || exit ${?}


# Validator for IP addresses and service ports
validator() {
  local mode="${1}"
  local value="${2}"
  local ret regex ip_octets fqdn cidr hostid netid

  ret=0
  case ${mode} in
    'ipaddress')
      # validator ipaddress 1.1.1.1
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
      # validator svcport 80
      regex='^[0-9]{1,5}$'
      svc_port=${value}

      if [[ ! ${svc_port} =~ ${regex} ]] || [[ ${svc_port} -gt 65535 ]]; then
        ret=1
      fi
    ;;
    'fqdn')
      # validator fqdn test.yourdomain.com
      regex='(?=^.{4,253}$)(^((?!-)[a-zA-Z0-9-]{0,62}[a-zA-Z0-9]\.)+[a-zA-Z]{2,63}$)'
      fqdn=${value}

      if ! echo ${fqdn} | grep -Pq ${regex}; then
        ret=1
      fi
    ;;
    'cidr')
      # validator cidr 24
      regex='^[0-9]{1,2}$'
      cidr=${value}

      if [[ ! ${cidr} =~ ${regex} ]] || [[ ${cidr} -gt 32 ]]; then
        ret=1
      fi
    ;;
    'in_cidr')
      # validator in_cidr "10.0.0.2 10.0.0.1/22"
      value=(${value})
      hostid=${value[0]}
      netid=${value[1]}

      if ! echo ${hostid} | grepcidr -e ${netid} &> /dev/null; then
        ret=1
      fi
  esac

  return ${ret}
}


# Generate password of specified length
genpass() {
  local length=${1:-40}
  local re='^[0-9]*$'

  if [[ ${length} =~ ${re} ]]; then
    # LC_CTYPE=C required if running on MacOS
    LC_CTYPE=C tr -dc 'A-Za-z0-9#$!@:/%' < /dev/urandom 2> /dev/null | head -c ${length} | xargs
  else
    return 1
  fi
}


# Encrypt configuration file by using symmetric encryption
encrypt() {
  local client_name="${1}"
  local passphrase="${2:-$(genpass)}"

  local client_config="${WORKING_DIR}/client-${client_name}.conf"
  local client_config_asc="${client_config}.asc"

  if [[ ! -f ${client_config} ]]; then
    echo -e "${RED}ERROR${NONE}: Client config ${BLUE}${client_config}${NONE} could not be found!"
    exit 1
  fi

  gpg \
    --yes \
    --armor \
    --pinentry-mode loopback \
    --passphrase "${passphrase}" \
    --symmetric ${client_config} 2> /dev/null

  if [[ ${?} -eq 0 ]]; then
    chmod 600 ${client_config_asc}
    echo -e "${GREEN}INFO${NONE}: Client config ${BLUE}${client_config}${NONE} => ${BLUE}${client_config_asc##*/}${NONE} has been successfully encrypted with following passphrase: ${RED}${passphrase}${NONE}"
    echo -e "${GREEN}INFO${NONE}: Client can use gpg tool to decrypt configuration file: ${GREEN}gpg -o ${client_config##*/} -d ${client_config_asc##*/}${NONE}"
  else
    echo -e "${RED}ERROR${NONE}: Failed to encrypt ${BLUE}${client_config}${NONE} configuration file!"
    exit 1
  fi
}


# Decrypt configuration file and print it out on stdout
decrypt() {
  local client_name="${1}"

  local client_config="${WORKING_DIR}/client-${client_name}.conf"
  local client_config_asc="${client_config}.asc"

  if [[ ! -f ${client_config_asc} ]]; then
    echo -e "${RED}ERROR${NONE}: Encrypted client config ${BLUE}${client_config_asc}${NONE} could not be found!"
    exit 1
  fi

  gpg --decrypt ${client_config_asc} 2> /dev/null

  if [[ ${?} -ne 0 ]]; then
    echo -e "${RED}ERROR${NONE}: Failed to decrypt ${BLUE}${client_config_asc}${NONE} configuration file!"
    exit 1
  fi
}


# Prepare system to run Wireguard
wg_sysprep() {
  local sysprep_module="${1}"
  local server_ssh_ip="${2}"
  local server_ssh_port="${3:-22}"

  local server_prepared="${WORKING_DIR}/.sysprepared"

  if [[ -f ${server_prepared} ]]; then
    echo -e "${YELLOW}WARNING${NONE}: System has already been prepared to run Wireguard!"
    echo -ne "Are you sure you want to run it again? (${GREEN}yes${NONE}/${RED}no${NONE}): "
    read answer

    [[ ${answer} != "yes" ]] && exit 1
  fi

  if [[ ! -f ${sysprep_module} ]]; then
    echo -e "${RED}ERROR${NONE}: Sysprep module ${RED}${sysprep_module}${NONE} could not be found!"
    exit 1
  fi

  if ! validator ipaddress ${server_ssh_ip} && ! validator fqdn ${server_ssh_ip}; then
    echo -e "${RED}ERROR${NONE}: ${RED}${server_ssh_ip}${NONE} is not valid IP address nor FQDN!"
    exit 1
  fi

  local sysprep_module_script="${sysprep_module##*/}"
  cat ${sysprep_module} | ssh -p ${server_ssh_port} root@${server_ssh_ip} "
    cat > /usr/local/bin/${sysprep_module_script} && \
    chmod +x /usr/local/bin/${sysprep_module_script} && \
    /usr/local/bin/${sysprep_module_script}
  "
  if [[ ${?} -ne 0 ]]; then
    echo -e "${RED}ERROR${NONE}: Something went wrong, execution of sysprep module ${BLUE}${sysprep_module_script}${NONE} failed!"
    exit 1
  fi

  touch ${server_prepared}
  echo -e "${GREEN}INFO${NONE}: Sysprep module executed successfully, Wireguard server is now ready to receive configuration file!"
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
  rm -f ${WORKING_DIR}/client-${client_name}{.conf,.conf.png,.conf.asc,-private.key,-public.key}

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
  local server_wg_ip_cidr="${2}"
  local server_port="${3}"

  local server_wg_ip="${server_wg_ip_cidr%%/*}"
  local cidr="$(echo ${server_wg_ip_cidr} | awk -F'/' '{print $2}')"
  local cidr="${cidr:-22}"

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

  validator cidr ${cidr}
  if [[ ${?} -ne 0 ]]; then
    echo -e "${RED}ERROR${NONE}: ${RED}${cidr}${NONE} is not valid CIDR!"
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
Address = ${server_wg_ip}/${cidr}
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
  local server_wg_ip_cidr server_wg_ip cidr client_config_match server_config_match

  local client_dns_ips="${6:-1.1.1.1 1.0.0.1}"
  local client_allowed_ips="${7:-0.0.0.0/0}"

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
    echo -e "${GREEN}INFO${NONE}: Server config and keys could not be found, please run script with ${GREEN}--add-server-config${NONE} option first"
    exit 1
  fi

  for ip in ${client_wg_ip} ${client_dns_ips} ${client_allowed_ips}; do
    validator ipaddress ${ip%/*}
    if [[ ${?} -ne 0 ]]; then
      echo -e "${RED}ERROR${NONE}: ${RED}${ip%/*}${NONE} is not valid IP address!"
      return 1
    fi
  done

  if ! validator ipaddress ${server_public_ip} && ! validator fqdn ${server_public_ip}; then
    echo -e "${RED}ERROR${NONE}: ${RED}${server_public_ip}${NONE} is not valid IP address nor FQDN!"
    return 1
  fi

  validator svcport ${server_port}
  if [[ ${?} -ne 0 ]]; then
    echo -e "${RED}ERROR${NONE}: ${RED}${server_port}${NONE} is not valid port number!"
    return 1
  fi

  server_config_match=$(grep -l "^Address = ${client_wg_ip}" ${server_config})
  if [[ -n ${server_config_match} ]]; then
    echo -e "${RED}ERROR${NONE}: WG private IP address ${RED}${client_wg_ip}${NONE} already in use by the server => ${BLUE}${server_config_match}${NONE}"
    return 1
  fi

  server_wg_ip_cidr=$(awk '/^Address =/ {print $NF}' ${server_config})
  server_wg_ip=${server_wg_ip_cidr%%/*}
  cidr=${server_wg_ip_cidr##*/}
  validator in_cidr "${client_wg_ip} ${server_wg_ip}/${cidr}"
  if [[ ${?} -ne 0 ]]; then
    echo -e "${RED}ERROR${NONE}: WG private IP address ${RED}${client_wg_ip}${NONE} is not in the same subnet as server's IP address => ${GREEN}${server_wg_ip}/${cidr}${NONE}"
    return 1
  fi

  if [[ -f ${client_private_key} ]]; then
    # Condition will be skipped if function called from the gen_client_config_batch() function
    if [[ ${SKIP_ANSWER} == false ]]; then
      echo -e "${YELLOW}WARNING${NONE}: All files for this client will be regenerated!"
      echo -ne "Config and key files for client ${GREEN}${client_name}${NONE} are already generated, do you want to overwrite it? (${GREEN}yes${NONE}/${RED}no${NONE}): "
      read answer

      [[ ${answer} == "yes" ]] || return 1

      remove_client_config ${client_name} ${server_name}
    else
      if [[ ${BATCH_REWRITE} == true ]]; then
        remove_client_config ${client_name} ${server_name}
      else
        return 1
      fi
    fi
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
Address = ${client_wg_ip}/${cidr}
PrivateKey = $(head -1 ${client_private_key})
DNS = $(echo ${client_dns_ips} | sed -E 's/ +/, /g')

[Peer]
PublicKey = $(head -1 ${server_public_key})
PresharedKey = $(head -1 ${preshared_key})
AllowedIPs = $(echo ${client_allowed_ips} | sed -E 's/ +/, /g')
Endpoint = ${server_public_ip}:${server_port}
PersistentKeepalive = 25
EOF

  cat >> ${server_config} <<EOF

### ${client_name} - START
[Peer]
# friendly_name = ${client_name}
PublicKey = $(head -1 ${client_public_key})
PresharedKey = $(head -1 ${preshared_key})
AllowedIPs = ${client_wg_ip}/32
### ${client_name} - END
EOF

  echo -e "${GREEN}INFO${NONE}: Client config ${BLUE}${client_config}${NONE} has been generated successfully!"
}


# Generate QR code
gen_qr() {
  local config_name="${1}"
  local output="${2}"
  local config_path="${WORKING_DIR}/client-${config_name}.conf"

  if [[ ! -f ${config_path} ]]; then
    echo -e "${RED}ERROR${NONE}: Error while generating QR code, config file ${BLUE}${config_path}${NONE} does not exist!"
    exit 1
  fi

  local options="-o ${config_path}.png"
  if [[ ${output} == "-" ]]; then
    local options="-t ANSIUTF8 -o -"
  fi

  cat ${config_path} | qrencode ${options}

  if [[ ${output} != "-" ]]; then
    chmod 600 ${config_path}.png
    echo -e "${GREEN}INFO${NONE}: QR file ${BLUE}${config_path}.png${NONE} has been generated successfully!"
  fi
}


# Generate client configs in batch
BATCH_REWRITE=false
gen_client_config_batch() {
  local client_batch_csv_file="${1%%:*}"
  local client_batch_csv_file_action="${1##*:}"
  local client_name client_wg_ip client_wg_gen_action

  if [[ ! -f ${client_batch_csv_file} ]]; then
    echo -e "${RED}ERROR${NONE}: Client batch file ${BLUE}${client_batch_csv_file}${NONE} does not exist, please create one first!"
    exit 1
  fi

  SKIP_ANSWER=true
  while IFS=',' read client_name client_wg_ip client_wg_gen_action; do
    BATCH_REWRITE=false
    case ${client_batch_csv_file_action} in
      "rewrite")
        BATCH_REWRITE=true
      ;;
    esac

    case ${client_wg_gen_action} in
      "rewrite")
        BATCH_REWRITE=true
      ;;
      "norewrite")
        BATCH_REWRITE=false
      ;;
    esac

    gen_client_config ${client_name} ${client_wg_ip} ${SERVER_NAME} ${SERVER_PORT} ${SERVER_PUBLIC_IP} "${CLIENT_DNS_IPS}" "${CLIENT_ALLOWED_IPS}"
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

  echo -ne ${ip_client_list} | sort -t . -k1,1n -k2,2n -k3,3n -k4,4n
}


# Sync configuration with server
wg_sync() {
  local server_name="${1}"
  local server_ssh_ip="${2}"
  local server_ssh_port="${3:-22}"

  local server_config="${WORKING_DIR}/server-${server_name}.conf"

  if [[ ! -f ${server_config} ]]; then
    echo -e "${RED}ERROR${NONE}: Server config ${BLUE}${server_config}${NONE} does not exist, aborting sync command..."
    exit 1
  fi

  if ! validator ipaddress ${server_ssh_ip} && ! validator fqdn ${server_ssh_ip}; then
    echo -e "${RED}ERROR${NONE}: ${RED}${server_ssh_ip}${NONE} is not valid IP address nor FQDN!"
    exit 1
  fi

  ssh -p ${server_ssh_port} root@${server_ssh_ip} "which wg-quick &> /dev/null"
  if [[ ${?} -ne 0 ]]; then
    echo -e "${YELLOW}WARNING${NONE}: It looks like ${GREEN}wireguard-tools${NONE} package isn't installed, please run script with ${GREEN}--sysprep${NONE} option first"
    exit 1
  fi

  cat ${server_config} | ssh -p ${server_ssh_port} root@${server_ssh_ip} "cat > /etc/wireguard/${server_name}.conf && chmod 600 /etc/wireguard/${server_name}.conf"
  if [[ ${?} -eq 0 ]]; then
    ssh -p ${server_ssh_port} root@${server_ssh_ip} "
      if ! systemctl is-enabled wg-quick@${server_name}.service &> /dev/null; then
        systemctl enable --now wg-quick@${server_name}.service &> /dev/null
      fi

      if systemctl is-active wg-quick@${server_name}.service &> /dev/null; then
        wg syncconf ${server_name} <(sed '/^Address =/d;/^DNS =/d;/^MTU =/d;/^PreUp =/d;/^PostUp =/d;/^PreDown =/d;/^PostDown =/d;/^SaveConfig =/d' /etc/wireguard/${server_name}.conf)
      fi
    "
  else
    echo -e "${RED}ERROR${NONE}: Syncing configuration ${BLUE}${server_config}${NONE} with server ${BLUE}${server_ssh_ip}${NONE} failed!"
    exit 1
  fi
}


case ${1} in
  '-P'|'--sysprep')
    shift
    # sysprep_module, server_ssh_ip, server_ssh_port
    wg_sysprep ${1:-''} ${SERVER_SSH_IP:-${SERVER_PUBLIC_IP}} ${SERVER_SSH_PORT}
  ;;
  '-s'|'--add-server-config')
    shift
    # server_name, server_wg_ip, server_port
    gen_server_config ${SERVER_NAME} ${SERVER_WG_IP} ${SERVER_PORT}
  ;;
  '-c'|'--add-client-config')
    shift
    # client_name, client_wg_ip, server_name, server_port, server_public_ip
    gen_client_config ${1:-''} ${2:-''} ${SERVER_NAME} ${SERVER_PORT} ${SERVER_PUBLIC_IP} "${CLIENT_DNS_IPS}" "${CLIENT_ALLOWED_IPS}"
    [[ ${?} -ne 0 ]] && exit 1
    # client_name
    gen_qr ${1}
  ;;
  '-e'|'--encrypt-config')
    shift
    # client_name, passphrase
    encrypt ${1} "${2}"
  ;;
  '-d'|'--decrypt-config')
    shift
    # client_name
    decrypt ${1}
  ;;
  '-r'|'--rm-client-config')
    shift
    # client_name, server_name
    remove_client_config ${1:-''} ${SERVER_NAME}
  ;;
  '-B'|'--add-clients-batch')
    shift
    # client_batch_csv_file
    gen_client_config_batch ${1}
  ;;
  '-q'|'--gen-qr-code')
    shift
    # client_name, output
    gen_qr ${1} ${2}
  ;;
  '-l'|'--list-used-ips')
    wg_list_used_ips
  ;;
  '-S'|'--sync')
    shift
    # server_name, server_ssh_ip, server_ssh_port
    wg_sync ${SERVER_NAME} ${SERVER_SSH_IP:-${SERVER_PUBLIC_IP}} ${SERVER_SSH_PORT}
  ;;
  *)
    help
esac
