wireguard-tools
===============

Full documentation about Wireguard installation and configuration process can be found [here](https://gitlab.com/snippets/1897102).

wgcg.sh
-------

### About

This script is created to ease manual process of Wireguard configuration and will help you to automatically generate all the required configuration files (client and server), PKI key pairs and preshared key.

### Usage

Before start using this script you will have to update [wgcg.vars](./wgcg.vars) configuration file.  
Practically the only variable you would have to modify is `WGCG_SERVER_PUBLIC_IP`.

```bash
# Server name (wireguard interface name e.g. wg0 || wg1 || wg2)
WGCG_SERVER_NAME="wg0"

# VPN (WG) IP private address
WGCG_SERVER_WG_IP="10.0.0.1"

# Static server port
WGCG_SERVER_PORT="52001"

# Server's public IP or FQDN
WGCG_SERVER_PUBLIC_IP="wg.example.com"

# All configuration and key files will be stored in this directory
WGCG_WORKING_DIR="${HOME}/wireguard/${WGCG_SERVER_NAME}"
```

All following commands must be executed from the local system!

Copy [wgcg.vars](./wgcg.vars) configuration file to the `wgcg` directory:

```bash
mkdir -p ${HOME}/wireguard/wgcg
cp wgcg.vars ${HOME}/wireguard/wgcg/
```

Print help and current default options

```plain
# ./wgcg.sh -h
Usage:
  wgcg.sh options

Options:
  -P|--sysprep filename.sh                             Install Wiregurad kernel module, required tools and scripts (will establish SSH connection with server)
  -s|--add-server-config                               Generate server configuration
  -c|--add-client-config client_name client_wg_ip      Generate client configuration
  -B|--add-clients-batch filename.csv                  Generate configuration for multiple clients in batch mode
  -r|--rm-client-config client_name                    Remove client configuration
  -q|--gen-qr-code client_name                         Generate QR code from client configuration file
  -l|--list-used-ips                                   List all client's IPs that are currently in use
  -S|--sync                                            Synchronize server configuration (will establish SSH connection with server)
  -h|--help                                            Show this help

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
