# Variáveis do Terraform. Os defaults são usados quando o workflow não passa
# TF_VAR_<nome> explicitamente.

variable "aws_region" {
  description = "Região AWS"
  type        = string
  default     = "us-east-1"
}

# kind exige ao menos 2 vCPU / 4 GB. t3.medium atende com folga.
variable "instance_type" {
  description = "Tipo da instância EC2"
  type        = string
  default     = "t3.medium"
}

# Tamanho do disco raiz em GB.
# Mínimo 30: a AMI mais recente do AL2023 tem snapshot raiz de 30 GB.
# Se aumentar no futuro, ajuste aqui — o workflow lê via TF_VAR_root_volume_size.
variable "root_volume_size" {
  description = "Tamanho do disco raiz em GB (mínimo 30)"
  type        = number
  default     = 30

  validation {
    condition     = var.root_volume_size >= 30
    error_message = "root_volume_size precisa ser >= 30 (snapshot raiz da AMI AL2023)."
  }
}

variable "key_name" {
  description = "Nome do Key Pair na AWS"
  type        = string
}

variable "allowed_cidr" {
  description = "CIDR liberado para SSH e API do k8s"
  type        = string
  default     = "0.0.0.0/0"
}

variable "project_name" {
  description = "Prefixo de nome dos recursos"
  type        = string
  default     = "ci-cd-app"
}
