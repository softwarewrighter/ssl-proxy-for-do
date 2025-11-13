# Quick Start Guide

Get SSL up and running in 5 steps.

## Prerequisites

- [ ] DigitalOcean droplet with Docker
- [ ] Domain: `codingtech.info`
- [ ] DO Container Registry: `crudibase-registry`
- [ ] `doctl` installed on Mac

## Step 1: DNS Setup (DigitalOcean Web UI)

1. Go to **Networking** → **Domains** → `codingtech.info`
2. Create A records:
   - `crudibase` → YOUR_DROPLET_IP
   - `cruditrack` → YOUR_DROPLET_IP
3. Wait 5-10 minutes for DNS propagation

## Step 2: Build & Push (Mac)

```bash
cd /Users/mike/github/softwarewrighter/ssl-proxy-for-do

# Configure
cp .env.example .env
nano .env  # Set your EMAIL

# Build and push
doctl registry login
./scripts/build-and-push.sh
```

## Step 3: Firewall (DigitalOcean Web UI)

1. Go to **Networking** → **Firewalls**
2. Create firewall with:
   - Allow port 22 (SSH)
   - Allow port 80 (HTTP)
   - Allow port 443 (HTTPS)
3. Apply to your droplet

## Step 4: Deploy Apps (Droplet)

```bash
ssh root@YOUR_DROPLET_IP

# Authenticate
doctl auth init
doctl registry login

# Deploy applications first
cd /opt/crudibase && docker compose up -d
cd /opt/cruditrack && docker compose up -d

# Verify running
docker ps
```

## Step 5: Deploy SSL Proxy (Droplet)

```bash
# Create directory
mkdir -p /opt/ssl-proxy
cd /opt/ssl-proxy

# Create docker-compose.prod.yml
cat > docker-compose.prod.yml << 'EOF'
version: '3.8'

services:
  ssl-proxy:
    image: registry.digitalocean.com/crudibase-registry/ssl-proxy:latest
    container_name: ssl-proxy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    environment:
      - DOMAIN=codingtech.info
      - EMAIL=your-email@codingtech.info  # CHANGE THIS
      - STAGING=false
      - ENABLE_CRUDIBASE=true
      - CRUDIBASE_BACKEND_HOST=crudibase-backend
      - CRUDIBASE_BACKEND_PORT=3001
      - CRUDIBASE_FRONTEND_HOST=crudibase-frontend
      - CRUDIBASE_FRONTEND_PORT=3000
      - ENABLE_CRUDITRACK=true
      - CRUDITRACK_BACKEND_HOST=cruditrack-backend
      - CRUDITRACK_BACKEND_PORT=3101
      - CRUDITRACK_FRONTEND_HOST=cruditrack-frontend
      - CRUDITRACK_FRONTEND_PORT=3100
    volumes:
      - letsencrypt:/etc/letsencrypt
      - certbot-www:/var/www/certbot
      - ./logs:/var/log/nginx
    networks:
      - crudibase-network
      - cruditrack-network

volumes:
  letsencrypt:
  certbot-www:

networks:
  crudibase-network:
    external: true
  cruditrack-network:
    external: true
EOF

# Update email
nano docker-compose.prod.yml

# Deploy
docker pull registry.digitalocean.com/crudibase-registry/ssl-proxy:latest
docker compose -f docker-compose.prod.yml up -d

# Watch logs
docker compose -f docker-compose.prod.yml logs -f
```

## Verify

```bash
# Check certificates
docker exec ssl-proxy certbot certificates

# Test endpoints
curl -I https://crudibase.codingtech.info
curl -I https://cruditrack.codingtech.info

# Visit in browser
# https://crudibase.codingtech.info
# https://cruditrack.codingtech.info
```

## ⚠️ IMPORTANT: Secure Application Ports

Your apps are now accessible via HTTPS, but they're still exposed on direct ports (e.g., `http://YOUR_IP:3000`). This is a **security risk**!

**Fix immediately**:

```bash
# Edit application docker-compose files to remove port mappings
cd /opt/crudibase
nano docker-compose.yml
# Comment out or remove all "ports:" sections

cd /opt/cruditrack
nano docker-compose.yml
# Comment out or remove all "ports:" sections

# Restart applications
cd /opt/crudibase && docker compose down && docker compose up -d
cd /opt/cruditrack && docker compose down && docker compose up -d

# Verify ports are no longer accessible
curl -m 5 http://YOUR_DROPLET_IP:3000 || echo "✅ Port 3000 secured"
curl -m 5 http://YOUR_DROPLET_IP:3100 || echo "✅ Port 3100 secured"

# Verify HTTPS still works
curl -I https://crudibase.codingtech.info
```

**See [SECURITY-HARDENING.md](docs/SECURITY-HARDENING.md) for complete security guide.**

## Troubleshooting

**DNS not resolving?**
```bash
dig crudibase.codingtech.info +short
# Wait 5-10 minutes if empty
```

**Certificate failed?**
```bash
# Use staging mode for testing
# Edit docker-compose.prod.yml: STAGING=true
docker compose -f docker-compose.prod.yml up -d
```

**502 Error?**
```bash
# Check apps are running
docker ps | grep crudibase
docker ps | grep cruditrack
```

## Full Documentation

- [README.md](README.md) - Complete project documentation
- [DEPLOYMENT-WORKFLOW.md](DEPLOYMENT-WORKFLOW.md) - Detailed workflow
- [docs/DO-SETUP-GUIDE.md](docs/DO-SETUP-GUIDE.md) - DigitalOcean manual steps
- [PROJECT-SUMMARY.md](PROJECT-SUMMARY.md) - Architecture overview

## Support

Check logs: `docker compose -f docker-compose.prod.yml logs ssl-proxy`

That's it! Your apps should now be served with SSL at:
- ✅ https://crudibase.codingtech.info
- ✅ https://cruditrack.codingtech.info
