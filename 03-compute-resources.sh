#!/usr/bin/env bash

echo "Creating internal network for k8s..."
openstack network create --provider-network-type vxlan kubernetes-the-hard-way
openstack subnet create --subnet-range 10.240.0.0/24 --network kubernetes-the-hard-way \
    --gateway 10.240.0.1 --dns-nameserver 192.169.5.1 kubernetes-the-hard-way-subnet
openstack router add subnet k8s-router kubernetes-the-hard-way-subnet

echo "Creating internal sec group..."
openstack security group create kubernetes-the-hard-way-allow-internal
openstack security group rule create --ingress --ethertype IPv4 \
    --protocol icmp kubernetes-the-hard-way-allow-internal
openstack security group rule create --egress --ethertype IPv4 \
    --protocol icmp kubernetes-the-hard-way-allow-internal

openstack security group rule create --ingress --ethertype IPv4 \
    --protocol tcp kubernetes-the-hard-way-allow-internal
openstack security group rule create --egress --ethertype IPv4 \
    --protocol tcp kubernetes-the-hard-way-allow-internal

openstack security group rule create --ingress --ethertype IPv4 \
    --protocol udp kubernetes-the-hard-way-allow-internal
openstack security group rule create --egress --ethertype IPv4 \
    --protocol udp kubernetes-the-hard-way-allow-internal

echo "Creating external sec group..."
openstack security group create kubernetes-the-hard-way-allow-external
openstack security group rule create --ingress --ethertype IPv4 \
    --dst-port 22 --protocol tcp kubernetes-the-hard-way-allow-external
openstack security group rule create --ingress --ethertype IPv4 \
    --dst-port 6443 --protocol tcp kubernetes-the-hard-way-allow-external
openstack security group rule create --ingress --ethertype IPv4 \
    --protocol icmp kubernetes-the-hard-way-allow-external

echo "Creating user-data..."
cat << EOF > user-data.txt
#cloud-config
runcmd:
  - 'echo "http_proxy=http://10.196.134.1:3128" >> /etc/environment'
  - 'echo "https_proxy=http://10.196.134.1:3128" >> /etc/environment'
  - 'echo "no_proxy=127.0.0.1,localhost" >> /etc/environment'
EOF

echo "Creating controllers..."
INTERNAL_NETWORK_UUID=$(openstack network show kubernetes-the-hard-way -f value -c id)
for i in 0 1 2; do
  openstack server create controller-${i} \
    --image ubuntu-bionic \
    --flavor m1.small \
    --key-name mykey \
    --nic v4-fixed-ip=10.240.0.1${i},net-id=${INTERNAL_NETWORK_UUID} \
    --user-data user-data.txt \
    --security-group kubernetes-the-hard-way-allow-internal
  ip=$(openstack floating ip create public1 -c floating_ip_address -f value)
  openstack server add floating ip controller-${i} ${ip}
done

echo "Creating workers..."
for i in 0 1 2; do
  openstack server create worker-${i} \
    --image ubuntu-bionic \
    --flavor m1.small \
    --key-name mykey \
    --nic v4-fixed-ip=10.240.0.2${i},net-id=${INTERNAL_NETWORK_UUID} \
    --user-data user-data.txt \
    --security-group kubernetes-the-hard-way-allow-internal
  ip=$(openstack floating ip create public1 -c floating_ip_address -f value)
  openstack server add floating ip worker-${i} ${ip}
done

