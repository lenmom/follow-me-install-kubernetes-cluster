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

#1. prepare docker binary file
prepare_docker_bin()
{
    if [ ! -d "${K8S_INSTALL_ROOT}/work/docker" ]; then
        if [ ! -f "${COMPONENTS_DIR}/docker-${DOCKER_VERSION}.tgz" ]; then
            echo docker installation tarball not exist, will download from internet!!!
            wget -nv https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz
            mv docker-${DOCKER_VERSION}.tgz ${COMPONENTS_DIR}/docker-${DOCKER_VERSION}.tgz
        fi
        tar -xzvf ${COMPONENTS_DIR}/docker-${DOCKER_VERSION}.tgz -C ${K8S_INSTALL_ROOT}/work/
    fi
} 

##############################################################################################

#2. generate docker service file
##notes: 
###a) EOF 前后有双引号，这样 bash 不会替换文档中的变量，如$DOCKER_NETWORK_OPTIONS (这些环境变量是 systemd 负责替换的。)；
###b) dockerd 运行时会调用其它 docker 命令，如 docker-proxy，所以需要将 docker 命令所在的目录加到 PATH 环境变量中；
###c) flanneld 启动时将网络配置写入/run/flannel/docker文件中，dockerd 启动前读取该文件中的环境变量DOCKER_NETWORK_OPTIONS，然后设置 docker0 网桥网段；
###d) 如果指定了多个EnvironmentFile选项，则必须将/run/flannel/docker放在最后(确保 docker0 使用 flanneld 生成的 bip 参数)；
###e) docker 需要以 root 用于运行；
###f) docker 从 1.13 版本开始，可能将iptables FORWARD chain的默认策略设置为DROP，从而导致 ping 其它 Node 上的 Pod IP 失败，遇到这种情况时，需要手动设置策略为ACCEPT：iptables -P FORWARD ACCEPT
process_docker_service() 
{
cat > docker.service <<"EOF"
[Unit]
Description=Docker Application Container Engine
Documentation=http://docs.docker.io

[Service]
WorkingDirectory=##DOCKER_DIR##
Environment="PATH=##K8S_INSTALL_ROOT##/bin:/bin:/sbin:/usr/bin:/usr/sbin"
EnvironmentFile=-/run/flannel/docker
ExecStart=##K8S_INSTALL_ROOT##/bin/dockerd $DOCKER_NETWORK_OPTIONS
ExecReload=/bin/kill -s HUP $MAINPID
Restart=on-failure
RestartSec=5
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
Delegate=yes
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

    sed -i -e "s|##DOCKER_DIR##|${DOCKER_DIR}|" docker.service
    sed -i -e "s|##K8S_INSTALL_ROOT##|${K8S_INSTALL_ROOT}|" docker.service
}
##############################################################################################

#3. docker configration file.
##mosted used dockerhub mirror in china**
###Aliyun: [prefix].mirror.aliyuncs.com
###Tencent: https://mirror.ccs.tencentyun.com
###163: http://hub-mirror.c.163.com
###Azure: dockerhub.azk8s.cn
###ustc: https://docker.mirrors.ustc.edu.cn

##"insecure-registries": ["docker02:35000"],
configrate_docker_daemon() 
{
cat > ${K8S_INSTALL_ROOT}/work/docker-daemon.json <<EOF
{
    "exec-opts": [
      "native.cgroupdriver=systemd"
    ],
    "log-driver": "json-file",
    "storage-driver": "overlay2",
    "storage-opts": [
      "overlay2.override_kernel_check=true"
    ],
    "registry-mirrors": [
      "https://docker.mirrors.ustc.edu.cn",
      "https://5f2jam6c.mirror.aliyuncs.com",
      "https://hub-mirror.c.163.com"
    ],
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

#   cp ${COMPONENTS_DIR}/docker-daemon.json  .
#   sed -i -e "s|##DOCKER_DIR##|${DOCKER_DIR}|" ${K8S_INSTALL_ROOT}/work/docker-daemon.json
}

##############################################################################################

install_docker()
{
    mkdir -p  ${K8S_INSTALL_ROOT}/work/etc/systemd/system/
    mkdir -p  ${K8S_INSTALL_ROOT}/work/etc/docker
    cp ${K8S_INSTALL_ROOT}/work/docker/*  ${K8S_INSTALL_ROOT}/bin/
    chmod +x ${K8S_INSTALL_ROOT}/bin/*

    cp docker.service     ${K8S_INSTALL_ROOT}/work/etc/systemd/system/
    cp docker-daemon.json ${K8S_INSTALL_ROOT}/work/etc/docker/daemon.json

    if [ ! $DRY_RUN = true ]; then
        for worker_ip in ${!iphostmap[@]}    # need to verify whether it is needed every nodes 
        do
            echo ">>> ${worker_ip} distribute docker-${DOCKER_VERSION} bin file"
            scp ${K8S_INSTALL_ROOT}/work/docker/*  root@${worker_ip}:${K8S_INSTALL_ROOT}/bin/
            ssh root@${worker_ip} "chmod +x ${K8S_INSTALL_ROOT}/bin/*"

            echo ">>> ${worker_ip} distribute docker-${DOCKER_VERSION} docker.service"
            scp docker.service root@${worker_ip}:/etc/systemd/system/
            ssh root@${worker_ip} "sed -i -e 's|/sbin/iptables -P FORWARD ACCEPT| |' /etc/rc.local"
            ssh root@${worker_ip} "cat  /sbin/iptables -P FORWARD ACCEPT >> /etc/rc.local"
            ssh root@${worker_ip} "iptables -P FORWARD ACCEPT"

            echo ">>> ${worker_ip} distribute docker-${DOCKER_VERSION} /etc/docker/daemon.json"
            ssh root@${worker_ip} "mkdir -p  /etc/docker/ ${DOCKER_DIR}/{data,exec}"
            scp docker-daemon.json root@${worker_ip}:/etc/docker/daemon.json

            echo ">>> ${worker_ip} start docker.service"
            #launch docker.service
            ssh root@${worker_ip} "systemctl daemon-reload && systemctl enable docker && systemctl restart docker"
            #check docker0 network bridge
            #do ensure docker0 bridge network address is compateble with  flannel.1 network address.
            # if not we can do as follows: 
            #     systemctl stop docker && ip link delete docker0 &&systemctl start docker
            ssh root@${worker_ip} "/usr/sbin/ip addr show flannel.1 && /usr/sbin/ip addr show docker0"
            #docker info
            ssh root@${worker_ip} "ps -elfH|grep docker"
        done
    fi
}

##############################################################################################

cd ${K8S_INSTALL_ROOT}/work

prepare_docker_bin
configrate_docker_daemon
process_docker_service
install_docker

##############################################################################################
##############################################################################################
##############################################################################################