# Outputs consumidos pelo workflow via `terraform output -raw <nome>`.
# Evita IP hardcoded nos workflows.

output "instance_public_ip" {
  description = "IP público da EC2"
  value       = aws_instance.web.public_ip
}

output "instance_id" {
  description = "ID da instância"
  value       = aws_instance.web.id
}

output "application_url" {
  description = "URL base da aplicação"
  value       = "http://${aws_instance.web.public_ip}"
}
