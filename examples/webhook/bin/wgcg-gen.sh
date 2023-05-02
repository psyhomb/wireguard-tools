#!/bin/bash
# Author: Milos Buncic
# Date: 2020/06/10
# Description: Generate and sync WireGuard configuration and publish the configuration via HTTP endpoint

export WGCG_CONFIG_FILE="${HOME}/wireguard/wgcg/wg-1.conf"
source ${WGCG_CONFIG_FILE}

WEBHOOK_ENDPOINT="https://wgcg.yourdomain.com/hooks/wgcg?servername=${WGCG_SERVER_NAME}"
WEBHOOK_CONFIG_PATH="/etc/webhook"


help() {
  echo "Usage:"
  echo "  $(basename ${0}) options"
  echo
  echo "Options:"
  echo "  list                            List existing clients"
  echo "  add client_name private_ip      Add a new client"
  echo "  remove client_name              Remove client"
  echo "  sync                            Synchronize server configuration"
  echo "  help                            Show this help"
}


genpass() {
  local length=${1:-40}
  local re='^[0-9]*$'

  if [[ ${length} =~ ${re} ]]; then
    # LC_CTYPE=C required if running on MacOS
    LC_CTYPE=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c ${length} | xargs
  else
    return 1
  fi
}


gen_webhook_config() {
  local client_name=${1}
  local auth_file=${2}
  local client_token=$(genpass)

  cat > ${auth_file} <<EOF
{
  "and": [
    {
      "match": {
        "type": "value",
        "value": "${client_name}",
        "parameter": {
          "source": "url",
          "name": "username"
        }
      }
    },
    {
      "match": {
        "type": "value",
        "value": "${client_token}",
        "parameter": {
          "source": "url",
          "name": "token"
        }
      }
    }
  ]
}
EOF
  echo -e "\nURL: ${WEBHOOK_ENDPOINT}&username=${client_name}&token=${client_token}\n"
}


wgcg_sync() {
  wgcg.sh --sync
  if [[ -f "/root/wireguard/wgcg/wg-2.conf" ]]; then
    WGCG_CONFIG_FILE=/root/wireguard/wgcg/wg-2.conf wgcg.sh --sync
  fi
}


case ${1} in
  'list')
    wgcg.sh --list-used-ips
  ;;
  'add')
    shift
    wgcg.sh --add-client-config ${1} ${2} || exit 1
    wgcg.sh --encrypt-config ${1}

    echo "Syncing configuration with server..."
    wgcg_sync

    gen_webhook_config ${1} "${WEBHOOK_CONFIG_PATH}/auth-${1}.json"
    wh.py
    chmod 600 "${WEBHOOK_CONFIG_PATH}/hooks.json" "${WEBHOOK_CONFIG_PATH}/auth-${1}.json"
  ;;
  'remove')
    shift
    wgcg.sh --rm-client-config ${1} || exit 1

    echo "Syncing configuration with server..."
    wgcg_sync

    rm -f "${WEBHOOK_CONFIG_PATH}/auth-${1}.json"
    wh.py
    chmod 600 "${WEBHOOK_CONFIG_PATH}/hooks.json"
  ;;
  'sync')
    wgcg_sync
  ;;
  *)
    help
esac
