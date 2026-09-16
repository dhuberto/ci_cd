# AMI: pega a Amazon Linux 2023 PADRÃO (x86_64), excluindo variantes
# ECS Optimized, EKS Optimized e Minimal.
# Filtros:
#   - name: "al2023-ami-2023.*-x86_64" (padrão AL2023)
#   - description: "Amazon Linux 2023 AMI*" (reforça contra ECS/EKS)
#   - architecture: x86_64
#   - virtualization-type: hvm
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "description"
    values = ["Amazon Linux 2023 AMI*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
