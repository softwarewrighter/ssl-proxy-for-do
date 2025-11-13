#!/bin/bash
set -e

echo "=== SSL Proxy Entrypoint ==="

# Environment variables with defaults
DOMAIN=${DOMAIN:-codingtech.info}
EMAIL=${EMAIL:-admin@${DOMAIN}}
STAGING=${STAGING:-false}

# Crudibase defaults
CRUDIBASE_BACKEND_HOST=${CRUDIBASE_BACKEND_HOST:-crudibase-backend}
CRUDIBASE_BACKEND_PORT=${CRUDIBASE_BACKEND_PORT:-3001}
CRUDIBASE_FRONTEND_HOST=${CRUDIBASE_FRONTEND_HOST:-crudibase-frontend}
CRUDIBASE_FRONTEND_PORT=${CRUDIBASE_FRONTEND_PORT:-3000}

# Cruditrack defaults
CRUDITRACK_BACKEND_HOST=${CRUDITRACK_BACKEND_HOST:-cruditrack-backend}
CRUDITRACK_BACKEND_PORT=${CRUDITRACK_BACKEND_PORT:-3101}
CRUDITRACK_FRONTEND_HOST=${CRUDITRACK_FRONTEND_HOST:-cruditrack-frontend}
CRUDITRACK_FRONTEND_PORT=${CRUDITRACK_FRONTEND_PORT:-3100}

echo "Domain: $DOMAIN"
echo "Email: $EMAIL"
echo "Staging mode: $STAGING"

# Process nginx templates
echo "Processing nginx templates..."
export DOMAIN CRUDIBASE_BACKEND_HOST CRUDIBASE_BACKEND_PORT CRUDIBASE_FRONTEND_HOST CRUDIBASE_FRONTEND_PORT
export CRUDITRACK_BACKEND_HOST CRUDITRACK_BACKEND_PORT CRUDITRACK_FRONTEND_HOST CRUDITRACK_FRONTEND_PORT

for template in /etc/nginx/templates/*.template; do
    if [ -f "$template" ]; then
        filename=$(basename "$template" .template)
        output="/etc/nginx/conf.d/$filename"
        echo "  Processing $filename..."
        envsubst '${DOMAIN} ${CRUDIBASE_BACKEND_HOST} ${CRUDIBASE_BACKEND_PORT} ${CRUDIBASE_FRONTEND_HOST} ${CRUDIBASE_FRONTEND_PORT} ${CRUDITRACK_BACKEND_HOST} ${CRUDITRACK_BACKEND_PORT} ${CRUDITRACK_FRONTEND_HOST} ${CRUDITRACK_FRONTEND_PORT}' < "$template" > "$output"
    fi
done

# Test nginx configuration
echo "Testing nginx configuration..."
nginx -t

# Function to obtain SSL certificate
obtain_certificate() {
    local subdomain=$1
    local full_domain="${subdomain}.${DOMAIN}"

    echo "Checking certificate for $full_domain..."

    if [ -f "/etc/letsencrypt/live/${full_domain}/fullchain.pem" ]; then
        echo "  Certificate already exists for $full_domain"
        return 0
    fi

    echo "  Obtaining certificate for $full_domain..."

    local certbot_args="certonly --webroot --webroot-path=/var/www/certbot --email $EMAIL --agree-tos --no-eff-email"

    if [ "$STAGING" = "true" ]; then
        certbot_args="$certbot_args --staging"
        echo "  Using Let's Encrypt staging environment"
    fi

    certbot_args="$certbot_args -d $full_domain"

    if certbot $certbot_args; then
        echo "  Successfully obtained certificate for $full_domain"
        return 0
    else
        echo "  Failed to obtain certificate for $full_domain"
        return 1
    fi
}

# Start nginx in background for ACME challenge
echo "Starting nginx for ACME challenges..."
nginx

# Wait a moment for nginx to start
sleep 2

# Obtain certificates for enabled subdomains
CERT_FAILED=false

if [ "${ENABLE_CRUDIBASE:-true}" = "true" ]; then
    echo "Obtaining certificate for crudibase..."
    if ! obtain_certificate "crudibase"; then
        CERT_FAILED=true
        echo "WARNING: Failed to obtain certificate for crudibase"
        # Remove the crudibase config so nginx can still start
        rm -f /etc/nginx/conf.d/crudibase.conf.template
    fi
fi

if [ "${ENABLE_CRUDITRACK:-false}" = "true" ]; then
    echo "Obtaining certificate for cruditrack..."
    if ! obtain_certificate "cruditrack"; then
        CERT_FAILED=true
        echo "WARNING: Failed to obtain certificate for cruditrack"
        # Remove the cruditrack config so nginx can still start
        rm -f /etc/nginx/conf.d/cruditrack.conf.template
    fi
fi

# Reload nginx with SSL configurations
if [ "$CERT_FAILED" = "false" ]; then
    echo "All certificates obtained successfully. Reloading nginx..."
    nginx -s reload
else
    echo "Some certificates failed. Reloading nginx with available configurations..."
    nginx -s reload || true
fi

# Setup certificate renewal cron job
echo "Setting up certificate renewal cron job..."
echo "0 0,12 * * * /usr/local/bin/renew-certificates.sh >> /var/log/letsencrypt/renew.log 2>&1" > /etc/crontabs/root
crond

echo "=== SSL Proxy Started ==="

# Stop nginx (it will be restarted by CMD)
nginx -s stop

# Execute CMD
exec "$@"
