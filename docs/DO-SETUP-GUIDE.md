# DigitalOcean Setup Guide - Manual Steps

This document outlines the manual steps you need to perform in the DigitalOcean web UI to set up SSL for your subdomains.

## Table of Contents

1. [DNS Configuration](#dns-configuration)
2. [Container Registry Setup](#container-registry-setup)
3. [Droplet Preparation](#droplet-preparation)
4. [Firewall Configuration](#firewall-configuration)
5. [Deployment](#deployment)
6. [Verification](#verification)
7. [Troubleshooting](#troubleshooting)

---

## DNS Configuration

You need to configure DNS A records to point your subdomains to your droplet's IP address.

### Steps in DigitalOcean Web UI

1. **Navigate to Networking**
   - Log in to DigitalOcean
   - Click **Networking** in the left sidebar
   - Select your domain: `codingtech.info`

2. **Create A Records**

   Add the following A records (one at a time):

   | Type | Hostname    | Value              | TTL  |
   |------|-------------|--------------------|------|
   | A    | crudibase   | YOUR_DROPLET_IP    | 3600 |
   | A    | cruditrack  | YOUR_DROPLET_IP    | 3600 |

   **For each record:**
   - Click **Add Record** button
   - Select **A** as the record type
   - Enter the hostname (e.g., `crudibase`)
   - Enter your droplet's IP address
   - Leave TTL at 3600 (default)
   - Click **Create Record**

3. **Verify DNS Records**

   After creating the records, verify them from your local machine:

   ```bash
   # Check crudibase subdomain
   dig crudibase.codingtech.info +short

   # Check cruditrack subdomain
   dig cruditrack.codingtech.info +short
   ```

   Both should return your droplet's IP address. DNS propagation can take a few minutes.

---

## Container Registry Setup

The SSL proxy image will be stored in your DigitalOcean Container Registry.

### Steps in DigitalOcean Web UI

1. **Verify Registry Exists**
   - Click **Container Registry** in the left sidebar
   - Confirm you see: `crudibase-registry`
   - If it doesn't exist, click **Create Registry** and name it `crudibase-registry`

2. **Note the Registry URL**
   - The registry URL should be: `registry.digitalocean.com/crudibase-registry`
   - This is already configured in the build scripts

3. **Generate API Token (if needed)**

   If you haven't already authenticated `doctl`:
   - Click **API** in the left sidebar
   - Click **Generate New Token**
   - Name it something like "ssl-proxy-deploy"
   - Check **Read** and **Write** scopes
   - Click **Generate Token**
   - Copy the token (you'll need it for `doctl auth init`)

---

## Droplet Preparation

Ensure your droplet is ready for deployment.

### Prerequisites Check

SSH into your droplet and verify:

```bash
# SSH to your droplet
ssh root@YOUR_DROPLET_IP

# Verify Docker is installed
docker --version

# Verify Docker Compose is installed
docker compose version

# Verify doctl is installed (if not, install it)
doctl version

# If doctl is not installed:
cd /tmp
wget https://github.com/digitalocean/doctl/releases/download/v1.104.0/doctl-1.104.0-linux-amd64.tar.gz
tar xf doctl-1.104.0-linux-amd64.tar.gz
mv doctl /usr/local/bin
```

### Authenticate Docker with Registry

```bash
# Initialize doctl authentication
doctl auth init
# Enter your API token when prompted

# Login to container registry
doctl registry login
```

---

## Firewall Configuration

Configure the firewall to allow HTTP (80) and HTTPS (443) traffic.

### Option 1: Using DigitalOcean Cloud Firewall (Recommended)

1. **Navigate to Networking**
   - Click **Networking** → **Firewalls**
   - Click **Create Firewall**

2. **Configure Firewall Rules**

   **Name:** `web-ssl-firewall`

   **Inbound Rules:**
   | Type  | Protocol | Port Range | Sources           |
   |-------|----------|------------|-------------------|
   | HTTP  | TCP      | 80         | All IPv4, All IPv6 |
   | HTTPS | TCP      | 443        | All IPv4, All IPv6 |
   | SSH   | TCP      | 22         | Your IP (recommended) |

   **Outbound Rules:**
   - Allow all outbound traffic (default)

3. **Apply to Droplet**
   - Under "Apply to Droplets", select your droplet
   - Click **Create Firewall**

### Option 2: Using UFW on Droplet

If you prefer to use UFW directly on the droplet:

```bash
# SSH to your droplet
ssh root@YOUR_DROPLET_IP

# Allow SSH (important - do this first!)
ufw allow 22/tcp

# Allow HTTP and HTTPS
ufw allow 80/tcp
ufw allow 443/tcp

# Enable firewall
ufw enable

# Verify status
ufw status
```

---

## Deployment

Now you're ready to deploy the SSL proxy and your applications.

### Step 1: Build and Push SSL Proxy Image (From Your Mac)

```bash
# Navigate to ssl-proxy-for-do directory
cd /Users/mike/github/softwarewrighter/ssl-proxy-for-do

# Copy and configure environment
cp .env.example .env
# Edit .env with your email address

# Build and push to registry
./scripts/build-and-push.sh
```

### Step 2: Deploy on Droplet

```bash
# SSH to droplet
ssh root@YOUR_DROPLET_IP

# Create deployment directory
mkdir -p /opt/ssl-proxy
cd /opt/ssl-proxy

# Clone or copy the repository
# Option 1: Clone from git (if you pushed it)
git clone YOUR_REPO_URL .

# Option 2: Create files manually
# Create docker-compose.yml for production
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
      - EMAIL=YOUR_EMAIL@codingtech.info
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

# Pull the image
docker pull registry.digitalocean.com/crudibase-registry/ssl-proxy:latest

# Start the SSL proxy (IMPORTANT: Make sure other apps are running first!)
docker compose -f docker-compose.prod.yml up -d

# Check logs
docker compose -f docker-compose.prod.yml logs -f ssl-proxy
```

### Step 3: Deploy Application Services

Make sure your application services (crudibase and cruditrack) are running:

```bash
# For Crudibase
cd /opt/crudibase
docker compose -f docker-compose.prod.yml up -d

# For Cruditrack
cd /opt/cruditrack
docker compose -f docker-compose.prod.yml up -d

# Verify all services are running
docker ps
```

---

## Verification

Verify that everything is working correctly.

### 1. Check SSL Certificates

```bash
# SSH to droplet
ssh root@YOUR_DROPLET_IP

# Check certificate status
docker exec ssl-proxy certbot certificates

# You should see certificates for:
# - crudibase.codingtech.info
# - cruditrack.codingtech.info
```

### 2. Test HTTPS Endpoints

From your local machine:

```bash
# Test Crudibase
curl -I https://crudibase.codingtech.info
# Should return 200 OK with SSL

# Test Cruditrack
curl -I https://cruditrack.codingtech.info
# Should return 200 OK with SSL

# Test API endpoints
curl https://crudibase.codingtech.info/api/health
curl https://cruditrack.codingtech.info/api/health
```

### 3. Browser Testing

Visit these URLs in your browser:
- https://crudibase.codingtech.info
- https://cruditrack.codingtech.info

Check that:
- ✅ Pages load correctly
- ✅ SSL certificate is valid (lock icon in address bar)
- ✅ No mixed content warnings
- ✅ API calls work correctly

---

## Troubleshooting

### DNS Not Resolving

**Problem:** `dig crudibase.codingtech.info` doesn't return your droplet IP

**Solution:**
1. Verify A records in DO Networking panel
2. Wait 5-10 minutes for DNS propagation
3. Clear your DNS cache: `sudo dscacheutil -flushcache` (macOS)

### Certificate Issuance Failed

**Problem:** Let's Encrypt certificate generation failed

**Solutions:**

1. **Check DNS is propagating:**
   ```bash
   dig crudibase.codingtech.info +short
   # Must return your droplet IP
   ```

2. **Check port 80 is accessible:**
   ```bash
   curl http://crudibase.codingtech.info/.well-known/acme-challenge/test
   ```

3. **Use staging mode for testing:**
   ```bash
   # Edit docker-compose.prod.yml
   # Set STAGING=true
   docker compose -f docker-compose.prod.yml up -d
   ```

4. **Check rate limits:**
   - Let's Encrypt has rate limits (5 certs per domain per week)
   - Use staging mode if testing repeatedly

### Services Can't Connect

**Problem:** nginx returns 502 Bad Gateway

**Solutions:**

1. **Verify backend services are running:**
   ```bash
   docker ps | grep crudibase
   docker ps | grep cruditrack
   ```

2. **Verify networks exist:**
   ```bash
   docker network ls | grep crudibase
   docker network ls | grep cruditrack
   ```

3. **Check service names match:**
   - Service names in docker-compose must match proxy environment variables
   - Default: `crudibase-backend`, `crudibase-frontend`, etc.

4. **Check logs:**
   ```bash
   docker compose -f docker-compose.prod.yml logs ssl-proxy
   ```

### HTTP Redirects Not Working

**Problem:** HTTP doesn't redirect to HTTPS

**Solution:**
1. Check nginx configuration was generated:
   ```bash
   docker exec ssl-proxy ls -la /etc/nginx/conf.d/
   ```

2. Test nginx config:
   ```bash
   docker exec ssl-proxy nginx -t
   ```

3. Reload nginx:
   ```bash
   docker exec ssl-proxy nginx -s reload
   ```

---

## Certificate Renewal

Certificates automatically renew via cron job. The renewal script runs twice daily.

### Manual Renewal

If you need to manually renew:

```bash
docker exec ssl-proxy /usr/local/bin/renew-certificates.sh
```

### Check Renewal Logs

```bash
docker exec ssl-proxy cat /var/log/letsencrypt/renew.log
```

---

## Summary Checklist

- [ ] DNS A records created for `crudibase` and `cruditrack`
- [ ] DNS records verified with `dig` command
- [ ] Container registry exists: `crudibase-registry`
- [ ] Droplet has Docker and Docker Compose installed
- [ ] `doctl` authenticated and logged into registry
- [ ] Firewall allows ports 22, 80, and 443
- [ ] SSL proxy image built and pushed from Mac
- [ ] Application services deployed and running
- [ ] SSL proxy deployed and running
- [ ] SSL certificates obtained successfully
- [ ] HTTPS endpoints accessible in browser
- [ ] No certificate warnings in browser

---

## Support

If you encounter issues not covered here:

1. Check nginx logs: `docker compose -f docker-compose.prod.yml logs ssl-proxy`
2. Check certificate logs: `docker exec ssl-proxy cat /var/log/letsencrypt/letsencrypt.log`
3. Verify service connectivity: `docker exec ssl-proxy ping crudibase-backend`
4. Test nginx config: `docker exec ssl-proxy nginx -t`
