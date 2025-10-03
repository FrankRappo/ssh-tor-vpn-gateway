#!/bin/bash

# OpenVPN Tor Routing Setup Script
# This script configures iptables rules to route specific OpenVPN clients through Tor
# while keeping other clients on direct connection.
#
# IMPORTANT: This script uses selective rule deletion to avoid breaking existing
# iptables rules, particularly the MASQUERADE rule needed for VPN connections.

set -e

# Configuration
TUN_INTERFACE="tun0"
WAN_INTERFACE="eth0"
VPN_NETWORK="10.8.0.0/24"
TOR_CLIENT_IP="10.8.0.100"
TOR_DNS_PORT="5353"
TOR_TRANS_PORT="9040"
TOR_GATEWAY="10.8.0.1"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Tor VPN routing setup...${NC}"

# Enable IP forwarding
echo -e "${YELLOW}Enabling IP forwarding...${NC}"
echo 1 > /proc/sys/net/ipv4/ip_forward

# Remove old Tor rules if they exist (gracefully, without errors)
echo -e "${YELLOW}Removing old Tor routing rules (if any)...${NC}"
iptables -t nat -D PREROUTING -i $TUN_INTERFACE -p udp --dport 53 -s $TOR_CLIENT_IP -j DNAT --to-destination $TOR_GATEWAY:$TOR_DNS_PORT 2>/dev/null || true
iptables -t nat -D PREROUTING -i $TUN_INTERFACE -p tcp -s $TOR_CLIENT_IP -j DNAT --to-destination $TOR_GATEWAY:$TOR_TRANS_PORT 2>/dev/null || true

# Add Tor routing rules
echo -e "${YELLOW}Adding Tor routing rules...${NC}"
iptables -t nat -A PREROUTING -i $TUN_INTERFACE -p udp --dport 53 -s $TOR_CLIENT_IP -j DNAT --to-destination $TOR_GATEWAY:$TOR_DNS_PORT
iptables -t nat -A PREROUTING -i $TUN_INTERFACE -p tcp -s $TOR_CLIENT_IP -j DNAT --to-destination $TOR_GATEWAY:$TOR_TRANS_PORT

# Ensure MASQUERADE rule exists (add only if not present)
# This is CRITICAL - without this rule, VPN connections will fail
echo -e "${YELLOW}Checking MASQUERADE rule...${NC}"
iptables -t nat -C POSTROUTING -s $VPN_NETWORK -o $WAN_INTERFACE -j MASQUERADE 2>/dev/null || {
    echo -e "${YELLOW}Adding MASQUERADE rule...${NC}"
    iptables -t nat -A POSTROUTING -s $VPN_NETWORK -o $WAN_INTERFACE -j MASQUERADE
}

echo -e "${GREEN}Tor VPN routing setup completed successfully!${NC}"
echo ""
echo "Current NAT rules:"
iptables -t nat -L -n -v | grep -E "(Chain|10.8.0)"

echo ""
echo -e "${GREEN}Setup complete. Tor routing is active for $TOR_CLIENT_IP${NC}"
