#! /bin/bash
set -e
set -x

sudo curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -

cat <<EOF > kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF

wget https://github.com/containerd/containerd/releases/download/v1.1.0/containerd-1.1.0.linux-amd64.tar.gz
wget https://storage.googleapis.com/cri-containerd-release/cri-containerd-1.1.0.linux-amd64.tar.gz

tar xzvf containerd-1.1.0.linux-amd64.tar.gz
tar xzvf cri-containerd-1.1.0.linux-amd64.tar.gz

sudo mv kubernetes.list /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y apt-transport-https
sudo apt-get install -y kubelet kubeadm

systemctl enable containerd.service
systemctl start containerd

cat <<EOF > 0-containerd.conf
[Service]
Environment="KUBELET_EXTRA_ARGS=--container-runtime=remote --runtime-request-timeout=15m --container-runtime-endpoint=unix:///run/containerd/containerd.sock"
EOF

sudo mv 0-containerd.conf /etc/systemd/system/kubelet.service.d/

cat <<EOF > 20-cloud-provider.conf
Environment="KUBELET_EXTRA_ARGS=--cloud-provider=gce"
EOF

sudo mv 20-cloud-provider.conf /etc/systemd/system/kubelet.service.d/
systemctl daemon-reload
systemctl restart kubelet

EXTERNAL_IP=$(curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip)
INTERNAL_IP=$(curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip)
KUBERNETES_VERSION=$(curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/kubernetes-version)

cat <<EOF > kubeadm.conf
kind: MasterConfiguration
apiVersion: kubeadm.k8s.io/v1alpha1
apiServerCertSANs:
  - 10.96.0.1
  - ${EXTERNAL_IP}
  - ${INTERNAL_IP}
apiServerExtraArgs:
  admission-control: NamespaceLifecycle,LimitRanger,ServiceAccount,PersistentVolumeLabel,DefaultStorageClass,DefaultTolerationSeconds,NodeRestriction,MutatingAdmissionWebhook,ValidatingAdmissionWebhook,ResourceQuota
  feature-gates: AllAlpha=true
  runtime-config: api/all
cloudProvider: gce
criSocket: unix:///run/containerd/containerd.sock
kubernetesVersion: ${KUBERNETES_VERSION}
networking:
  podSubnet: 192.168.0.0/16
noTaintMaster: true
EOF

sudo kubeadm init --config=kubeadm.conf --skip-preflight-checks

sudo chmod 644 /etc/kubernetes/admin.conf

kubectl apply \
  -f https://docs.projectcalico.org/v3.0/getting-started/kubernetes/installation/hosted/kubeadm/1.7/calico.yaml \
  --kubeconfig /etc/kubernetes/admin.conf
