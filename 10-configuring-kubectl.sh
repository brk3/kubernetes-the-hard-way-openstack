#!/usr/bin/env bash

ip=$(openstack floating ip list --long | grep k8s-public-ip | cut -d'|' -f3 | sed 's/ //g')

export no_proxy=$no_proxy,${ip}
export NO_PROXY=$NO_PROXY,${ip}

kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=https://${ip}:6443

kubectl config set-credentials admin \
  --client-certificate=admin.pem \
  --client-key=admin-key.pem

kubectl config set-context kubernetes-the-hard-way \
  --cluster=kubernetes-the-hard-way \
  --user=admin

kubectl config use-context kubernetes-the-hard-way

kubectl get componentstatuses
kubectl get nodes

