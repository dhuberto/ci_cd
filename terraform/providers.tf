# Declara o provider AWS e a versão mínima do Terraform.
# Sem backend remoto — o state fica local no runner do GitHub Actions (efêmero).
# Suficiente para o Learner Lab, que não permite criar bucket S3/DynamoDB custom.
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Provider AWS — a região vem da variável aws_region.
provider "aws" {
  region = var.aws_region
}
