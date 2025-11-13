# Deployment Workflow

Complete workflow from Mac to DigitalOcean droplet with SSL.

## Quick Overview

```
┌─────────────┐         ┌──────────────────┐         ┌─────────────────┐
│   Mac/Dev   │  Build  │  DO Container    │  Pull   │   DO Droplet    │
│   Machine   │ ──────> │    Registry      │ ──────> │  (Production)   │
│             │         │                  │         │                 │
└─────────────┘         └──────────────────┘         └─────────────────┘
      │                                                       │
      │ 1. Build AMD64 image                                 │ 3. Pull image
      │ 2. Push to registry                                  │ 4. Deploy with compose
      │                                                       │ 5. Get SSL certs
      │                                                       │ 6. Serve HTTPS
      └───────────────────────────────────────────────────────┘
```

## Prerequisites Checklist

### On Mac (Local Development)

- [ ] Docker Desktop installed and running
- [ ] `doctl` CLI installed (`brew install doctl`)
- [ ] Authenticated with DigitalOcean (`doctl auth init`)
- [ ] Repository cloned locally

### On DigitalOcean

- [ ] Droplet created with Docker installed
- [ ] Domain name (`codingtech.info`) pointing to droplet
- [ ] DNS A records created:
  - `crudibase.codingtech.info` → Droplet IP
  - `cruditrack.codingtech.info` → Droplet IP
- [ ] Container Registry created (`crudibase-registry`)
- [ ] Firewall configured (ports 22, 80, 443)

## Step-by-Step Deployment

### Phase 1: Build and Push (Mac)

```bash
# 1. Navigate to project
cd /Users/mike/github/softwarewrighter/ssl-proxy-for-do

# 2. Configure environment
cp .env.example .env
nano .env  # Update EMAIL address

# 3. Login to DO registry
doctl registry login

# 4. Build and push image (takes ~2-3 minutes)
./scripts/build-and-push.sh

# ✅ Expected output:
# "Successfully built and pushed: registry.digitalocean.com/crudibase-registry/ssl-proxy:latest"
```

### Phase 2: Prepare Applications (Droplet)

```bash
# 1. SSH to droplet
ssh root@YOUR_DROPLET_IP

# 2. Authenticate with DO registry
doctl auth init  # Enter your API token
doctl registry login

# 3. Deploy Crudibase
cd /opt/crudibase
docker compose up -d
docker ps | grep crudibase  # Verify running

# 4. Deploy Cruditrack
cd /opt/cruditrack
docker compose up -d
docker ps | grep cruditrack  # Verify running

# ✅ Expected: 4 containers running (2 frontend, 2 backend)
```

### Phase 3: Deploy SSL Proxy (Droplet)

```bash
# 1. Create SSL proxy directory
mkdir -p /opt/ssl-proxy
cd /opt/ssl-proxy

# 2. Create production compose file
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
      - EMAIL=your-email@codingtech.info  # CHANGE THIS!
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

# 3. Update email in the file
nano docker-compose.prod.yml  # Change EMAIL value

# 4. Pull image
docker pull registry.digitalocean.com/crudibase-registry/ssl-proxy:latest

# 5. Start SSL proxy
docker compose -f docker-compose.prod.yml up -d

# 6. Watch logs (wait for certificate generation)
docker compose -f docker-compose.prod.yml logs -f ssl-proxy

# ✅ Expected: See "Successfully obtained certificate" messages
# Press Ctrl+C when you see "SSL Proxy Started"
```

### Phase 4: Verify Deployment

```bash
# On droplet, check all containers
docker ps

# ✅ Expected: 5 containers running:
# - ssl-proxy
# - crudibase-frontend
# - crudibase-backend
# - cruditrack-frontend
# - cruditrack-backend

# Check SSL certificates
docker exec ssl-proxy certbot certificates

# ✅ Expected: Shows certificates for both subdomains

# Test from droplet
curl -I https://crudibase.codingtech.info
curl -I https://cruditrack.codingtech.info

# ✅ Expected: HTTP/2 200 responses
```

### Phase 5: Browser Testing

From your local machine, visit:

1. **Crudibase**: https://crudibase.codingtech.info
   - [ ] Page loads correctly
   - [ ] Green lock icon (valid SSL)
   - [ ] No certificate warnings
   - [ ] Application functions normally

2. **Cruditrack**: https://cruditrack.codingtech.info
   - [ ] Page loads correctly
   - [ ] Green lock icon (valid SSL)
   - [ ] No certificate warnings
   - [ ] Application functions normally

## Common Issues & Solutions

### Issue: DNS not resolving

```bash
# Check DNS propagation
dig crudibase.codingtech.info +short
# Should return: YOUR_DROPLET_IP

# If not, wait 5-10 minutes for DNS to propagate
```

### Issue: Certificate generation failed

```bash
# Check logs
docker compose -f docker-compose.prod.yml logs ssl-proxy

# Common causes:
# 1. DNS not propagating yet → Wait and retry
# 2. Port 80 blocked → Check firewall
# 3. Rate limit hit → Use STAGING=true for testing
```

### Issue: 502 Bad Gateway

```bash
# Check if backend services are running
docker ps | grep crudibase
docker ps | grep cruditrack

# Check network connectivity
docker exec ssl-proxy ping crudibase-backend
docker exec ssl-proxy ping cruditrack-backend

# If ping fails, check network configuration
docker network ls
```

### Issue: Build fails on Mac

```bash
# Ensure Docker Desktop is running
docker info

# Ensure buildx is available
docker buildx version

# Try test build first
./scripts/test-build.sh
```

## Updating the Deployment

### Update SSL Proxy Configuration

```bash
# On Mac: Make changes, rebuild, and push
cd /Users/mike/github/softwarewrighter/ssl-proxy-for-do
# Edit files...
./scripts/build-and-push.sh

# On Droplet: Pull and restart
cd /opt/ssl-proxy
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d
```

### Update Applications

```bash
# On Droplet
cd /opt/crudibase
docker compose pull
docker compose up -d

cd /opt/cruditrack
docker compose pull
docker compose up -d

# SSL proxy will automatically route to updated containers
```

## Monitoring

### Check Status

```bash
# All containers
docker ps

# SSL proxy logs
docker compose -f docker-compose.prod.yml logs -f ssl-proxy

# Certificate expiry
docker exec ssl-proxy certbot certificates
```

### Certificate Renewal

Certificates auto-renew via cron (runs twice daily).

Manual renewal:
```bash
docker exec ssl-proxy /usr/local/bin/renew-certificates.sh
```

Check renewal logs:
```bash
docker exec ssl-proxy cat /var/log/letsencrypt/renew.log
```

## Rollback Procedure

### Rollback SSL Proxy

```bash
# On Droplet
cd /opt/ssl-proxy

# Stop current version
docker compose -f docker-compose.prod.yml down

# Use previous image tag
docker pull registry.digitalocean.com/crudibase-registry/ssl-proxy:previous-tag

# Update docker-compose.prod.yml to use previous tag
# Then restart
docker compose -f docker-compose.prod.yml up -d
```

## Security Checklist

- [ ] Firewall configured (only ports 22, 80, 443 open)
- [ ] SSH key authentication enabled (no password auth)
- [ ] SSL certificates obtained from Let's Encrypt
- [ ] HSTS headers enabled
- [ ] Security headers configured (XSS, Frame protection)
- [ ] Secrets stored in .env files (not in git)
- [ ] Registry access limited to authorized users
- [ ] Regular updates applied to droplet

## Performance Optimization

### Enable Caching (Optional)

Add to nginx templates:
```nginx
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=my_cache:10m max_size=1g;
proxy_cache my_cache;
proxy_cache_valid 200 1h;
```

### Monitor Resources

```bash
# On droplet
docker stats

# Check disk usage
df -h

# Check logs size
du -sh /var/lib/docker/containers/*/*-json.log
```

## Backup and Recovery

### Backup SSL Certificates

```bash
# On droplet
docker run --rm \
  -v ssl-proxy_letsencrypt:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/ssl-certs-backup-$(date +%Y%m%d).tar.gz -C /data .
```

### Restore Certificates

```bash
# Extract to volume
docker run --rm \
  -v ssl-proxy_letsencrypt:/data \
  -v $(pwd):/backup \
  alpine sh -c "cd /data && tar xzf /backup/ssl-certs-backup-YYYYMMDD.tar.gz"
```

## Cost Optimization

### Use Smaller Droplet (Optional)

For low-traffic sites:
- Minimum: 1GB RAM, 1 vCPU ($6/month)
- Recommended: 2GB RAM, 1 vCPU ($12/month)

### Registry Cleanup

```bash
# List images
doctl registry repository list-tags crudibase-registry/ssl-proxy

# Delete old tags
doctl registry repository delete-tag crudibase-registry/ssl-proxy old-tag
```

## Support and Documentation

- **Full Documentation**: [README.md](README.md)
- **DO Setup Guide**: [docs/DO-SETUP-GUIDE.md](docs/DO-SETUP-GUIDE.md)
- **Troubleshooting**: See DO Setup Guide
- **SSL Research**: [docs/ssl-research.txt](docs/ssl-research.txt)

## Timeline Estimate

- **Initial Setup**: 30-45 minutes
- **DNS Propagation**: 5-10 minutes
- **Image Build**: 2-3 minutes
- **SSL Certificate Generation**: 2-5 minutes
- **Total First Deployment**: ~1 hour

- **Subsequent Updates**: 5-10 minutes
- **Certificate Renewals**: Automatic (no manual intervention)
