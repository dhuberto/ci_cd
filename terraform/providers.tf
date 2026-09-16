terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # State local no runner do GitHub Actions (efêmero).
  # Suficiente para o lab. Fora do Learner Lab, troque por backend "s3".
}

provider "aws" {
  region = var.aws_region
}
