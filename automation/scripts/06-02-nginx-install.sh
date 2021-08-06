#!/bin/bash

basepath=$(cd `dirname $0`; pwd)
COMPONENTS_DIR=${basepath}/../components
source ${basepath}/../USERDATA

if [ ! -f "${K8S_INSTALL_ROOT}/work/kube-scheduler.service.template" ]; then
    ${basepath}/05-04-kube-scheduler-install.sh
fi


source ${K8S_INSTALL_ROOT}/work/iphostinfo
source ${K8S_INSTALL_ROOT}/bin/environment.sh

cd ${K8S_INSTALL_ROOT}/work
if [ ! -d "${K8S_INSTALL_ROOT}/work/nginx-1.15.3" ]; then
    if [ ! -f "${COMPONENTS_DIR}/nginx-1.15.3.tar.gz" ]; then
        echo nginx installation tarball not exist, will download from internet!!!
        wget -nv http://nginx.org/download/nginx-1.15.3.tar.gz
        mv nginx-1.15.3.tar.gz ${COMPONENTS_DIR}/nginx-1.15.3.tar.gz
    fi
    tar -xzvf ${COMPONENTS_DIR}/nginx-1.15.3.tar.gz -C ${K8S_INSTALL_ROOT}/work/
fi 

cd ${K8S_INSTALL_ROOT}/work/nginx-1.15.3
mkdir nginx-prefix
yum install -y gcc make
./configure --with-stream --without-http --prefix=$(pwd)/nginx-prefix --without-http_uwsgi_module --without-http_scgi_module --without-http_fastcgi_module

cd ${K8S_INSTALL_ROOT}/work/nginx-1.15.3
make && make install

######BC the ngix proxy s mainly on worker sidem, but if we want to show master on kubectl get nodes command ======
cd ${K8S_INSTALL_ROOT}/work
if [ $MASTER_WORKER_SEPERATED = true ] &&  [ "$SHOW_MASTER" = "true" ]; then
  for machine_ip in ${!iphostmap[@]}
  do
    echo ">>> ${machine_ip} scp nginx binary"
    ssh root@${machine_ip} "mkdir -p ${K8S_INSTALL_ROOT}/kube-nginx/{conf,logs,sbin}"
    scp ${K8S_INSTALL_ROOT}/work/nginx-1.15.3/nginx-prefix/sbin/nginx  root@${machine_ip}:${K8S_INSTALL_ROOT}/kube-nginx/sbin/kube-nginx
    ssh root@${machine_ip} "chmod a+x ${K8S_INSTALL_ROOT}/kube-nginx/sbin/*"
  done
else
  for worker_ip in ${WORKER_IPS[@]}
  do
    echo ">>> ${worker_ip} scp nginx binary"
    ssh root@${worker_ip} "mkdir -p ${K8S_INSTALL_ROOT}/kube-nginx/{conf,logs,sbin}"
    scp ${K8S_INSTALL_ROOT}/work/nginx-1.15.3/nginx-prefix/sbin/nginx  root@${worker_ip}:${K8S_INSTALL_ROOT}/kube-nginx/sbin/kube-nginx
    ssh root@${worker_ip} "chmod a+x ${K8S_INSTALL_ROOT}/kube-nginx/sbin/*"
  done
fi

cd ${K8S_INSTALL_ROOT}/work
cat > kube-nginx.conf << EOF
worker_processes 1;

events {
    worker_connections  1024;
}

stream {
    upstream backend {
        hash $remote_addr consistent;
`for ip in ${MASTER_IPS[@]};do echo "       server ${ip}:6443 max_fails=3 fail_timeout=30s;";done`
    }

    server {
        listen 127.0.0.1:8443;
        proxy_connect_timeout 1s;
        proxy_pass backend;
    }
}
EOF

cd ${K8S_INSTALL_ROOT}/work
if [ $MASTER_WORKER_SEPERATED = true ] &&  [ "$SHOW_MASTER" = "true" ]; then
  for machine_ip in ${!iphostmap[@]}
  do
    echo ">>> ${machine_ip} scp nginx.conf"
    scp kube-nginx.conf  root@${machine_ip}:${K8S_INSTALL_ROOT}/kube-nginx/conf/kube-nginx.conf
  done
else
  for worker_ip in ${WORKER_IPS[@]}
  do
    echo ">>> ${worker_ip} scp nginx.conf"
    scp kube-nginx.conf  root@${worker_ip}:${K8S_INSTALL_ROOT}/kube-nginx/conf/kube-nginx.conf
  done
fi

cd ${K8S_INSTALL_ROOT}/work
cat > kube-nginx.service <<EOF
[Unit]
Description=kube-apiserver nginx proxy
After=network.target
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
ExecStartPre=${K8S_INSTALL_ROOT}/kube-nginx/sbin/kube-nginx -c ${K8S_INSTALL_ROOT}/kube-nginx/conf/kube-nginx.conf -p ${K8S_INSTALL_ROOT}/kube-nginx -t
ExecStart=${K8S_INSTALL_ROOT}/kube-nginx/sbin/kube-nginx -c ${K8S_INSTALL_ROOT}/kube-nginx/conf/kube-nginx.conf -p ${K8S_INSTALL_ROOT}/kube-nginx
ExecReload=${K8S_INSTALL_ROOT}/kube-nginx/sbin/kube-nginx -c ${K8S_INSTALL_ROOT}/kube-nginx/conf/kube-nginx.conf -p ${K8S_INSTALL_ROOT}/kube-nginx -s reload
PrivateTmp=true
Restart=always
RestartSec=5
StartLimitInterval=0
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

cd ${K8S_INSTALL_ROOT}/work
if [ $MASTER_WORKER_SEPERATED = true ] &&  [ "$SHOW_MASTER" = "true" ]; then
  for machine_ip in ${!iphostmap[@]}
  do
    echo ">>> ${machine_ip} scp kube-nginx.service"
    scp kube-nginx.service  root@${machine_ip}:/etc/systemd/system/
  done
else
  for worker_ip in ${WORKER_IPS[@]}
  do
    echo ">>> ${worker_ip} scp kube-nginx.service"
    scp kube-nginx.service  root@${worker_ip}:/etc/systemd/system/
  done
fi

cd ${K8S_INSTALL_ROOT}/work
if [ $MASTER_WORKER_SEPERATED = true ] &&  [ "$SHOW_MASTER" = "true" ]; then
  for machine_ip in ${!iphostmap[@]}
  do
    echo ">>> ${machine_ip} start nginx"
    ssh root@${machine_ip} "systemctl daemon-reload && systemctl enable kube-nginx && systemctl restart kube-nginx"
  done
else
  for worker_ip in ${WORKER_IPS[@]}
  do
    echo ">>> ${worker_ip} start nginx"
    ssh root@${worker_ip} "systemctl daemon-reload && systemctl enable kube-nginx && systemctl restart kube-nginx"
  done
fi
