#!/bin/bash
# =============================================================================
# inventory.sh — inventory dinâmico do Ansible
# =============================================================================
# Gera o inventory em tempo de execução a partir da variável EC2_IP,
# que é exportada pelo workflow (vem do output do Terraform).
#
# Por que dinâmico?
#   O IP da EC2 muda a cada provisionamento. Um arquivo de inventory estático
#   exigiria edição manual a cada run — anti-padrão em Pipeline as Code.
# =============================================================================

set -euo pipefail

if [ -z "${EC2_IP:-}" ]; then
  echo "ERRO: variável EC2_IP não definida" >&2
  echo "O workflow precisa exportar EC2_IP antes de rodar o ansible-playbook" >&2
  exit 1
fi

cat <<EOF
[ec2]
${EC2_IP} ansible_host=${EC2_IP} ansible_user=ec2-user

[ec2:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
EOF
