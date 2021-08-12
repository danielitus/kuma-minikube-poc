# kuma-minikube-poc

# https://kuma.io/docs/1.2.3/deployments/multi-zone/#multi-zone-mode
# https://github.com/kumahq/kuma-demo/blob/master/kubernetes/README.md
# https://www.youtube.com/watch?v=_3y_4A9qdKU

kcp=kuma-cp
k1=kuma-01
k2=kuma-02

# Clean clusters
minikube delete -p $kcp
minikube delete -p $k1
minikube delete -p $k2

# install
#cd ~; curl -L https://kuma.io/installer.sh | sh -

# Control Plane
minikube start -p $kcp --driver=hyperkit --kubernetes-version=v1.18.12 --service-cluster-ip-range=10.96.0.0/24 --listen-address=0.0.0.0

# Data Planes
minikube start -p $k1 --driver=hyperkit --kubernetes-version=v1.18.12 --service-cluster-ip-range=10.97.0.0/24 --listen-address=0.0.0.0
minikube start -p $k2 --driver=hyperkit --kubernetes-version=v1.18.12 --service-cluster-ip-range=10.98.0.0/24 --listen-address=0.0.0.0

# Luego de la corrida de screen hay que entrar en cada session para clavarle la clave del usuario
screen -S $kcp -d -m minikube tunnel -p $kcp; screen -S $k1 -d -m minikube tunnel -p $k1; screen -S $k2 -d -m minikube tunnel -p $k2

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

# Configuracion de kumactl para hablar con el CP
kubectx $kcp; cp=$(kubectl get svc -A | grep kuma-control-plane | awk '{print $4":5681"}')
cd ~/kuma-1.2.3/bin; ./kumactl config control-planes add --name $kcp --overwrite --address http://$cp
sleep 30

# Configuracion de Data Planes
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

screen -dm bash -c "kubectx kuma-cp; kubectl port-forward svc/kuma-control-plane 5681 -n kuma-system --address 0.0.0.0"

# configurar los data plane proxies para namespace default
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

# configurar los data plane proxies para namespace kuma-demo
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