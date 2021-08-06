#!/bin/bash

basepath=$(cd `dirname $0`; pwd)
COMPONENTS_DIR=${basepath}/../components
source ${basepath}/../USERDATA

if [ ! -f "${K8S_INSTALL_ROOT}/bin/environment.sh" ]; then
    ${basepath}/02-kubernetes-ca-generation.sh
fi

source ${K8S_INSTALL_ROOT}/work/iphostinfo
source ${K8S_INSTALL_ROOT}/bin/environment.sh

######## 03 kubectl ####
cd ${K8S_INSTALL_ROOT}/work
if [ ! -d "${K8S_INSTALL_ROOT}/work/kubernetes" ]; then
    if [ ! -f "${COMPONENTS_DIR}/kubernetes-server-linux-amd64-1.16.7.tar.gz" ]; then
        echo kubernetes installation tarball not exist, will download from internet!!!
        wget -nv https://dl.k8s.io/v1.16.7/kubernetes-server-linux-amd64.tar.gz # 自行解决翻墙下载问题
        mv kubernetes-server-linux-amd64.tar.gz ${COMPONENTS_DIR}/kubernetes-server-linux-amd64-1.16.7.tar.gz
    fi
    tar -xzvf ${COMPONENTS_DIR}/kubernetes-server-linux-amd64-1.16.7.tar.gz -C ${K8S_INSTALL_ROOT}/work/
fi 
# as I am on a seperate box, where I need to use kubectl to generate configuration file
cp ${K8S_INSTALL_ROOT}/work/kubernetes/server/bin/kubectl ${K8S_INSTALL_ROOT}/bin/
chmod +x ${K8S_INSTALL_ROOT}/bin/*

cd ${K8S_INSTALL_ROOT}/work
for ip in ${!iphostmap[@]}    # it doesn't hurt to have kubectl everywhere
  do
    echo ">>> ${ip}"
    scp kubernetes/server/bin/kubectl root@${ip}:${K8S_INSTALL_ROOT}/bin/
    ssh root@${ip} "chmod +x ${K8S_INSTALL_ROOT}/bin/*"
  done

#### admin cert ####
cd ${K8S_INSTALL_ROOT}/work
cat > admin-csr.json <<EOF
{
  "CN": "admin",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "ST": "MD",
      "L": "Rockville",
      "O": "system:masters",
      "OU": "opsnull"
    }
  ]
}
EOF

cd ${K8S_INSTALL_ROOT}/work
cfssl gencert -ca=${K8S_INSTALL_ROOT}/work/ca.pem \
  -ca-key=${K8S_INSTALL_ROOT}/work/ca-key.pem \
  -config=${K8S_INSTALL_ROOT}/work/ca-config.json \
  -profile=kubernetes admin-csr.json | cfssljson -bare admin

cd ${K8S_INSTALL_ROOT}/work

# 设置集群参数
kubectl config set-cluster kubernetes \
  --certificate-authority=${K8S_INSTALL_ROOT}/work/ca.pem \
  --embed-certs=true \
  --server=https://${MASTER_IPS[0]}:6443 \
  --kubeconfig=kubectl.kubeconfig
# question:  why we use MASTER_IPS[0]  ???  - it is mentioned in Zhangjun's doc

# 设置客户端认证参数
kubectl config set-credentials admin \
  --client-certificate=${K8S_INSTALL_ROOT}/work/admin.pem \
  --client-key=${K8S_INSTALL_ROOT}/work/admin-key.pem \
  --embed-certs=true \
  --kubeconfig=kubectl.kubeconfig

# 设置上下文参数
kubectl config set-context kubernetes \
  --cluster=kubernetes \
  --user=admin \
  --kubeconfig=kubectl.kubeconfig

# 设置默认上下文
kubectl config use-context kubernetes --kubeconfig=kubectl.kubeconfig

cd ${K8S_INSTALL_ROOT}/work
for ip in ${!iphostmap[@]}    # it doesn't hurt if we have it everywhere
  do
    echo ">>> ${ip}"
    ssh root@${ip} "mkdir -p ~/.kube"
    scp kubectl.kubeconfig root@${ip}:~/.kube/config
  done


# optional: copy the kubeconfig file to this central box so it can talk to the k8s cluster
mkdir -p ~/.kube
cp kubectl.kubeconfig ~/.kube/config
