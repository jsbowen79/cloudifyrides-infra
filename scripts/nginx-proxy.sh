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

# Install and configure automatic updates
DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades
echo 'Unattended-Upgrade::Automatic-Reboot "true";' > /etc/apt/apt.conf.d/51>
cat <<EOF > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
cat <<EOF > /etc/apt/apt.conf.d/50unattended-upgrades
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}-security";
};
#Unattended-Upgrade::Automatic-Reboot "true";
EOF


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

# Ensure that SSH login by password is disabled
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication no/PasswordAuthentication no/' /etc/ssh/sshd_config

# Disable root SSH login
sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

systemctl restart sshd
