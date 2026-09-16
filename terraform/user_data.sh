#!/bin/bash
# =============================================================================
# user_data.sh — bootstrap da EC2
# =============================================================================
# A EC2 sobe apenas com o que a AMI já traz. Docker, kind e kubectl ficam
# por conta do Ansible (ansible/playbook.yml).
#
# Por que não instalar Docker aqui:
#   O AL2023 tem conflito entre curl-minimal e curl, e o `dnf install docker`
#   pode falhar deixando o cache do DNF corrompido. O Ansible lida com isso
#   usando `dnf clean all` + `rm -rf /var/cache/dnf/*` + `dnf makecache`.
# =============================================================================

set -euxo pipefail

# Configura o grupo docker (o serviço em si é instalado depois pelo Ansible).
usermod -aG docker ec2-user 2>/dev/null || true

# Marcador para debug.
echo "user_data OK em $(date)" > /home/ec2-user/user_data.done
chown ec2-user:ec2-user /home/ec2-user/user_data.done
