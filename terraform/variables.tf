variable "aws_region" {
  description = "Região AWS"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "Tipo da instância EC2 (kind exige >= 2 vCPU e 4 GB)"
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "Nome do Key Pair a ser criado/importado"
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
