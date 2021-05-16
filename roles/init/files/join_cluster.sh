#!/bin/bash

# 创建worker节点加入集群命令
kubeadm token create --print-join-command > worker_join.sh

# 创建master节点加入集群命令
sed 's/$/ --control-plane --certificate-key/' worker_join.sh > master_join.sh
cert=`kubeadm init --config=/root/kubeadm-config.yaml phase upload-certs --upload-certs 2>/dev/null | tail -1`
sed -i "s/$/  ${cert}/" master_join.sh
