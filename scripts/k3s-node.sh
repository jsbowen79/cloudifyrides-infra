kubectl apply -f /home/ubuntu/cloudifyrides/k8s/rides-pv.yaml
kubectl apply -f /home/ubuntu/cloudifyrides/k8s/rides-pvc.yaml
kubectl apply -f /home/ubuntu/cloudifyrides/k8s/backend-deployment.yaml
kubectl apply -f /home/ubuntu/cloudifyrides/k8s/backend-service.yaml
kubectl apply -f /home/ubuntu/cloudifyrides/k8s/frontend-deployment.yaml
kubectl apply -f /home/ubuntu/cloudifyrides/k8s/frontend-service.yaml
