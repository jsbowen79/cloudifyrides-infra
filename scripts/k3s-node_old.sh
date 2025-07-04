#!/bin/bash
set -euxo pipefail
exec > /var/log/user-data.log 2>&1

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

# Apply Kubernetes manifests
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: rides-pv
spec:
  capacity:
    storage: 10Mi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  hostPath:
    path: /mnt/data/rides
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: rides-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Mi
  volumeName: rides-pv
  storageClassName: ""

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: frontend
        image: jsbowen79/cloudifyrides-frontend:v7
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 250m
            memory: 256Mi
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
spec:
  type: NodePort
  selector:
    app: frontend
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30081
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      initContainers:
      - name: init-backend-data-dir
        image: busybox
        command: ["sh", "-c", "mkdir -p /data && chmod -R 777 /data"]
        volumeMounts:
        - name: rides-data
          mountPath: /data
      containers:
      - name: backend
        image: jsbowen79/cloudifyrides-backend:v6
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 3000
        volumeMounts:
        - name: rides-data
          mountPath: /data
        env:
        - name: DATA_FILE
          value: /data/rides.db
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 250m
            memory: 256Mi
        readinessProbe:
          httpGet:
            path: /rides
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: rides-data
        persistentVolumeClaim:
          claimName: rides-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: backend-service
spec:
  type: NodePort
  selector:
    app: backend
  ports:
  - port: 80
    targetPort: 3000
    nodePort: 30080
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: frontend-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: frontend
  minReplicas: 2
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 50
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: backend-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: backend
  minReplicas: 2
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 50
EOF
