#!/usr/bin/env bash
set -Eeuo pipefail

readonly versions_file=${1:?Usage: install-kubernetes-tools.sh VERSIONS_FILE}
# shellcheck source=/dev/null
source "$versions_file"

required_variables=(
  MINIKUBE_VERSION
  MINIKUBE_SHA256
  KUBECTX_VERSION
  KUBECTX_SHA256
  KUBENS_SHA256
)
for variable in "${required_variables[@]}"; do
  if [[ -z ${!variable:-} ]]; then
    echo "Missing external-tool metadata: $variable" >&2
    exit 1
  fi
done

minikube_rpm=/tmp/minikube.rpm
curl -fL -o "$minikube_rpm" \
  "https://github.com/kubernetes/minikube/releases/download/v${MINIKUBE_VERSION}/minikube-${MINIKUBE_VERSION}-0.x86_64.rpm"
echo "${MINIKUBE_SHA256}  ${minikube_rpm}" | sha256sum -c -
dnf5 install -y "$minikube_rpm"

for tool in kubectx kubens; do
  checksum_variable=$(printf '%s_SHA256' "$tool" | tr '[:lower:]' '[:upper:]')
  archive="/tmp/${tool}.tar.gz"
  curl -fL -o "$archive" \
    "https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX_VERSION}/${tool}_v${KUBECTX_VERSION}_linux_x86_64.tar.gz"
  echo "${!checksum_variable}  ${archive}" | sha256sum -c -
  tar -xzf "$archive" -C /usr/bin "$tool"
done

chmod 0755 /usr/bin/kubectx /usr/bin/kubens
mkdir -p /etc/bash_completion.d /tmp/minikube-home
kubectl completion bash > /etc/bash_completion.d/kubectl
MINIKUBE_HOME=/tmp/minikube-home minikube completion bash > /etc/bash_completion.d/minikube
chmod 0644 /etc/bash_completion.d/kubectl /etc/bash_completion.d/minikube

rm -rf /tmp/minikube-home
rm -f "$minikube_rpm" /tmp/kubectx.tar.gz /tmp/kubens.tar.gz
dnf5 clean all
