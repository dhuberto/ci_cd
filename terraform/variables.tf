variable "aws_region"    { default = "us-east-1" }
variable "instance_type" { default = "t3.medium" }
variable "key_name"      { type = string }
variable "allowed_cidr"  { default = "0.0.0.0/0" }
variable "project_name"  { default = "ci-cd-app" }
