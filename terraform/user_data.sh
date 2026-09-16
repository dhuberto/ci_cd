#!/bin/bash
# Script de bootstrap da EC2.
# - Não roda `dnf update -y` no início porque o AL2023 tem um conflito
#   conhecido entre `curl-minimal` (já instalado) e `curl` (que o update
#   tenta trazer) — o dnf aborta com "Transaction test error".
# - Usa `--allowerasing` no install para permitir o dnf resolver os conflitos
#   quando necessário.
# - Instala Docker e adiciona ec2-user ao grupo docker.
set -euxo pipefail

# Instala Docker (kind e kubectl ficam por conta do Ansible)
dnf install -y --allowerasing docker git curl

# Habilita e inicia o Docker
systemctl enable --now docker

# Adiciona o ec2-user ao grupo docker (para não precisar de sudo)
usermod -aG docker ec2-user

# Marca que o user_data terminou (útil para debug)
echo "user_data OK em $(date)" > /home/ec2-user/user_data.done
chown ec2-user:ec2-user /home/ec2-user/user_data.done
