#!/bin/bash
# Script executado na primeira inicialização da EC2.
# Só instala o Docker base — kind/kubectl/ingress ficam no Ansible.
set -euo pipefail
dnf update -y
dnf install -y docker git curl
systemctl enable --now docker
usermod -aG docker ec2-user
