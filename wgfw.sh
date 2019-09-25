#!/bin/bash

# Local private interface
PRIVATE_INTERFACE="eth0"

rules() {
  local action=${1}

  iptables -t nat ${action} POSTROUTING -o ${PRIVATE_INTERFACE} -j MASQUERADE
}

case ${1} in
  'add')
    rules -A
  ;;
  'del')
    rules -D
  ;;
  *)
    echo "Usage: $(basename ${0}) add|del"
esac
