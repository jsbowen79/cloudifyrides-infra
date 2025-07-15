#!/bin/bash
set -euxo pipefail

# Log everything to a file for debugging
exec > /var/log/user-data.log 2>&1

# Variables
DOMAIN_NAME="cloudifyrides.xyz"
K3S_PRIVATE_IP="10.0.1.10"
EMAIL="jsbowen79@outlook.com"

# Install required packages
apt-get update -y
apt-get install -y nginx certbot python3-certbot-nginx ufw

# Open firewall ports (optional, in case UFW is in use)
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow from 10.0.1.10 to any port 30080 proto tcp
sudo ufw allow from 10.0.1.10 to any port 30081 proto tcp
sudo ufw allow 'OpenSSH'
sudo ufw --force enable

# Write temporary Nginx config with only HTTP
cat > /etc/nginx/sites-available/default <<EOF
server {
    listen 80;
    server_name $DOMAIN_NAME;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

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
}
EOF

# Ensure the webroot exists for validation
mkdir -p /var/www/html

# Validate and start Nginx
nginx -t
systemctl enable nginx
systemctl restart nginx

# Request and install Let's Encrypt cert (non-interactive)
certbot --nginx --non-interactive --agree-tos --redirect -d $DOMAIN_NAME -m $EMAIL

# Done. Certbot modifies the config to use HTTPS and reloads Nginx.

