#!/usr/bin/env bash

for instance in controller-0 controller-1 controller-2; do
  ip=$(openstack server show ${instance} -f value -c addresses | cut -f2 -d' ')
  internal_ip=$(openstack server show -f value -c addresses ${instance} \
    | sed 's/kubernetes-the-hard-way=//g' | cut -f1 -d, | xargs)

  ssh ubuntu@${ip} << EOF
wget https://github.com/coreos/etcd/releases/download/v3.3.5/etcd-v3.3.5-linux-amd64.tar.gz
tar -xvf etcd-v3.3.5-linux-amd64.tar.gz
sudo mv etcd-v3.3.5-linux-amd64/etcd* /usr/local/bin/
sudo mkdir -p /etc/etcd /var/lib/etcd
sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/
EOF

cat << EOF > etcd.service
[Unit]
Description=etcd
Documentation=https://github.com/coreos

[Service]
ExecStart=/usr/local/bin/etcd \\
  --name ${instance} \\
  --cert-file=/etc/etcd/kubernetes.pem \\
  --key-file=/etc/etcd/kubernetes-key.pem \\
  --peer-cert-file=/etc/etcd/kubernetes.pem \\
  --peer-key-file=/etc/etcd/kubernetes-key.pem \\
  --trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --initial-advertise-peer-urls https://${internal_ip}:2380 \\
  --listen-peer-urls https://${internal_ip}:2380 \\
  --listen-client-urls https://${internal_ip}:2379,https://127.0.0.1:2379 \\
  --advertise-client-urls https://${internal_ip}:2379 \\
  --initial-cluster-token etcd-cluster-0 \\
  --initial-cluster controller-0=https://10.240.0.10:2380,controller-1=https://10.240.0.11:2380,controller-2=https://10.240.0.12:2380 \\
  --initial-cluster-state new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  scp etcd.service ubuntu@${ip}:
  ssh ubuntu@${ip} sudo mv etcd.service /etc/systemd/system/etcd.service

  ssh ubuntu@${ip} << EOF
sudo systemctl daemon-reload
sudo systemctl enable etcd
sudo systemctl start etcd
sudo ETCDCTL_API=3 etcdctl member list \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/etcd/ca.pem \
    --cert=/etc/etcd/kubernetes.pem \
    --key=/etc/etcd/kubernetes-key.pem
EOF
done
