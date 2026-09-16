# =============================================================================
# main.tf — recursos AWS (VPC, subnet, IGW, SG, EC2)
# =============================================================================
# Topologia:
#   VPC 10.0.0.0/16
#     └─ Subnet pública 10.0.1.0/24 (AZ-a)
#          └─ Security Group (22, 80, 6443)
#               └─ EC2 Amazon Linux 2023 (t3.medium)
#
# O user_data.sh instala Docker. kind/kubectl/ingress-nginx são instalados
# depois pelo Ansible (ansible/playbook.yml).
# =============================================================================

# AMI: pega a Amazon Linux 2023 x86_64 mais recente.
# O tamanho do disco raiz vem de var.root_volume_size (não do data source,
# que NÃO expõe root_device_size).
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# VPC dedicada — isola o lab de outras redes da conta.
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc" }
}

# Internet Gateway — dá saída para a internet à subnet pública.
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

# Subnet pública — onde a EC2 vive. IP público automático ligado.
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = { Name = "${var.project_name}-subnet" }
}

# Route table: rota default 0.0.0.0/0 → IGW.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "${var.project_name}-rt" }
}

# Associa a route table à subnet pública.
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security Group com 3 portas:
#   22   → SSH (GitHub Actions entra para instalar/configurar)
#   80   → HTTP (ingress-nginx expõe a app)
#   6443 → API do k8s (OpenLens/Freelens, opcional)
resource "aws_security_group" "web" {
  name        = "${var.project_name}-sg"
  description = "SG para kind + ingress-nginx"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH do GitHub Actions"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  ingress {
    description = "HTTP do ingress-nginx"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "API do Kubernetes (OpenLens/Freelens)"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-sg" }
}

# EC2 — roda o user_data.sh no boot. O Ansible configura o resto depois.
#
# volume_size vem de var.root_volume_size (default 30).
# NÃO usar data.aws_ami.al2023.root_device_size — esse atributo não existe
# no data source da AWS. A variável permite controle e tem validação >= 30.
resource "aws_instance" "web" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]
  key_name               = var.key_name
  user_data              = file("${path.module}/user_data.sh")

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  tags = { Name = "${var.project_name}-ec2" }
}
