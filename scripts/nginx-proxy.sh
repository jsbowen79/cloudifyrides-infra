#!/bin/bash
set -euxo pipefail

# Log everything to a file for debugging
exec > /var/log/user-data.log 2>&1

# Install Nginx and Certbot
apt-get update -y
apt-get install -y nginx certbot python3-certbot-nginx ufw

# Define static private IP of K3s node
export K3S_PRIVATE_IP="10.0.1.10"

# Configure Nginx reverse proxy to K3s services
sudo tee /etc/nginx/sites-available/default > /dev/null <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name cloudifyrides.xyz;

    location / {
        proxy_pass http://${K3S_PRIVATE_IP}:30081;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location /api/ {
        rewrite ^/api/(.*)\$ /\$1 break;
        proxy_pass http://${K3S_PRIVATE_IP}:30080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF


#Validate and reload Nginx
nginx -t
systemctl reload nginx

# Configure UFW (optional: enable at end if desired)
ufw allow 22/tcp
ufw allow 'Nginx Full'
# ufw --force enable

# Obtain Let's Encrypt SSL certificate (safe fallback if DNS or timing fails)
certbot --nginx -d cloudifyrides.xyz --non-interactive --agree-tos -m admin@cloudifyrides.xyz || true
