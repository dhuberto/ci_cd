terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  # State local no runner — efêmero, ok para o lab.
  # Se quiser persistir, troque por backend "s3" (fora do Learner Lab).
}

provider "aws" {
  region = var.aws_region
}
