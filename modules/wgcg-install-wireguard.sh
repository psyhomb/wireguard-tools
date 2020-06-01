#!/bin/bash
# Author: Milos Buncic
# Date: 2019/10/01
# Description: Prepare Wireguard server

set -e

echo "Installing Wireguard and required dependencies on the server, please wait..."
echo

# Installing wireguard kernel module and required dependencies
add-apt-repository ppa:wireguard/wireguard
apt-get update && apt-get install -y wireguard

# Allow module to be loaded at boot time
echo wireguard > /etc/modules-load.d/wgcg.conf

# Load the module
modprobe -v wireguard

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
    echo 1 > /proc/sys/net/ipv4/ip_forward
    rules -A
  ;;
  'del')
    rules -D
    echo 0 > /proc/sys/net/ipv4/ip_forward
  ;;
  *)
    echo "Usage: \$(basename \${0}) add|del"
esac
EOF

### Enable permanent IP forwarding (routing)
#cat > /etc/sysctl.d/10-wgcg.conf <<'EOF' && sysctl -p /etc/sysctl.d/10-wgcg.conf
## Enable IP forwarding (routing) - WireGuard
#net.ipv4.ip_forward = 1
#EOF
