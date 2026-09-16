#!/bin/bash
# Gera o inventory dinamicamente a partir da variável EC2_IP
# exportada pelo workflow (vem do output do Terraform).
if [ -z "${EC2_IP:-}" ]; then
  echo "EC2_IP não definido" >&2
  exit 1
fi
echo "[ec2]"
echo "${EC2_IP} ansible_host=${EC2_IP} ansible_user=ec2-user"
