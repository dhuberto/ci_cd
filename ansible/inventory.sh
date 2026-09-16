#!/bin/bash
# Inventory dinâmico: gera o grupo [ec2] a partir da variável EC2_IP
# exportada pelo workflow (vem do output do Terraform).
set -euo pipefail

if [ -z "${EC2_IP:-}" ]; then
  echo "ERRO: variável EC2_IP não definida" >&2
  exit 1
fi

cat <<EOF
[ec2]
${EC2_IP} ansible_host=${EC2_IP} ansible_user=ec2-user

[ec2:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
EOF
