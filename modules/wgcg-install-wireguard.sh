#!/bin/bash
# Author: Milos Buncic
# Date: 2019/10/01
# Description: Prepare Wireguard server

set -e

echo "Installing Wireguard and required dependencies on the server, please wait..."
echo

# Installing wireguard kernel module and required dependencies
# DEPRECATION NOTICE: WireGuard packages have now moved into official Ubuntu repository (Ubuntu 20.04, 19.10, 18.04, and 16.04)
#add-apt-repository ppa:wireguard/wireguard
apt-get update && apt-get install -y linux-headers-$(uname -r) wireguard
mkdir -p /etc/wireguard

# Allow module to be loaded at boot time
echo wireguard > /etc/modules-load.d/wgcg.conf

# Load the module
echo -e "\nLoading module..."
echo -e "NOTE: If error encountered please try upgrading the Linux kernel to the latest version available and reboot\n"
modprobe -v wireguard

### Generate wgfw.sh script - will be used for adding required firewall rules
cat > /usr/local/bin/wgfw.sh <<EOF && chmod +x /usr/local/bin/wgfw.sh
#!/bin/bash
# Author: Milos Buncic
# Date: 2019/09/25
# Description: Set firewall rules on Wireguard server

# iptables binary
IPTABLES_BIN=\$(which iptables)

# Custom rules file
CUSTOM_RULES_FILE="/etc/wireguard/wgfw.rules"

# wgcg chain name
CHAIN_NAME="WGCG-CUSTOM"

# Local private interface
PRIVATE_INTERFACE="\$(ip a | awk -F'[ :]' '/^[0-9]+:/ {print \$3}' | tail -n+2 | head -n1)"

### Text colors
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
NONE="\033[0m"

# Enable/disable routing aka ip forwarding
ip_forward() {
  local enabled=\${1}
  local proc_ip_forward="/proc/sys/net/ipv4/ip_forward"

  case \${enabled} in
    'true'|'1')
      echo 1 > \${proc_ip_forward}
    ;;
    'false'|'0')
      echo 0 > \${proc_ip_forward}
  esac
}

# Delete user defined firewall chain
flush_custom_rules() {
  (
    \${IPTABLES_BIN} -F \${CHAIN_NAME}
    \${IPTABLES_BIN} -D FORWARD -j \${CHAIN_NAME}
    \${IPTABLES_BIN} -X \${CHAIN_NAME}
  ) &> /dev/null

  return 0
}

# Set server startup firewall rules
rules() {
  local action=\${1}

  case \${action} in
    'add'|'a')
      action="-A"
    ;;
    'insert'|'i')
      action="-I"
    ;;
    'del'|'d')
      action="-D"
  esac

  # Rules below this line will be set only at server startup.
  \${IPTABLES_BIN} -t nat \${action} POSTROUTING -o \${PRIVATE_INTERFACE} -j MASQUERADE
}

# Set custom firewall rules
set_custom_rules() {
  local rule_args
  local rule_action
  local rule_rest
  local rule_cmd
  local check_output
  local check_status
  local malformed_rules_counter

  if ! \${IPTABLES_BIN} -L \${CHAIN_NAME} &> /dev/null; then
    \${IPTABLES_BIN} -N \${CHAIN_NAME}
    \${IPTABLES_BIN} -I FORWARD -j \${CHAIN_NAME}
    \${IPTABLES_BIN} -A \${CHAIN_NAME} -j RETURN
  fi

  if [[ ! -f \${CUSTOM_RULES_FILE} ]] || [[ -z "\$(grep -Ev '^( *#|$)' \${CUSTOM_RULES_FILE})" ]]; then
    echo -e "\${GREEN}INFO\${NONE}: \${CUSTOM_RULES_FILE} does not exist or empty, no custom firewall rules will be applied"
    return 0
  fi

  malformed_rules_counter=0
  while read rule; do
    rule_args=(\$(echo \${rule}))
    rule_action=\${rule_args[0]}
    rule_rest=\${rule_args[@]:2:\$((\${#rule_args[@]}-1))}

    check_output=\$(\${IPTABLES_BIN} -C \${CHAIN_NAME} \${rule_rest} 2>&1)
    check_status=\${?}

    if [[ \${check_status} -eq 2 ]]; then
      echo -e "\${RED}ERROR\${NONE}: firewall rule command malformed: \${check_output} => \${RED}\${IPTABLES_BIN} \${rule_action} \${CHAIN_NAME} \${rule_rest}\${NONE}"
      let malformed_rules_counter++
    fi
  done < <(grep -Ev '^( *#|$)' \${CUSTOM_RULES_FILE})

  if [[ \${malformed_rules_counter} -gt 0 ]]; then
    echo -e "\n\${GREEN}INFO\${NONE}: 0 firewall rules have been applied due to \${RED}\${malformed_rules_counter}\${NONE} malformed rule/s, fix all the malformed rules and try again"
    return 2
  fi

  while read rule; do
    rule_args=(\$(echo \${rule}))
    rule_action=\${rule_args[0]}
    rule_rest=\${rule_args[@]:2:\$((\${#rule_args[@]}-1))}

    check_output=\$(\${IPTABLES_BIN} -C \${CHAIN_NAME} \${rule_rest} 2>&1)
    check_status=\${?}

    rule_cmd="\${IPTABLES_BIN} \${rule_action} \${CHAIN_NAME} \${rule_rest}"
    if [[ \${check_status} -eq 1 ]]; then
      if [[ \${rule_action} =~ ^-[AI]$ ]]; then
        \${rule_cmd}
      elif [[ \${rule_action} == "-D" ]]; then
        echo -e "\${YELLOW}WARNING\${NONE}: firewall rule does not exist, delete action will be skipped: \${check_output} => \${GREEN}\${rule_cmd}\${NONE}"
      fi
    elif [[ \${check_status} -eq 0 ]] && [[ \${rule_action} == "-D" ]]; then
      \${rule_cmd}
    fi
  done < <(grep -Ev '^( *#|$)' \${CUSTOM_RULES_FILE})

  \${IPTABLES_BIN} -D \${CHAIN_NAME} -j RETURN &> /dev/null && \${IPTABLES_BIN} -A \${CHAIN_NAME} -j RETURN
}

case \${1} in
  'add')
    ip_forward 1
    rules add
    set_custom_rules
  ;;
  'set')
    ip_forward 1
    set_custom_rules
  ;;
  'del')
    ip_forward 0
    rules del
    flush_custom_rules
  ;;
  *)
    echo "Usage: \$(basename \${0}) add|set|del"
esac
EOF

### Enable permanent IP forwarding (routing)
#cat > /etc/sysctl.d/10-wgcg.conf <<'EOF' && sysctl -p /etc/sysctl.d/10-wgcg.conf
## Enable IP forwarding (routing) - WireGuard
#net.ipv4.ip_forward = 1
#EOF
