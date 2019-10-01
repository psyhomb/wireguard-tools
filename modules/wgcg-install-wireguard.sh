#!/bin/bash
# Author: Milos Buncic
# Date: 2019/10/01
# Description: Prepare Wireguard server

set -e

echo "Installing Wireguard and required dependencies, please wait..."
echo

# Installing wireguard kernel module and required dependencies
apt-get update && apt-get install -y wireguard

# Allow module to be loaded at boot time
echo wireguard > /etc/modules-load.d/wg.conf

# Load the module
modprobe wireguard

### Generate wgfw.sh script - will be used for adding required firewall rules
cat > /usr/local/bin/wgfw.sh <<EOF && chmod +x /usr/local/bin/wgfw.sh
#!/bin/bash
# Author: Milos Buncic
# Date: 2019/09/25
# Description: Add required Wireguard firewall rules

# Local private interface
PRIVATE_INTERFACE="$(ip a | awk -F'[ :]' '/^2:/ {print $3}')"

rules() {
  local action=\${1}

  iptables -t nat \${action} POSTROUTING -o \${PRIVATE_INTERFACE} -j MASQUERADE
}

case \${1} in
  'add')
    rules -A
  ;;
  'del')
    rules -D
  ;;
  *)
    echo "Usage: \$(basename \${0}) add|del"
esac
EOF

### Enable IP forwarding (routing)
cat > /etc/sysctl.d/10-wgcg.conf <<'EOF' && sysctl -p /etc/sysctl.d/10-wgcg.conf
# Enable IP forwarding (routing) - WireGuard
net.ipv4.ip_forward = 1
EOF

echo
echo "Wireguard installed successfully!"
