# Todas as variáveis do projeto. Os valores default são usados quando o workflow
# não passa TF_VAR_<nome> explicitamente.

variable "aws_region" {
  description = "Região AWS"
  type        = string
  default     = "us-east-1"
}

# kind exige pelo menos 2 vCPU / 4 GB. t3.medium atende com folga.
variable "instance_type" {
  description = "Tipo da instância EC2"
  type        = string
  default     = "t3.medium"
}

# Nome do Key Pair importado pelo workflow de provisionamento.
variable "key_name" {
  description = "Nome do Key Pair na AWS"
  type        = string
}

# CIDR com acesso a SSH (22) e à API do k8s (6443).
variable "allowed_cidr" {
  description = "CIDR liberado para SSH e API do k8s"
  type        = string
  default     = "0.0.0.0/0"
}

# Prefixo dos nomes dos recursos (tags).
variable "project_name" {
  description = "Prefixo de nome dos recursos"
  type        = string
  default     = "ci-cd-app"
}
