#!/bin/bash
set -euxo pipefail

# Log everything to a file for debugging
exec > /var/log/user-data.log 2>&1

# Install Nginx and Certbot
apt-get update -y
apt-get install -y nginx certbot python3-certbot-nginx ufw

# Define static private IP of K3s node
export K3S_PRIVATE_IP="10.0.1.10"

# Create self signed Certificate
sudo mkdir -p /etc/nginx/ssl
cd /etc/nginx/ssl

sudo openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout selfsigned.key \
  -out selfsigned.crt \
  -subj "/CN=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"

# Configure Nginx reverse proxy to K3s services
sudo tee /etc/nginx/sites-available/default > /dev/null <<EOF
server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;

    ssl_certificate /etc/nginx/ssl/selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/selfsigned.key;

    server_name _;

    location / {
        proxy_pass http://10.0.1.10:30081/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /api/ {
        proxy_pass http://10.0.1.10:30080/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_redirect off;
    }
}
EOF


#Validate and reload Nginx
nginx -t
systemctl reload nginx


