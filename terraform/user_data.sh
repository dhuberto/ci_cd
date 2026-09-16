#!/bin/bash
set -euo pipefail
dnf update -y
dnf install -y docker git curl
systemctl enable --now docker
usermod -aG docker ec2-user
