# SSL Reverse Proxy for DigitalOcean Droplet
# Nginx + Certbot for automatic SSL certificate management
# Platform: AMD64/x86_64

FROM nginx:1.25-alpine

# Install certbot and dependencies
RUN apk add --no-cache \
    certbot \
    certbot-nginx \
    openssl \
    bash \
    curl \
    tzdata

# Create directories for certificates and challenges
RUN mkdir -p /etc/letsencrypt \
    && mkdir -p /var/www/certbot \
    && mkdir -p /var/log/letsencrypt

# Copy nginx configuration templates
COPY nginx/templates /etc/nginx/templates
COPY nginx/nginx.conf /etc/nginx/nginx.conf

# Copy SSL renewal script
COPY scripts/renew-certificates.sh /usr/local/bin/renew-certificates.sh
RUN chmod +x /usr/local/bin/renew-certificates.sh

# Copy entrypoint script
COPY scripts/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose HTTP and HTTPS
EXPOSE 80 443

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/health || exit 1

ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
