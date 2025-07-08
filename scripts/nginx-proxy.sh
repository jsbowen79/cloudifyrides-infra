#!/bin/bash
set -euxo pipefail

exec > /var/log/user-data.log 2>&1

DOMAIN_NAME="cloudifyrides.xyz"
K3S_PRIVATE_IP="10.0.1.10"

# Update and install necessary packages
apt-get update -y
apt-get install -y nginx certbot python3-certbot-nginx ufw

# Allow HTTP/HTTPS traffic via UFW
ufw allow 'OpenSSH'
ufw allow 'Nginx Full'
ufw --force enable

# Initial Nginx config (only port 80) so certbot can pass challenge
cat >/etc/nginx/sites-available/default <<EOF
server {
    listen 80;
    server_name ${DOMAIN_NAME};

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        proxy_pass http://${K3S_PRIVATE_IP}:30081/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location /api/ {
        proxy_pass http://${K3S_PRIVATE_IP}:30080/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_redirect off;
    }
}
EOF

# Start Nginx so Certbot can validate
nginx -t
systemctl restart nginx

# Obtain SSL certificate using Certbot
certbot --nginx -d "${DOMAIN_NAME}" --non-interactive --agree-tos -m you@example.com

# Restart Nginx with HTTPS now that cert exists
systemctl reload nginx
