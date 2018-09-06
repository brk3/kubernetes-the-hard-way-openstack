#!/usr/bin/env bash

echo "Cleaning up..."
for i in $(openstack server list -f value -c ID); do
  openstack server delete $i
done
for i in $(openstack floating ip list -f value -c ID); do
  openstack floating ip delete $i
done
for i in $(openstack router list -f value -c ID); do
  for j in $(openstack port list --router $i -f value -c ID); do
    openstack router remove port $i $j
  done
done
for i in $(openstack router list -f value -c ID); do
  openstack router delete $i
done
for i in $(openstack subnet list -f value -c ID); do
  openstack subnet delete $i
done
for i in $(openstack network list -f value -c ID); do
  openstack network delete $i
done
for i in $(openstack security group list -f value -c ID); do
  openstack security group delete $i
done
for i in $(openstack image list -f value -c ID); do
  openstack image delete $i
done
for i in $(openstack flavor list -f value -c ID); do
  openstack flavor delete $i
done
for i in $(openstack keypair list -f value -c Name); do
  openstack keypair delete $i
done

echo "Creating provider network and router..."
openstack network create --external --provider-physical-network physnet1 \
    --provider-network-type flat public1
openstack subnet create --no-dhcp \
    --allocation-pool start=192.169.5.150,end=192.169.5.199 --network public1 \
    --subnet-range 192.169.5.0/24 --gateway 192.169.5.1 public1-subnet
openstack router create k8s-router
openstack router set --external-gateway public1 k8s-router

echo "Creating image..."
wget https://cloud-images.ubuntu.com/bionic/current/bionic-server-cloudimg-amd64.img
openstack image create --disk-format qcow2 --container-format bare --public \
    --file bionic-server-cloudimg-amd64.img ubuntu-bionic
rm -f bionic-server-cloudimg-amd64.img

echo "Creating flavor..."
openstack flavor create --ram 2048 --disk 20 --vcpus 2 m1.small

echo "Creating keypair..."
openstack keypair create --public-key ~/.ssh/id_rsa.pub mykey
