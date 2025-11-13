# SSL Proxy for DigitalOcean

Nginx-based SSL reverse proxy with automatic Let's Encrypt certificate management for serving multiple Docker Compose applications on DigitalOcean droplets with HTTPS.

## Overview

This project provides a pre-built Docker image that acts as an SSL termination proxy for multiple applications running on the same DigitalOcean droplet. It automatically obtains and renews SSL certificates from Let's Encrypt.

### Features

- 🔒 Automatic SSL certificate generation and renewal
- 🔄 HTTP to HTTPS automatic redirects
- 🎯 Multi-application support (Crudibase, Cruditrack)
- 🚀 AMD64/x86_64 optimized for DigitalOcean droplets
- 📦 Pre-built image pushed to DO Container Registry
- ⚙️ Zero-downtime certificate renewals
- 🛡️ Security headers (HSTS, XSS protection, etc.)
- 📊 Health check endpoint

## Architecture

```
Internet
    ↓
SSL Proxy (Nginx + Certbot)
    ├─ crudibase.codingtech.info → Crudibase Frontend (3000) + Backend (3001)
    └─ cruditrack.codingtech.info → Cruditrack Frontend (3100) + Backend (3101)
```

## Quick Start

### Prerequisites

- DigitalOcean droplet with Docker and Docker Compose
- Domain name pointing to droplet (e.g., `codingtech.info`)
- DigitalOcean Container Registry (`crudibase-registry`)
- DNS A records configured (see [DO Setup Guide](docs/DO-SETUP-GUIDE.md))

### 1. Build and Push Image (From Mac)

```bash
# Clone repository
git clone <repository-url>
cd ssl-proxy-for-do

# Configure environment
cp .env.example .env
# Edit .env and set your email address

# Build and push to DigitalOcean Container Registry
./scripts/build-and-push.sh
```

### 2. Deploy on Droplet

```bash
# SSH to droplet
ssh root@YOUR_DROPLET_IP

# Ensure your apps are running first
cd /opt/crudibase && docker compose up -d
cd /opt/cruditrack && docker compose up -d

# Deploy SSL proxy
cd /opt/ssl-proxy
docker pull registry.digitalocean.com/crudibase-registry/ssl-proxy:latest
docker compose -f docker-compose.prod.yml up -d

# Check logs
docker compose -f docker-compose.prod.yml logs -f
```

### 3. Verify

```bash
# Test HTTPS endpoints
curl -I https://crudibase.codingtech.info
curl -I https://cruditrack.codingtech.info

# Visit in browser and check SSL certificate
```

## Configuration

### Environment Variables

Configure via `.env` file or `docker-compose.yml`:

| Variable | Description | Default |
|----------|-------------|---------|
| `DOMAIN` | Base domain name | `codingtech.info` |
| `EMAIL` | Email for Let's Encrypt notifications | `admin@codingtech.info` |
| `STAGING` | Use Let's Encrypt staging (testing) | `false` |
| `ENABLE_CRUDIBASE` | Enable Crudibase proxy | `true` |
| `ENABLE_CRUDITRACK` | Enable Cruditrack proxy | `true` |
| `CRUDIBASE_BACKEND_HOST` | Backend container hostname | `crudibase-backend` |
| `CRUDIBASE_BACKEND_PORT` | Backend container port | `3001` |
| `CRUDIBASE_FRONTEND_HOST` | Frontend container hostname | `crudibase-frontend` |
| `CRUDIBASE_FRONTEND_PORT` | Frontend container port | `3000` |
| `CRUDITRACK_BACKEND_HOST` | Backend container hostname | `cruditrack-backend` |
| `CRUDITRACK_BACKEND_PORT` | Backend container port | `3101` |
| `CRUDITRACK_FRONTEND_HOST` | Frontend container hostname | `cruditrack-frontend` |
| `CRUDITRACK_FRONTEND_PORT` | Frontend container port | `3100` |

## Project Structure

```
ssl-proxy-for-do/
├── Dockerfile                      # Main Docker image definition
├── docker-compose.yml              # Local development compose
├── .env.example                    # Environment variable template
├── nginx/
│   ├── nginx.conf                  # Main nginx configuration
│   └── templates/
│       ├── default.conf.template   # Health check & ACME challenge
│       ├── crudibase.conf.template # Crudibase proxy config
│       └── cruditrack.conf.template# Cruditrack proxy config
├── scripts/
│   ├── entrypoint.sh              # Container startup script
│   ├── renew-certificates.sh      # Certificate renewal (cron)
│   ├── build-and-push.sh          # Build & push to DO registry
│   └── test-build.sh              # Test build locally
└── docs/
    └── DO-SETUP-GUIDE.md          # Manual steps for DO web UI
```

## Documentation

- **[DO Setup Guide](docs/DO-SETUP-GUIDE.md)** - Complete setup instructions including manual steps in DigitalOcean web UI
- **[SSL Research](docs/ssl-research.txt)** - Background research and planning
- **[Background](docs/background.md)** - Project context and decisions

## Scripts

### Build and Push to Registry

```bash
./scripts/build-and-push.sh
```

Builds AMD64 Docker image and pushes to DigitalOcean Container Registry.

### Test Build Locally

```bash
./scripts/test-build.sh
```

Builds image locally for testing without pushing to registry.

### Certificate Renewal

Automatic renewal runs twice daily via cron. Manual renewal:

```bash
docker exec ssl-proxy /usr/local/bin/renew-certificates.sh
```

## DNS Configuration

Create these A records in your domain DNS:

| Hostname    | Type | Value           | TTL  |
|-------------|------|-----------------|------|
| crudibase   | A    | YOUR_DROPLET_IP | 3600 |
| cruditrack  | A    | YOUR_DROPLET_IP | 3600 |

See [DO Setup Guide](docs/DO-SETUP-GUIDE.md#dns-configuration) for detailed steps.

## Networking

The SSL proxy connects to your application networks:

- `crudibase-network` - For Crudibase frontend/backend
- `cruditrack-network` - For Cruditrack frontend/backend

Make sure these networks are created by your application docker-compose files with `external: false` (default), or create them manually.

## Troubleshooting

### Certificate Issuance Failed

1. Verify DNS is propagating: `dig crudibase.codingtech.info`
2. Check port 80 is accessible
3. Use `STAGING=true` for testing to avoid rate limits
4. Check logs: `docker compose logs ssl-proxy`

### 502 Bad Gateway

1. Verify backend services are running: `docker ps`
2. Check network connectivity: `docker exec ssl-proxy ping crudibase-backend`
3. Verify service names match environment variables

### HTTP Not Redirecting

1. Check nginx config: `docker exec ssl-proxy nginx -t`
2. Reload nginx: `docker exec ssl-proxy nginx -s reload`
3. Check logs for errors

See [DO Setup Guide - Troubleshooting](docs/DO-SETUP-GUIDE.md#troubleshooting) for more details.

## Security

- SSL/TLS via Let's Encrypt with automatic renewal
- HTTP to HTTPS automatic redirects
- HSTS enabled with 1-year max-age
- XSS protection headers
- Frame protection headers
- CORS configured per application

## Certificate Management

- Certificates are automatically obtained on first run
- Automatic renewal runs twice daily (via cron)
- Certificates stored in Docker volume: `letsencrypt`
- Renewal logs: `/var/log/letsencrypt/renew.log`

## Adding New Applications

To add a new application:

1. Create new nginx template in `nginx/templates/myapp.conf.template`
2. Add environment variables for the app
3. Update `entrypoint.sh` to process the new config
4. Rebuild and push image
5. Update `docker-compose.yml` with new environment variables

## Development

### Local Testing

```bash
# Build test image
./scripts/test-build.sh

# Run locally (requires backend services)
docker compose up

# Test health endpoint
curl http://localhost/health
```

### Staging Mode

For testing certificate issuance without hitting rate limits:

```bash
# Set in .env or docker-compose.yml
STAGING=true
```

This uses Let's Encrypt staging environment (certificates won't be trusted by browsers).

## License

MIT

## Support

For issues and questions:
1. Check [DO Setup Guide](docs/DO-SETUP-GUIDE.md)
2. Review logs: `docker compose logs ssl-proxy`
3. Test nginx config: `docker exec ssl-proxy nginx -t`

## Related Projects

- [crudibase](../crudibase) - CRUD application framework
- [cruditrack](../cruditrack) - Time tracking application
