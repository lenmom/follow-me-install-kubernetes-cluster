#!/bin/bash

basepath=$(cd `dirname $0`; pwd)

if [ ! -f "${basepath}/../USERDATA" ]; then
    echo error, missing file:  ${basepath}/../USERDATA
    exit 1
fi
source ${basepath}/../USERDATA


if [ ! -f "${K8S_INSTALL_ROOT}/work/iphostinfo" ]; then
    echo error, missing file:  ${K8S_INSTALL_ROOT}/work/iphostinfo
    exit 1
fi

if [ ! -f "${K8S_INSTALL_ROOT}/bin/environment.sh" ]; then
    echo error, missing file:  ${K8S_INSTALL_ROOT}/bin/environment.sh
    exit 1
fi


source ${K8S_INSTALL_ROOT}/work/iphostinfo
source ${K8S_INSTALL_ROOT}/bin/environment.sh

##############################################################################################
##############################################################################################
##############################################################################################

cd ${K8S_INSTALL_ROOT}/work
cat > clean-worker-node.sh <<EOF
#!/bin/bash

#worker node:
##停相关进程
systemctl stop kubelet kube-proxy kube-nginx
systemctl disable kubelet kube-proxy kube-nginx

##停容器进程
crictl ps -q | xargs crictl stop
killall -9 containerd-shim-runc-v1 pause

##停 containerd 服务
systemctl stop containerd && systemctl disable containerd

##清理文件
### umount k8s 挂载的目录
#mount |grep -E 'kubelet|cni|containerd' | awk '{print $3}'|xargs umount
### 删除 kubelet 目录
rm -rf ${K8S_DIR}/bin/kubelet
### 删除 docker 目录
rm -rf ${DOCKER_DIR}
### 删除 containerd 目录
rm -rf ${CONTAINERD_DIR}
### 删除 systemd unit 文件
rm -rf /etc/systemd/system/{kubelet,kube-proxy,containerd,kube-nginx}.service
### 删除程序文件
rm -rf ${K8S_INSTALL_ROOT}/bin/*
### 删除证书文件
rm -rf /etc/flanneld/cert /etc/kubernetes/cert

##清理 kube-proxy 和 calico 创建的 iptables
iptables -F && iptables -X && iptables -F -t nat && iptables -X -t nat

EOF

cd ${K8S_INSTALL_ROOT}/work
cat > clean-master-node.sh <<EOF
#!/bin/bash

#master node:
##停相关进程
systemctl stop kube-apiserver kube-controller-manager kube-scheduler
systemctl disable kube-apiserver kube-controller-manager kube-scheduler

##清理文件
### 删除 systemd unit 文件
rm -rf /etc/systemd/system/{kube-apiserver,kube-controller-manager,kube-scheduler}.service
### 删除程序文件
rm -rf ${K8S_INSTALL_ROOT}/bin/{kube-apiserver,kube-controller-manager,kube-scheduler}
### 删除证书文件
rm -rf /etc/flanneld/cert /etc/kubernetes/cert

##############################################################################################

#清理 etcd 集群
systemctl stop etcd && systemctl disable etcd
## 删除 etcd 的工作目录和数据目录
rm -rf ${ETCD_DATA_DIR} ${ETCD_WAL_DIR}
## 删除 systemd unit 文件
rm -rf /etc/systemd/system/etcd.service
## 删除程序文件
rm -rf ${K8S_INSTALL_ROOT}/bin/etcd
## 删除 x509 证书文件
rm -rf /etc/etcd/cert/*

EOF

##############################################################################################


cd ${K8S_INSTALL_ROOT}/work

# destroy k8s master nodes
for master_ip in ${MASTER_IPS[@]}
do
    echo ">>>clean k8s master node ${master_ip}"
    scp ${K8S_INSTALL_ROOT}/work/{clean-worker-node.sh,clean-master-node.sh}  root@${master_ip}:${K8S_INSTALL_ROOT}/
    ssh root@${master_ip} "sh ${K8S_INSTALL_ROOT}/clean-worker-node.sh && sh ${K8S_INSTALL_ROOT}/clean-master-node.sh"
    ssh root@${master_ip} "rm -rf ${K8S_INSTALL_ROOT}"
done

# destroy k8s worker nodes
if [ $MASTER_WORKER_SEPERATED = true ]; then
    for worker_ip in ${WORKER_IPS[@]}
    do
        echo ">>>clean k8s worker node ${worker_ip}"
        scp ${K8S_INSTALL_ROOT}/work/{clean-worker-node.sh}  root@${worker_ip}:${K8S_INSTALL_ROOT}/
        ssh root@${worker_ip} "sh ${K8S_INSTALL_ROOT}/clean-worker-node.sh"
        ssh root@${worker_ip} "rm -rf ${K8S_INSTALL_ROOT}"
    done
fi

##############################################################################################
##############################################################################################
##############################################################################################