FROM ubuntu:20.04

LABEL maintainer="psyhomb"

ARG USER
ARG UID

ENV USER=${USER:-wgcg} \
    UID=${UID:-1000}

WORKDIR /data/wgcg

COPY . ./

RUN case ${UID} in \
      0) HOME="/root" ;; \
      *) HOME="/home/${USER}"; useradd -ou ${UID} ${USER} ;; \
    esac \
 && mkdir -p ${HOME}/.gnupg ${HOME}/wireguard/wgcg \
 && chmod 700 ${HOME}/.gnupg \
 && mv wgcg.conf ${HOME}/wireguard/wgcg/ \
 && mv wgcg.sh /usr/local/bin/ \
 && chmod 644 ${HOME}/wireguard/wgcg/wgcg.conf \
 && chmod 755 /usr/local/bin/wgcg.sh \
 && chown -R ${USER}:${USER} ${HOME} \
 && apt-get update \
 && apt-get -y install --no-install-recommends wireguard-tools openssh-client gpg gpg-agent qrencode grepcidr \
 && apt-get -y --purge autoremove \
 && apt-get clean \
 && rm -vrf /var/lib/apt/lists/*

USER ${USER}
ENTRYPOINT ["/usr/local/bin/wgcg.sh"]
