#!/bin/bash
# Author: Milos Buncic
# Date: 2020/06/04
# Description: Run Wireguard config generator in Docker container

DOCKER_IMAGE="wgcg:latest"

CONTAINER_HOME="/home/${USER}"
if [[ ${UID} -eq 0 ]]; then
  CONTAINER_HOME="/root"
fi

OPTIONS="
  -e WGCG_CONFIG_FILE
  -v ${HOME}/.ssh:${CONTAINER_HOME}/.ssh
  -v ${HOME}/wireguard:${CONTAINER_HOME}/wireguard
"
if [[ -n ${SSH_AUTH_SOCK} ]]; then
  OPTIONS="
    ${OPTIONS}
    -e SSH_AUTH_SOCK=${CONTAINER_HOME}/ssh-agent.sock
    -v ${SSH_AUTH_SOCK}:${CONTAINER_HOME}/ssh-agent.sock
  "
fi

docker run -it --rm --user ${UID} ${OPTIONS} ${DOCKER_IMAGE} ${@}
