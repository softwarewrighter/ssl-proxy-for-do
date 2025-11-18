# Request Flow Documentation

This document details how HTTP and HTTPS requests flow through the SSL Proxy system, from the initial client request to the final application response.

## Table of Contents

- [Overview](#overview)
- [HTTPS Request Flow](#https-request-flow)
- [HTTP to HTTPS Redirect](#http-to-https-redirect)
- [Frontend Request Flow](#frontend-request-flow)
- [API Request Flow](#api-request-flow)
- [WebSocket Connection Flow](#websocket-connection-flow)
- [Health Check Flow](#health-check-flow)
- [Error Response Flow](#error-response-flow)

## Overview

The SSL Proxy acts as a reverse proxy, handling SSL/TLS termination and routing requests to appropriate backend services based on:
- **Host header** (subdomain routing)
- **Path** (frontend vs. API routing)
- **Protocol** (HTTP → HTTPS redirects)

### Request Flow Layers

```mermaid
graph LR
    Client[Client<br/>Browser]
    DNS[DNS<br/>Resolution]
    TCP[TCP<br/>Connection]
    TLS[TLS<br/>Handshake]
    Nginx[Nginx<br/>Routing]
    App[Application<br/>Processing]

    Client --> DNS --> TCP --> TLS --> Nginx --> App

    style TLS fill:#4CAF50
    style Nginx fill:#2196F3
```

## HTTPS Request Flow

### Complete HTTPS Request Sequence

```mermaid
sequenceDiagram
    participant Client as Client Browser
    participant DNS as DNS Server
    participant SSLProxy as SSL Proxy (Nginx)
    participant Backend as Backend Service (Node.js)
    participant Frontend as Frontend Service (Nginx/React)

 Note over Client: User navigates to https://crudibase.codingtech.info/api/users

    Client->>DNS: Resolve crudibase.codingtech.info
    DNS-->>Client: IP: 123.45.67.89

    Client->>SSLProxy: TCP SYN (port 443)
    SSLProxy-->>Client: TCP SYN-ACK
    Client->>SSLProxy: TCP ACK
 Note over Client,SSLProxy: TCP Connection Established

    Client->>SSLProxy: TLS ClientHello
 Note over SSLProxy: Select certificate for crudibase.codingtech.info
    SSLProxy-->>Client: TLS ServerHello + Certificate
    Client->>Client: Validate certificate
    Client->>SSLProxy: TLS Finished
    SSLProxy-->>Client: TLS Finished
 Note over Client,SSLProxy: TLS 1.3 Connection Established

    Client->>SSLProxy: Encrypted HTTP GET /api/users HTTP/2
    SSLProxy->>SSLProxy: Decrypt request
    SSLProxy->>SSLProxy: Parse Host header crudibase.codingtech.info
    SSLProxy->>SSLProxy: Parse Path /api/users
    SSLProxy->>SSLProxy: Match server block

 Note over SSLProxy: Route to backend based on /api/ path

    SSLProxy->>Backend: HTTP GET / with headers
    Backend->>Backend: Process request Query database
    Backend-->>SSLProxy: HTTP 200 OK with JSON users data

    SSLProxy->>SSLProxy: Add security headers HSTS etc
    SSLProxy->>SSLProxy: Encrypt response
    SSLProxy-->>Client: Encrypted HTTP Response HTTP/2 200 OK

    Client->>Client: Decrypt response
    Client->>Client: Render data
```

### Request Headers Added by Nginx

When Nginx forwards requests to backend services, it adds several headers:

```nginx
proxy_set_header Host $host;                          # crudibase.codingtech.info
proxy_set_header X-Real-IP $remote_addr;              # Client's actual IP
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;  # Proxy chain
proxy_set_header X-Forwarded-Proto $scheme;           # https
proxy_set_header X-Forwarded-Host $host;              # crudibase.codingtech.info
proxy_set_header X-Forwarded-Port $server_port;       # 443
```

**Example Request to Backend**:
```http
GET /users HTTP/1.1
Host: crudibase-backend:3001
X-Real-IP: 203.0.113.42
X-Forwarded-For: 203.0.113.42
X-Forwarded-Proto: https
X-Forwarded-Host: crudibase.codingtech.info
X-Forwarded-Port: 443
User-Agent: Mozilla/5.0...
```

### Response Headers Added by Nginx

Nginx adds security headers to all responses:

```nginx
# Security headers (in nginx.conf)
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;

# HSTS header (in crudibase.conf.template)
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
```

**Example Response to Client**:
```http
HTTP/2 200 OK
Content-Type: application/json
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Frame-Options: SAMEORIGIN
X-Content-Type-Options: nosniff
X-XSS-Protection: 1; mode=block

{"users": [...]}
```

## HTTP to HTTPS Redirect

### HTTP Redirect Flow

```mermaid
sequenceDiagram
    participant Client as Client Browser
    participant SSLProxy as SSL Proxy (Port 80)

    Note over Client: User navigates to HTTP URL

    Client->>SSLProxy: GET / HTTP/1.1

    SSLProxy->>SSLProxy: Match server block

    Note over SSLProxy: Return 301 redirect to HTTPS

    SSLProxy-->>Client: HTTP/1.1 301 Moved Permanently

    Client->>Client: Follow redirect
    Client->>SSLProxy: GET / to port 443 (HTTPS)

    Note over SSLProxy: Continue with HTTPS flow
```

### HTTP Redirect Configuration

```nginx
# crudibase.conf.template - HTTP server block
server {
    listen 80;
    server_name crudibase.${DOMAIN};

    # Let's Encrypt challenge (must be accessible via HTTP)
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # Redirect all other traffic to HTTPS
    location / {
        return 301 https://$host$request_uri;
    }
}
```

**Redirect Behavior**:
- `http://crudibase.codingtech.info` → `https://crudibase.codingtech.info/`
- `http://crudibase.codingtech.info/api/users` → `https://crudibase.codingtech.info/api/users`
- `http://crudibase.codingtech.info/login?next=/dashboard` → `https://crudibase.codingtech.info/login?next=/dashboard`

## Frontend Request Flow

### Static Asset Request

```mermaid
sequenceDiagram
    participant Browser as Client Browser
    participant SSLProxy as SSL Proxy (Nginx)
    participant Frontend as Frontend Container (Nginx)

 Note over Browser: User requests https://crudibase.codingtech.info/

    Browser->>SSLProxy: GET / with Host: crudibase.codingtech.info
    SSLProxy->>SSLProxy: Decrypt HTTPS
    SSLProxy->>SSLProxy: Match HTTPS server block
    SSLProxy->>SSLProxy: Match location / {}

 Note over SSLProxy: proxy_pass http://crudibase-frontend:3000

    SSLProxy->>Frontend: GET / to crudibase-frontend:3000
    Frontend->>Frontend: Serve index.html
    Frontend-->>SSLProxy: 200 OK (text/html)

    SSLProxy->>SSLProxy: Add security headers
    SSLProxy->>SSLProxy: Encrypt response
    SSLProxy-->>Browser: 200 OK (HTTPS)

    Browser->>Browser: Parse HTML
    Browser->>Browser: Find resource /static/js/main.js

    Browser->>SSLProxy: GET /static/js/main.js
    SSLProxy->>Frontend: GET /static/js/main.js
    Frontend->>Frontend: Serve JS file
    Frontend-->>SSLProxy: 200 OK (application/javascript)
    SSLProxy-->>Browser: 200 OK (HTTPS)

    Browser->>Browser: Execute JavaScript and Initialize React app
```

### Frontend Nginx Configuration

Inside the frontend container (`crudibase-frontend`), there's typically an Nginx configuration like:

```nginx
server {
    listen 3000;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;  # SPA fallback
    }

    location /static/ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
```

## API Request Flow

### API Request with CORS

```mermaid
sequenceDiagram
    participant Browser as Client Browser
    participant SSLProxy as SSL Proxy (Nginx)
    participant Backend as Backend API (Node.js)
    participant DB as PostgreSQL Database

 Note over Browser: React app makes API call

    Browser->>SSLProxy: OPTIONS /api/users (CORS preflight)

    SSLProxy->>SSLProxy: Decrypt HTTPS
    SSLProxy->>SSLProxy: Match /api/ location block
    SSLProxy->>SSLProxy: Check request method = OPTIONS

 Note over SSLProxy: CORS preflight: return 204

    SSLProxy-->>Browser: 204 No Content + CORS headers

    Browser->>Browser: CORS check passed

    Browser->>SSLProxy: GET /api/users + Auth header

    SSLProxy->>SSLProxy: Decrypt HTTPS
    SSLProxy->>SSLProxy: Match /api/ location

 Note over SSLProxy: proxy_pass http://crudibase-backend:3001/

    SSLProxy->>Backend: GET /users + headers

    Backend->>Backend: Validate JWT token
    Backend->>Backend: Parse request
    Backend->>DB: SELECT * FROM users;
    DB-->>Backend: Query results

    Backend->>Backend: Format JSON response
    Backend-->>SSLProxy: 200 OK + JSON data

    SSLProxy->>SSLProxy: Add CORS headers
    SSLProxy->>SSLProxy: Add security headers
    SSLProxy->>SSLProxy: Encrypt response

    SSLProxy-->>Browser: 200 OK (HTTPS) + JSON

    Browser->>Browser: Process response and Update UI
```

### API Path Rewriting

The `/api/` prefix is stripped when forwarding to the backend:

**Nginx Configuration**:
```nginx
location /api/ {
    proxy_pass http://${CRUDIBASE_BACKEND_HOST}:${CRUDIBASE_BACKEND_PORT}/;
    # Note the trailing slash ──────────────────────────────────────────^
}
```

**Path Transformation**:
| Client Request | Nginx Receives | Backend Receives |
|----------------|----------------|------------------|
| `GET /api/users` | `/api/users` | `GET /users` |
| `POST /api/users/create` | `/api/users/create` | `POST /users/create` |
| `GET /api/auth/login` | `/api/auth/login` | `GET /auth/login` |

### CORS Configuration

```nginx
# In crudibase.conf.template - /api/ location block
location /api/ {
    # ... proxy settings ...

    # CORS headers
    add_header Access-Control-Allow-Origin "https://crudibase.${DOMAIN}" always;
    add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Authorization, Content-Type" always;
    add_header Access-Control-Allow-Credentials "true" always;

    # Handle preflight requests
    if ($request_method = 'OPTIONS') {
        return 204;
    }
}
```

## WebSocket Connection Flow

### WebSocket Upgrade Sequence

```mermaid
sequenceDiagram
    participant Client as Client Browser
    participant SSLProxy as SSL Proxy (Nginx)
    participant Backend as Backend Service (WebSocket)

    Note over Client: Client initiates WebSocket

    Client->>SSLProxy: GET /api/ws + WebSocket headers

    SSLProxy->>SSLProxy: Decrypt HTTPS (WSS)
    SSLProxy->>SSLProxy: Detect Upgrade header

    Note over SSLProxy: Nginx proxies WebSocket upgrade

    SSLProxy->>Backend: GET /ws + WebSocket headers

    Backend->>Backend: Accept WebSocket upgrade
    Backend-->>SSLProxy: HTTP/1.1 101 Switching Protocols

    SSLProxy-->>Client: HTTP/1.1 101 Switching Protocols (WSS)

    Note over Client,Backend: WebSocket connection established

    loop Real-time messaging
        Client->>SSLProxy: WebSocket frame (encrypted)
        SSLProxy->>Backend: WebSocket frame (decrypted)
        Backend->>SSLProxy: WebSocket frame
        SSLProxy->>Client: WebSocket frame (encrypted)
    end
```

### WebSocket Nginx Configuration

```nginx
location /api/ {
    proxy_pass http://${CRUDIBASE_BACKEND_HOST}:${CRUDIBASE_BACKEND_PORT}/;
    proxy_http_version 1.1;

    # WebSocket support
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_cache_bypass $http_upgrade;

    # Standard proxy headers
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

## Health Check Flow

### Health Check Sequence

```mermaid
sequenceDiagram
    participant Docker as Docker Engine
    participant Container as SSL Proxy Container
    participant Nginx as Nginx Process

    Note over Docker: Every 30 seconds

    Docker->>Container: Execute healthcheck command

    Container->>Nginx: GET /health HTTP/1.1

    Nginx->>Nginx: Match default server block

    Note over Nginx: Return 200 healthy

    Nginx-->>Container: HTTP/1.1 200 OK

    Container-->>Docker: Exit code 0 (success)

    Docker->>Docker: Mark container as healthy

    Note over Docker: If 3 consecutive failures mark unhealthy
```

### Health Check Configuration

**Dockerfile**:
```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/health || exit 1
```

**Nginx Configuration**:
```nginx
# default.conf.template
server {
    listen 80;
    server_name _;

    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }

    # ... other locations ...
}
```

**Testing**:
```bash
# Manual health check
curl http://YOUR_DROPLET_IP/health
# Response: healthy

# Check Docker health status
docker ps
# CONTAINER ID   STATUS
# abc123         Up 5 mins (healthy)
```

## Error Response Flow

### 502 Bad Gateway (Backend Down)

```mermaid
sequenceDiagram
    participant Client as Client Browser
    participant SSLProxy as SSL Proxy (Nginx)
    participant Backend as Backend Service (Down)

    Client->>SSLProxy: GET /api/users HTTPS

    SSLProxy->>SSLProxy: Decrypt request
    SSLProxy->>SSLProxy: Match /api/ location

    SSLProxy->>Backend: Attempt connection
    Note over Backend: Connection refused (container stopped)

    Backend--XSSLProxy: Connection failed

    SSLProxy->>SSLProxy: Generate 502 error page

    SSLProxy-->>Client: HTTP/2 502 Bad Gateway

    Note over Client: Display error page to user
```

### 404 Not Found

```mermaid
sequenceDiagram
    participant Client as Client Browser
    participant SSLProxy as SSL Proxy (Nginx)
    participant Frontend as Frontend Service

    Client->>SSLProxy: GET /nonexistent-page HTTPS

    SSLProxy->>SSLProxy: Decrypt request
    SSLProxy->>SSLProxy: Match location / {}

    SSLProxy->>Frontend: GET /nonexistent-page

    Frontend->>Frontend: Check if file exists
    Frontend->>Frontend: File not found, try index.html (SPA fallback)

    Frontend-->>SSLProxy: 200 OK with React app HTML

    SSLProxy-->>Client: 200 OK (HTTPS) React app loads

    Note over Client: React Router handles 404 and shows Page Not Found
```

### Common HTTP Status Codes

| Status Code | Scenario | Cause |
|-------------|----------|-------|
| **200 OK** | Successful request | Normal operation |
| **204 No Content** | CORS preflight | OPTIONS request handled by Nginx |
| **301 Moved Permanently** | HTTP → HTTPS redirect | Request to port 80 |
| **400 Bad Request** | Invalid request | Malformed headers, bad syntax |
| **401 Unauthorized** | Authentication failed | Invalid/missing JWT token (from backend) |
| **403 Forbidden** | Access denied | Backend authorization failed |
| **404 Not Found** | Resource not found | Backend returns 404 |
| **500 Internal Server Error** | Backend error | Application crash, unhandled exception |
| **502 Bad Gateway** | Backend unreachable | Container stopped, network issue |
| **503 Service Unavailable** | Backend overloaded | Too many connections |
| **504 Gateway Timeout** | Backend timeout | Backend taking too long (default: 60s) |

## Request Processing Summary

### Decision Tree

```mermaid
graph TD
    Start[Incoming Request] --> Protocol{Protocol?}

    Protocol -->|HTTP :80| HostHTTP{Host Match?}
    Protocol -->|HTTPS :443| TLS[TLS Handshake]

    TLS --> HostHTTPS{Host Match?}

    HostHTTP -->|crudibase.*| ACMECheck{Path starts with<br/>/.well-known/?}
    HostHTTP -->|cruditrack.*| ACMECheck2{Path starts with<br/>/.well-known/?}
    HostHTTP -->|Other| RedirectHTTPS[301 Redirect to HTTPS]

    ACMECheck -->|Yes| ServeACME[Serve ACME challenge]
    ACMECheck -->|No| RedirectHTTPS
    ACMECheck2 -->|Yes| ServeACME
    ACMECheck2 -->|No| RedirectHTTPS

    HostHTTPS -->|crudibase.*| PathCB{Path?}
    HostHTTPS -->|cruditrack.*| PathCT{Path?}
    HostHTTPS -->|Other| Error404[404 Not Found]

    PathCB -->|/api/*| ProxyCB_BE[Proxy to<br/>crudibase-backend:3001]
    PathCB -->|/*| ProxyCB_FE[Proxy to<br/>crudibase-frontend:3000]

    PathCT -->|/api/*| ProxyCT_BE[Proxy to<br/>cruditrack-backend:3101]
    PathCT -->|/*| ProxyCT_FE[Proxy to<br/>cruditrack-frontend:3100]

    ProxyCB_BE --> AddHeaders[Add Proxy Headers]
    ProxyCB_FE --> AddHeaders
    ProxyCT_BE --> AddHeaders
    ProxyCT_FE --> AddHeaders

    AddHeaders --> BackendReq[Forward to Backend]
    BackendReq --> BackendResp[Receive Response]
    BackendResp --> SecHeaders[Add Security Headers]
    SecHeaders --> Encrypt[Encrypt Response]
    Encrypt --> Client[Return to Client]

    RedirectHTTPS --> Client
    ServeACME --> Client
    Error404 --> Client

    style TLS fill:#4CAF50
    style AddHeaders fill:#2196F3
    style SecHeaders fill:#FF9800
```

## Performance Considerations

### Connection Pooling

Nginx maintains connection pools to backend services:
- Reduces TCP handshake overhead
- Reuses connections for multiple requests
- Configurable keepalive settings

```nginx
upstream backend {
    server crudibase-backend:3001;
    keepalive 32;  # Number of idle connections to keep
}

location /api/ {
    proxy_pass http://backend/;
    proxy_http_version 1.1;
    proxy_set_header Connection "";  # Enable keepalive
}
```

### Caching (Optional)

To enable response caching:

```nginx
# Add to nginx.conf
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=api_cache:10m max_size=1g;

# Add to location block
location /api/ {
    proxy_cache api_cache;
    proxy_cache_valid 200 5m;  # Cache successful responses for 5 minutes
    proxy_cache_bypass $http_cache_control;
    add_header X-Cache-Status $upstream_cache_status;
}
```

## Related Documentation

- **[Architecture](Architecture.md)** - System architecture overview
- **[SSL Certificate Management](SSL-Certificate-Management.md)** - TLS handshake details
- **[Network Architecture](Network-Architecture.md)** - Docker networking configuration
- **[Components](Components.md)** - Nginx component details
- **[Troubleshooting](Troubleshooting.md)** - Debugging request issues

---

**Last Updated**: 2025-11-18
