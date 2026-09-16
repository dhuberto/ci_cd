#!/bin/bash
# =============================================================================
# user_data.sh — bootstrap da EC2
# =============================================================================
# A EC2 sobe apenas com os pacotes auxiliares (git, curl) já presentes na AMI.
# Docker, kind e kubectl ficam por conta do Ansible (ansible/playbook.yml).
#
# Por que não instalar Docker aqui:
#   O AL2023 tem conflito entre curl-minimal e curl, e o `dnf install docker`
#   pode falhar deixando o cache do DNF corrompido. O Ansible lida com isso
#   removendo /var/cache/dnf e reinstalando com --allowerasing.
# =============================================================================

set -euxo pipefail

# Garante que o ec2-user tem o grupo docker (o serviço em si é instalado depois).
# Nada é instalado aqui — só configuração de grupo.
usermod -aG docker ec2-user 2>/dev/null || true

# Marcador para debug: confirma que o user_data terminou.
echo "user_data OK em $(date)" > /home/ec2-user/user_data.done
chown ec2-user:ec2-user /home/ec2-user/user_data.done
