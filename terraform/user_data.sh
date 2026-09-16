#!/bin/bash
# Bootstrap da EC2: instala Docker e adiciona ec2-user ao grupo docker.
# NÃO roda `dnf update` porque gera conflito curl vs curl-minimal no AL2023.
# kind/kubectl/ingress ficam por conta do Ansible.
set -euxo pipefail

# Instala Docker. --allowerasing permite resolver o conflito curl/curl-minimal.
dnf install -y --allowerasing docker git curl

# Habilita e inicia o Docker.
systemctl enable --now docker

# Adiciona o ec2-user ao grupo docker (evita sudo em cada comando).
usermod -aG docker ec2-user

# Marcador para debug: confirma que o user_data terminou com sucesso.
echo "user_data OK em $(date)" > /home/ec2-user/user_data.done
chown ec2-user:ec2-user /home/ec2-user/user_data.done
