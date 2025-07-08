#!/bin/bash
set -euxo pipefail

# Log output to a file for troubleshooting
exec > /var/log/user-data.log 2>&1

# Set domain name and K3s private IP
DOMAIN_NAME="cloudifyrides.xyz"
K3S_PRIVATE_IP="10.0.1.10"

# Install Nginx and Certbot
apt-get update -y
apt-get install -y nginx certbot python3-certbot-nginx ufw

# Allow HTTP and HTTPS through UFW (if enabled)
ufw allow 'Nginx Full' || true
ufw --force enable || true

# Temporary HTTP-only config so Certbot can validate domain
cat > /etc/nginx/sites-available/default <<EOF
server {
    listen 80;
    server_name $DOMAIN_NAME;

    location / {
        proxy_pass http://$K3S_PRIVATE_IP:30081/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location /api/ {
        proxy_pass http://$K3S_PRIVATE_IP:30080/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_redirect off;
    }

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
}
EOF

# Reload Nginx to apply HTTP-only config
nginx -t
systemctl reload nginx

# Request Let's Encrypt cert
certbot --nginx --non-interactive --agree-tos --email your-email@example.com -d $DOMAIN_NAME

# At this point, Certbot automatically updates the Nginx config to use HTTPS

# Reload Nginx with SSL enabled
systemctl reload nginx
