#!/bin/bash
# Certificate renewal script for cron
# This runs twice daily to check and renew certificates

set -e

echo "[$(date)] Starting certificate renewal check..."

# Attempt to renew certificates
if certbot renew --quiet --webroot --webroot-path=/var/www/certbot; then
    echo "[$(date)] Certificate renewal check completed successfully"

    # Reload nginx if any certificates were renewed
    if nginx -t 2>/dev/null; then
        nginx -s reload
        echo "[$(date)] Nginx reloaded"
    fi
else
    echo "[$(date)] Certificate renewal check failed"
    exit 1
fi

echo "[$(date)] Certificate renewal process finished"
