# Installation Guide

Complete step-by-step guide for setting up OpenVPN with selective Tor routing.

## Prerequisites

- Ubuntu 20.04+ (tested on 24.04)
- OpenVPN server already installed and working
- Root access to the server
- At least 2 client certificates created (one with CN=tor, one with different CN)

## Step 1: Install Required Packages

```bash
apt update
apt install -y tor iptables-persistent
```

## Step 2: Configure Tor

Edit `/etc/tor/torrc`:

```bash
nano /etc/tor/torrc
```

Add or modify these lines:

```
VirtualAddrNetwork 10.192.0.0/10
AutomapHostsOnResolve 1
DNSPort 10.8.0.1:5353
TransPort 10.8.0.1:9040
```

Save and restart Tor:

```bash
systemctl restart tor
systemctl enable tor
```

Verify Tor is running:

```bash
systemctl status tor
ss -tlnp | grep tor
```

Expected output:
```
LISTEN 0   4096   10.8.0.1:9040   0.0.0.0:*   users:(("tor",pid=XXX))
LISTEN 0   4096   10.8.0.1:5353   0.0.0.0:*   users:(("tor",pid=XXX))
```

## Step 3: Configure OpenVPN Server

### 3.1: Enable Client-Config-Dir

Edit `/etc/openvpn/server.conf`:

```bash
nano /etc/openvpn/server.conf
```

Ensure this line exists:

```
client-config-dir /etc/openvpn/ccd
```

### 3.2: Create CCD Directory

```bash
mkdir -p /etc/openvpn/ccd
```

### 3.3: Create Tor Client Config

Create `/etc/openvpn/ccd/tor`:

```bash
cat > /etc/openvpn/ccd/tor << EOF
ifconfig-push 10.8.0.100 255.255.255.0
push "route-gateway 10.8.0.1"
EOF
```

**Important**: The filename `tor` must match the CN in your client certificate.

### 3.4: Restart OpenVPN

```bash
systemctl restart openvpn@server
systemctl status openvpn@server
```

## Step 4: Setup Routing Script

### 4.1: Copy Routing Script

```bash
cp scripts/setup-tor-routing.sh /etc/openvpn/
chmod +x /etc/openvpn/setup-tor-routing.sh
```

### 4.2: Review Script Configuration

Edit `/etc/openvpn/setup-tor-routing.sh` if needed to match your network:

```bash
# Default configuration
TUN_INTERFACE="tun0"
WAN_INTERFACE="eth0"
VPN_NETWORK="10.8.0.0/24"
TOR_CLIENT_IP="10.8.0.100"
```

### 4.3: Apply Routing Rules

```bash
/etc/openvpn/setup-tor-routing.sh
```

Expected output:
```
Starting Tor VPN routing setup...
Enabling IP forwarding...
Removing old Tor routing rules (if any)...
Adding Tor routing rules...
Checking MASQUERADE rule...
Tor VPN routing setup completed successfully!
```

### 4.4: Verify iptables Rules

```bash
iptables -t nat -L -n -v
```

You should see:
- DNAT rules for 10.8.0.100 -> Tor ports (5353, 9040)
- MASQUERADE rule for 10.8.0.0/24

## Step 5: Configure Systemd Service

### 5.1: Copy Service File

```bash
cp configs/tor-vpn-routing.service /etc/systemd/system/
```

### 5.2: Enable Service

```bash
systemctl daemon-reload
systemctl enable tor-vpn-routing.service
```

### 5.3: Verify Service

```bash
systemctl status tor-vpn-routing.service
```

## Step 6: Save iptables Rules

Make rules persistent across reboots:

```bash
iptables-save > /etc/iptables/rules.v4
```

## Step 7: Enable IP Forwarding Permanently

Edit `/etc/sysctl.conf`:

```bash
nano /etc/sysctl.conf
```

Add or uncomment:

```
net.ipv4.ip_forward=1
```

Apply:

```bash
sysctl -p
```

## Step 8: Create Client Configurations

### 8.1: Tor Client (tor.ovpn)

Use the example from `examples/tor.ovpn.example`:

- Client certificate must have `CN=tor`
- Will route through Tor network
- IP will be 10.8.0.100

### 8.2: Direct Client (vpn.ovpn)

Use the example from `examples/vpn.ovpn.example`:

- Client certificate can have any CN except "tor" (e.g., `CN=vpn`)
- Will use direct internet connection
- IP will be assigned from pool (e.g., 10.8.0.2)

## Step 9: Testing

### 9.1: Test Tor Client

```bash
# Connect with tor.ovpn
openvpn --config tor.ovpn

# In another terminal, check IP
curl https://check.torproject.org/api/ip
```

Expected: `{"IsTor":true,"IP":"XXX.XXX.XXX.XXX"}`

### 9.2: Test Direct Client

```bash
# Connect with vpn.ovpn
openvpn --config vpn.ovpn

# In another terminal, check IP
curl https://check.torproject.org/api/ip
```

Expected: `{"IsTor":false,"IP":"YOUR_SERVER_IP"}`

## Step 10: SSH Tunnel Setup (Optional)

### 10.1: Create SSH Tunnel

**Linux/Mac:**

```bash
ssh -f -N -L 8443:127.0.0.1:443 -p 22 user@YOUR_SERVER_IP
```

**Windows (PowerShell):**

```powershell
plink.exe -ssh -2 -P 22 -N -l USERNAME -pw PASSWORD -L 8443:127.0.0.1:443 YOUR_SERVER_IP
```

### 10.2: Modify Client Config

Change remote line in your .ovpn file:

```
# From:
remote YOUR_SERVER_IP 443

# To:
remote 127.0.0.1 8443
```

### 10.3: Test SSH Tunnel Connection

```bash
openvpn --config tor.ovpn  # or vpn.ovpn
```

Run stability test:

```bash
for i in {1..10}; do
  echo "Test $i: $(curl -s https://check.torproject.org/api/ip)"
  sleep 3
done
```

All 10 tests should succeed without reconnections.

## Verification Checklist

- [ ] Tor service is running and listening on 10.8.0.1:9040 and 10.8.0.1:5353
- [ ] OpenVPN server is running
- [ ] Client-Config-Dir is configured
- [ ] `/etc/openvpn/ccd/tor` file exists
- [ ] Routing script executed without errors
- [ ] iptables shows both DNAT and MASQUERADE rules
- [ ] Systemd service is enabled
- [ ] IP forwarding is enabled
- [ ] tor.ovpn routes through Tor
- [ ] vpn.ovpn uses direct connection
- [ ] SSH tunnel connections are stable

## Troubleshooting

If you encounter issues, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Next Steps

- Configure additional clients
- Set up monitoring
- Review security settings
- Test failover scenarios
