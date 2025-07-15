#!/bin/bash
set -euxo pipefail
exec > /var/log/user-data.log 2>&1
echo 'Rendering with token length: ${#key}' >> /var/log/user-data.log



# Enable swap for t2.micro stability
fallocate -l 1G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile none swap sw 0 0" >> /etc/fstab

# Install dependencies
apt-get update -y
apt-get install -y curl git

# Install and configure automatic updates
DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades
echo 'Unattended-Upgrade::Automatic-Reboot "true";' > /etc/apt/apt.conf.d/51auto-reboot
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

# Install Docker
curl -fsSL https://get.docker.com | sh
usermod -aG docker ubuntu

# Install K3s
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" sh -

# Export kubeconfig for this script
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Wait for cluster to be ready
until kubectl get nodes &>/dev/null; do sleep 2; done
until kubectl get pods -n kube-system | grep -q 'Running'; do sleep 2; done

# Create hostPath directory for PV
mkdir -p /mnt/data/rides
chmod 777 /mnt/data/rides

# Clone your repo to get YAML files
cd /home/ubuntu

# Clone private repo using GitHub token (passed via user-data env var or inserted directly)

git clone https://jsbowen79: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@github.com/jsbowen79/cloudifyrides-infra.git

ls -l /home/ubuntu/cloudifyrides-infra/k8s >> /var/log/user-data.log



kubectl apply -f /home/ubuntu/cloudifyrides-infra/k8s/rides-pv.yaml >> /var/log/user-data.log 2>&1
kubectl apply -f /home/ubuntu/cloudifyrides-infra/k8s/rides-pvc.yaml >> /var/log/user-data.log 2>&1
kubectl apply -f /home/ubuntu/cloudifyrides-infra/k8s/backend-deployment.yaml >> /var/log/user-data.log 2>&1
kubectl apply -f /home/ubuntu/cloudifyrides-infra/k8s/backend-service.yaml >> /var/log/user-data.log 2>&1
kubectl apply -f /home/ubuntu/cloudifyrides-infra/k8s/frontend-deployment.yaml >> /var/log/user-data.log 2>&1
kubectl apply -f /home/ubuntu/cloudifyrides-infra/k8s/frontend-service.yaml >> /var/log/user-data.log 2>&1

# Harden the k3s-node
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 52.200.76.169 to any port 30080 proto tcp
sudo ufw allow from 52.200.76.169 to any port 30081 proto tcp
sudo ufw allow 'OpenSSH'

sudo ufw --force enable

# Ensure that SSH login by password is disabled

sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication no/PasswordAuthentication no/' /etc/ssh/sshd_config

# Disable root SSH login
sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

systemctl restart sshd
