#!/usr/bin/env bash

for instance in controller-0 controller-1 controller-2; do
  ip=$(openstack server show ${instance} -f value -c addresses | cut -f2 -d' ')
  internal_ip=$(openstack server show -f value -c addresses ${instance} \
    | sed 's/kubernetes-the-hard-way=//g' | cut -f1 -d, | xargs)

  ssh ubuntu@${ip} << EOF
sudo mkdir -p /etc/kubernetes/config

wget -q --show-progress --https-only --timestamping \
    "https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kube-apiserver" \
    "https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kube-controller-manager" \
    "https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kube-scheduler" \
    "https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kubectl"

chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl
sudo mv kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/local/bin/

sudo mkdir -p /var/lib/kubernetes/
sudo mv ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem \
  service-account-key.pem service-account.pem \
  encryption-config.yaml /var/lib/kubernetes/
EOF

cat << EOF > kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --advertise-address=${internal_ip} \\
  --allow-privileged=true \\
  --apiserver-count=3 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/audit.log \\
  --authorization-mode=Node,RBAC \\
  --bind-address=0.0.0.0 \\
  --client-ca-file=/var/lib/kubernetes/ca.pem \\
  --enable-admission-plugins=Initializers,NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --enable-swagger-ui=true \\
  --etcd-cafile=/var/lib/kubernetes/ca.pem \\
  --etcd-certfile=/var/lib/kubernetes/kubernetes.pem \\
  --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem \\
  --etcd-servers=https://10.240.0.10:2379,https://10.240.0.11:2379,https://10.240.0.12:2379 \\
  --event-ttl=1h \\
  --experimental-encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \\
  --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem \\
  --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem \\
  --kubelet-https=true \\
  --runtime-config=api/all \\
  --service-account-key-file=/var/lib/kubernetes/service-account.pem \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --service-node-port-range=30000-32767 \\
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \\
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  scp kube-apiserver.service ubuntu@${ip}:
  ssh ubuntu@${ip} sudo mv kube-apiserver.service /etc/systemd/system/kube-apiserver.service

  ssh ubuntu@${ip} sudo mv kube-controller-manager.kubeconfig /var/lib/kubernetes/

cat << EOF > kube-controller-manager.service
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --address=0.0.0.0 \\
  --cluster-cidr=10.200.0.0/16 \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem \\
  --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem \\
  --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \\
  --leader-elect=true \\
  --root-ca-file=/var/lib/kubernetes/ca.pem \\
  --service-account-private-key-file=/var/lib/kubernetes/service-account-key.pem \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --use-service-account-credentials=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  scp kube-controller-manager.service ubuntu@${ip}:
  ssh ubuntu@${ip} sudo mv kube-controller-manager.service /etc/systemd/system/kube-controller-manager.service

  ssh ubuntu@${ip} sudo mv kube-scheduler.kubeconfig /var/lib/kubernetes/

cat <<EOF > kube-scheduler.yaml
apiVersion: componentconfig/v1alpha1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: "/var/lib/kubernetes/kube-scheduler.kubeconfig"
leaderElection:
  leaderElect: true
EOF
  scp kube-scheduler.yaml ubuntu@${ip}:
  ssh ubuntu@${ip} sudo mv kube-scheduler.yaml /etc/kubernetes/config/kube-scheduler.yaml

cat <<EOF > kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --config=/etc/kubernetes/config/kube-scheduler.yaml \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  scp kube-scheduler.service ubuntu@${ip}:
  ssh ubuntu@${ip} sudo mv kube-scheduler.service /etc/systemd/system/kube-scheduler.service

  ssh ubuntu@${ip} sudo systemctl daemon-reload
  ssh ubuntu@${ip} sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler
  ssh ubuntu@${ip} sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler

  # Allow up to 10 seconds for the Kubernetes API Server to fully initialize.
  sleep 10

  ssh ubuntu@${ip} sudo apt-get install -y nginx

cat > kubernetes.default.svc.cluster.local <<EOF
server {
  listen      80;
  server_name kubernetes.default.svc.cluster.local;

  location /healthz {
     proxy_pass                    https://127.0.0.1:6443/healthz;
     proxy_ssl_trusted_certificate /var/lib/kubernetes/ca.pem;
  }
}
EOF
  scp kubernetes.default.svc.cluster.local ubuntu@${ip}:
  ssh ubuntu@${ip} sudo mv kubernetes.default.svc.cluster.local /etc/nginx/sites-available/kubernetes.default.svc.cluster.local

  ssh ubuntu@${ip} << EOF
sudo ln -s /etc/nginx/sites-available/kubernetes.default.svc.cluster.local /etc/nginx/sites-enabled/
sudo systemctl restart nginx
sudo systemctl enable nginx
kubectl get componentstatuses --kubeconfig admin.kubeconfig
curl -H "Host: kubernetes.default.svc.cluster.local" -i http://127.0.0.1/healthz
EOF
done

ip=$(openstack server show controller-0 -f value -c addresses | cut -f2 -d' ')
scp kubernetes.default.svc.cluster.local ubuntu@${ip}:
ssh ubuntu@${ip} sudo mv kubernetes.default.svc.cluster.local /etc/nginx/sites-available/kubernetes.default.svc.cluster.local

ssh ubuntu@${ip} << EOF
cat <<EOF1 | kubectl apply --kubeconfig admin.kubeconfig -f -
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups:
      - ""
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
    verbs:
      - "*"
EOF1

cat <<EOF1 | kubectl apply --kubeconfig admin.kubeconfig -f -
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
  namespace: ""
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: kubernetes
EOF1

EOF

openstack server create k8s-lb --image ubuntu-bionic --flavor m1.small --key-name mykey \
  --network kubernetes-the-hard-way --user-data user-data.txt \
  --security-group kubernetes-the-hard-way-allow-internal
ip=$(openstack floating ip list --long | grep k8s-public-ip | cut -d'|' -f3 | sed 's/ //g')
openstack server add floating ip k8s-lb ${ip}

echo "Giving instances time to become available..."
sleep 120

ssh ubuntu@${ip} << EOF
sudo apt-get install -y haproxy
cat << EOF1 >> haproxy.cfg
frontend localhost
    bind *:6443
    option tcplog
    mode tcp
    default_backend nodes

backend nodes
    mode tcp
    balance roundrobin
    option ssl-hello-chk
    server controller-0 10.240.0.10:6443 check
    server controller-1 10.240.0.11:6443 check
    server controller-2 10.240.0.12:6443 check
EOF1
sudo cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.original
sudo mv haproxy.cfg /etc/haproxy/haproxy.cfg
sudo systemctl restart haproxy
EOF
