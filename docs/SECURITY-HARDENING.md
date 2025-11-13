# Security Hardening Guide

## Problem: Direct Application Port Access

After deploying the SSL proxy, you may find that applications are still accessible directly via their exposed ports (e.g., `http://your-ip:3000`), bypassing SSL and security controls.

**Security Risk**: This allows:
- Unencrypted HTTP access to sensitive data
- Bypassing of security headers (HSTS, XSS protection, etc.)
- Direct access to application ports from the internet

## Solution 1: Docker Network Isolation (Recommended)

The standard practice is to **remove external port exposure** from application containers and rely solely on Docker networking for communication.

### How It Works

```
Internet → Only ports 80/443 exposed → SSL Proxy Container
                                            ↓ (Docker network)
                                       Application Containers
                                       (No external ports)
```

### Implementation

#### For Crudibase

Edit `/opt/crudibase/docker-compose.yml` and **remove or comment out** the `ports:` sections:

```yaml
services:
  crudibase-frontend:
    # ports:
    #   - "3000:3000"  # REMOVE THIS
    networks:
      - crudibase-network
    # ... rest of config

  crudibase-backend:
    # ports:
    #   - "3001:3001"  # REMOVE THIS
    networks:
      - crudibase-network
    # ... rest of config

networks:
  crudibase-network:
    # This network is how SSL proxy reaches the apps
```

#### For Cruditrack

Edit `/opt/cruditrack/docker-compose.yml` similarly:

```yaml
services:
  cruditrack-frontend:
    # ports:
    #   - "3100:3100"  # REMOVE THIS
    networks:
      - cruditrack-network
    # ... rest of config

  cruditrack-backend:
    # ports:
    #   - "3101:3101"  # REMOVE THIS
    networks:
      - cruditrack-network
    # ... rest of config

networks:
  cruditrack-network:
    # This network is how SSL proxy reaches the apps
```

#### Apply Changes

```bash
# Restart applications with new config
cd /opt/crudibase
docker compose down
docker compose up -d

cd /opt/cruditrack
docker compose down
docker compose up -d

# Restart SSL proxy to reconnect
cd /opt/ssl-proxy
docker compose -f docker-compose.prod.yml restart
```

#### Verify

```bash
# These should now FAIL (ports not exposed):
curl http://YOUR_IP:3000  # Should timeout/refuse
curl http://YOUR_IP:3001  # Should timeout/refuse
curl http://YOUR_IP:3100  # Should timeout/refuse
curl http://YOUR_IP:3101  # Should timeout/refuse

# These should WORK (via SSL proxy):
curl https://crudibase.codingtech.info  # Should work
curl https://cruditrack.codingtech.info  # Should work

# Verify SSL proxy can still reach apps via Docker network:
docker exec ssl-proxy ping crudibase-frontend
docker exec ssl-proxy ping cruditrack-backend
```

---

## Solution 2: Firewall Rules (Defense-in-Depth)

Even with network isolation, add firewall rules as an extra security layer.

### Using UFW (Ubuntu Firewall)

```bash
# Enable UFW
ufw --force enable

# Allow SSH (IMPORTANT: Do this first!)
ufw allow 22/tcp

# Allow HTTP/HTTPS
ufw allow 80/tcp
ufw allow 443/tcp

# Deny application ports from external access
ufw deny 3000/tcp
ufw deny 3001/tcp
ufw deny 3100/tcp
ufw deny 3101/tcp

# Check status
ufw status verbose
```

### Using DigitalOcean Cloud Firewall

1. Go to **Networking** → **Firewalls** in DO web UI
2. Create or edit your firewall
3. **Inbound Rules**:
   - Allow TCP 22 (SSH) from All sources
   - Allow TCP 80 (HTTP) from All sources
   - Allow TCP 443 (HTTPS) from All sources
   - **Do NOT add** rules for 3000, 3001, 3100, 3101
4. Apply firewall to your droplet

**Note**: If using DO Cloud Firewall, you may not need UFW (using both can cause conflicts).

---

## Solution 3: Application Binding (Alternative)

If you need to keep ports exposed (e.g., for local debugging), configure applications to bind only to `localhost`:

### Example: Bind to 127.0.0.1

In your application's docker-compose.yml:

```yaml
services:
  crudibase-frontend:
    ports:
      - "127.0.0.1:3000:3000"  # Only accessible from localhost
    # ... rest of config
```

**Limitation**: This prevents the SSL proxy from reaching the app unless it's also using host networking, which is not recommended.

---

## Recommended Approach

**Use Solution 1 (Docker Network Isolation) + Solution 2 (Firewall)**

This provides defense-in-depth:

1. **Primary defense**: Applications don't expose ports externally
2. **Secondary defense**: Firewall blocks direct access even if ports were accidentally exposed
3. **Only entry point**: SSL proxy on ports 80/443

---

## Complete Security Checklist

After implementing the solutions above:

- [ ] Application ports removed from docker-compose.yml
- [ ] Applications restarted with new configuration
- [ ] Direct port access fails (`curl http://YOUR_IP:3000` times out)
- [ ] HTTPS access works (`curl https://crudibase.codingtech.info` succeeds)
- [ ] SSL proxy can ping application containers
- [ ] Firewall configured (only 22, 80, 443 allowed)
- [ ] Firewall status verified (`ufw status` or DO web UI)
- [ ] SSL certificates valid (check in browser)
- [ ] Security headers present (check with browser DevTools)

---

## Verification Commands

```bash
# 1. Check what ports are listening externally
netstat -tlnp | grep LISTEN

# 2. Test external port access (should fail)
curl -m 5 http://YOUR_DROPLET_IP:3000 || echo "Port 3000 correctly blocked"
curl -m 5 http://YOUR_DROPLET_IP:3001 || echo "Port 3001 correctly blocked"

# 3. Test HTTPS access (should work)
curl -I https://crudibase.codingtech.info
curl -I https://cruditrack.codingtech.info

# 4. Check Docker networks
docker network inspect crudibase-network
docker network inspect cruditrack-network

# 5. Verify SSL proxy connectivity to apps
docker exec ssl-proxy curl -I http://crudibase-frontend:3000
docker exec ssl-proxy curl -I http://crudibase-backend:3001

# 6. Check firewall status
ufw status verbose  # or check DO web UI
```

---

## Troubleshooting

### "502 Bad Gateway" after removing ports

**Cause**: SSL proxy can't reach application containers

**Solution**:
```bash
# Verify networks exist
docker network ls | grep crudibase
docker network ls | grep cruditrack

# Verify SSL proxy is connected to networks
docker inspect ssl-proxy | grep -A 10 Networks

# Verify applications are on the correct networks
docker inspect crudibase-frontend | grep -A 10 Networks

# Restart everything
cd /opt/crudibase && docker compose restart
cd /opt/cruditrack && docker compose restart
cd /opt/ssl-proxy && docker compose -f docker-compose.prod.yml restart
```

### Applications still accessible on ports

**Cause**: Port mappings still in docker-compose.yml

**Solution**:
```bash
# Check current port mappings
docker ps --format "table {{.Names}}\t{{.Ports}}"

# If ports are shown, remove them from docker-compose.yml
# Then recreate containers:
cd /opt/crudibase
docker compose down
docker compose up -d
```

### Can't access from localhost either

**Cause**: This is expected and correct! Applications should only be accessible via HTTPS through the proxy.

**Solution**: If you need local debugging access:
1. SSH into the droplet
2. Use `docker exec` to access containers directly
3. Or temporarily add `127.0.0.1:3000:3000` binding for debugging (remove when done)

---

## Additional Security Measures

### 1. Enable Fail2Ban (Optional)

Protect against brute force attacks:

```bash
apt update && apt install fail2ban
systemctl enable fail2ban
systemctl start fail2ban
```

### 2. Disable Root SSH Login (Recommended)

After setting up a non-root user with sudo:

```bash
# Edit SSH config
nano /etc/ssh/sshd_config

# Change:
PermitRootLogin no

# Restart SSH
systemctl restart sshd
```

### 3. Keep System Updated

```bash
# Set up automatic security updates
apt install unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades
```

### 4. Monitor Certificate Expiry

Let's Encrypt certificates auto-renew, but monitor just in case:

```bash
# Check certificate expiry
docker exec ssl-proxy certbot certificates

# Check renewal logs
docker exec ssl-proxy tail -f /var/log/letsencrypt/renew.log
```

---

## References

- [Docker Network Security Best Practices](https://docs.docker.com/network/network-tutorial-standalone/)
- [DigitalOcean Firewall Documentation](https://docs.digitalocean.com/products/networking/firewalls/)
- [OWASP Docker Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)

---

**Status**: Follow Solution 1 (remove port mappings) + Solution 2 (configure firewall) for production-grade security.
