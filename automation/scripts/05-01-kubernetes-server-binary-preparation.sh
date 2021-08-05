#!/bin/bash

basepath=$(cd `dirname $0`; pwd)
COMPONENTS_DIR=${basepath}/../components

if [ ! -d "/opt/k8s/work/etcd-v3.4.3-linux-amd64" ]; then
    ${basepath}/04-etcd-install.sh
fi

source ${basepath}/../USERDATA
source /opt/k8s/work/iphostinfo
source /opt/k8s/bin/environment.sh

###### 05-01 master deployment ####

cd /opt/k8s/work

if [ ! -d "/opt/k8s/work/kubernetes" ]; then
    if [ ! -f "${COMPONENTS_DIR}/kubernetes-server-linux-amd64-1.16.7.tar.gz" ]; then
        echo kubernetes installation tarball not exist, will download from internet!!!
        wget -nv https://dl.k8s.io/v1.16.7/kubernetes-client-linux-amd64.tar.gz # 自行解决翻墙下载问题
        mv kubernetes-client-linux-amd64.tar ${COMPONENTS_DIR}/kubernetes-server-linux-amd64-1.16.7.tar.gz
    fi
    tar -xzvf ${COMPONENTS_DIR}/kubernetes-server-linux-amd64-1.16.7.tar.gz -C /opt/k8s/work/
fi 

cd /opt/k8s/work
# if the master and nodes are different, then we don't need to cp controller, apiserve to worker hosts
for master_ip in ${MASTER_IPS[@]}
  do
    echo ">>> ${master_ip}"
    scp kubernetes/server/bin/{apiextensions-apiserver,kube-apiserver,kube-controller-manager,kube-proxy,kube-scheduler,kubeadm,kubectl,kubelet,mounter} root@${master_ip}:/opt/k8s/bin/
    ssh root@${master_ip} "chmod +x /opt/k8s/bin/*"
  done

if [ $MASTER_WORKER_SEPERATED == true ]; then
  # they are seperated. the worker nodes don't need k8s servers
  for worker_ip in ${WORKER_IPS[@]}
  do
    echo ">>> ${worker_ip}"
    scp kubernetes/server/bin/{kube-proxy,kubeadm,kubectl,kubelet}  root@${worker_ip}:/opt/k8s/bin/
    ssh root@${worker_ip} "chmod +x /opt/k8s/bin/*"
  done
fi


# we need to use kubeadm command in 06-04.sh to create token
scp kubernetes/server/bin/{apiextensions-apiserver,kube-apiserver,kube-controller-manager,kube-proxy,kube-scheduler,kubeadm,kubectl,kubelet,mounter} /opt/k8s/bin/
chmod +x /opt/k8s/bin/*
