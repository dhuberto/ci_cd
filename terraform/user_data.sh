#!/bin/bash
# =============================================================================
# user_data.sh — bootstrap da EC2
# =============================================================================
# Roda uma única vez, na primeira inicialização da instância.
#
# O que este script faz:
#   1. Instala Docker (com --allowerasing para resolver conflito curl/curl-minimal)
#   2. Habilita e inicia o serviço Docker
#   3. Adiciona o ec2-user ao grupo docker
#   4. Cria um marcador para debug (/home/ec2-user/user_data.done)
#
# O que NÃO faz (fica no Ansible):
#   - Instalar kind, kubectl
#   - Criar o cluster kind
#   - Instalar ingress-nginx
#   - Criar namespaces
#
# Por que NÃO tem `dnf update -y`:
#   O Amazon Linux 2023 tem conflito conhecido entre `curl-minimal` (já instalado)
#   e `curl` (que o update traz). O dnf aborta com "Transaction test error".
#   A correção é usar `dnf install --allowerasing` no lugar.
# =============================================================================

set -euxo pipefail

# -----------------------------------------------------------------------------
# 1) Instalar Docker, git e curl
# -----------------------------------------------------------------------------
# --allowerasing permite ao dnf remover pacotes conflitantes automaticamente.
dnf install -y --allowerasing docker git curl

# -----------------------------------------------------------------------------
# 2) Habilitar e iniciar o Docker
# -----------------------------------------------------------------------------
systemctl enable --now docker

# -----------------------------------------------------------------------------
# 3) Adicionar o ec2-user ao grupo docker
# -----------------------------------------------------------------------------
usermod -aG docker ec2-user

# -----------------------------------------------------------------------------
# 4) Marcar que o user_data terminou com sucesso
# -----------------------------------------------------------------------------
echo "user_data OK em $(date)" > /home/ec2-user/user_data.done
chown ec2-user:ec2-user /home/ec2-user/user_data.done
