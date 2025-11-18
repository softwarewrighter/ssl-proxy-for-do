# Architecture Overview

This document provides a comprehensive overview of the SSL Proxy architecture, including system components, design patterns, and architectural decisions.

## Table of Contents

- [System Architecture](#system-architecture)
- [Component Architecture](#component-architecture)
- [Container Architecture](#container-architecture)
- [Data Flow Architecture](#data-flow-architecture)
- [Security Architecture](#security-architecture)
- [Design Patterns](#design-patterns)
- [Architectural Decisions](#architectural-decisions)

## System Architecture

### High-Level Architecture

```mermaid
graph TB
    subgraph "External"
        DNS[DNS Server codingtech.info]
        LE[Let's Encrypt Certificate Authority]
        Client[Client Browsers]
    end

    subgraph "DigitalOcean Infrastructure"
        Registry[DO Container Registry crudibase-registry]

        subgraph "Droplet: Ubuntu 20.04 LTS"
            Docker[Docker Engine]

            subgraph "SSL Proxy Container"
                Nginx[Nginx 1.25 Reverse Proxy]
                Certbot[Certbot 2.7 ACME Client]
                Cron[Crond Scheduler]
                Entrypoint[Entrypoint Script]

                Entrypoint -.Initializes.-> Nginx
                Entrypoint -.Obtains Certs.-> Certbot
                Entrypoint -.Configures.-> Cron
                Certbot -.Writes Certs.-> VolLetsEncrypt
                Cron -.Triggers 2x Daily.-> RenewScript[Renew Script]
                RenewScript -.Calls.-> Certbot
                RenewScript -.Reloads.-> Nginx
            end

            subgraph "Application Containers"
                CB_Frontend[Crudibase Frontend React/Nginx:3000]
                CB_Backend[Crudibase Backend Node.js:3001]
                CT_Frontend[Cruditrack Frontend React/Nginx:3100]
                CT_Backend[Cruditrack Backend Node.js:3101]
            end

            subgraph "Docker Volumes"
                VolLetsEncrypt[letsencrypt SSL Certificates]
                VolCertbotWWW[certbot-www ACME Challenge Files]
            end

            subgraph "Docker Networks"
                NetCrudibase[crudibase-network]
                NetCruditrack[cruditrack-network]
            end
        end
    end

    Client -->|HTTPS :443| Nginx
    Client -->|HTTP :80| Nginx
    DNS -.Resolves.-> Client
    Certbot <-->|ACME Protocol| LE
    Registry -.Pulls Image.-> Docker

    Nginx <--> NetCrudibase
    Nginx <--> NetCruditrack
    CB_Frontend <--> NetCrudibase
    CB_Backend <--> NetCrudibase
    CT_Frontend <--> NetCruditrack
    CT_Backend <--> NetCruditrack

    style Nginx fill:#4CAF50,color:#fff
    style Certbot fill:#2196F3,color:#fff
    style Cron fill:#FF9800,color:#fff
    style LE fill:#003366,color:#fff
```

### Architecture Layers

```mermaid
graph LR
    subgraph "Layer 1: Edge"
        L1[Internet Traffic HTTPS/HTTP]
    end

    subgraph "Layer 2: SSL Termination"
        L2A[Nginx SSL TLS 1.2/1.3]
        L2B[Certificate Management]
    end

    subgraph "Layer 3: Routing"
        L3A[Host-based Routing]
        L3B[Path-based Routing]
    end

    subgraph "Layer 4: Application"
        L4A[Frontend Static Files]
        L4B[Backend API Services]
    end

    subgraph "Layer 5: Data"
        L5[PostgreSQL Database]
    end

    L1 --> L2A
    L2B -.Provides.-> L2A
    L2A --> L3A
    L3A --> L3B
    L3B --> L4A
    L3B --> L4B
    L4B --> L5

    style L2A fill:#4CAF50
    style L2B fill:#2196F3
    style L3A fill:#9C27B0
    style L3B fill:#9C27B0
```

## Component Architecture

### SSL Proxy Container Internals

```mermaid
graph TB
    subgraph "Container Startup Sequence"
        Start([Container Start])
        Start --> Entrypoint[Entrypoint Script /entrypoint.sh]

        Entrypoint --> ProcessTemplates[Process Nginx Templates envsubst]
        ProcessTemplates --> TestNginx[Test Nginx Config nginx -t]
        TestNginx --> StartNginx1[Start Nginx Background Mode]

        StartNginx1 --> CheckCerts{Certificates Exist?}

        CheckCerts -->|No| ObtainCerts[Obtain Certificates certbot certonly]
        CheckCerts -->|Yes| SkipObtain[Skip Certificate Acquisition]

        ObtainCerts --> ReloadNginx[Reload Nginx nginx -s reload]
        SkipObtain --> ReloadNginx

        ReloadNginx --> SetupCron[Setup Cron Job Twice Daily Renewal]
        SetupCron --> StopNginx[Stop Background Nginx]
        StopNginx --> ExecNginx[Start Nginx Foreground Mode]
        ExecNginx --> Running([Container Running])
    end

    style Entrypoint fill:#FF9800
    style ObtainCerts fill:#2196F3
    style ExecNginx fill:#4CAF50
```

### Nginx Configuration Hierarchy

```mermaid
graph TB
    MainConf[nginx.conf Main Configuration]

    MainConf --> HTTP[HTTP Context]

    HTTP --> GlobalSettings[Global Settings • Worker processes • Logging • Gzip compression • Security headers]

    HTTP --> IncludeConf[Include /etc/nginx/conf.d/*.conf]

    IncludeConf --> DefaultConf[default.conf Health & ACME]
    IncludeConf --> CrudibaseConf[crudibase.conf Crudibase Routing]
    IncludeConf --> CruditrackConf[cruditrack.conf Cruditrack Routing]

    DefaultConf --> DefaultHTTP[HTTP :80 • /health endpoint • ACME challenge • Redirect to HTTPS]

    CrudibaseConf --> CB_HTTP[HTTP :80 • ACME challenge • Redirect to HTTPS]
    CrudibaseConf --> CB_HTTPS[HTTPS :443 • SSL config • /api → backend • / → frontend]

    CruditrackConf --> CT_HTTP[HTTP :80 • ACME challenge • Redirect to HTTPS]
    CruditrackConf --> CT_HTTPS[HTTPS :443 • SSL config • /api → backend • / → frontend]

    style MainConf fill:#4CAF50
    style CrudibaseConf fill:#2196F3
    style CruditrackConf fill:#9C27B0
```

## Container Architecture

### Dockerfile Build Stages

```mermaid
graph LR
    Base[FROM nginx:1.25-alpine Base Image]

    Base --> Install[Install Packages • certbot • certbot-nginx • openssl • bash • curl • tzdata]

    Install --> Dirs[Create Directories • /etc/letsencrypt • /var/www/certbot • /var/log/letsencrypt]

    Dirs --> CopyNginx[Copy Nginx Configs • nginx.conf • templates/*.template]

    CopyNginx --> CopyScripts[Copy Scripts • entrypoint.sh • renew-certificates.sh]

    CopyScripts --> Perms[Set Permissions chmod +x scripts]

    Perms --> Expose[Expose Ports 80, 443]

    Expose --> Health[Configure Healthcheck curl /health]

    Health --> Entry[Set Entrypoint /entrypoint.sh]

    Entry --> CMD[Set CMD nginx -g 'daemon off;']

    CMD --> Final([Final Image ~48MB])

    style Base fill:#90CAF9
    style Final fill:#4CAF50
```

### Runtime Process Tree

```
ssl-proxy container (PID 1)
│
├── /entrypoint.sh (PID 1)
│   └── exec nginx -g 'daemon off;' (replaces PID 1)
│
├── nginx: master process (PID 1 after exec)
│   ├── nginx: worker process (PID 7)
│   ├── nginx: worker process (PID 8)
│   ├── nginx: worker process (PID 9)
│   └── nginx: worker process (PID 10)
│
└── crond (PID 15)
    └── (spawns renew-certificates.sh at 00:00 and 12:00)
```

## Data Flow Architecture

### Request Processing Pipeline

```mermaid
graph TB
    Client[Client Request https://crudibase.codingtech.info/api/users]

    Client --> DNS[DNS Resolution IP Address]
    DNS --> TCP[TCP Handshake Port 443]
    TCP --> TLS[TLS Handshake Certificate Validation]

    TLS --> NginxSSL[Nginx SSL Termination Decrypt HTTPS]

    NginxSSL --> HostMatch{Host Header Matching}

    HostMatch -->|crudibase.*| PathMatch1{Path Matching}
    HostMatch -->|cruditrack.*| PathMatch2{Path Matching}

    PathMatch1 -->|/api/*| CB_Backend[Crudibase Backend http://crudibase-backend:3001]
    PathMatch1 -->|/*| CB_Frontend[Crudibase Frontend http://crudibase-frontend:3000]

    PathMatch2 -->|/api/*| CT_Backend[Cruditrack Backend http://cruditrack-backend:3101]
    PathMatch2 -->|/*| CT_Frontend[Cruditrack Frontend http://cruditrack-frontend:3100]

    CB_Backend --> AppProcess[Application Processing]
    CB_Frontend --> AppProcess
    CT_Backend --> AppProcess
    CT_Frontend --> AppProcess

    AppProcess --> Response[HTTP Response]
    Response --> NginxEncrypt[Nginx SSL Encryption]
    NginxEncrypt --> ClientResponse[Encrypted Response to Client]

    style NginxSSL fill:#4CAF50
    style NginxEncrypt fill:#4CAF50
    style HostMatch fill:#FF9800
    style PathMatch1 fill:#9C27B0
    style PathMatch2 fill:#9C27B0
```

### Certificate Data Flow

```mermaid
graph TB
    Start([First Container Start])

    Start --> Check{Certificate Files Exist?}

    Check -->|No| PrepareNginx[Start Nginx HTTP Only Mode]
    PrepareNginx --> ACMEChallenge[Certbot Initiates ACME Challenge]

    ACMEChallenge --> WriteChallenge[Write Challenge File /var/www/certbot/.well-known/]
    WriteChallenge --> LERequest[Let's Encrypt Validates Challenge]
    LERequest --> ReceiveCert[Receive Certificate & Private Key]

    ReceiveCert --> WriteCert[Write to Volume /etc/letsencrypt/live/]

    Check -->|Yes| LoadCert[Load Existing Certificates]
    WriteCert --> EnableHTTPS[Enable HTTPS in Nginx]
    LoadCert --> EnableHTTPS

    EnableHTTPS --> ReloadNginx[Nginx Reload Zero Downtime]
    ReloadNginx --> Serving([Serving HTTPS])

    Serving -.30 Days Before Expiry.-> RenewCron[Cron Triggers Renewal]
    RenewCron --> RenewCert[Certbot Renew Command]
    RenewCert --> WriteCert

    style ReceiveCert fill:#4CAF50
    style WriteCert fill:#2196F3
    style ReloadNginx fill:#FF9800
```

## Security Architecture

### Security Layers

```mermaid
graph TB
    subgraph "Layer 1: Network Security"
        FW[Firewall Rules Ports: 22, 80, 443]
        DNS_SEC[DNS Security A Records Only]
    end

    subgraph "Layer 2: SSL/TLS Security"
        TLS_VER[TLS Versions 1.2, 1.3 Only]
        CIPHER[Strong Ciphers HIGH:!aNULL:!MD5]
        HSTS[HSTS Header 1 Year Max-Age]
    end

    subgraph "Layer 3: HTTP Security"
        XSS[X-XSS-Protection 1; mode=block]
        FRAME[X-Frame-Options SAMEORIGIN]
        NOSNIFF[X-Content-Type-Options nosniff]
        CORS[CORS Headers Per Application]
    end

    subgraph "Layer 4: Application Security"
        JWT[JWT Authentication Backend Validation]
        INPUT[Input Validation Application Layer]
    end

    subgraph "Layer 5: Container Security"
        ALPINE[Alpine Linux Minimal Attack Surface]
        NONROOT[Non-Root User nginx user]
        READONLY[Read-Only Configs Template System]
    end

    Client[Client] --> FW
    FW --> TLS_VER
    TLS_VER --> XSS
    XSS --> JWT
    JWT --> ALPINE

    style TLS_VER fill:#4CAF50
    style HSTS fill:#4CAF50
    style ALPINE fill:#2196F3
```

### Certificate Security Model

```mermaid
graph LR
    subgraph "Private Key Security"
        PK[Private Key RSA 2048+]
        PK_PERM[File Permissions 600 (owner only)]
        PK_VOL[Docker Volume Persistent Storage]

        PK --> PK_PERM
        PK_PERM --> PK_VOL
    end

    subgraph "Certificate Chain"
        CERT[Server Certificate]
        INTER[Intermediate CA]
        ROOT[Root CA Let's Encrypt]

        CERT --> INTER
        INTER --> ROOT
    end

    subgraph "Validation"
        OCSP[OCSP Stapling]
        VALID[Certificate Validity 90 Days]
        RENEW[Auto-Renewal at 60 Days]

        VALID --> RENEW
    end

    PK -.Signs.-> CERT
    CERT --> OCSP

    style PK fill:#F44336,color:#fff
    style CERT fill:#4CAF50,color:#fff
```

## Design Patterns

### 1. Template Pattern
Nginx configuration templates use environment variable substitution:
- **Templates**: `/etc/nginx/templates/*.template`
- **Processing**: `envsubst` command in entrypoint
- **Output**: `/etc/nginx/conf.d/*.conf`

**Benefits**:
- Single image for multiple environments
- Configuration via environment variables
- No rebuild needed for config changes

### 2. Sidecar Pattern
Certbot runs as a companion process to Nginx:
- **Primary**: Nginx (reverse proxy)
- **Sidecar**: Certbot (certificate management)
- **Coordination**: Shared volume for certificates

**Benefits**:
- Separation of concerns
- Independent updates possible
- Simplified container design

### 3. Volume Pattern
Persistent storage for certificates:
- **Volume**: `letsencrypt`
- **Mount**: `/etc/letsencrypt`
- **Lifecycle**: Survives container restarts

**Benefits**:
- Certificates persist across deployments
- No re-issuance on container restart
- Volume backups possible

### 4. Health Check Pattern
HTTP endpoint for container health:
- **Endpoint**: `GET /health`
- **Response**: `200 OK "healthy"`
- **Frequency**: Every 30 seconds

**Benefits**:
- Docker orchestration integration
- Early failure detection
- Load balancer integration ready

### 5. Zero-Downtime Reload Pattern
Graceful configuration reloads:
- **Command**: `nginx -s reload`
- **Process**: Master process spawns new workers
- **Old Workers**: Finish existing requests before exit

**Benefits**:
- No dropped connections
- Certificate updates without downtime
- Configuration changes without restart

## Architectural Decisions

### ADR-001: Nginx + Certbot over Traefik

**Decision**: Use Nginx with Certbot instead of Traefik for SSL proxy.

**Context**:
- Need SSL termination for multiple applications
- Automatic certificate management required
- Familiarity with Nginx vs. Traefik

**Rationale**:
- ✅ Nginx is well-understood and battle-tested
- ✅ Certbot is the official Let's Encrypt client
- ✅ Simpler configuration for basic use case
- ✅ Lower resource usage (Alpine base)
- ✅ Extensive documentation available

**Consequences**:
- Manual template creation for new apps
- Less dynamic than Traefik
- More configuration files to manage

### ADR-002: Single Container vs. Separate Containers

**Decision**: Run Nginx and Certbot in a single container.

**Context**:
- Certbot needs to write files that Nginx reads
- Certificate renewal requires Nginx reload
- Tight coupling between components

**Rationale**:
- ✅ Simplified deployment (single docker-compose service)
- ✅ Shared file system (no volume sharing complexity)
- ✅ Coordinated lifecycle
- ✅ Easier to manage cron for renewal

**Consequences**:
- Violates "one process per container" guideline
- Can't scale Nginx independently
- Both components update together

### ADR-003: Template-Based Configuration

**Decision**: Use `envsubst` templates instead of dynamic configuration.

**Context**:
- Need to support multiple applications
- Configuration should be environment-specific
- Must avoid rebuilding image for config changes

**Rationale**:
- ✅ Environment variables provide flexibility
- ✅ Single image works across environments
- ✅ Standard Unix tool (envsubst)
- ✅ Easy to validate generated configs

**Consequences**:
- Templates must be updated for new features
- All variables must be defined
- Requires container restart for config changes

### ADR-004: AMD64 Only Build

**Decision**: Build for AMD64/x86_64 platform only.

**Context**:
- DigitalOcean droplets use AMD64 architecture
- Multi-arch builds take significantly longer
- No ARM deployment planned

**Rationale**:
- ✅ Faster build times (2-3 minutes vs. 5-10 minutes)
- ✅ Smaller registry storage
- ✅ Matches deployment target exactly
- ✅ Simpler build process

**Consequences**:
- Won't run on ARM-based systems
- Not compatible with M1/M2 Macs natively (use emulation)
- Would need rebuild for ARM deployment

### ADR-005: Twice-Daily Certificate Renewal

**Decision**: Run certificate renewal check twice daily (00:00 and 12:00).

**Context**:
- Certbot renews certificates 30 days before expiry
- Let's Encrypt certificates valid for 90 days
- Need balance between freshness and API usage

**Rationale**:
- ✅ Provides redundancy (if one run fails, next is 12 hours away)
- ✅ Aligns with Certbot best practices
- ✅ Low API usage (only checks, doesn't renew unless needed)
- ✅ Ensures certificates always fresh

**Consequences**:
- Slightly more API calls than once-daily
- Small CPU usage twice per day
- Logs may have many "not due for renewal" entries

## Scalability Considerations

### Current Design Limitations

1. **Single Instance**: One SSL proxy per droplet
2. **No Load Balancing**: Single point of entry
3. **Vertical Scaling Only**: Add more resources to droplet

### Future Scaling Options

```mermaid
graph TB
    subgraph "Current Architecture"
        LB1[Single SSL Proxy]
        LB1 --> App1[Application 1]
        LB1 --> App2[Application 2]
    end

    subgraph "Scaled Architecture (Future)"
        DNS_LB[DNS Load Balancing or CDN]
        DNS_LB --> Proxy1[SSL Proxy 1 Droplet 1]
        DNS_LB --> Proxy2[SSL Proxy 2 Droplet 2]

        Proxy1 --> AppPool[Application Pool Shared Backend]
        Proxy2 --> AppPool
    end

    style LB1 fill:#4CAF50
    style DNS_LB fill:#2196F3
```

## Related Documentation

- **[Components](Components)** - Detailed component documentation
- **[Network Architecture](Network-Architecture)** - Docker networking details
- **[SSL Certificate Management](SSL-Certificate-Management)** - Certificate lifecycle
- **[Deployment Workflow](Deployment-Workflow)** - Build and deployment process

---

**Last Updated**: 2025-11-18
