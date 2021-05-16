#!/bin/bash
# Author: yuhui@live.it

# 将ansible-playbook变量替换成shell变量并且导入到脚本环境中
sed 's/: /=/g' group_vars/all >> env.tmp
source env.tmp

# 设置/etc/hosts /etc/resolv.conf并禁止篡改
# mv /etc/hosts{,.bak} && cp roles/hostname/files/hosts /etc/hosts
# mv /etc/resolv.conf{,.bak} && cp roles/hostname/files/resolv.conf /etc/resolv.conf
# chattr +i /etc/resolv.conf && chattr +i /etc/hosts
mv /etc/hosts{,.bak} && cp roles/hostname/files/hosts /etc/hosts
chattr +i /etc/hosts

# 安装EPEL
yum install epel-release -y

# 安装Ansible
yum install ansible  -y && echo "Ansible安装完成"

# 生成密钥并分发到所有节点
mkdir -p /root/.ssh
ssh-keygen -t rsa -N '' -f /root/.ssh/id_rsa -q
read -p "请输入统一的root密码:" Root_Password
for i in `grep host hosts | awk '{print $1}'`;do
    sshpass -p${Root_Password} ssh-copy-id -o "StrictHostKeyChecking no"  -i /root/.ssh/id_rsa.pub ${i}
    echo "${i} 密钥设置完成"
done

# 生成证书etcd证书,默认配置是10年有效期,可以通过修改cfssl/ca-config.json文件中expiry字段设置所需有效期
cfssl/cfssl gencert \
    -initca cfssl/etcd-ca-csr.json | cfssl/cfssljson -bare roles/etcd/files/etcd-ca
cfssl/cfssl gencert \
    -ca=roles/etcd/files/etcd-ca.pem \
    -ca-key=roles/etcd/files/etcd-ca-key.pem \
    -config=cfssl/ca-config.json \
    -hostname=${etcd_host} \
    -profile=kubernetes cfssl/etcd-ca-csr.json | cfssl/cfssljson -bare roles/etcd/files/etcd

# 初始化集群
ansible-playbook -i hosts init.yml

# 等待集群Pod初始化完成
echo "等待集群Pod初始化完成"
sleep 60

# 添加Kubernetes源
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF

# 安装Kubectl
yum install -y kubectl-${kubernetes_version}

mkdir -p ~/.kube
cp fetch_files/admin.conf ~/.kube/config
chmod 600 ~/.kube/config

# 安装Docker依赖
yum install -y \
    lvm2 \
    yum-utils \
    device-mapper-persistent-data

# 添加Docker源
yum-config-manager \
    --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo

# 安装Docker
yum install -y \
    docker-ce-${docker_version} \
    docker-ce-cli-${docker_version}
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["https://dbzucv6w.mirror.aliyuncs.com"],
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
}
EOF
systemctl restart docker && systemctl enable docker

# 删除shell变量文件
rm -f env.tmp
echo "集群初始化完成!!!"
kubectl get nodes && kubectl top nodes && kubectl get pod -A 