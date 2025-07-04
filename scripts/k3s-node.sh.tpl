#!/bin/bash
set -euxo pipefail
exec > /var/log/user-data.log 2>&1
echo "Rendering with token length: ${#key}" >> /var/log/user-data.log



# Enable swap for t2.micro stability
fallocate -l 1G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# Install dependencies
apt-get update -y
apt-get install -y curl git

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
GITHUB_TOKEN="${key}"

git clone https://jsbowen79:${GITHUB_TOKEN}@github.com/jsbowen79/cloudifyrides-infra.git

cd cloudifyrides-infra/k8s


kubectl apply -f /home/ubuntu/cloudifyrides/k8s/rides-pv.yaml
kubectl apply -f /home/ubuntu/cloudifyrides/k8s/rides-pvc.yaml
kubectl apply -f /home/ubuntu/cloudifyrides/k8s/backend-deployment.yaml
kubectl apply -f /home/ubuntu/cloudifyrides/k8s/backend-service.yaml
kubectl apply -f /home/ubuntu/cloudifyrides/k8s/frontend-deployment.yaml
kubectl apply -f /home/ubuntu/cloudifyrides/k8s/frontend-service.yaml
