wireguard-tools
===============

Full documentation about Wireguard installation and configuration process can be found [here](https://gitlab.com/snippets/1897102).

wgcg.sh
-------

### About

This script is created to ease manual process of Wireguard configuration and will help you to automatically generate all the required configuration files (client and server), PKI key pairs and preshared key.

### Usage

Before start using this script I would suggest updating default options in [wgcg.vars](./wgcg.vars) file, otherwise you will have to specify these options from the command line every time you run the script.  
Practically the only variable you would have to modify is `WGCG_SERVER_PUBLIC_IP`.

```bash
# Server name (wireguard interface name e.g. wg0 || wg1 || wg2)
export WGCG_SERVER_NAME="wg0"

# VPN (WG) IP private address
export WGCG_SERVER_WG_IP="10.0.0.1"

# Static server port
export WGCG_SERVER_PORT="52001"

# Server's public IP or FQDN
export WGCG_SERVER_PUBLIC_IP="wg.example.com"

# All configuration and key files will be stored in this directory
export WGCG_WORKING_DIR="${HOME}/wireguard/${WGCG_SERVER_NAME}"
```

Export variables defined in [wgcg.vars](./wgcg.vars) file

```bash
source wgcg.vars
```

Print help and current default options

```plain
# ./wgcg.sh -h
Usage:
  wgcg.sh options

Options:
  -P|--sysprep filename.sh [server_public_ip]
  -s|--add-server-config [server_name] [server_wg_ip] [server_port]
  -c|--add-client-config client_name client_wg_ip [server_name] [server_port] [server_public_ip]
  -B|--add-clients-batch filename.csv
  -r|--rm-client-config client_name [server_name]
  -q|--gen-qr-code client_name
  -l|--list-used-ips
  -S|--sync [server_name] [server_public_ip]
  -h|--help

Current default options:
  WGCG_SERVER_NAME="wg0"
  WGCG_SERVER_WG_IP="10.0.0.1"
  WGCG_SERVER_PORT="52001"
  WGCG_SERVER_PUBLIC_IP="wg.example.com"
  WGCG_WORKING_DIR="/home/username/wireguard/wg0"
```

This module will do all required system preparations on the Wiregurad server (this is idempotent operation):

- Install `wireguard` kernel module and tools
- Load the module
- Generate `wgfw.sh` script
- Enable IP forwarding (routing)

**Note:** You have to run it only once!

```bash
./wgcg.sh --sysprep modules/wgcg-install-wireguard.sh
```

Generate server keys and config

```bash
./wgcg.sh -s
```

Generate client config, PKI key pairs and update server config (add new Peer block)

```bash
./wgcg.sh -c foo 10.0.0.2
```

or if you want to generate multiple client configs, create `client-configs.csv` file

```bash
cat > client-configs.csv <<'EOF'
foo,10.0.0.2
bar,10.0.0.3
EOF
```

and run

**WARNING**: In batch mode if client configuration and key files exist all will be regenerated non-interactively

```bash
./wgcg.sh -B client-configs.csv
```

Remove client config, PKI key pairs and update server config (remove Peer block)

```bash
./wgcg.sh -r foo
```

Copy over updated server configuration to the server

```bash
./wgcg.sh --sync
```
