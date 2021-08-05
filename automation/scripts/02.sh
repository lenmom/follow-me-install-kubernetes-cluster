#!/bin/bash

basepath=$(cd `dirname $0`; pwd)
COMPONENTS_DIR=${basepath}/../components

if [ ! -f "/opt/k8s/bin/environment.sh" ]; then
    source $(cd `dirname $0`; pwd)/01.sh
fi

source /opt/k8s/work/iphostinfo
source /opt/k8s/bin/environment.sh

########################
if [ ! -d "/opt/k8s/work" ]; then
   mkdir -p /opt/k8s/work
fi

if [ ! -d "/opt/k8s/cert" ]; then
   mkdir -p /opt/k8s/cert
fi

if [ ! -d "/etc/kubernetes/cert" ]; then
   mkdir -p /etc/kubernetes/cert
fi

if [ ! -d "/opt/k8s/bin" ]; then
   mkdir -p /opt/k8s/bin
fi

cd /opt/k8s/work

# wget -nv https://github.com/cloudflare/cfssl/releases/download/v1.4.1/cfssl_1.4.1_linux_amd64
cp ${COMPONENTS_DIR}/cfssl_linux-amd64 /opt/k8s/bin/cfssl

# wget -nv https://github.com/cloudflare/cfssl/releases/download/v1.4.1/cfssljson_1.4.1_linux_amd64
cp ${COMPONENTS_DIR}/cfssljson_linux-amd64 /opt/k8s/bin/cfssljson

# wget -nv https://github.com/cloudflare/cfssl/releases/download/v1.4.1/cfssl-certinfo_1.4.1_linux_amd64
cp ${COMPONENTS_DIR}/cfssl-certinfo_linux-amd64 /opt/k8s/bin/cfssl-certinfo

chmod +x /opt/k8s/bin/*
export PATH=/opt/k8s/bin:$PATH

#### CA ####
cd /opt/k8s/work
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

cd /opt/k8s/work
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

cd /opt/k8s/work
cfssl gencert -initca ca-csr.json | cfssljson -bare ca

cd /opt/k8s/work
for ip in ${!iphostmap[@]}    # need to verify whether it is needed every nodes 
  do
    echo ">>> ${ip}"
    ssh root@${ip} "mkdir -p /etc/kubernetes/cert"
    scp ca*.pem ca-config.json root@${ip}:/etc/kubernetes/cert
  done

# as we run the cert on this box, not neccessarily on the k8s nodes, we need to copy the files on this localbox
cp ca*.pem ca-config.json /etc/kubernetes/cert
