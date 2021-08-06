#!/bin/bash

basepath=$(cd `dirname $0`; pwd)
COMPONENTS_DIR=${basepath}/../components

source ${basepath}/../USERDATA

cd ${K8S_INSTALL_ROOT}/work
if [ ! -d "${K8S_INSTALL_ROOT}/work/calico-release-v3.12.0" ]; then
    if [ ! -f "${COMPONENTS_DIR}/calico-release-v3.12.0.tgz" ]; then
        echo calico installation tarball not exist, will download from internet!!!
        #curl https://docs.projectcalico.org/manifests/calico.yaml -O     # this is newer version
        curl -L -O https://github.com/projectcalico/calico/releases/download/v3.12.0/release-v3.12.0.tgz
        mv release-v3.12.0.tgz ${COMPONENTS_DIR}/calico-release-v3.12.0.tgz
    fi
    tar -xzvf ${COMPONENTS_DIR}/calico-release-v3.12.0.tgz -C ${K8S_INSTALL_ROOT}/work/
    mv ${K8S_INSTALL_ROOT}/work/release-v3.12.0  ${K8S_INSTALL_ROOT}/work/calico-release-v3.12.0
fi 

## to be refined for the yaml file: /opt/k8s !!!
sed -e "s/192.168.0.0/172.30.0.0/" -e "s/path: \/opt\/cni\/bin/path: \/opt\/k8s\/bin/"  release-v3.12.0/k8s-manifests/calico.yaml > calico.yaml

${K8S_INSTALL_ROOT}/bin/kubectl apply -f calico.yaml

echo "sleep 60 seconds now, wait the calico to be ready"
sleep 60
