#!/bin/bash

basepath=$(cd `dirname $0`; pwd)
COMPONENTS_DIR=${basepath}/../components
source $(cd `dirname $0`; pwd)/../USERDATA

if [ ! -f "${K8S_INSTALL_ROOT}/bin/environment.sh" ]; then
    source $(cd `dirname $0`; pwd)/01-kernel-upgrade.sh
fi

source ${K8S_INSTALL_ROOT}/work/iphostinfo
source ${K8S_INSTALL_ROOT}/bin/environment.sh

########################
if [ ! -d "${K8S_INSTALL_ROOT}/work" ]; then
   mkdir -p ${K8S_INSTALL_ROOT}/work
fi

if [ ! -d "${K8S_INSTALL_ROOT}/cert" ]; then
   mkdir -p ${K8S_INSTALL_ROOT}/cert
fi

if [ ! -d "/etc/kubernetes/cert" ]; then
   mkdir -p /etc/kubernetes/cert
fi

if [ ! -d "${K8S_INSTALL_ROOT}/bin" ]; then
   mkdir -p ${K8S_INSTALL_ROOT}/bin
fi

cd ${K8S_INSTALL_ROOT}/work

# wget -nv https://github.com/cloudflare/cfssl/releases/download/v1.4.1/cfssl_1.4.1_linux_amd64
cp ${COMPONENTS_DIR}/cfssl_linux-amd64 ${K8S_INSTALL_ROOT}/bin/cfssl

# wget -nv https://github.com/cloudflare/cfssl/releases/download/v1.4.1/cfssljson_1.4.1_linux_amd64
cp ${COMPONENTS_DIR}/cfssljson_linux-amd64 ${K8S_INSTALL_ROOT}/bin/cfssljson

# wget -nv https://github.com/cloudflare/cfssl/releases/download/v1.4.1/cfssl-certinfo_1.4.1_linux_amd64
cp ${COMPONENTS_DIR}/cfssl-certinfo_linux-amd64 ${K8S_INSTALL_ROOT}/bin/cfssl-certinfo

chmod +x ${K8S_INSTALL_ROOT}/bin/*
export PATH=${K8S_INSTALL_ROOT}/bin:$PATH

#### CA ####
cd ${K8S_INSTALL_ROOT}/work
cat > ca-config.json <<EOF
{
  "signing": {	
    "default": {
      "expiry": "876000h"
    },
    "profiles": {
      "kubernetes": {
        "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ],
        "expiry": "876000h"
      }
    }
  }
}
EOF

cd ${K8S_INSTALL_ROOT}/work
cat > ca-csr.json <<EOF
{
  "CN": "kubernetes-ca",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "ST": "MD",
      "L": "Rockville",
      "O": "k8s",
      "OU": "opsnull"
    }
  ],
  "ca": {
    "expiry": "876000h"
 }
}
EOF

cd ${K8S_INSTALL_ROOT}/work
cfssl gencert -initca ca-csr.json | cfssljson -bare ca

cd ${K8S_INSTALL_ROOT}/work
for ip in ${!iphostmap[@]}    # need to verify whether it is needed every nodes 
  do
    echo ">>> ${ip}"
    ssh root@${ip} "mkdir -p /etc/kubernetes/cert"
    scp ca*.pem ca-config.json root@${ip}:/etc/kubernetes/cert
  done

# as we run the cert on this box, not neccessarily on the k8s nodes, we need to copy the files on this localbox
cp ca*.pem ca-config.json /etc/kubernetes/cert
