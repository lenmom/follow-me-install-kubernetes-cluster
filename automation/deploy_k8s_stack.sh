#!/bin/bash

set -e

CURRENT_DIR=$(cd `dirname $0`; pwd)
source ${CURRENT_DIR}/USERDATA

# clean the staged files for the previous run (if applicable)
# rm -rf ${K8S_INSTALL_ROOT}  /etc/kubernetes

cd ${CURRENT_DIR}/scripts

##############################################################################################
##############################################################################################
##############################################################################################

deploy_k8s_dockerd()
{
     # #./00.sh 2>&1 | tee /tmp/00.log
    # # |tee casues wrapper contines to next step even the 00.sh called exit 1
    # # If there is user data error, it should not continue at all.
    # # so I take away the tee for the 00.sh
    ./00-hosts-preparation.sh
    # # as 00-hosts-preparation.sh is only validating user inout, no need to redirect to log file

    ./01-kernel-upgrade.sh 2>&1 | tee /tmp/01-kernel-upgrade.log

    ./02-kubernetes-ca-generation.sh 2>&1 | tee /tmp/02-kubernetes-ca-generation.log

    ./03-kubectl-ca-generation.sh 2>&1 | tee /tmp/03-kubectl-ca-generation.log

    ./04-etcd-install.sh 2>&1 | tee /tmp/04-etcd-install.log

    ./05-01-kubernetes-server-binary-preparation.sh 2>&1 | tee /tmp/05-01-kubernetes-server-binary-preparation.log

    ./05-02-kube-apiserver-install.sh 2>&1 | tee /tmp/05-02-kube-apiserver-install.log

    ./05-03-kube-controller-manager_install.sh 2>&1 | tee /tmp/05-03-kube-controller-manager_install.log

    ./05-04-kube-scheduler-install.sh 2>&1 | tee /tmp/05-04-kube-scheduler-install.log
}

deploy_k8s_containerd()
{
    # #./00.sh 2>&1 | tee /tmp/00.log
    # # |tee casues wrapper contines to next step even the 00.sh called exit 1
    # # If there is user data error, it should not continue at all.
    # # so I take away the tee for the 00.sh
    ./00-hosts-preparation.sh
    # # as 00-hosts-preparation.sh is only validating user inout, no need to redirect to log file

    ./01-kernel-upgrade.sh 2>&1 | tee /tmp/01-kernel-upgrade.log

    ./02-kubernetes-ca-generation.sh 2>&1 | tee /tmp/02-kubernetes-ca-generation.log

    ./03-kubectl-ca-generation.sh 2>&1 | tee /tmp/03-kubectl-ca-generation.log

    ./04-etcd-install.sh 2>&1 | tee /tmp/04-etcd-install.log

    ./05-01-kubernetes-server-binary-preparation.sh 2>&1 | tee /tmp/05-01-kubernetes-server-binary-preparation.log

    ./05-02-kube-apiserver-install.sh 2>&1 | tee /tmp/05-02-kube-apiserver-install.log

    ./05-03-kube-controller-manager_install.sh 2>&1 | tee /tmp/05-03-kube-controller-manager_install.log

    ./05-04-kube-scheduler-install.sh 2>&1 | tee /tmp/05-04-kube-scheduler-install.log
}

deploy_k8s_dockerd
./09-01-flannel-install.sh 2>&1 | tee /tmp/09-01-flannel-install.log

# ./06-01.sh 2>&1 | tee /tmp/06-01.log

# ./06-02-nginx-install.sh 2>&1 | tee /tmp/06-02-nginx-install.log

# ./06-03-containerd-install.sh 2>&1 | tee /tmp/06-03-containerd-install.log

# ./06-04-kubelet-install.sh 2>&1 | tee /tmp/06-04-kubelet-install.log

# ./06-05-kube-proxy-install.sh 2>&1 | tee /tmp/06-05-kube-proxy-install.log

# ./06-06-calico-install.sh 2>&1 | tee /tmp/06-06-calico-install.log

# ./07-test.sh 2>&1 | tee /tmp/07-01.log

# there is no 08-01 as it was a description

# ./08-02-coredns-install.sh 2>&1 | tee /tmp/08-02-coredns-install.log &
# tee holds the session even though I put the kubectl port-forward command in background
# I don't think there is dependency among the 08-03,08-04,08-05, so it should be ok

# ./08-03-dashboard-install.sh 2>&1 | tee /tmp/08-03-dashboard-install.log &

# ./08-04-kube-prometheus-install.sh 2>&1 | tee /tmp/08-04-kube-prometheus-install.log &

# ./08-05-EFK.sh 2>&1 | tee /tmp/08-05-EFK.log &
