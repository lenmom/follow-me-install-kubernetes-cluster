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

#1.uninstall older version of docker
uninstall_docker() 
{
    if [ ! $DRY_RUN = true ]; then
        for worker_ip in ${!iphostmap[@]}    # need to verify whether it is needed every nodes 
        do
            ##query if docker installed
            ssh root@${worker_ip} "rpm -qa |grep docker"

            ssh root@${worker_ip} "yum -y  remove docker  docker-common docker-selinux docker-engine"
            ##remove docker images and containers data.
            ssh root@${worker_ip} "rm -rf /var/lib/docker"
            ssh root@${worker_ip} "rm -rf /etc/systemd/system/docker.service.d"
            ssh root@${worker_ip} "rm -rf /var/run/docker"
        done    
    fi
}

##############################################################################################

#2. install docker
install_docker() 
{
    if [ ! $DRY_RUN = true ]; then
        for worker_ip in ${!iphostmap[@]}    # need to verify whether it is needed every nodes 
        do
            ssh root@${worker_ip} "yum install -y yum-utils device-mapper-persistent-data lvm2"
            ssh root@${worker_ip} "yum-config-manager  --add-repo  http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo"
            #ssh root@${worker_ip} "yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo"

            ##search docker version list in the repo
            ssh root@${worker_ip} "yum list docker-ce --showduplicates | sort -r"

            ##yum install  -y <FQPN> 
            ssh root@${worker_ip} "yum install -y docker-ce-${DOCKER_VERSION}.ce-3.el7"
        done    
    fi
}
##############################################################################################

#3. docker configration file.

##mosted used dockerhub mirror in china**
###Aliyun: [prefix].mirror.aliyuncs.com
###Tencent: https://mirror.ccs.tencentyun.com
###163: http://hub-mirror.c.163.com
###Azure: dockerhub.azk8s.cn
###ustc: https://docker.mirrors.ustc.edu.cn

configrate_docker() 
{
##"insecure-registries": ["docker02:35000"],
cat > docker-daemon.json <<EOF
{
    "exec-opts": ["native.cgroupdriver=systemd"],   
    "log-driver": "json-file", 
    "storage-driver": "overlay2",
    "storage-opts": ["overlay2.override_kernel_check=true"]
    "registry-mirrors": ["https://docker.mirrors.ustc.edu.cn","https://5f2jam6c.mirror.aliyuncs.com","https://hub-mirror.c.163.com"],
    "max-concurrent-downloads": 20,
    "live-restore": true,
    "max-concurrent-uploads": 10,
    "debug": true,
    "data-root": "${DOCKER_DIR}/data",
    "exec-root": "${DOCKER_DIR}/exec",
    "log-opts": {
      "max-size": "100m",
      "max-file": "5"
    }
}
EOF

    mkdir -p  ${K8S_INSTALL_ROOT}/etc/docker
    cp docker-daemon.json ${K8S_INSTALL_ROOT}/etc/docker/daemon.json

    if [ ! $DRY_RUN = true ]; then
        echo ">>> ${worker_ip} distribute docker-${DOCKER_VERSION} /etc/docker/daemon.json"
        ssh root@${worker_ip} "mkdir -p  /etc/docker/ ${DOCKER_DIR}/{data,exec}"
        scp docker-daemon.json root@${worker_ip}:/etc/docker/daemon.json
    fi
}

##############################################################################################
#4. process docker.service

process_docker_service() {
cat > docker.service <<"EOF"
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com

[Service]
WorkingDirectory=##DOCKER_DIR##
Environment="PATH=##K8S_INSTALL_ROOT##/bin:/bin:/sbin:/usr/bin:/usr/sbin"
EnvironmentFile=-/run/flannel/docker
# the default is not to use systemd for cgroups because the delegate issues still
# exists and systemd currently does not support the cgroup feature set required
# for containers run by docker
ExecStart=/usr/bin/dockerd $DOCKER_NETWORK_OPTIONS
ExecReload=/bin/kill -s HUP $MAINPID
# restart the docker process if it exits prematurely
Restart=on-failure
RestartSec=5
# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
# set delegate yes so that systemd does not reset the cgroups of docker containers
Delegate=yes
# kill only the docker process, not all processes in the cgroup
KillMode=process

# Uncomment TasksMax if your systemd version supports it.
# Only systemd 226 and above support this version.
#TasksMax=infinity
TimeoutStartSec=0
StartLimitBurst=3
StartLimitInterval=60s

[Install]
WantedBy=multi-user.target
EOF

    sed -i -e "s|##DOCKER_DIR##|${DOCKER_DIR}|" docker.service
    sed -i -e "s|##K8S_INSTALL_ROOT##|${K8S_INSTALL_ROOT}|" docker.service

    mkdir -p  ${K8S_INSTALL_ROOT}/etc/systemd/system/
    mkdir -p  ${K8S_INSTALL_ROOT}/etc/docker
    cp docker.service     ${K8S_INSTALL_ROOT}/etc/systemd/system/
    cp docker-daemon.json ${K8S_INSTALL_ROOT}/etc/docker/daemon.json
    
    if [ ! $DRY_RUN = true ]; then
        for worker_ip in ${!iphostmap[@]}    # need to verify whether it is needed every nodes 
        do
            scp docker.service root@${worker_ip}:/etc/systemd/system/
            ssh root@${worker_ip} "systemctl daemon-reload && systemctl enable docker && systemctl restart docker"
        done    
    fi
}

##############################################################################################

cd ${K8S_INSTALL_ROOT}/work

uninstall_docker
install_docker
configrate_docker
process_docker_service

##############################################################################################
##############################################################################################
##############################################################################################