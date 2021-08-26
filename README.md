# Kuma Minikube PoC basado en los siguientes links:
- https://kuma.io/docs/1.2.3/deployments/multi-zone/#multi-zone-mode
- https://github.com/kumahq/kuma-demo/blob/master/kubernetes/README.md
- https://www.youtube.com/watch?v=_3y_4A9qdKU
- https://www.youtube.com/watch?v=vKYQu0r1hDw
- 
# Variables (1 global control plane y 2 k8s clusters)
```shell
kcp=kuma-cp
k1=kuma-01
k2=kuma-02
```

# Clean clusters en caso de que haya quedado basura anterior
```shell
minikube delete -p $kcp
minikube delete -p $k1
minikube delete -p $k2
```

# Kuma install en la máquina que va a correr kumactl (máquina local)
```shell
cd ~; curl -L https://kuma.io/installer.sh | sh -
```

# Control Plane
```shell
minikube start -p $kcp --driver=hyperkit --kubernetes-version=v1.18.12 --service-cluster-ip-range=10.96.0.0/24 --listen-address=0.0.0.0
```

# Data Planes
```shell
minikube start -p $k1 --driver=hyperkit --kubernetes-version=v1.18.12 --service-cluster-ip-range=10.97.0.0/24 --listen-address=0.0.0.0
minikube start -p $k2 --driver=hyperkit --kubernetes-version=v1.18.12 --service-cluster-ip-range=10.98.0.0/24 --listen-address=0.0.0.0
```

# Luego de la corrida de screen hay que entrar en cada session para clavarle la clave del usuario
```shell
screen -S $kcp -d -m minikube tunnel -p $kcp; screen -S $k1 -d -m minikube tunnel -p $k1; screen -S $k2 -d -m minikube tunnel -p $k2
```

# Armado de certificados mTLS para el mesh e instalar un traffic policy con default permitir tráfico
```shell
kubectx $kcp
cd ~/kuma-1.2.3/bin; ./kumactl install control-plane --mode=global | kubectl apply -f -
sleep 5
echo "apiVersion: kuma.io/v1alpha1
kind: Mesh
metadata:
  name: default
spec:
  mtls:
    enabledBackend: ca-1
    backends:
      - name: ca-1
        type: builtin
        dpCert:
          rotation:
            expiration: 1d
        conf:
          caCert:
            RSAbits: 2048
            expiration: 10y" | kubectl apply -f -
            
echo "apiVersion: kuma.io/v1alpha1
kind: TrafficPermission
mesh: default
metadata:
  name: allow-all-traffic
spec:
  sources:
    - match:
        kuma.io/service: '*'
  destinations:
    - match:
        kuma.io/service: '*'" | kubectl apply -f -
        
echo "apiVersion: kuma.io/v1alpha1
kind: TrafficRoute
mesh: default
metadata:
  name: route-all-default
spec:
  sources:
    - match:
        kuma.io/service: '*'
  destinations:
    - match:
        kuma.io/service: '*'
  conf:
    loadBalancer:
      roundRobin: {}
    destination:
      kuma.io/service: '*'" | kubectl apply -f -
 ```

# Configuracion de kumactl para hablar con el CP
```shell
kubectx $kcp; cp=$(kubectl get svc -A | grep kuma-control-plane | awk '{print $4":5681"}')
cd ~/kuma-1.2.3/bin; ./kumactl config control-planes add --name $kcp --overwrite --address http://$cp
sleep 30
```

# Configuracion de Data Planes
```shell
kubectx $kcp; gzs=$(kubectl get svc -A | grep global-zone-sync | awk '{print $5":5685"}')
kubectx $k1
cd ~/kuma-1.2.3/bin;./kumactl install control-plane \
  --mode=zone \
  --zone=k1 \
  --ingress-enabled \
  --kds-global-address grpcs://$gzs | kubectl apply -f -
sleep 20
./kumactl get zones
kubectx $k2
cd ~/kuma-1.2.3/bin;./kumactl install control-plane \
  --mode=zone \
  --zone=k2 \
  --ingress-enabled \
  --kds-global-address grpcs://$gzs | kubectl apply -f -
sleep 20
cd ~/kuma-1.2.3/bin;./kumactl get zones
```
```shell
screen -dm bash -c "kubectx kuma-cp; kubectl port-forward svc/kuma-control-plane 5681 -n kuma-system --address 0.0.0.0"
```

# configurar los data plane proxies para namespace default
```shell
kubectx $k1
echo "apiVersion: v1
kind: Namespace
metadata:
  name: default
  namespace: default
  annotations:
    kuma.io/sidecar-injection: enabled
    kuma.io/mesh: default" | kubectl apply -f - && kubectl delete pod --all -n default

kubectx $k2
echo "apiVersion: v1
kind: Namespace
metadata:
  name: default
  namespace: default
  annotations:
    kuma.io/sidecar-injection: enabled
    kuma.io/mesh: default" | kubectl apply -f - && kubectl delete pod --all -n default
```

# instalar demo
```shell
kubectx $k1
kubectl apply -f https://raw.githubusercontent.com/danielitus/kuma-minikube-poc/main/demo-kuma-01.yaml
kubectx $k2
kubectl apply -f https://raw.githubusercontent.com/danielitus/kuma-minikube-poc/main/demo-kuma-02.yaml
screen -dm bash -c "kubectx kuma-01; kubectl port-forward svc/demo-app 5000 -n kuma-demo --address 0.0.0.0"
```

# opcional!! configurar los data plane proxies para namespace kuma-demo
```shell
kubectx $k1
echo "apiVersion: v1
kind: Namespace
metadata:
  name: kuma-demo
  namespace: kuma-demo
  annotations:
    kuma.io/sidecar-injection: enabled
    kuma.io/mesh: default" | kubectl apply -f - && kubectl delete pod --all -n kuma-demo

kubectx $k2
echo "apiVersion: v1
kind: Namespace
metadata:
  name: kuma-demo
  namespace: kuma-demo
  annotations:
    kuma.io/sidecar-injection: enabled
    kuma.io/mesh: default" | kubectl apply -f - && kubectl delete pod --all -n kuma-demo
```
