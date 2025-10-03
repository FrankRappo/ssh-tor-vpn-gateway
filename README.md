# OpenVPN over SSH with Tor Routing

Selective Tor routing for OpenVPN connections with full SSH tunnel support - route specific clients through Tor network while keeping others on direct connection.

## Overview

This project enables **selective Tor routing** for OpenVPN connections with robust SSH tunnel support. It allows you to:

- Route specific VPN clients through the Tor network for anonymity
- Keep other VPN clients on direct connection for better performance
- Connect via SSH tunnels without reconnection issues
- Maintain stable connections in all scenarios

## Features

- ✅ **Selective Routing**: Choose which clients use Tor based on certificate CN
- ✅ **SSH Tunnel Support**: Stable connections over SSH tunnels (no 3-5 second reconnects)
- ✅ **Dual Configuration**: Support for both Tor and direct VPN configs
- ✅ **Automatic Startup**: Systemd service for automatic rule application
- ✅ **No Route Conflicts**: Proper iptables management without breaking existing rules
- ✅ **Cross-Platform**: Works with Windows, Linux, and macOS clients

## Architecture

```
┌──────────────────┐         ┌──────────────────┐
│  Windows Client  │         │   Linux Client   │
│   (tor.ovpn)     │         │    (vpn.ovpn)    │
└────────┬─────────┘         └────────┬─────────┘
         │                            │
         │  SSH Tunnel (Optional)     │
         │  127.0.0.1:8443           │
         │                            │
         └────────────┬───────────────┘
                      │
              ┌───────▼────────┐
              │  OpenVPN       │
              │  Server        │
              │  :443/TCP      │
              └───────┬────────┘
                      │
              ┌───────▼────────┐
              │   iptables     │
              │   Routing      │
              └───────┬────────┘
                      │
         ┌────────────┴────────────┐
         │                         │
  ┌──────▼──────┐         ┌───────▼────────┐
  │ Tor Network │         │ Direct Internet│
  │ (10.8.0.100)│         │  (other IPs)   │
  └─────────────┘         └────────────────┘
```

## Key Problem Solved

**Issue**: Traditional Tor routing scripts use `iptables -t nat -F` which deletes ALL NAT rules, including the critical MASQUERADE rule. This causes VPN connections (especially over SSH tunnels) to reconnect every 3-5 seconds.

**Solution**: Our routing script uses selective rule deletion with `-D` flag and rule checking with `-C` flag, preserving the MASQUERADE rule while updating Tor routing rules.

## Requirements

- Ubuntu 20.04+ (tested on Ubuntu 24.04)
- OpenVPN server installed and configured
- Root access
- Basic knowledge of iptables and networking

## Quick Start

### 1. Install Dependencies

```bash
apt update
apt install -y tor iptables-persistent
```

### 2. Configure Tor

Edit `/etc/tor/torrc`:

```
VirtualAddrNetwork 10.192.0.0/10
AutomapHostsOnResolve 1
DNSPort 10.8.0.1:5353
TransPort 10.8.0.1:9040
```

Restart Tor:

```bash
systemctl restart tor
systemctl enable tor
```

### 3. Configure OpenVPN Client

Create Client-Config-Dir file `/etc/openvpn/ccd/tor`:

```
ifconfig-push 10.8.0.100 255.255.255.0
push "route-gateway 10.8.0.1"
```

**Important**: Your tor client certificate must have `CN=tor`

### 4. Setup Routing Script

Copy the routing script:

```bash
cp scripts/setup-tor-routing.sh /etc/openvpn/
chmod +x /etc/openvpn/setup-tor-routing.sh
```

Apply rules:

```bash
/etc/openvpn/setup-tor-routing.sh
```

### 5. Configure Systemd Service

Copy the service file:

```bash
cp configs/tor-vpn-routing.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable tor-vpn-routing.service
systemctl start tor-vpn-routing.service
```

### 6. Save iptables Rules

```bash
iptables-save > /etc/iptables/rules.v4
```

## Usage

### Direct Connection

Simply connect using your OpenVPN config:

```bash
openvpn --config tor.ovpn
# or
openvpn --config vpn.ovpn
```

### SSH Tunnel Connection

**Windows (using PuTTY plink.exe):**

```cmd
plink.exe -ssh -2 -P 22 -N -l USERNAME -pw PASSWORD -L 8443:127.0.0.1:443 YOUR_SERVER_IP
```

**Linux/Mac:**

```bash
ssh -f -N -L 8443:127.0.0.1:443 -p 22 user@YOUR_SERVER_IP
```

Then modify your OpenVPN config to use the tunnel:

```
remote 127.0.0.1 8443
proto tcp-client
```

### Testing

**Check if using Tor:**

```bash
curl https://check.torproject.org/api/ip
```

Expected outputs:
- Tor client: `{"IsTor":true,"IP":"XXX.XXX.XXX.XXX"}`
- Direct client: `{"IsTor":false,"IP":"YOUR_SERVER_IP"}`

## Configuration Files

### Routing Script: `scripts/setup-tor-routing.sh`

The core routing script that:
- Enables IP forwarding
- Removes old Tor rules gracefully (using `-D`)
- Adds new Tor routing rules
- Preserves the MASQUERADE rule (using `-C` check)

**Key difference from typical scripts:**

```bash
# ❌ WRONG - Deletes ALL NAT rules including MASQUERADE
iptables -t nat -F

# ✅ CORRECT - Deletes only specific Tor rules
iptables -t nat -D PREROUTING -i tun0 -p udp --dport 53 -s 10.8.0.100 -j DNAT --to-destination 10.8.0.1:5353 2>/dev/null
iptables -t nat -D PREROUTING -i tun0 -p tcp -s 10.8.0.100 -j DNAT --to-destination 10.8.0.1:9040 2>/dev/null

# ✅ CORRECT - Checks before adding MASQUERADE
iptables -t nat -C POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
```

### Client Config Dir: `/etc/openvpn/ccd/tor`

Assigns fixed IP to tor clients:

```
ifconfig-push 10.8.0.100 255.255.255.0
push "route-gateway 10.8.0.1"
```

### Tor Config: `/etc/tor/torrc`

```
VirtualAddrNetwork 10.192.0.0/10
AutomapHostsOnResolve 1
DNSPort 10.8.0.1:5353
TransPort 10.8.0.1:9040
```

### Systemd Service: `configs/tor-vpn-routing.service`

Ensures routing rules are applied on system boot.

## Troubleshooting

### Connection Drops Every 3-5 Seconds

**Symptoms:**
- Client shows "Connection reset, restarting"
- `SIGUSR1[soft,connection-reset]` in logs
- Works initially but drops repeatedly

**Cause:**
Using `iptables -t nat -F` which deletes the MASQUERADE rule.

**Solution:**
Use our routing script that properly manages iptables rules.

**Verification:**

```bash
# Check NAT rules
iptables -t nat -L -n -v

# Should see both DNAT and MASQUERADE rules
# DNAT for 10.8.0.100 -> Tor
# MASQUERADE for 10.8.0.0/24 -> Internet
```

### Multiple Clients Kicking Each Other

**Symptoms:**
- Server log: "MULTI: new connection by client 'vpn' will cause previous active sessions to be dropped"
- Clients with same CN disconnect each other

**Cause:**
Multiple clients using the same certificate CN.

**Solution:**
- Create separate certificates for each client
- OR add `duplicate-cn` to OpenVPN server config (less secure)

### Tor Not Working

**Check Tor status:**

```bash
systemctl status tor
journalctl -u tor --since today
```

**Verify Tor ports:**

```bash
ss -tlnp | grep tor
```

Expected output:
```
LISTEN 0   4096   10.8.0.1:9040   0.0.0.0:*   users:(("tor",pid=XXX))
LISTEN 0   4096   10.8.0.1:5353   0.0.0.0:*   users:(("tor",pid=XXX))
```

### SSH Tunnel Not Working

**Check tunnel is active:**

```bash
# Linux/Mac
ps aux | grep "ssh.*8443"

# Windows
tasklist | findstr plink
```

**Test tunnel:**

```bash
telnet 127.0.0.1 8443
```

Should connect to OpenVPN server.

## Testing

### Stability Test (10 iterations)

```bash
for i in {1..10}; do
  echo "Test $i: $(curl -s https://check.torproject.org/api/ip)"
  sleep 3
done
```

**Expected:** All tests should succeed without reconnections.

### Lab Test Results

| Test Scenario | Result | Success Rate | Notes |
|---------------|--------|--------------|-------|
| tor.ovpn direct | ✅ Pass | 100% | Routes through Tor |
| vpn.ovpn direct | ✅ Pass | 100% | Direct connection |
| tor.ovpn via SSH | ✅ Pass | 80% | Occasional Tor timeouts (normal) |
| vpn.ovpn via SSH | ✅ Pass | 100% | Stable, no reconnects |

See [docs/TESTING.md](docs/TESTING.md) for detailed test logs.

## Security Considerations

1. **Certificate Management**: Use separate certificates for tor and non-tor clients
2. **Tor Exit Nodes**: Tor exit nodes can see unencrypted traffic
3. **DNS Leaks**: Configuration routes DNS through Tor for tor clients only
4. **SSH Tunnel Security**: Use strong passwords or key-based authentication
5. **Logging**: Monitor `/var/log/openvpn/` for suspicious activity

## Performance

- **Tor Client**: 1-5 Mbps (Tor network limitation)
- **Direct Client**: Full server bandwidth
- **SSH Tunnel Overhead**: ~5-10% (minimal)

## Documentation

- [Installation Guide](docs/INSTALLATION.md) - Step-by-step setup
- [Configuration Guide](docs/CONFIGURATION.md) - Detailed configuration options
- [Troubleshooting Guide](docs/TROUBLESHOOTING.md) - Common issues and solutions
- [Testing Results](docs/TESTING.md) - Lab test documentation

## Files Structure

```
openvpn-over-ssh-tor/
├── README.md
├── LICENSE
├── scripts/
│   └── setup-tor-routing.sh      # Main routing script
├── configs/
│   ├── tor-vpn-routing.service   # Systemd service
│   ├── torrc.example             # Tor configuration example
│   └── ccd-tor.example           # Client config dir example
├── examples/
│   ├── tor.ovpn.example          # Tor client config
│   └── vpn.ovpn.example          # Direct client config
└── docs/
    ├── INSTALLATION.md
    ├── CONFIGURATION.md
    ├── TROUBLESHOOTING.md
    └── TESTING.md
```

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) file for details

## Support

- 📖 Read the [documentation](docs/)
- 🐛 Open an issue on GitHub
- 💬 Check closed issues for similar problems

## Acknowledgments

- Developed through extensive testing and troubleshooting
- Special thanks to the Tor Project and OpenVPN community
- Inspired by the need for selective anonymity with SSH tunnel support

## Changelog

### Version 1.0.0 (2025-10-03)

- Initial release
- Selective Tor routing for OpenVPN clients
- Full SSH tunnel support without reconnection issues
- Systemd service for automatic startup
- Comprehensive documentation and testing
- Proven stable in lab environment (100% success rate for direct VPN over SSH)
