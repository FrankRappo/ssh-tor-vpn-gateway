# Troubleshooting Guide

Common issues and their solutions for OpenVPN over SSH with Tor routing.

## Connection Drops Every 3-5 Seconds

### Symptoms

- Client log shows: `Connection reset, restarting [0]`
- Client log shows: `SIGUSR1[soft,connection-reset] received, process restarting`
- Connection establishes, works briefly, then drops
- Happens repeatedly every 3-5 seconds
- More common with SSH tunnel connections

### Root Cause

The routing script is using `iptables -t nat -F` which **deletes ALL NAT rules**, including the critical MASQUERADE rule needed for VPN to work.

### Diagnosis

Check your NAT rules:

```bash
iptables -t nat -L -n -v
```

If you see DNAT rules for Tor but **NO MASQUERADE rule**, this is your problem:

```bash
# Missing MASQUERADE - THIS IS WRONG
Chain POSTROUTING (policy ACCEPT)
target     prot opt source               destination
# (empty or missing MASQUERADE for 10.8.0.0/24)
```

### Solution

Use our routing script from `scripts/setup-tor-routing.sh` which:

1. Uses `-D` to delete specific rules instead of `-F`
2. Uses `-C` to check if MASQUERADE exists before adding

**Wrong approach:**
```bash
iptables -t nat -F  # ❌ Deletes EVERYTHING
```

**Correct approach:**
```bash
# Delete only specific Tor rules
iptables -t nat -D PREROUTING -i tun0 -p udp --dport 53 -s 10.8.0.100 -j DNAT --to-destination 10.8.0.1:5353 2>/dev/null || true
iptables -t nat -D PREROUTING -i tun0 -p tcp -s 10.8.0.100 -j DNAT --to-destination 10.8.0.1:9040 2>/dev/null || true

# Check and add MASQUERADE if missing
iptables -t nat -C POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
```

### Verification

After running our script, verify both rule types exist:

```bash
iptables -t nat -L -n -v | grep -E "10.8.0"
```

Should show:
```
DNAT       udp  --  tun0   *   10.8.0.100   0.0.0.0/0   udp dpt:53 to:10.8.0.1:5353
DNAT       tcp  --  tun0   *   10.8.0.100   0.0.0.0/0   to:10.8.0.1:9040
MASQUERADE all  --  *      eth0 10.8.0.0/24  0.0.0.0/0
```

---

## Multiple Clients Kicking Each Other Off

### Symptoms

- Server log: `MULTI: new connection by client 'vpn' will cause previous active sessions by this client to be dropped`
- Two clients can't connect simultaneously with same credentials
- Each connection kicks the other one off
- Happens every few seconds when both try to connect

### Root Cause

Multiple clients are using the same certificate (same CN). OpenVPN server won't allow duplicate connections by default.

### Diagnosis

Check server logs:

```bash
journalctl -u openvpn@server | grep "MULTI"
```

Look for:
```
MULTI: new connection by client 'vpn' will cause previous active sessions by this client to be dropped
```

Check connected clients:

```bash
cat /var/log/openvpn/status.log
```

### Solution Option 1: Separate Certificates (Recommended)

Create unique certificates for each client:

```bash
# For each client
cd /path/to/easy-rsa
./easyrsa build-client-full client1 nopass
./easyrsa build-client-full client2 nopass
```

### Solution Option 2: Allow Duplicate CN (Less Secure)

Edit `/etc/openvpn/server.conf`:

```bash
duplicate-cn
```

Restart OpenVPN:

```bash
systemctl restart openvpn@server
```

**Warning**: This allows multiple clients with same credentials to connect simultaneously. Not recommended for production.

---

## Tor Not Working

### Symptoms

- Tor client shows `{"IsTor":false}` instead of `{"IsTor":true}`
- Direct client and Tor client show same IP
- Connection works but doesn't route through Tor

### Diagnosis

**Check Tor service status:**

```bash
systemctl status tor
```

**Check Tor is listening on correct ports:**

```bash
ss -tlnp | grep tor
```

Expected:
```
LISTEN 0   4096   10.8.0.1:9040   0.0.0.0:*   users:(("tor",pid=XXX))
LISTEN 0   4096   10.8.0.1:5353   0.0.0.0:*   users:(("tor",pid=XXX))
```

**Check Tor logs:**

```bash
journalctl -u tor --since today
```

### Solution 1: Tor Not Listening on VPN Gateway

Edit `/etc/tor/torrc`:

```bash
# Wrong
DNSPort 5353
TransPort 9040

# Correct - Must specify VPN gateway IP
DNSPort 10.8.0.1:5353
TransPort 10.8.0.1:9040
```

Restart:

```bash
systemctl restart tor
```

### Solution 2: Wrong Client IP

Check client is getting 10.8.0.100:

```bash
cat /var/log/openvpn/status.log | grep tor
```

Should show:
```
tor,127.0.0.1:XXXXX,XXXX,XXXX,2025-XX-XX XX:XX:XX
10.8.0.100,tor,127.0.0.1:XXXXX,2025-XX-XX XX:XX:XX
```

If client gets different IP, check:
- `/etc/openvpn/ccd/tor` exists
- Filename matches CN in certificate
- OpenVPN server config has `client-config-dir /etc/openvpn/ccd`

### Solution 3: iptables Rules Missing

Check NAT rules:

```bash
iptables -t nat -L -n -v | grep 10.8.0.100
```

Should show DNAT rules. If missing, run:

```bash
/etc/openvpn/setup-tor-routing.sh
```

---

## SSH Tunnel Issues

### Symptoms

- Can't connect when using `remote 127.0.0.1 8443`
- "Connection refused" errors
- SSH tunnel works but VPN doesn't

### Diagnosis

**Check SSH tunnel is running:**

Linux/Mac:
```bash
ps aux | grep "ssh.*8443"
```

Windows:
```powershell
tasklist | findstr plink
```

**Test tunnel connectivity:**

```bash
telnet 127.0.0.1 8443
```

Should connect (then Ctrl+C to exit).

**Check tunnel is forwarding:**

```bash
# On client machine
netstat -an | grep 8443
```

Should show:
```
tcp    0      0 127.0.0.1:8443    0.0.0.0:*    LISTEN
```

### Solution 1: Tunnel Not Started

**Linux/Mac:**

```bash
ssh -f -N -L 8443:127.0.0.1:443 -p 22 user@SERVER_IP
```

**Windows:**

```cmd
plink.exe -ssh -2 -P 22 -N -l USERNAME -pw PASSWORD -L 8443:127.0.0.1:443 SERVER_IP
```

### Solution 2: Port Already in Use

Kill existing process using port 8443:

**Linux/Mac:**

```bash
sudo lsof -ti:8443 | xargs kill -9
```

**Windows:**

```powershell
Get-Process -Id (Get-NetTCPConnection -LocalPort 8443).OwningProcess | Stop-Process -Force
```

### Solution 3: Firewall Blocking

**Linux:**

```bash
sudo ufw allow 8443/tcp
```

**Windows:**

Temporarily disable firewall for testing or add rule.

---

## IP Forwarding Not Working

### Symptoms

- VPN connects but no internet
- Can ping VPN gateway (10.8.0.1) but nothing else
- Works after reboot but stops later

### Diagnosis

Check IP forwarding:

```bash
cat /proc/sys/net/ipv4/ip_forward
```

Should return `1`. If it returns `0`, forwarding is disabled.

### Solution

**Temporary (until reboot):**

```bash
echo 1 > /proc/sys/net/ipv4/ip_forward
```

**Permanent:**

Edit `/etc/sysctl.conf`:

```bash
net.ipv4.ip_forward=1
```

Apply:

```bash
sysctl -p
```

---

## DNS Not Working

### Symptoms

- Can ping IP addresses but can't resolve domain names
- `nslookup google.com` fails
- `curl http://1.1.1.1` works but `curl http://google.com` doesn't

### Diagnosis

**Check DNS settings in client:**

```bash
cat /etc/resolv.conf
```

**Test DNS resolution:**

```bash
nslookup google.com
```

**For Tor clients, check Tor DNS port:**

```bash
ss -tlnp | grep 5353
```

### Solution

**For direct VPN clients:**

Edit server.conf to push DNS:

```bash
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 1.0.0.1"
```

Restart OpenVPN server.

**For Tor clients:**

Ensure Tor DNS is running:

```bash
systemctl restart tor
ss -tlnp | grep 5353
```

Should show Tor listening on `10.8.0.1:5353`.

---

## Connection Timeout

### Symptoms

- Client hangs at "Attempting to establish TCP connection"
- Times out after 60 seconds
- Never reaches "Initialization Sequence Completed"

### Diagnosis

**Check OpenVPN is listening:**

```bash
ss -tlnp | grep 443
```

**Test connectivity:**

```bash
telnet SERVER_IP 443
```

**Check firewall:**

```bash
iptables -L -n | grep 443
```

### Solution

**Open firewall port:**

```bash
ufw allow 443/tcp
```

Or add iptables rule:

```bash
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables-save > /etc/iptables/rules.v4
```

**Check OpenVPN is running:**

```bash
systemctl status openvpn@server
systemctl start openvpn@server
```

---

## Performance Issues

### Symptoms

- Very slow speeds through Tor
- High latency
- Frequent timeouts

### Diagnosis

This is **expected behavior** for Tor connections. Tor routes through multiple relays globally, which adds significant latency.

### Expected Performance

- **Tor client**: 1-5 Mbps, 500-2000ms latency
- **Direct client**: Full server bandwidth, 10-50ms latency

### Solution

If you need better performance:

1. Use direct VPN (vpn.ovpn) for performance-critical tasks
2. Use Tor (tor.ovpn) only when anonymity is required
3. Consider using Tor bridges for better reliability

---

## Logs and Debugging

### OpenVPN Server Logs

```bash
journalctl -u openvpn@server --since today -f
```

### OpenVPN Client Logs

```bash
openvpn --config client.ovpn --verb 5
```

### Tor Logs

```bash
journalctl -u tor --since today -f
```

### iptables Rules

```bash
# NAT table (routing rules)
iptables -t nat -L -n -v

# Filter table (firewall rules)
iptables -L -n -v
```

### Connection Status

```bash
# Active VPN clients
cat /var/log/openvpn/status.log

# Network connections
ss -tunap | grep openvpn
```

---

## Getting Help

If you're still stuck:

1. Check all logs above
2. Verify each step in [INSTALLATION.md](INSTALLATION.md)
3. Search existing GitHub issues
4. Open a new issue with:
   - Exact error messages
   - Relevant log excerpts
   - Your configuration (without sensitive data)
   - Steps to reproduce

---

## Quick Diagnostic Script

Save this as `diagnose.sh`:

```bash
#!/bin/bash
echo "=== IP Forwarding ==="
cat /proc/sys/net/ipv4/ip_forward

echo -e "\n=== Tor Status ==="
systemctl status tor --no-pager | head -5

echo -e "\n=== Tor Ports ==="
ss -tlnp | grep tor

echo -e "\n=== OpenVPN Status ==="
systemctl status openvpn@server --no-pager | head -5

echo -e "\n=== NAT Rules ==="
iptables -t nat -L -n | grep -E "(Chain|10.8.0)"

echo -e "\n=== Active VPN Clients ==="
cat /var/log/openvpn/status.log | grep -E "(CLIENT LIST|Common Name|^[0-9])"

echo -e "\n=== Recent OpenVPN Errors ==="
journalctl -u openvpn@server --since "10 min ago" | grep -i error | tail -5
```

Run with:

```bash
chmod +x diagnose.sh
./diagnose.sh
```
