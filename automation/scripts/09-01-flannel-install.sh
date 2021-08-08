#!/bin/bash

basepath=$(cd `dirname $0`; pwd)
COMPONENTS_DIR=${basepath}/../components

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

prepare_flannel_bin()
{
    if [ ! -d "${K8S_INSTALL_ROOT}/work/flannel" ]; then
        if [ ! -f "${COMPONENTS_DIR}/flannel-${FLANNEL_VERSION}-linux-amd64.tar.gz" ]; then
            echo flannel-${FLANNEL_VERSION}-linux-amd64.tar.gz not exist, will download from internet!!!
            wget https://github.com/flannel-io/flannel/releases/download/${FLANNEL_VERSION}/flannel-${FLANNEL_VERSION}-linux-amd64.tar.gz
            mv flannel-${FLANNEL_VERSION}-linux-amd64.tar.gz ${COMPONENTS_DIR}/
        fi

        mkdir -p ${K8S_INSTALL_ROOT}/work/flannel
        tar -xzvf ${COMPONENTS_DIR}/flannel-${FLANNEL_VERSION}-linux-amd64.tar.gz -C ${K8S_INSTALL_ROOT}/work/flannel
    fi 

    cp ${K8S_INSTALL_ROOT}/work/flannel/{flanneld,mk-docker-opts.sh} ${K8S_INSTALL_ROOT}/bin/
    chmod +x ${K8S_INSTALL_ROOT}/bin/*

    if [ ! $DRY_RUN = true ]; then
        for ip in ${!iphostmap[@]}    # need to verify whether it is needed every nodes 
        do
            echo ">>> ${ip} ${K8S_INSTALL_ROOT}/work/flannel/{flanneld,mk-docker-opts.sh}"
            scp ${K8S_INSTALL_ROOT}/work/flannel/{flanneld,mk-docker-opts.sh} root@${ip}:${K8S_INSTALL_ROOT}/bin/
            ssh root@${ip} "chmod +x ${K8S_INSTALL_ROOT}/bin/*"
        done
    fi

}

##############################################################################################

generate_flanneld_certs()
{

cat > ${K8S_INSTALL_ROOT}/work/flanneld-csr.json <<EOF
{
  "CN": "flanneld",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "4Paradigm"
    }
  ]
}
EOF

    ${K8S_INSTALL_ROOT}/bin/cfssl gencert -ca=${K8S_INSTALL_ROOT}/work/ca.pem \
    -ca-key=${K8S_INSTALL_ROOT}/work/ca-key.pem \
    -config=${K8S_INSTALL_ROOT}/work/ca-config.json \
    -profile=kubernetes ${K8S_INSTALL_ROOT}/work/flanneld-csr.json | ${K8S_INSTALL_ROOT}/bin/cfssljson -bare flanneld

    ls ${K8S_INSTALL_ROOT}/work/flanneld*pem

    mkdir -p ${K8S_INSTALL_ROOT}/work/etc/flanneld/cert
    cp  ${K8S_INSTALL_ROOT}/work/flanneld*.pem  ${K8S_INSTALL_ROOT}/work/etc/flanneld/cert/

    if [ ! $DRY_RUN = true ]; then
    
        ETCDCTL_API=2 ${K8S_INSTALL_ROOT}/bin/etcdctl \
        --endpoints=${ETCD_ENDPOINTS} \
        --ca-file=${K8S_INSTALL_ROOT}/work/ca.pem \
        --cert-file=${K8S_INSTALL_ROOT}/work/flanneld.pem \
        --key-file=${K8S_INSTALL_ROOT}/work/flanneld-key.pem \
        mk ${FLANNEL_ETCD_PREFIX}/config '{"Network":"'${CLUSTER_CIDR}'", "SubnetLen": 21, "Backend": {"Type": "vxlan"}}'

        # #write pod network config info into etcd cluster,
        # #this step reqiured to run only once is ok.
        # ETCDCTL_API=3 ${K8S_INSTALL_ROOT}/bin/etcdctl \
        # --endpoints=${ETCD_ENDPOINTS} \
        # --cacert=${K8S_INSTALL_ROOT}/work/ca.pem \
        # --cert=${K8S_INSTALL_ROOT}/work/flanneld.pem \
        # --key=${K8S_INSTALL_ROOT}/work/flanneld-key.pem \
        # put ${FLANNEL_ETCD_PREFIX}/config '{"Network":"'${CLUSTER_CIDR}'", "SubnetLen": 21, "Backend": {"Type": "vxlan"}}'

        # # get value which is set above.
        # ETCDCTL_API=3 ${K8S_INSTALL_ROOT}/bin/etcdctl \
        # --endpoints=${ETCD_ENDPOINTS} \
        # --cacert=${K8S_INSTALL_ROOT}/work/ca.pem \
        # --cert=${K8S_INSTALL_ROOT}/work/flanneld.pem \
        # --key=${K8S_INSTALL_ROOT}/work/flanneld-key.pem \
        # get ${FLANNEL_ETCD_PREFIX}/config 
    fi

    if [ ! $DRY_RUN = true ]; then
        for ip in ${!iphostmap[@]}    # need to verify whether it is needed every nodes 
        do
            echo ">>> ${ip} /etc/flanneld/cert"
            scp ${K8S_INSTALL_ROOT}/work/flanneld*.pem root@${ip}:/etc/flanneld/cert
            ssh root@${ip} "mkdir -p /etc/flanneld/cert"
        done
    fi
}

##############################################################################################

process_flanneld_service()
{
cat > ${K8S_INSTALL_ROOT}/work/flanneld.service << EOF
[Unit]
Description=Flanneld overlay address etcd agent
After=network.target
After=network-online.target
Wants=network-online.target
After=etcd.service
Before=docker.service

[Service]
Type=notify
ExecStart=${K8S_INSTALL_ROOT}/bin/flanneld \\
  -etcd-cafile=/etc/kubernetes/cert/ca.pem \\
  -etcd-certfile=/etc/flanneld/cert/flanneld.pem \\
  -etcd-keyfile=/etc/flanneld/cert/flanneld-key.pem \\
  -etcd-endpoints=${ETCD_ENDPOINTS} \\
  -etcd-prefix=${FLANNEL_ETCD_PREFIX} \\
  -iface=${EffectiveNI} \\
  -ip-masq
ExecStartPost=${K8S_INSTALL_ROOT}/bin/mk-docker-opts.sh -k DOCKER_NETWORK_OPTIONS -d /run/flannel/docker
Restart=always
RestartSec=5
StartLimitInterval=0

[Install]
WantedBy=multi-user.target
RequiredBy=docker.service
EOF

    mkdir -p ${K8S_INSTALL_ROOT}/work/etc/systemd/system/
    cp ${K8S_INSTALL_ROOT}/work/flanneld.service ${K8S_INSTALL_ROOT}/work/etc/systemd/system/

    if [ ! $DRY_RUN = true ]; then
        for node_ip in ${!iphostmap[@]}    # need to verify whether it is needed every nodes 
        do
            echo ">>> ${node_ip} launch flanneld.service"
            scp ${K8S_INSTALL_ROOT}/work/flanneld.service root@${node_ip}:/etc/systemd/system/
            ssh root@${node_ip} "systemctl daemon-reload && systemctl enable flanneld && systemctl restart flanneld"
        done
    fi
}

##############################################################################################

cd  ${K8S_INSTALL_ROOT}/work

prepare_flannel_bin
generate_flanneld_certs
process_flanneld_service

##############################################################################################
##############################################################################################
##############################################################################################