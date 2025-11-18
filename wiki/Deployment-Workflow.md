# Deployment Workflow

This document details the complete deployment workflow for the SSL Proxy, from building the Docker image on a development machine to running it in production on a DigitalOcean droplet.

## Table of Contents

- [Overview](#overview)
- [Deployment Architecture](#deployment-architecture)
- [Build Process](#build-process)
- [Push to Registry](#push-to-registry)
- [Deployment Process](#deployment-process)
- [Update Process](#update-process)
- [Rollback Process](#rollback-process)

## Overview

The deployment workflow follows a three-stage pipeline:

1. **Build** - Create AMD64 Docker image on development machine
2. **Push** - Upload image to DigitalOcean Container Registry
3. **Deploy** - Pull and run image on production droplet

### Deployment Flow Diagram

```mermaid
graph TB
    subgraph "Development Machine (Mac)"
        Dev[Developer] --> Git[Git Repository ssl-proxy-for-do]
        Git --> Build[Build Script build-and-push.sh]
    end

    subgraph "Build Process"
        Build --> Docker[Docker Buildx AMD64 Build]
        Docker --> Test[Test Build nginx -t]
    end

    subgraph "DigitalOcean Container Registry"
        Test --> Push[Push Image registry.digitalocean.com/crudibase-registry/ssl-proxy:latest]
        Push --> Registry[(Container Registry Image Storage)]
    end

    subgraph "Production Droplet"
        Registry --> Pull[Pull Image docker pull]
        Pull --> Deploy[Deploy Container docker compose up]
        Deploy --> Run[Running Container Serving HTTPS]
    end

    subgraph "Verification"
        Run --> Health[Health Check curl /health]
        Health --> SSL[Verify SSL curl https://...]
        SSL --> Monitor[Monitor Logs docker logs]
    end

    style Build fill:#FF9800
    style Registry fill:#2196F3
    style Run fill:#4CAF50
```

## Deployment Architecture

### Infrastructure Overview

```mermaid
graph LR
    subgraph "Developer Workstation"
        MacOS[Mac OS Docker Desktop]
        DOCTL[doctl CLI DigitalOcean API]
    end

    subgraph "DigitalOcean Cloud"
        Registry[Container Registry crudibase-registry]

        subgraph "Droplet"
            Docker[Docker Engine]
            Compose[Docker Compose]

            subgraph "Containers"
                SSLProxy[SSL Proxy]
                App1[Crudibase]
                App2[Cruditrack]
            end
        end
    end

    MacOS -->|Build & Push| Registry
    DOCTL -.Authenticate.-> Registry
    Registry -->|Pull| Docker
    Docker --> Compose
    Compose --> SSLProxy
    Compose --> App1
    Compose --> App2

    style Registry fill:#2196F3
    style SSLProxy fill:#4CAF50
```

## Build Process

### Build Script Execution Flow

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant Script as build-and-push.sh
    participant Docker as Docker Buildx
    participant Registry as DO Registry

    Dev->>Script: Execute ./scripts/build-and-push.sh

    Note over Script: Load environment variables

    Script->>Script: Check prerequisites - Docker running? - doctl installed?

    Script->>Docker: doctl registry login
    Note over Docker: Authenticate with DigitalOcean registry

    Script->>Docker: docker buildx build --platform linux/amd64 --tag registry.../ssl-proxy:latest --push

    Note over Docker: Multi-stage build process

    Docker->>Docker: FROM nginx:1.25-alpine
    Docker->>Docker: Install certbot + dependencies
    Docker->>Docker: Copy nginx configs
    Docker->>Docker: Copy scripts
    Docker->>Docker: Set permissions
    Docker->>Docker: Configure healthcheck

    Docker->>Registry: Push image layers
    Registry-->>Docker: Upload complete

    Docker-->>Script: Build successful

    Script->>Script: Verify image in registry
    Script-->>Dev: ✅ Successfully built and pushed: registry.../ssl-proxy:latest
```

### Build Script (`scripts/build-and-push.sh`)

```bash
#!/bin/bash
set -e

echo "=== Building and Pushing SSL Proxy to DigitalOcean Registry ==="

# Configuration
REGISTRY="registry.digitalocean.com/crudibase-registry"
IMAGE_NAME="ssl-proxy"
TAG="latest"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${TAG}"

echo "Image: ${FULL_IMAGE}"
echo "Platform: linux/amd64"

# Check Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker is not running"
    exit 1
fi

# Login to DigitalOcean Container Registry
echo "Logging in to DigitalOcean Container Registry..."
doctl registry login

# Build and push for AMD64 (DigitalOcean droplet architecture)
echo "Building and pushing image..."
docker buildx build \
    --platform linux/amd64 \
    --tag "${FULL_IMAGE}" \
    --push \
    .

echo "✅ Successfully built and pushed: ${FULL_IMAGE}"
echo ""
echo "Next steps:"
echo "  1. SSH to your droplet"
echo "  2. Pull the image: docker pull ${FULL_IMAGE}"
echo "  3. Deploy: docker compose -f docker-compose.prod.yml up -d"
```

### Build Process Stages

```mermaid
graph TB
    Start([Start Build])

    Start --> CheckDocker{Docker Running?}
    CheckDocker -->|No| ErrorDocker[Error: Start Docker]
    CheckDocker -->|Yes| Login[doctl registry login]

    Login --> AuthCheck{Auth Success?}
    AuthCheck -->|No| ErrorAuth[Error: Check API token]
    AuthCheck -->|Yes| BuildCommand[docker buildx build]

    BuildCommand --> Stage1[Stage 1: Base Image nginx:1.25-alpine]
    Stage1 --> Stage2[Stage 2: Install Packages certbot, bash, curl, etc.]
    Stage2 --> Stage3[Stage 3: Create Directories]
    Stage3 --> Stage4[Stage 4: Copy Configs nginx.conf, templates]
    Stage4 --> Stage5[Stage 5: Copy Scripts entrypoint.sh, renew-*.sh]
    Stage5 --> Stage6[Stage 6: Set Permissions chmod +x scripts]
    Stage6 --> Stage7[Stage 7: Configure Healthcheck]

    Stage7 --> Push[Push Layers to Registry]
    Push --> Verify[Verify Upload]
    Verify --> Success([Build Complete])

    ErrorDocker --> End([End])
    ErrorAuth --> End
    Success --> End

    style Start fill:#90CAF9
    style Success fill:#4CAF50
    style ErrorDocker fill:#F44336
    style ErrorAuth fill:#F44336
```

### Build Output Example

```
=== Building and Pushing SSL Proxy to DigitalOcean Registry ===
Image: registry.digitalocean.com/crudibase-registry/ssl-proxy:latest
Platform: linux/amd64

Logging in to DigitalOcean Container Registry...
Logging Docker in to registry.digitalocean.com

Building and pushing image...
[+] Building 45.3s (12/12) FINISHED
 => [internal] load build definition from Dockerfile                      0.1s
 => [internal] load .dockerignore                                         0.0s
 => [internal] load metadata for docker.io/library/nginx:1.25-alpine      1.2s
 => [1/7] FROM docker.io/library/nginx:1.25-alpine@sha256:abc123...       5.4s
 => [internal] load build context                                         0.1s
 => [2/7] RUN apk add --no-cache certbot certbot-nginx openssl bash...  28.3s
 => [3/7] RUN mkdir -p /etc/letsencrypt /var/www/certbot...              0.3s
 => [4/7] COPY nginx/templates /etc/nginx/templates                       0.1s
 => [5/7] COPY nginx/nginx.conf /etc/nginx/nginx.conf                     0.0s
 => [6/7] COPY scripts/renew-certificates.sh /usr/local/bin/              0.0s
 => [7/7] COPY scripts/entrypoint.sh /entrypoint.sh                       0.0s
 => exporting to image                                                    3.2s
 => => exporting layers                                                   3.1s
 => => writing image sha256:def456...                                     0.0s
 => => naming to registry.digitalocean.com/crudibase-registry/ssl-proxy   0.0s
 => pushing image to registry                                            6.7s

✅ Successfully built and pushed: registry.../ssl-proxy:latest

Next steps:
  1. SSH to your droplet
  2. Pull the image: docker pull registry.../ssl-proxy:latest
  3. Deploy: docker compose -f docker-compose.prod.yml up -d
```

## Push to Registry

### Registry Authentication Flow

```mermaid
sequenceDiagram
    participant CLI as doctl CLI
    participant API as DigitalOcean API
    participant Docker as Docker Client
    participant Registry as Container Registry

    Note over CLI: doctl registry login

    CLI->>API: GET /v2/registry/docker-credentials
    Note over API: Verify API token

    API-->>CLI: Return Docker credentials {username, password, server}

    CLI->>Docker: docker login registry.digitalocean.com --username <token> --password <password>

    Docker->>Registry: Authenticate
    Registry-->>Docker: Authentication successful

    Docker-->>CLI: Login Succeeded

    Note over Docker,Registry: Can now push/pull images
```

### Image Layers and Pushing

```mermaid
graph TB
    subgraph "Local Image Layers"
        L1[Layer 1: Alpine Base 5.6 MB]
        L2[Layer 2: Nginx 12.3 MB]
        L3[Layer 3: Certbot Install 18.7 MB]
        L4[Layer 4: Config Files 0.1 MB]
        L5[Layer 5: Scripts 0.01 MB]
        L6[Layer 6: Permissions 0.001 MB]
    end

    subgraph "Push Process"
        L1 --> Check1{Layer exists in registry?}
        L2 --> Check2{Layer exists in registry?}
        L3 --> Check3{Layer exists in registry?}
        L4 --> Check4{Layer exists in registry?}
        L5 --> Check5{Layer exists in registry?}
        L6 --> Check6{Layer exists in registry?}
    end

    Check1 -->|Yes| Skip1[Skip Upload]
    Check1 -->|No| Upload1[Upload Layer]
    Check2 -->|Yes| Skip2[Skip Upload]
    Check2 -->|No| Upload2[Upload Layer]
    Check3 -->|Yes| Skip3[Skip Upload]
    Check3 -->|No| Upload3[Upload Layer]
    Check4 -->|No| Upload4[Upload Layer]
    Check5 -->|No| Upload5[Upload Layer]
    Check6 -->|No| Upload6[Upload Layer]

    Upload1 --> Registry[(Registry Storage)]
    Upload2 --> Registry
    Upload3 --> Registry
    Upload4 --> Registry
    Upload5 --> Registry
    Upload6 --> Registry
    Skip1 --> Registry
    Skip2 --> Registry
    Skip3 --> Registry

    Registry --> Manifest[Update Image Manifest ssl-proxy:latest]

    style Registry fill:#2196F3
```

## Deployment Process

### Complete Deployment Sequence

```mermaid
sequenceDiagram
    participant Admin as System Administrator
    participant Droplet as DigitalOcean Droplet
    participant Docker as Docker Engine
    participant Registry as DO Container Registry
    participant Compose as Docker Compose
    participant Container as SSL Proxy Container
    participant LE as Let's Encrypt

    Admin->>Droplet: SSH to droplet
    Note over Admin,Droplet: ssh root@123.45.67.89

    Admin->>Droplet: Navigate to /opt/ssl-proxy
    Admin->>Docker: doctl registry login

    Admin->>Docker: docker pull registry.../ssl-proxy:latest
    Docker->>Registry: Request image
    Registry-->>Docker: Send image layers
    Docker->>Docker: Extract and store locally

    Admin->>Compose: docker compose -f docker-compose.prod.yml up -d
    Compose->>Compose: Read docker-compose.prod.yml
    Compose->>Docker: Create networks (if needed)
    Compose->>Docker: Create volumes (if needed)
    Compose->>Docker: Create container

    Docker->>Container: Start container
    Container->>Container: Execute /entrypoint.sh

    Note over Container: Entrypoint Process

    Container->>Container: Process nginx templates
    Container->>Container: Test nginx config
    Container->>Container: Start nginx (background)

    Container->>Container: Check for certificates
    alt Certificates don't exist
        Container->>LE: Request certificates via Certbot
        LE-->>Container: Issue certificates
    else Certificates exist
        Container->>Container: Use existing certificates
    end

    Container->>Container: Reload nginx with SSL
    Container->>Container: Setup cron for renewal
    Container->>Container: Start nginx (foreground)

    Container-->>Admin: Container running

    Admin->>Container: docker logs ssl-proxy
    Container-->>Admin: Show logs: ✅ Certificate obtained ✅ SSL Proxy Started

    Admin->>Container: curl https://crudibase.../
    Container-->>Admin: 200 OK (HTTPS working)

    Admin->>Container: docker exec ssl-proxy certbot certificates
    Container-->>Admin: Show certificate details
```

### Deployment Steps

#### Step 1: Prerequisites on Droplet

Ensure the following are ready before deployment:

```bash
# 1. Check Docker is installed and running
docker --version
# Docker version 24.0.7, build afdd53b

# 2. Check Docker Compose is available
docker compose version
# Docker Compose version v2.23.0

# 3. Verify applications are running
docker ps | grep crudibase
docker ps | grep cruditrack

# 4. Check networks exist
docker network ls | grep crudibase
docker network ls | grep cruditrack
```

#### Step 2: Create Production Directory

```bash
# Create directory structure
mkdir -p /opt/ssl-proxy
cd /opt/ssl-proxy

# Create production docker-compose file
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
      - EMAIL=admin@codingtech.info
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
```

#### Step 3: Pull and Deploy

```bash
# Authenticate with registry
doctl registry login

# Pull latest image
docker pull registry.digitalocean.com/crudibase-registry/ssl-proxy:latest

# Start the service
docker compose -f docker-compose.prod.yml up -d

# Watch logs
docker compose -f docker-compose.prod.yml logs -f ssl-proxy
```

#### Step 4: Verification

```bash
# 1. Check container status
docker ps | grep ssl-proxy
# Should show: Up X minutes (healthy)

# 2. View logs for successful startup
docker logs ssl-proxy
# Should see:
# ✅ Successfully obtained certificate for crudibase.codingtech.info
# ✅ Successfully obtained certificate for cruditrack.codingtech.info
# ✅ SSL Proxy Started

# 3. Check certificates
docker exec ssl-proxy certbot certificates
# Should list both certificates with expiry dates

# 4. Test HTTPS endpoints
curl -I https://crudibase.codingtech.info
curl -I https://cruditrack.codingtech.info
# Should return: HTTP/2 200

# 5. Test HTTP redirect
curl -I http://crudibase.codingtech.info
# Should return: HTTP/1.1 301 Moved Permanently
# Location: https://crudibase.codingtech.info/

# 6. Check health endpoint
curl http://YOUR_DROPLET_IP/health
# Should return: healthy
```

## Update Process

### Update Workflow

```mermaid
graph TB
    Start([Code Change]) --> Commit[Commit to Git]
    Commit --> BuildLocal[Build on Mac ./scripts/build-and-push.sh]
    BuildLocal --> PushReg[Push to Registry]

    PushReg --> SSHDrop[SSH to Droplet]
    SSHDrop --> PullNew[docker pull ...ssl-proxy:latest]

    PullNew --> StopOld[docker compose down]
    StopOld --> StartNew[docker compose up -d]

    StartNew --> CheckLogs[Check logs]
    CheckLogs --> Verify{Working?}

    Verify -->|Yes| Success([Update Complete])
    Verify -->|No| Rollback[Rollback to previous version]
    Rollback --> Success

    style Success fill:#4CAF50
    style Rollback fill:#FF9800
```

### Update Commands

```bash
# On Mac - Build and push new version
cd /path/to/ssl-proxy-for-do
git pull  # Get latest code
./scripts/build-and-push.sh

# On Droplet - Deploy update
cd /opt/ssl-proxy
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d

# Verify update
docker compose -f docker-compose.prod.yml logs -f ssl-proxy
```

### Zero-Downtime Updates

For zero-downtime updates, use rolling update strategy:

```bash
# 1. Pull new image (doesn't affect running container)
docker pull registry.digitalocean.com/crudibase-registry/ssl-proxy:latest

# 2. Create new container with new image
docker compose -f docker-compose.prod.yml up -d --no-deps ssl-proxy

# Docker will:
# - Start new container with new image
# - Wait for new container to be healthy
# - Stop old container
# - Remove old container
```

## Rollback Process

### Rollback Scenario

```mermaid
sequenceDiagram
    participant Admin as Administrator
    participant Droplet as Droplet
    participant Docker as Docker
    participant Registry as DO Registry

    Note over Admin: New deployment has issues

    Admin->>Admin: Identify previous working version

    alt Tagged version available
        Admin->>Registry: docker pull ...ssl-proxy:v1.2.3
        Registry-->>Docker: Previous image
    else Only latest available
        Admin->>Docker: Check docker images
        Docker-->>Admin: List local images with IDs
        Admin->>Admin: Find previous image by ID/timestamp
    end

    Admin->>Docker: Stop current container
    Admin->>Docker: Update compose file with image:tag
    Admin->>Docker: docker compose up -d

    Docker->>Docker: Start container with old image

    Admin->>Docker: Verify rollback
    Docker-->>Admin: Container running with old version

    Note over Admin: System restored to previous state
```

### Rollback Commands

#### Option 1: Using Image ID (if image still local)

```bash
# 1. List local images with timestamps
docker images registry.digitalocean.com/crudibase-registry/ssl-proxy

# Output example:
# REPOSITORY                                            TAG       IMAGE ID       CREATED
# registry.../ssl-proxy   latest    abc123     2 hours ago
# registry.../ssl-proxy   <none>    def456     1 day ago

# 2. Stop current container
docker compose -f docker-compose.prod.yml down

# 3. Tag the old image
docker tag def456 registry.digitalocean.com/crudibase-registry/ssl-proxy:rollback

# 4. Update docker-compose.prod.yml to use :rollback tag
# Change: image: ...ssl-proxy:latest
# To:     image: ...ssl-proxy:rollback

# 5. Start with old image
docker compose -f docker-compose.prod.yml up -d
```

#### Option 2: Using Git Tags (recommended)

```bash
# On Mac - Checkout previous version
cd /path/to/ssl-proxy-for-do
git log --oneline
# abc123 Update nginx config (current - broken)
# def456 Fix SSL certificate renewal (previous - working)

git checkout def456

# Build and push with specific tag
docker buildx build \
    --platform linux/amd64 \
    --tag registry.../ssl-proxy:rollback-$(date +%Y%m%d) \
    --push \
    .

# On Droplet - Deploy previous version
docker pull registry.../ssl-proxy:rollback-20251118
docker compose -f docker-compose.prod.yml down
# Update image tag in docker-compose.prod.yml
docker compose -f docker-compose.prod.yml up -d
```

### Rollback Verification

```bash
# Check container is running
docker ps | grep ssl-proxy

# Verify certificate status
docker exec ssl-proxy certbot certificates

# Test HTTPS endpoints
curl -I https://crudibase.codingtech.info
curl -I https://cruditrack.codingtech.info

# Check logs for errors
docker logs ssl-proxy --tail 100
```

## Deployment Checklist

### Pre-Deployment

- [ ] Code changes committed to Git
- [ ] Local build successful (`./scripts/build-and-push.sh`)
- [ ] Image pushed to registry
- [ ] DNS records configured and propagated
- [ ] Application containers running on droplet
- [ ] Docker networks exist (`crudibase-network`, `cruditrack-network`)
- [ ] Firewall allows ports 80 and 443

### Deployment

- [ ] SSH to droplet
- [ ] Pull latest image
- [ ] Update `docker-compose.prod.yml` if needed
- [ ] Deploy container (`docker compose up -d`)
- [ ] Watch logs for successful startup
- [ ] Wait for certificate acquisition (first deploy only)

### Post-Deployment

- [ ] Container status: healthy
- [ ] Certificates obtained/loaded
- [ ] HTTPS endpoints respond with 200 OK
- [ ] HTTP redirects to HTTPS
- [ ] Security headers present in responses
- [ ] Health check endpoint responding
- [ ] No errors in logs

### Monitoring (First 24 Hours)

- [ ] Check logs periodically: `docker logs ssl-proxy`
- [ ] Monitor certificate renewal cron job
- [ ] Verify application functionality
- [ ] Check for any 502/504 errors
- [ ] Monitor SSL certificate expiry dates

## Related Documentation

- **[Architecture](Architecture)** - System architecture
- **[Components](Components)** - Docker and component details
- **[Configuration](Configuration)** - Environment variables and settings
- **[Troubleshooting](Troubleshooting)** - Debugging deployment issues

---

**Last Updated**: 2025-11-18
